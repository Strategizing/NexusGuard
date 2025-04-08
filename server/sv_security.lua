--[[
    NexusGuard Server Security Module
    Handles secure token generation, validation, and anti-replay cache.
]]

local Utils = require('server/sv_utils') -- Load the utils module
local Log = Utils.Log

local Security = {
    recentTokens = {}, -- Cache for anti-replay { [signature] = expiryTimestamp }
    tokenCacheCleanupInterval = 60000, -- ms (e.g., clean up every minute)
    lastTokenCacheCleanup = 0
}

-- Generates a secure token for a player using HMAC-SHA256
-- @param playerId number: The server ID of the player.
-- @return table or nil: A table { timestamp = ..., signature = ... } or nil on error.
function Security.GenerateToken(playerId)
    if not lib or not lib.crypto or not lib.crypto.hmac or not lib.crypto.hmac.sha256 then
        Log("^1SECURITY ERROR: ox_lib crypto functions not available for GenerateToken.^7", 1)
        return nil
    end
    -- Access Config directly as it's loaded globally early
    local secret = (_G.Config and _G.Config.SecuritySecret)
    if not secret or secret == "CHANGE_THIS_TO_A_VERY_LONG_RANDOM_SECRET_STRING" then
        Log("^1SECURITY ERROR: Config.SecuritySecret is not set or is default in GenerateToken.^7", 1)
        return nil
    end

    local timestamp = os.time()
    local message = tostring(playerId) .. ":" .. tostring(timestamp)
    local success, signature = pcall(lib.crypto.hmac.sha256, secret, message)
    if not success or not signature then
        Log("^1SECURITY ERROR: Failed to generate HMAC signature: " .. tostring(signature) .. "^7", 1)
        return nil
    end
    return { timestamp = timestamp, signature = signature }
end

-- Validates a received security token
-- @param playerId number: The server ID of the player sending the token.
-- @param tokenData table: The received token table { timestamp = ..., signature = ... }.
-- @return boolean: True if the token is valid and not replayed, false otherwise.
function Security.ValidateToken(playerId, tokenData)
    if not lib or not lib.crypto or not lib.crypto.hmac or not lib.crypto.hmac.sha256 then
        Log("^1SECURITY ERROR: ox_lib crypto functions not available for ValidateToken.^7", 1)
        return false
    end
    -- Access Config directly
    local secret = (_G.Config and _G.Config.SecuritySecret)
    if not secret or secret == "CHANGE_THIS_TO_A_VERY_LONG_RANDOM_SECRET_STRING" then
        Log("^1SECURITY ERROR: Config.SecuritySecret is not set or is default in ValidateToken.^7", 1)
        return false
    end
    if not tokenData or type(tokenData) ~= "table" or not tokenData.timestamp or not tokenData.signature then
        Log("^1Invalid token data structure received from player " .. playerId .. "^7", 1)
        return false
    end

    local receivedTimestamp = tonumber(tokenData.timestamp)
    local receivedSignature = tokenData.signature
    if not receivedTimestamp or type(receivedSignature) ~= "string" then
        Log("^1Invalid token data types received from player " .. playerId .. "^7", 1)
        return false
    end

    local currentTime = os.time()
    local maxTimeDifference = 60 -- Consider making this configurable?
    if math.abs(currentTime - receivedTimestamp) > maxTimeDifference then
        Log("^1Token timestamp expired/invalid for player " .. playerId .. "^7", 1)
        return false
    end

    -- Recalculate expected signature
    local message = tostring(playerId) .. ":" .. tostring(receivedTimestamp)
    local success, expectedSignature = pcall(lib.crypto.hmac.sha256, secret, message)
    if not success or not expectedSignature then
        Log("^1SECURITY ERROR: Failed to recalculate HMAC signature: " .. tostring(expectedSignature) .. "^7", 1)
        return false
    end

    -- Compare signatures
    if expectedSignature ~= receivedSignature then
        Log("^1Token signature mismatch for player " .. playerId .. "^7", 1)
        return false
    end

    -- Anti-Replay Check
    local cacheKey = receivedSignature -- Use the signature as the key
    local expiryTime = Security.recentTokens[cacheKey]

    if expiryTime and currentTime < expiryTime then
        Log("^1Token replay detected for player " .. playerId .. ". Signature: " .. cacheKey .. "^7", 1)
        return false -- Token already used recently
    end

    -- Add token to cache with expiry slightly longer than validation window
    local buffer = 5 -- Add 5 seconds buffer
    Security.recentTokens[cacheKey] = currentTime + maxTimeDifference + buffer
    -- Log("Token validated and cached for " .. playerId, 4) -- Debugging only

    return true
end

-- Function to clean up expired tokens from the anti-replay cache
function Security.CleanupTokenCache()
    local currentTime = os.time()
    -- Use GetGameTimer for interval checks as it's monotonic
    if GetGameTimer() - Security.lastTokenCacheCleanup < Security.tokenCacheCleanupInterval then
        return -- Not time to clean yet
    end

    local cleanupCount = 0
    for signature, expiryTimestamp in pairs(Security.recentTokens) do
        if currentTime >= expiryTimestamp then
            Security.recentTokens[signature] = nil
            cleanupCount = cleanupCount + 1
        end
    end

    if cleanupCount > 0 then
        Log("Cleaned up " .. cleanupCount .. " expired entries from token cache.", 3)
    end
    Security.lastTokenCacheCleanup = GetGameTimer()
end

return Security
