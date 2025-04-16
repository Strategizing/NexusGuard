--[[
    NexusGuard Teleport Detector (client/detectors/teleport_detector.lua)

    Purpose:
    - Performs basic client-side checks for large, sudden changes in player position
      over a short time interval, potentially indicating teleportation cheats.
    - Excludes checks when the player is in a vehicle or during screen transitions
      (fades, player switching) which can cause legitimate large position changes.

    Note on Reporting & Reliability:
    - Client-side position data can be manipulated. Direct reporting based solely on this
      client-side check is unreliable and has been REMOVED.
    - The definitive detection of teleportation/speed hacks is performed SERVER-SIDE
      in `server/modules/detections.lua` by analyzing the distance traveled between
      periodic position updates received from the client (`NEXUSGUARD_POSITION_UPDATE` event).
      Server-side checks may also incorporate raycasting for noclip detection.
    - This client-side check remains primarily for potential local logging (currently commented out)
      or as a reference, but it does not trigger anti-cheat actions.
]]

local DetectorName = "teleporting" -- Unique key for this detector (matches Config.Detectors key)
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 1000,    -- Default check interval (ms). Overridden by config.
    lastCheck = 0,      -- Timestamp of the last check.
    state = {           -- Local state for tracking position between checks.
        position = nil, -- Stores the player's position from the previous check. Initialized as nil.
        lastPositionUpdate = 0 -- Timestamp of the last position update in this detector.
    }
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
    -- Note: Config key for interval might be 'teleport' while detector key is 'teleporting'. Ensure consistency or update config.lua.
    Detector.interval = (cfg and cfg.Intervals and cfg.Intervals.teleport) or Detector.interval

    -- Initialize the starting position state.
    local initialPed = PlayerPedId()
    if DoesEntityExist(initialPed) then
        Detector.state.position = GetEntityCoords(initialPed)
    else
        Detector.state.position = vector3(0,0,0) -- Use a default vector if ped doesn't exist yet.
    end
    Detector.state.lastPositionUpdate = GetGameTimer() -- Set initial timestamp.

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
    -- Re-initialize position state on start in case player moved while detector was inactive.
    local playerPed = PlayerPedId()
    if DoesEntityExist(playerPed) then Detector.state.position = GetEntityCoords(playerPed) end
    Detector.state.lastPositionUpdate = GetGameTimer()
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
    Compares current position to the last known position to detect large jumps.
    NOTE: Does NOT report cheats; relies on server-side validation.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available.
    if not NexusGuard then return true end -- Skip check if core instance is missing.

    -- Access config thresholds via the stored NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Max distance allowed to travel within the `timeDiffThreshold`.
    local teleportThreshold = (cfg and cfg.Thresholds and cfg.Thresholds.teleportDistance) or 100.0
    -- Time window (ms) within which the `teleportThreshold` distance check applies.
    local timeDiffThreshold = (cfg and cfg.Thresholds and cfg.Thresholds.teleportTimeThreshold) or 1000

    local playerPed = PlayerPedId()

    -- Basic safety check.
    if not DoesEntityExist(playerPed) then return true end

    local currentPos = GetEntityCoords(playerPed)
    local lastPos = Detector.state.position
    local currentTime = GetGameTimer()

    -- Perform check only if we have a valid position from the previous check.
    if lastPos and #(lastPos) > 0 then -- Ensure lastPos is a valid vector.
        local distance = #(currentPos - lastPos) -- Calculate distance moved since last check.
        local timeDiff = currentTime - Detector.state.lastPositionUpdate -- Time elapsed since last check.

        -- Check for large distance moved within a short time frame.
        -- Ensure timeDiff > 0 to avoid division by zero or issues on the very first check after start.
        if timeDiff > 0 and timeDiff < timeDiffThreshold and distance > teleportThreshold then
            -- Exclude common legitimate scenarios for large position changes.
            local isInVehicle = GetVehiclePedIsIn(playerPed, false) ~= 0
            local isSwitching = IsPlayerSwitchInProgress()
            local isFading = IsScreenFadedOut() or IsScreenFadingOut() or IsScreenFadingIn()

            if not isInVehicle and not isSwitching and not isFading then
                -- Potential teleport detected based on client-side check.
                local reason = ("Moved %.1f meters in %dms while on foot and not fading."):format(distance, timeDiff)
                -- Log(("[%s Detector] Client detected potential teleport: %s"):format(DetectorName, reason), 2) -- Log locally if desired

                -- NOTE: Reporting removed. Server-side position validation is more reliable.
                -- if NexusGuard.ReportCheat then
                --     NexusGuard:ReportCheat(DetectorName, {
                --         reason = reason, distance = distance, timeDiff = timeDiff
                --     })
                -- end
                -- return false -- Indicate suspicion for adaptive timing (optional)
            end
        end
    end

    -- Update the state with the current position and time for the next check.
    Detector.state.position = currentPos
    Detector.state.lastPositionUpdate = currentTime

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
        interval = Detector.interval,
        lastPos = Detector.state.position -- Include last known position if useful
    }
end

-- Return the Detector table for the registry.
return Detector
