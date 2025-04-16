local Security = {}
local Core = exports["NexusGuard"]:GetCore()
local usedTokens = {}

-- Enhanced token validation with replay protection
function Security.ValidateToken(playerId, eventName, token, timestamp)
    if not Config.Security.tokenValidationEnabled then return true end
    if not token or not timestamp then return false end
    
    -- Check for token reuse (replay attack)
    local tokenKey = playerId .. ":" .. token:sub(1, 8)
    if usedTokens[tokenKey] then
        print("^1[NexusGuard] SECURITY: Token reuse detected for player " .. playerId)
        return false
    end
    
    -- Validate timestamp is recent
    local currentTime = os.time()
    local timeDiff = currentTime - tonumber(timestamp)
    if timeDiff > Config.Security.tokenValidityWindow or timeDiff < -10 then
        print("^1[NexusGuard] SECURITY: Token timestamp invalid for player " .. playerId)
        return false
    end
    
    -- Validate HMAC
    local expectedToken = Security.GenerateToken(playerId, eventName, timestamp)
    local isValid = token == expectedToken
    
    -- If valid, remember token to prevent replay
    if isValid then
        usedTokens[tokenKey] = currentTime
        
        -- Cleanup old tokens periodically
        if #usedTokens > 1000 then
            Security.CleanupOldTokens(currentTime)
        end
    end
    
    return isValid
end

function Security.GenerateToken(playerId, eventName, timestamp)
    -- Use ox_lib for HMAC-SHA256 if available
    if lib and lib.crypto then
        return lib.crypto.hmac('sha256', playerId .. ":" .. eventName .. ":" .. timestamp, Config.SecuritySecret)
    else
        print("^1[NexusGuard] CRITICAL: ox_lib crypto module not available. Security compromised!")
        return ""
    end
end

function Security.CleanupOldTokens(currentTime)
    for k, timestamp in pairs(usedTokens) do
        if currentTime - timestamp > Config.Security.tokenValidityWindow * 2 then
            usedTokens[k] = nil
        end
    end
end

-- New: Generate short-lived challenge tokens for critical actions
function Security.GenerateChallengeToken(playerId)
    local timestamp = os.time()
    local challenge = Security.GenerateToken(playerId, "challenge", timestamp) .. ":" .. timestamp
    
    -- Store challenge for validation
    Core.PlayerMetrics[playerId].activeChallenge = {
        token = challenge,
        expires = timestamp + 30 -- 30 second validity
    }
    
    return challenge
end

-- New: Verify challenge response
function Security.VerifyChallengeResponse(playerId, response)
    local metrics = Core.PlayerMetrics[playerId]
    if not metrics or not metrics.activeChallenge then return false end
    
    local valid = response == metrics.activeChallenge.token and 
                  os.time() < metrics.activeChallenge.expires
    
    -- Invalidate after use regardless of result
    metrics.activeChallenge = nil
    
    return valid
end

return Security
