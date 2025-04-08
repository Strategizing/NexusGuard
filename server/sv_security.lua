--[[
    NexusGuard Server Security Module (server/sv_security.lua)

    Purpose:
    - Provides functions for generating and validating security tokens used in client-server communication.
    - Implements HMAC-SHA256 signing to ensure message integrity and authenticity.
    - Includes an anti-replay mechanism using a timed cache to prevent reuse of tokens.

    Dependencies:
    - `server/sv_utils.lua` (for logging)
    - `ox_lib` resource (for `lib.crypto.hmac.sha256`)
    - Global `Config` table (for `Config.SecuritySecret`)

    Usage:
    - Required by `globals.lua` and exposed via the `NexusGuardServer.Security` API table.
    - `GenerateToken` is called when a client requests a token (e.g., during connection).
    - `ValidateToken` is called by server-side event handlers receiving data from clients to verify authenticity.
    - `CleanupTokenCache` is called periodically (e.g., by a scheduled task in `server_main.lua`) to clear expired tokens.
]]

local Utils = require('server/sv_utils') -- Load the utils module for logging.
local Log = Utils.Log

local Security = {
    -- Anti-Replay Cache: Stores recently validated token signatures and their expiry times.
    -- Prevents the same token from being accepted multiple times within its validity window.
    -- Key: Token signature (string)
    -- Value: Expiry timestamp (number, os.time() format)
    recentTokens = {},
    tokenCacheCleanupInterval = 60000, -- How often to clean the cache (milliseconds). Default: 1 minute.
    lastTokenCacheCleanup = 0          -- Timestamp (GetGameTimer) of the last cleanup.
}

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
    -- Retrieve the security secret from the global Config table.
    local secret = (_G.Config and _G.Config.SecuritySecret)
    -- CRITICAL: Ensure the secret is set and is not the default placeholder value.
    if not secret or secret == "" or secret == "CHANGE_THIS_TO_A_VERY_LONG_RANDOM_SECRET_STRING" then
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
        return false
    end
    -- Retrieve the security secret.
    local secret = (_G.Config and _G.Config.SecuritySecret)
    if not secret or secret == "" or secret == "CHANGE_THIS_TO_A_VERY_LONG_RANDOM_SECRET_STRING" then
        Log("^1SECURITY CRITICAL: Config.SecuritySecret is missing, empty, or default in ValidateToken. Cannot validate.^7", 1)
        return false
    end
    -- Validate the structure and presence of required fields in the received token data.
    if not tokenData or type(tokenData) ~= "table" or not tokenData.timestamp or not tokenData.signature then
        Log(("^1Security Warning: Invalid token data structure received from player %d.^7"):format(playerId), 1)
        return false
    end

    -- Validate data types of timestamp and signature.
    local receivedTimestamp = tonumber(tokenData.timestamp)
    local receivedSignature = tokenData.signature
    if not receivedTimestamp or type(receivedSignature) ~= "string" then
        Log(("^1Security Warning: Invalid token data types (timestamp or signature) received from player %d.^7"):format(playerId), 1)
        return false
    end

    -- 1. Timestamp Check: Ensure the token's timestamp is within an acceptable window relative to the server's current time.
    local currentTime = os.time()
    -- Define the maximum allowed time difference in seconds (e.g., 60 seconds). Consider making this configurable.
    local maxTimeDifference = (_G.Config and _G.Config.SecurityTokenValidityWindow) or 60
    if math.abs(currentTime - receivedTimestamp) > maxTimeDifference then
        Log(("^1Security Warning: Token timestamp expired or invalid for player %d. Diff: %ds, Max: %ds.^7"):format(playerId, currentTime - receivedTimestamp, maxTimeDifference), 1)
        return false -- Token is too old or from the future.
    end

    -- 2. Signature Verification: Recalculate the expected signature using the received timestamp and player ID.
    local message = tostring(playerId) .. ":" .. tostring(receivedTimestamp)
    local success, expectedSignature = pcall(lib.crypto.hmac.sha256, secret, message)
    if not success or not expectedSignature then
        Log(("^1SECURITY ERROR: Failed to recalculate HMAC signature during validation for player %d: %s^7"):format(playerId, tostring(expectedSignature)), 1)
        return false -- Internal error during recalculation.
    end

    -- Compare the recalculated signature with the signature received from the client.
    if expectedSignature ~= receivedSignature then
        Log(("^1SECURITY ALERT: Token signature mismatch for player %d! Potential tampering or configuration issue.^7"):format(playerId), 1)
        return false -- Signatures do not match.
    end

    -- 3. Anti-Replay Check: Prevent the same token from being used multiple times.
    local cacheKey = receivedSignature -- Use the unique signature as the key in the cache.
    local expiryTime = Security.recentTokens[cacheKey] -- Check if this signature exists in the cache.

    -- If the signature is in the cache AND the current time is before its expiry time, it's a replay attempt.
    if expiryTime and currentTime < expiryTime then
        Log(("^1Security Warning: Token replay detected for player %d. Signature: %s^7"):format(playerId, cacheKey), 1)
        return false -- Token has already been used recently.
    end

    -- If all checks passed: Add the token signature to the anti-replay cache with an expiry time.
    -- The expiry time should be slightly longer than the validation window to cover edge cases.
    local cacheBuffer = 5 -- Add a small buffer (e.g., 5 seconds).
    Security.recentTokens[cacheKey] = currentTime + maxTimeDifference + cacheBuffer
    -- Log("Token validated and cached for player " .. playerId, 4) -- Optional debug log

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

-- Export the Security table for use in other modules via globals.lua.
return Security
