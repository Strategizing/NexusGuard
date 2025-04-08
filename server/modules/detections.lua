local Detections = {}
local Core = exports["NexusGuard"]:GetCore()

-- Process detections with enhanced server validation
function Detections.Process(playerId, detectionType, detectionData)
    -- Extract from globals.lua, add improved server-side validation
    -- Standardize detection data format
    if type(detectionData) ~= "table" then
        detectionData = { value = detectionData }
    end
    
    -- Add server validation flag
    detectionData.serverValidated = detectionData.serverValidated or false
    
    -- Implement context-aware validation logic
    if detectionType == "speedHack" then
        -- Validate speed considering falling, parachuting states
        detectionData.serverValidated = Detections.ValidateSpeed(playerId, detectionData)
    elseif detectionType == "godMode" then
        -- Correlate with recent damage events
        detectionData.serverValidated = Detections.ValidateHealth(playerId, detectionData)
    end
    
    -- Decision logic for actions based on severity and validation
    -- ...existing code...
    
    return true
end

-- Add specialized validation functions
function Detections.ValidateSpeed(playerId, data)
    -- Check if player recently spawned/respawned
    local playerMetrics = Core.PlayerMetrics[playerId]
    if not playerMetrics then return false end
    
    -- Exempt falling or recently spawned players
    if playerMetrics.isFalling or (playerMetrics.lastSpawn and 
       (os.time() - playerMetrics.lastSpawn) < Config.Thresholds.spawnGracePeriod) then
        return false
    end
    
    -- Compare against server-side threshold
    return data.speed > Config.Thresholds.serverSideSpeedThreshold
end

-- Add more validation functions
-- ...

return Detections
