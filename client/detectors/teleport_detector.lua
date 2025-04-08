local DetectorName = "teleporting" -- Match the key in Config.Detectors
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 1000, -- Default, will be overridden by config if available
    lastCheck = 0,
    state = { -- Local state for position tracking
        position = nil, -- Initialize as nil
        lastPositionUpdate = 0
    }
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
    if cfg and cfg.Detectors and cfg.Detectors.teleporting and NexusGuard.intervals and NexusGuard.intervals.teleport then
        Detector.interval = NexusGuard.intervals.teleport
    end
    -- Initialize position state
    local initialPed = PlayerPedId()
    if DoesEntityExist(initialPed) then
        Detector.state.position = GetEntityCoords(initialPed)
    else
        Detector.state.position = vector3(0,0,0) -- Fallback if ped doesn't exist yet
    end
    Detector.state.lastPositionUpdate = GetGameTimer()
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
-- NOTE: As per Prompt 22, this detector now primarily exists to potentially feed
-- client-side position data if needed elsewhere, but the actual cheat *detection*
-- and reporting is handled server-side via the periodic position updates.
function Detector.Check()
    -- Cache config values locally
    -- Access Config via the stored NexusGuard instance
    local cfg = NexusGuard.Config
    local teleportThreshold = (cfg and cfg.Thresholds and cfg.Thresholds.teleportDistance) or 100.0
    local timeDiffThreshold = 1000 -- ms, time window to check for large distance change

    local ped = PlayerPedId()

    -- Safety checks
    if not DoesEntityExist(ped) then return end

    local currentPos = GetEntityCoords(ped)
    local lastPos = Detector.state.position
    local currentTime = GetGameTimer()

    -- Only check if we have a valid previous position
    if lastPos and #(lastPos) > 0 then -- Check if lastPos is a valid vector
        local distance = #(currentPos - lastPos)
        local timeDiff = currentTime - Detector.state.lastPositionUpdate

        -- Check if player moved significantly in a short time without being in a vehicle
        -- Added check for timeDiff > 0 to avoid division by zero or issues on first check
        if timeDiff > 0 and timeDiff < timeDiffThreshold and distance > teleportThreshold then
            -- Check if player is in a vehicle (teleporting on foot is more suspicious)
            if GetVehiclePedIsIn(ped, false) == 0 then
                -- Ignore legitimate teleports (game loading screens, player switching, screen fades)
                if not IsPlayerSwitchInProgress() and not IsScreenFadedOut() and not IsScreenFadingOut() and not IsScreenFadingIn() then
                    -- NOTE: As per Prompt 22, client-side reporting for teleport is removed. Server-side validation handles this now.
                    -- if NexusGuard and NexusGuard.ReportCheat then
                    --     NexusGuard:ReportCheat(DetectorName, "Possible teleport detected: " .. math.floor(distance) .. " meters in " .. timeDiff .. "ms")
                    -- else
                    --     print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: Possible teleport detected: " .. math.floor(distance) .. " meters in " .. timeDiff .. "ms (NexusGuard instance unavailable)")
                    -- end
                end
            end
        end
    end -- End if lastPos exists

    -- Update player state regardless of detection
    Detector.state.position = currentPos
    Detector.state.lastPositionUpdate = currentTime
end


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
