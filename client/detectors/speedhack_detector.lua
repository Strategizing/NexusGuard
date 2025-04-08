--[[
    NexusGuard Speed Hack Detector (client/detectors/speedhack_detector.lua)

    Purpose:
    - Performs basic client-side checks on player and vehicle speeds against configured thresholds
      or known maximums.
    - Excludes legitimate high-speed states like falling or parachuting.

    Note on Reporting & Reliability:
    - Similar to other movement detectors, client-side speed values (`GetEntitySpeed`) can be
      manipulated or inaccurate. Direct reporting based solely on these values is unreliable.
    - This detector NO LONGER uses `NexusGuard:ReportCheat`.
    - The definitive speed hack detection is performed SERVER-SIDE in `server/modules/detections.lua`
      by analyzing the distance traveled between periodic position updates received from the client
      (`NEXUSGUARD_POSITION_UPDATE` event).
    - The checks remain here primarily for potential local logging (currently commented out) or
      as a reference, but they do not trigger anti-cheat actions.
]]

local DetectorName = "speedHack" -- Unique key for this detector
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 2000,    -- Default check interval (ms). Overridden by config.
    lastCheck = 0       -- Timestamp of the last check.
    -- No specific local state needed for this detector
}

--[[
    Initialization Function
    Called by the DetectorRegistry during startup.
    @param nexusGuardInstance (table): The main NexusGuard client instance.
]]
function Detector.Initialize(nexusGuardInstance)
    if not nexusGuardInstance then
        print(("^1[NexusGuard:%s] CRITICAL: Failed to receive NexusGuard instance during initialization.^7"):format(DetectorName))
        return false
    end
    NexusGuard = nexusGuardInstance -- Store the reference.

    -- Read configuration (interval) via the NexusGuard instance.
    local cfg = NexusGuard.Config
    Detector.interval = (cfg and cfg.Intervals and cfg.Intervals[DetectorName]) or Detector.interval

    Log(("[%s Detector] Initialized. Interval: %dms. Note: Detection relies on server-side position validation.^7"):format(DetectorName, Detector.interval), 2)
    return true
end

--[[
    Start Function
    Called by the DetectorRegistry to activate the detector.
]]
function Detector.Start()
    if Detector.active then return false end -- Already active
    Log(("[%s Detector] Starting checks..."):format(DetectorName), 3)
    Detector.active = true
    Detector.lastCheck = 0
    return true -- Indicate successful start
end

--[[
    Stop Function
    Called by the DetectorRegistry to deactivate the detector.
]]
function Detector.Stop()
    if not Detector.active then return false end -- Already stopped
    Log(("[%s Detector] Stopping checks..."):format(DetectorName), 3)
    Detector.active = false
    return true -- Indicate successful stop signal
end

--[[
    Core Check Function
    Called periodically by the DetectorRegistry's managed thread.
    Performs local speed checks for vehicles and players on foot.
    NOTE: Does NOT report cheats; relies on server-side validation of position updates.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available.
    if not NexusGuard then
        -- print(("^1[NexusGuard:%s] Error: NexusGuard instance not available in Check function.^7"):format(DetectorName))
        return true -- Skip check if core instance is missing
    end

    -- Access config thresholds via the stored NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Multiplier applied to a vehicle's max speed to get the threshold.
    local speedThresholdMultiplier = (cfg and cfg.Thresholds and cfg.Thresholds.speedHackMultiplier) or 1.3
    -- Base speed threshold for players on foot (m/s). Could be configurable.
    local onFootSpeedThreshold = (cfg and cfg.Thresholds and cfg.Thresholds.onFootSpeedThreshold) or 10.0

    local playerPed = PlayerPedId()

    -- Basic safety check.
    if not DoesEntityExist(playerPed) then return true end

    local vehicle = GetVehiclePedIsIn(playerPed, false)

    -- Check Vehicle Speed
    if vehicle ~= 0 then
        local currentSpeed = GetEntitySpeed(vehicle)
        local vehicleModel = GetEntityModel(vehicle)
        -- Get the theoretical maximum speed for this vehicle model.
        local maxModelSpeed = GetVehicleModelMaxSpeed(vehicleModel)
        local vehicleThreshold = maxModelSpeed * speedThresholdMultiplier

        -- Check if current speed significantly exceeds the model's max speed * multiplier.
        -- Check maxModelSpeed > 0.1 to avoid issues with stationary/invalid models.
        if maxModelSpeed > 0.1 and currentSpeed > vehicleThreshold then
            -- Log locally if needed for debugging, but DO NOT report. Server validation is key.
            -- Log(("[%s Detector] Client detected vehicle speed (%.1f km/h) potentially exceeds threshold (%.1f km/h) for model %d."):format(
            --     DetectorName, currentSpeed * 3.6, vehicleThreshold * 3.6, vehicleModel
            -- ), 3)
        end
    -- Check On-Foot Speed
    else
        local currentSpeed = GetEntitySpeed(playerPed)
        -- Check if on-foot speed exceeds threshold, excluding legitimate high-speed states.
        if currentSpeed > onFootSpeedThreshold and
           not IsPedInParachuteFreeFall(playerPed) and
           not IsPedRagdoll(playerPed) and
           not IsPedFalling(playerPed) and
           not IsPedJumping(playerPed) -- Added jump check for completeness
        then
            -- Log locally if needed for debugging, but DO NOT report. Server validation is key.
            -- Log(("[%s Detector] Client detected on-foot speed (%.1f km/h) potentially exceeds threshold (%.1f km/h)."):format(
            --     DetectorName, currentSpeed * 3.6, onFootSpeedThreshold * 3.6
            -- ), 3)
        end
    end

    -- No NexusGuard:ReportCheat calls are made from this detector anymore.
    -- Server-side position validation in `server/modules/detections.lua` handles actual speed hack detection.
    return true -- Indicate check cycle completed.
end

--[[
    (Optional) GetStatus Function
    Provides current status information for this detector.
    @return (table): Status details.
]]
function Detector.GetStatus()
    return {
        active = Detector.active,
        lastCheck = Detector.lastCheck,
        interval = Detector.interval
        -- Add any speedhack-specific state if needed in the future
    }
end

-- Return the Detector table for the registry.
return Detector
