local DetectorName = "template"
local Detector = {}
local NexusGuard = nil
local checkInterval = 1000 -- ms between checks
local isEnabled = false

function Detector.Initialize(nexusGuardObj)
    NexusGuard = nexusGuardObj
    
    -- Read configuration
    isEnabled = Config.Detectors[DetectorName] or false
    checkInterval = Config.Intervals[DetectorName] or checkInterval
    
    -- Only set up timer if detector is enabled
    if isEnabled then
        Detector.StartChecking()
    end
    
    return isEnabled
end

function Detector.StartChecking()
    -- Use more efficient timing approach
    Citizen.CreateThread(function()
        local nextCheck = GetGameTimer()
        
        while isEnabled do
            -- Adaptive timing
            local currentTime = GetGameTimer()
            if currentTime >= nextCheck then
                -- Run check and schedule next one
                if not Detector.Check() then
                    -- Detection failed, check more frequently
                    nextCheck = currentTime + math.floor(checkInterval * 0.5)
                else
                    nextCheck = currentTime + checkInterval
                end
            end
            
            -- Yield less frequently, but still responsive
            Citizen.Wait(250)
        end
    end)
end

function Detector.Check()
    -- Add detection logic here
    return true -- No cheat detected
end

-- Register with NexusGuard if enabled
if Config.Detectors[DetectorName] then
    AddEventHandler("NexusGuard:Initialize", function(nexusGuardObj)
        Detector.Initialize(nexusGuardObj)
    end)
end

return Detector
