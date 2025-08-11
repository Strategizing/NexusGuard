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

local Utils = require('server/sv_utils')                  -- Load the utils module for logging
local Natives = require('shared/natives')                 -- Load the natives wrapper
local Dependencies = require('shared/dependency_manager') -- Load the dependency manager
local Log -- Local alias for Log, set during Initialize

-- Local reference to the Config table, set during Initialize
local Config, Core = nil, nil

local Security = {
    -- Anti-Replay Cache: Stores recently validated token signatures and their expiry times.
    -- Prevents the same token from being accepted multiple times within its validity window.
    -- Key: Token signature (string)
    -- Value: Expiry timestamp (number, os.time() format)
    recentTokens = {},
    -- Track used timestamps per player to prevent replay attacks with the same timestamp
    usedTimestamps = {},
    -- Active per-player challenge tokens
    activeChallenges = {},
    tokenCacheCleanupInterval = 60000, -- Default cleanup interval (ms), overridden by config
    lastTokenCacheCleanup = 0,         -- Timestamp (GetGameTimer) of the last cleanup.
    maxTimeDifference = 60,            -- Default validity window (seconds), overridden by config
    nonceLength = 16,                  -- Length of the random nonce in bytes

    -- Security statistics for monitoring
    stats = {
        tokensGenerated = 0,
        tokensValidated = 0,
        tokensFailed = 0,
        replayAttempts = 0,
        lastResetTime = os.time()
    },

    -- Indicates whether the security subsystem is active. If false, token
    -- generation/validation will be disabled to prevent insecure operation.
    isActive = true
}

--[[
    Initialization Function
    Called by globals.lua after loading modules.
    Sets local references to Config and Log.
    Reads configuration values.

    @param cfg (table): The main Config table.
    @param logFunc (function): The logging function (Utils.Log).
]]
function Security.Initialize(cfg, logFunc, core)
    Config = cfg or {} -- Store config reference
    Log = logFunc or function(...) print("[Security Fallback Log]", ...) end -- Store log function reference
    Core = core

    -- Validate security secret early to prevent insecure startup
    local secret = Config.SecuritySecret
    if not secret or secret == "" or secret == "CHANGE_THIS_TO_A_LONG_RANDOM_STRING" or secret == "!!CHANGE_THIS_TO_A_SECURE_RANDOM_STRING!!" then
        Log("^1SECURITY CRITICAL: Config.SecuritySecret is missing, empty, or default. Stopping resource.^7", 1)
        Security.isActive = false

        -- Attempt to stop this resource to prevent insecure operation
        local resName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or nil
        if resName then
            if type(StopResource) == 'function' then
                StopResource(resName)
            elseif Natives and Natives.ExecuteCommand then
                Natives.ExecuteCommand("stop " .. resName)
            end
        end
        return false
    end

    -- Initialize the dependency manager
    Dependencies.Initialize(Log)
    -- Read configurable values, using defaults if not present in config
    Security.maxTimeDifference = (Config.Security and Config.Security.TokenValidityWindow) or Security.maxTimeDifference
    Security.tokenCacheCleanupInterval = (Config.Security and Config.Security.TokenCacheCleanupIntervalMs) or Security.tokenCacheCleanupInterval

    -- Check for required dependencies
    if not Dependencies.status.ox_lib.available then
        Log("^1SECURITY CRITICAL: ox_lib not available. Security token system will have limited functionality.^7", 1)
    end

    Log(("^2[Security]^7 Initialized. Token Validity: %ds, Cache Cleanup Interval: %dms"):format(
        Security.maxTimeDifference, Security.tokenCacheCleanupInterval
    ), 3)
end


--[[
    Generates a secure token for a player using HMAC-SHA256.
    The token consists of a timestamp, nonce, and signature calculated from the player ID, timestamp, nonce,
    and the server's secret key (`Config.SecuritySecret`).

    @param playerId (number): The server ID of the player requesting the token.
    @return (table | nil): A table `{ timestamp = number, nonce = string, signature = string }` on success, or nil on error
                           (e.g., missing crypto library or security secret).
]]
function Security.GenerateToken(playerId)
    if not Security.isActive then
        return nil
    end
    -- Validate player ID
    if not playerId or playerId <= 0 then
        Log("^1SECURITY ERROR: Invalid player ID provided to GenerateToken.^7", 1)
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
    -- Generate a random nonce for additional security (prevents replay attacks)
    local nonce = Security.GenerateNonce()
    if not nonce then
        Log("^1SECURITY ERROR: Failed to generate nonce for token.^7", 1)
        return nil
    end

    -- Construct the message to be signed: "playerId:timestamp:nonce".
    local message = tostring(playerId) .. ":" .. tostring(timestamp) .. ":" .. nonce

    -- Calculate the HMAC-SHA256 signature using the dependency manager
    local signature = Dependencies.Crypto.hmac.sha256(secret, message)
    if not signature then
        Log(("^1SECURITY ERROR: Failed to generate HMAC-SHA256 signature for player %d^7"):format(playerId), 1)
        return nil
    end

    -- Track token generation in statistics
    Security.stats.tokensGenerated = Security.stats.tokensGenerated + 1

    -- Return the token data table containing the timestamp, nonce, and the calculated signature.
    return { timestamp = timestamp, nonce = nonce, signature = signature }
end

--[[
    Generates a cryptographically secure random nonce.
    Returns nil if a secure random generator is unavailable, disabling token issuance.

    @return (string | nil): A random nonce string, or nil on failure.
]]
function Security.GenerateNonce()
    -- Use ox_lib's secure random function if available
    if Dependencies.status.ox_lib.available and lib and lib.crypto and lib.crypto.randomBytes then
        local success, result = pcall(function()
            return lib.crypto.randomBytes(Security.nonceLength)
        end)

        if success and result then
            return result
        else
            Log("^1SECURITY ERROR: Failed to generate secure random bytes for nonce.^7", 1)
            return nil
        end
    end

    -- Secure random generator not available
    Log("^1SECURITY CRITICAL: Secure random generator unavailable. Cannot generate nonce.^7", 1)
    return nil
end

--[[
    Validates a security token received from a client.
    Checks:
    1. Token structure and data types.
    2. Timestamp validity (within a defined window around the current server time).
    3. Signature correctness (recalculates HMAC signature and compares).
    4. Anti-replay (checks if the signature has been used recently).

    @param playerId (number): The server ID of the player who supposedly sent the token.
    @param tokenData (table): The received token table, expected: `{ timestamp = number, nonce = string, signature = string }`.
    @return (boolean): True if the token is valid and has not been replayed, false otherwise.
]]
function Security.ValidateToken(playerId, tokenData)
    if not Security.isActive then
        return false
    end
    -- Validate player ID
    if not playerId or playerId <= 0 then
        Log("^1SECURITY ERROR: Invalid player ID provided to ValidateToken.^7", 1)
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

    -- Validate data types of timestamp, nonce, and signature.
    local receivedTimestamp = tonumber(tokenData.timestamp)
    local receivedNonce = tokenData.nonce
    local receivedSignature = tokenData.signature

    if not receivedTimestamp or type(receivedSignature) ~= "string" then
        Log(("^1Security Warning: Invalid token data types (timestamp or signature) received from player %d.^7"):format(playerId), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false
    end

    -- Check if nonce is present (for backward compatibility with older clients)
    local hasNonce = receivedNonce ~= nil and type(receivedNonce) == "string" and receivedNonce ~= ""
    if not hasNonce then
        Log(("^3Security Warning: Token from player %d missing nonce. Using legacy validation.^7"):format(playerId), 2)
    end
    -- 1. Timestamp Check: Ensure the token's timestamp is within an acceptable window relative to the server's current time.
    local currentTime = os.time()
    -- Use the configured maximum allowed time difference.
    if math.abs(currentTime - receivedTimestamp) > Security.maxTimeDifference then
        Log(("^1Security Warning: Token timestamp expired or invalid for player %d. Diff: %ds, Max: %ds.^7"):format(playerId, currentTime - receivedTimestamp, Security.maxTimeDifference), 1)
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false -- Token is too old or from the future.
    end

    -- Prevent reuse of the same timestamp within the validity window
    Security.usedTimestamps[playerId] = Security.usedTimestamps[playerId] or {}
    local lastUsed = Security.usedTimestamps[playerId][receivedTimestamp]
    if lastUsed and (currentTime - lastUsed) < Security.maxTimeDifference then
        Log(("^1Security Warning: Token timestamp replay detected for player %d (timestamp: %d)^7"):format(playerId, receivedTimestamp), 1)
        Security.stats.replayAttempts = Security.stats.replayAttempts + 1
        Security.stats.tokensFailed = Security.stats.tokensFailed + 1
        return false
    end

    -- 2. Signature Verification: Recalculate the expected signature using the received timestamp, nonce, and player ID.
    local message
    if hasNonce then
        -- Use the enhanced format with nonce
        message = tostring(playerId) .. ":" .. tostring(receivedTimestamp) .. ":" .. receivedNonce
    else
        -- Fallback to legacy format without nonce
        message = tostring(playerId) .. ":" .. tostring(receivedTimestamp)
    end

    local expectedSignature = Dependencies.Crypto.hmac.sha256(secret, message)
    if not expectedSignature then
        Log(
            ("^1SECURITY ERROR: Failed to recalculate HMAC signature during validation for player %d^7"):format(playerId),
            1)
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

    -- Record the timestamp as used for this player
    Security.usedTimestamps[playerId][receivedTimestamp] = currentTime

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
        if currentServerTime >= expiryTimestamp then
            Security.recentTokens[signature] = nil
            cleanupCount = cleanupCount + 1
        end
    end

    -- Cleanup used timestamp cache
    local buffer = Security.maxTimeDifference + 5
    for playerId, tsTable in pairs(Security.usedTimestamps) do
        for ts, usedAt in pairs(tsTable) do
            if currentServerTime - usedAt > buffer then
                tsTable[ts] = nil
            end
        end
        if next(tsTable) == nil then
            Security.usedTimestamps[playerId] = nil
        end
    end

    -- Cleanup expired challenge tokens
    for playerId, data in pairs(Security.activeChallenges) do
        if currentServerTime >= data.expires then
            Security.activeChallenges[playerId] = nil
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
    if not Natives.GetPlayerEndpoint(source) then
        Log("^1[Security] Event from disconnected player ID: " .. tostring(source) .. "^7", 1)
        return false
    end

    -- Check for valid session if required
    if requireSession then
        -- Try to access the global NexusGuardServer table safely
        local hasSession = false
        local success, result = pcall(function()
            if Core and type(Core.GetSession) == "function" then
                local session = Core.GetSession(source)
                return session ~= nil
            end
            return false
        end)

        hasSession = success and result

        if not hasSession then
            Log("^1[Security] Event from player without valid session ID: " .. tostring(source) .. "^7", 1)
            return false
        end
    end

    return true
end

--[[
    Generate a short-lived challenge token for a player.
    @param playerId (number): Player server ID.
    @return (string | nil): Challenge token or nil on failure.
]]
function Security.GenerateChallengeToken(playerId)
    if not Security.isActive then return nil end
    if not playerId or playerId <= 0 then return nil end
    local secret = Config and Config.SecuritySecret
    if not secret or secret == "" then return nil end
    local timestamp = os.time()
    local message = tostring(playerId) .. ":challenge:" .. tostring(timestamp)
    local signature = Dependencies.Crypto.hmac.sha256(secret, message)
    if not signature then return nil end
    local token = signature .. ":" .. timestamp
    Security.activeChallenges[playerId] = { token = token, expires = timestamp + 30 }
    return token
end

--[[
    Verify a challenge response from a client.
    @param playerId (number): Player server ID.
    @param response (string): Challenge response from client.
    @return (boolean): True if valid, false otherwise.
]]
function Security.VerifyChallengeResponse(playerId, response)
    local data = Security.activeChallenges[playerId]
    if not data then return false end
    local valid = response == data.token and os.time() < data.expires
    Security.activeChallenges[playerId] = nil
    return valid
end

--[[
    Creates a secure hash of data using SHA-256.
    Useful for creating identifiers or checksums.

    @param data (string): The data to hash.
    @return (string): The SHA-256 hash of the data, or nil on failure.
]]
function Security.SecureHash(data)
    if not data or type(data) ~= "string" then
        Log("^1SECURITY ERROR: Invalid data provided for hashing.^7", 1)
        return nil
    end

    local hash = Dependencies.Crypto.hash.sha256(data)
    if not hash then
        Log("^1SECURITY ERROR: Failed to generate SHA-256 hash.^7", 1)
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
