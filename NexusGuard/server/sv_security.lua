--[[
    NexusGuard Server Security Module (server/sv_security.lua)

    Purpose:
    - Provides functions for generating and validating security tokens used in client-server communication.
    - Implements HMAC-SHA256 signing to ensure message integrity and authenticity.
    - Includes an anti-replay mechanism using a timed cache to prevent reuse of tokens.
    - Provides additional security utilities for secure event handling and data validation.

    Dependencies:
    - `server/sv_utils.lua` (for logging)
    - `ox_lib` resource (for `lib.crypto.hmac.sha256`)
    - Global `Config` table (for `Config.SecuritySecret`)

    Usage:
    - Required by `globals.lua` and exposed via the `NexusGuardServer.Security` API table.
    - `GenerateToken` is called when a client requests a token (e.g., during connection).
    - `ValidateToken` is called by server-side event handlers receiving data from clients to verify authenticity.
    - `CleanupTokenCache` is called periodically (e.g., by a scheduled task in `server_main.lua`) to clear expired tokens.
    - `ValidateEventSource` provides additional validation for network events.
    - `SecureHash` provides a utility for hashing sensitive data.
]]

local Utils = require('server/sv_utils') -- Load the utils module for logging.
local Log -- Local alias for Log, set during Initialize

-- Local reference to the Config table, set during Initialize
local Config = nil

local Security = {
    -- Anti-Replay Cache: Stores recently validated token signatures and their expiry times.
    -- Prevents the same token from being accepted multiple times within its validity window.
    -- Key: Token signature (string)
    -- Value: Expiry timestamp (number, os.time() format)
    recentTokens = {},
    tokenCacheCleanupInterval = 60000, -- Default cleanup interval (ms), overridden by config
    lastTokenCacheCleanup = 0,         -- Timestamp (GetGameTimer) of the last cleanup.
    maxTimeDifference = 60,            -- Default validity window (seconds), overridden by config

    -- Security statistics for monitoring
    stats = {
        tokensGenerated = 0,
        tokensValidated = 0,
        tokensFailed = 0,
        replayAttempts = 0,
        lastResetTime = os.time()
    }
}

--[[
    Initialization Function
    Called by globals.lua after loading modules.
    Sets local references to Config and Log.
    Reads configuration values.

    @param cfg (table): The main Config table.
    @param logFunc (function): The logging function (Utils.Log).
]]
function Security.Initialize(cfg, logFunc)
    Config = cfg or {} -- Store config reference
    Log = logFunc or function(...) print("[Security Fallback Log]", ...) end -- Store log function reference

    -- Read configurable values, using defaults if not present in config
    Security.maxTimeDifference = (Config.Security and Config.Security.TokenValidityWindow) or Security.maxTimeDifference
    Security.tokenCacheCleanupInterval = (Config.Security and Config.Security.TokenCacheCleanupIntervalMs) or Security.tokenCacheCleanupInterval

    Log(("[Security] Initialized. Token Validity: %ds, Cache Cleanup Interval: %dms"):format(
        Security.maxTimeDifference, Security.tokenCacheCleanupInterval
    ), 3)
end


--[[
    Generates a secure token for a player using HMAC-SHA256.
    The token consists of a timestamp and a signature calculated from the player ID, timestamp,
    and the server's secret key (`Config.SecuritySecret`).

    @param playerId (number): The server ID of the player requesting the token.
    @return (table | nil): A table `{ timestamp = number, signature = string }` on success, or nil on error
                           (e.g., missing crypto library or security secret).
]]
function Security.GenerateToken(playerId)
    -- Ensure ox_lib crypto functions are available.
    if not lib or not lib.crypto or not lib.crypto.hmac or not lib.crypto.hmac.sha256 then
        Log("^1SECURITY CRITICAL: ox_lib crypto functions (lib.crypto.hmac.sha256) not available. Cannot generate security token. Ensure ox_lib is started before NexusGuard and is up-to-date.^7", 1)
        return nil
    end
    -- Retrieve the security secret from the local Config reference.
    local secret = (Config and Config.SecuritySecret)
    -- CRITICAL: Ensure the secret is set and is not the default placeholder value.
    if not secret or secret == "" or secret == "!!CHANGE_THIS_TO_A_SECURE_RANDOM_STRING!!" then -- Check against actual default
        Log("^1SECURITY CRITICAL: Config.SecuritySecret is missing, empty, or default. Cannot generate security token. Set a strong, unique secret in config.lua!^7", 1)
        return nil
    end

    local timestamp = os.time() -- Current Unix timestamp.
    -- Construct the message to be signed: "playerId:timestamp".
    local message = tostring(playerId) .. ":" .. tostring(timestamp)
    -- Calculate the HMAC-SHA256 signature using the secret key and the message.
    local success, signature = pcall(lib.crypto.hmac.sha256, secret, message)
    if not success or not signature then
        Log(("^1SECURITY ERROR: Failed to generate HMAC-SHA256 signature for player %d: %s^7"):format(playerId, tostring(signature)), 1) -- 'signature' holds error message on pcall failure
        return nil
    end

    -- Track token generation in statistics
    Security.stats.tokensGenerated = Security.stats.tokensGenerated + 1

    -- Return the token data table containing the timestamp and the calculated signature.
    return { timestamp = timestamp, signature = signature }
end

--[[
    Validates a security token received from a client.
    Checks:
    1. Token structure and data types.
    2. Timestamp validity (within a defined window around the current server time).
    3. Signature correctness (recalculates HMAC signature and compares).
    4. Anti-replay (checks if the signature has been used recently).

    @param playerId (number): The server ID of the player who supposedly sent the token.
    @param tokenData (table): The received token table, expected: `{ timestamp = number, signature = string }`.
    @return (boolean): True if the token is valid and has not been replayed, false otherwise.
]]
function Security.ValidateToken(playerId, tokenData)
    -- Ensure ox_lib crypto functions are available.
    if not lib or not lib.crypto or not lib.crypto.hmac or not lib.crypto.hmac.sha256 then
        Log("^1SECURITY CRITICAL: ox_lib crypto functions not available for ValidateToken. Cannot validate.^7", 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false
    end
    -- Retrieve the security secret from the local Config reference.
    local secret = (Config and Config.SecuritySecret)
    if not secret or secret == "" or secret == "!!CHANGE_THIS_TO_A_SECURE_RANDOM_STRING!!" then -- Check against actual default
        Log("^1SECURITY CRITICAL: Config.SecuritySecret is missing, empty, or default in ValidateToken. Cannot validate.^7", 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false
    end
    -- Validate the structure and presence of required fields in the received token data.
    if not tokenData or type(tokenData) ~= "table" or not tokenData.timestamp or not tokenData.signature then
        Log(("^1Security Warning: Invalid token data structure received from player %d.^7"):format(playerId), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false
    end

    -- Validate data types of timestamp and signature.
    local receivedTimestamp = tonumber(tokenData.timestamp)
    local receivedSignature = tokenData.signature
    if not receivedTimestamp or type(receivedSignature) ~= "string" then
        Log(("^1Security Warning: Invalid token data types (timestamp or signature) received from player %d.^7"):format(playerId), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false
    end

    -- 1. Timestamp Check: Ensure the token's timestamp is within an acceptable window relative to the server's current time.
    local currentTime = os.time()
    -- Use the configured maximum allowed time difference.
    if math.abs(currentTime - receivedTimestamp) > Security.maxTimeDifference then
        Log(("^1Security Warning: Token timestamp expired or invalid for player %d. Diff: %ds, Max: %ds.^7"):format(playerId, currentTime - receivedTimestamp, Security.maxTimeDifference), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false -- Token is too old or from the future.
    end

    -- 2. Signature Verification: Recalculate the expected signature using the received timestamp and player ID.
    local message = tostring(playerId) .. ":" .. tostring(receivedTimestamp)
    local success, expectedSignature = pcall(lib.crypto.hmac.sha256, secret, message)
    if not success or not expectedSignature then
        Log(("^1SECURITY ERROR: Failed to recalculate HMAC signature during validation for player %d: %s^7"):format(playerId, tostring(expectedSignature)), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false -- Internal error during recalculation.
    end

    -- Compare the recalculated signature with the signature received from the client.
    if expectedSignature ~= receivedSignature then
        Log(("^1SECURITY ALERT: Token signature mismatch for player %d! Potential tampering or configuration issue.^7"):format(playerId), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false -- Signatures do not match.
    end

    -- 3. Anti-Replay Check: Prevent the same token from being used multiple times.
    local cacheKey = receivedSignature -- Use the unique signature as the key in the cache.
    local expiryTime = Security.recentTokens[cacheKey] -- Check if this signature exists in the cache.

    -- If the signature is in the cache AND the current time is before its expiry time, it's a replay attempt.
    if expiryTime and currentTime < expiryTime then
        Log(("^1Security Warning: Token replay detected for player %d. Signature: %s^7"):format(playerId, cacheKey), 1)
        Security.stats.replayAttempts = Security.stats.replayAttempts + 1
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false -- Token has already been used recently.
    end

    -- If all checks passed: Add the token signature to the anti-replay cache with an expiry time.
    -- The expiry time should be slightly longer than the validation window to cover edge cases.
    local cacheBuffer = 5 -- Add a small buffer (e.g., 5 seconds).
    Security.recentTokens[cacheKey] = currentTime + Security.maxTimeDifference + cacheBuffer

    -- Track successful validation in statistics
    Security.stats.tokensValidated = Security.stats.tokensValidated + 1

    return true -- Token is valid.
end

--[[
    Cleans up expired token signatures from the anti-replay cache (`Security.recentTokens`).
    Should be called periodically by a scheduled task.
]]
function Security.CleanupTokenCache()
    local currentServerTime = os.time()
    local currentGameTime = GetGameTimer() -- Use game timer for interval checking (monotonic).

    -- Check if the cleanup interval has passed since the last cleanup.
    if currentGameTime - Security.lastTokenCacheCleanup < Security.tokenCacheCleanupInterval then
        return -- Not time to clean yet.
    end

    local cleanupCount = 0
    -- Iterate through the cached tokens.
    for signature, expiryTimestamp in pairs(Security.recentTokens) do
        -- If the current server time is past the token's expiry time, remove it.
        if currentServerTime >= expiryTimestamp then
            Security.recentTokens[signature] = nil
            cleanupCount = cleanupCount + 1
        end
    end

    if cleanupCount > 0 then
        Log(("Security: Cleaned up %d expired entries from token anti-replay cache."):format(cleanupCount), 3)
    end
    -- Update the last cleanup timestamp.
    Security.lastTokenCacheCleanup = currentGameTime
end

--[[
    Validates an event source to ensure it's coming from a legitimate player.
    Checks if the source is a valid player ID and optionally if they have a valid session.

    @param source (number): The source ID from the event.
    @param requireSession (boolean): Whether to require a valid session (default: true).
    @return (boolean): True if the source is valid, false otherwise.
]]
function Security.ValidateEventSource(source, requireSession)
    -- Default to requiring a session if not specified
    if requireSession == nil then requireSession = true end

    -- Basic source validation
    if not source or source <= 0 then
        Log("^1[Security] Invalid event source ID: " .. tostring(source) .. "^7", 1)
        return false
    end

    -- Check if player is connected
    if not GetPlayerEndpoint(source) then
        Log("^1[Security] Event from disconnected player ID: " .. tostring(source) .. "^7", 1)
        return false
    end

    -- Check for valid session if required
    if requireSession and NexusGuardServer and NexusGuardServer.GetSession then
        local session = NexusGuardServer.GetSession(source)
        if not session then
            Log("^1[Security] Event from player without valid session ID: " .. tostring(source) .. "^7", 1)
            return false
        end
    end

    return true
end

--[[
    Creates a secure hash of data using SHA-256.
    Useful for creating identifiers or checksums.

    @param data (string): The data to hash.
    @return (string): The SHA-256 hash of the data, or nil on failure.
]]
function Security.SecureHash(data)
    if not lib or not lib.crypto or not lib.crypto.hash or not lib.crypto.hash.sha256 then
        Log("^1SECURITY ERROR: ox_lib crypto hash functions not available.^7", 1)
        return nil
    end

    if not data or type(data) ~= "string" then
        Log("^1SECURITY ERROR: Invalid data provided for hashing.^7", 1)
        return nil
    end

    local success, hash = pcall(lib.crypto.hash.sha256, data)
    if not success or not hash then
        Log("^1SECURITY ERROR: Failed to generate SHA-256 hash: " .. tostring(hash) .. "^7", 1)
        return nil
    end

    return hash
end

--[[
    Gets security statistics for monitoring purposes.

    @return (table): Table containing security statistics.
]]
function Security.GetStats()
    return {
        tokensGenerated = Security.stats.tokensGenerated,
        tokensValidated = Security.stats.tokensValidated,
        tokensFailed = Security.stats.tokensFailed,
        replayAttempts = Security.stats.replayAttempts,
        cacheSize = #Security.recentTokens,
        uptime = os.time() - Security.stats.lastResetTime
    }
end

--[[
    Resets security statistics.
]]
function Security.ResetStats()
    Security.stats.tokensGenerated = 0
    Security.stats.tokensValidated = 0
    Security.stats.tokensFailed = 0
    Security.stats.replayAttempts = 0
    Security.stats.lastResetTime = os.time()
    Log("^2[Security] Statistics reset.^7", 3)
end

-- Export the Security table for use in other modules via globals.lua.
return Security
