local DetectorName = "speedHack"
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 2000, -- Default, will be overridden by config if available
    lastCheck = 0
}

-- Initialize the detector (called once by the registry)
-- Receives the NexusGuard instance from the registry
function Detector.Initialize(nexusGuardInstance)
    if not nexusGuardInstance then
        print("^1[NexusGuard:" .. DetectorName .. "] CRITICAL: Failed to receive NexusGuard instance during initialization.^7")
        return false
    end
    NexusGuard = nexusGuardInstance -- Store the instance locally

    -- Update interval from global config if available
    -- Access Config via the passed instance
    local cfg = NexusGuard.Config
    if cfg and cfg.Detectors and cfg.Detectors.speedHack and NexusGuard.intervals and NexusGuard.intervals.speedHack then
        Detector.interval = NexusGuard.intervals.speedHack
    end
    print("^2[NexusGuard:" .. DetectorName .. "]^7 Initialized with interval: " .. Detector.interval .. "ms")
    return true
end

-- Start the detector (Called by Registry)
-- The registry now handles the thread creation loop.
function Detector.Start()
    if Detector.active then return false end -- Already active
    Detector.active = true
    -- No need to create thread here, registry does it.
    -- Print statement moved to registry for consistency.
    return true -- Indicate success
end

-- Stop the detector (Called by Registry)
-- The registry relies on this setting the active flag to false.
function Detector.Stop()
    if not Detector.active then return false end -- Already stopped
    Detector.active = false
    -- Print statement moved to registry for consistency.
    return true -- Indicate success
end

-- Check for violations (Moved logic from client_main.lua)
-- NOTE: As per Prompt 21, this detector now primarily exists to potentially feed
-- client-side speed data if needed elsewhere, but the actual cheat *detection*
-- and reporting is handled server-side via the periodic position updates.
function Detector.Check()
    -- Cache config values locally
    -- Access Config via the stored NexusGuard instance
    local cfg = NexusGuard.Config
    local speedThresholdMultiplier = (cfg and cfg.Thresholds and cfg.Thresholds.speedHackMultiplier) or 1.3
    local onFootSpeedThreshold = 10.0 -- Base threshold for on-foot speed, could also be made configurable

    local ped = PlayerPedId()

    -- Safety checks
    if not DoesEntityExist(ped) then return end

    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 then
        -- Vehicle speed check (Client-side check for reference/logging, no report)
        local speed = GetEntitySpeed(vehicle)
        local model = GetEntityModel(vehicle)
        local maxSpeed = GetVehicleModelMaxSpeed(model)

        if maxSpeed > 0.1 and speed > (maxSpeed * speedThresholdMultiplier) then
            -- Log locally if needed for debugging, but don't report to server
            -- print("^3[NexusGuard:" .. DetectorName .. "]^7 Client detected vehicle speed potentially abnormal: " .. math.floor(speed * 3.6) .. " km/h")
        end
    else
        -- On-foot speed check (Client-side check for reference/logging, no report)
        local speed = GetEntitySpeed(ped)
        if speed > onFootSpeedThreshold and not IsPedInParachuteFreeFall(ped) and not IsPedRagdoll(ped) and not IsPedFalling(ped) then
            -- Log locally if needed for debugging, but don't report to server
            -- print("^3[NexusGuard:" .. DetectorName .. "]^7 Client detected on-foot speed potentially abnormal: " .. math.floor(speed * 3.6) .. " km/h")
        end
    end
    -- No NexusGuard:ReportCheat calls here anymore for speedHack type
end -- End of Detector.Check function

-- Get detector status
function Detector.GetStatus()
    return {
        active = Detector.active,
        lastCheck = Detector.lastCheck,
        interval = Detector.interval
    }
end

-- Register with the detector system
-- NOTE: The registry now handles calling Initialize and Start based on config.
Citizen.CreateThread(function()
    -- Wait for DetectorRegistry to be available
    while not _G.DetectorRegistry do
        Citizen.Wait(500)
    end
    _G.DetectorRegistry.Register(DetectorName, Detector)
    -- Initialization and starting is now handled by the registry calling the methods on the registered module
end)
