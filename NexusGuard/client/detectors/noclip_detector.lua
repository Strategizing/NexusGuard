--[[
    NexusGuard Noclip Detector (client/detectors/noclip_detector.lua)

    Purpose:
    - Attempts to detect noclip cheats by checking the player's vertical distance
      from the ground and their vertical velocity.
    - Excludes various legitimate states where the player might be off the ground
      (in vehicle, falling, jumping, climbing, ragdolling, etc.).

    Note on Reporting & Reliability:
    - This detector previously used `NexusGuard:ReportCheat`. However, client-side position
      and ground checks can be unreliable or bypassed. Reporting has been removed.
    - Server-side validation, particularly using raycasting as implemented in
      `server/modules/detections.lua` (handling `NEXUSGUARD_POSITION_UPDATE`), is the
      more robust method for detecting noclip/teleportation through objects.
    - This client-side check remains as a potential heuristic or for local logging,
      but it does not trigger direct anti-cheat actions. False positives are possible,
      especially with complex map geometry or custom movement mechanics.
]]

local DetectorName = "noclip" -- Unique key for this detector
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 1000,    -- Default check interval (ms). Overridden by config.
    lastCheck = 0       -- Timestamp of the last check.
    -- No specific local state needed for this basic check
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

    Log(("[%s Detector] Initialized. Interval: %dms"):format(DetectorName, Detector.interval), 3)
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
    Checks player's height above ground and vertical velocity, excluding legitimate states.
    NOTE: Does NOT report cheats; relies on server-side validation.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available.
    if not NexusGuard then
        -- print(("^1[NexusGuard:%s] Error: NexusGuard instance not available in Check function.^7"):format(DetectorName))
        return true -- Skip check if core instance is missing
    end

    -- Access config thresholds via the stored NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Tolerance for how far above the ground is considered suspicious when stationary.
    local noclipTolerance = (cfg and cfg.Thresholds and cfg.Thresholds.noclipTolerance) or 3.0

    local playerPed = PlayerPedId()

    -- 1. Exclude Legitimate States: Check various conditions where being off the ground is normal.
    if not DoesEntityExist(playerPed) then return true end -- Ped doesn't exist
    if GetVehiclePedIsIn(playerPed, false) ~= 0 then return true end -- In a vehicle
    if IsEntityDead(playerPed) then return true end -- Dead
    if IsPedInParachuteFreeFall(playerPed) then return true end -- Parachuting
    if IsPedFalling(playerPed) then return true end -- Falling
    if IsPedJumping(playerPed) then return true end -- Jumping
    if IsPedClimbing(playerPed) then return true end -- Climbing
    if IsPedVaulting(playerPed) then return true end -- Vaulting
    if IsPedDiving(playerPed) then return true end -- Diving
    if IsPedGettingUp(playerPed) then return true end -- Getting up from ragdoll
    if IsPedRagdoll(playerPed) then return true end -- Ragdolling
    if IsPedSwimming(playerPed) then return true end -- Swimming

    local currentPos = GetEntityCoords(playerPed)

    -- Ensure position data is valid.
    if not currentPos or not currentPos.x then return true end

    -- 2. Get Ground Z Coordinate: Find the ground height below the player.
    -- The `false` argument means it won't consider water as ground.
    local foundGround, groundZ = GetGroundZFor_3dCoord(currentPos.x, currentPos.y, currentPos.z, false)

    -- 3. Analyze Position Relative to Ground:
    if foundGround then
        local distanceToGround = currentPos.z - groundZ

        -- Check if the player is significantly above the found ground Z.
        if distanceToGround > noclipTolerance then
            -- Player is floating. Check vertical velocity to distinguish from jumping/falling not caught by natives.
            local _, _, zVelocity = GetEntityVelocity(playerPed)
            zVelocity = zVelocity or 0

            -- If vertical velocity is low (i.e., not actively moving up/down significantly), it's suspicious.
            local verticalVelocityThreshold = 0.5 -- Small tolerance for slight vertical movement.
            if math.abs(zVelocity) < verticalVelocityThreshold then
                -- Player is floating relatively still above the ground. This is a strong indicator of noclip.
                local collisionDisabled = GetEntityCollisionDisabled(playerPed) -- Check collision status as extra info.
                local reason = ("Floating %.1f units above ground with low vertical velocity (%.2f). Collision: %s"):format(
                    distanceToGround, zVelocity, tostring(collisionDisabled)
                )
                -- Log(("[%s Detector] Client detected potential noclip: %s"):format(DetectorName, reason), 2) -- Log locally if desired

                -- NOTE: Reporting removed. Server-side position updates + raycasting is preferred.
                -- if NexusGuard.ReportCheat then
                --     NexusGuard:ReportCheat(DetectorName, {
                --         reason = reason, distance = distanceToGround, velocityZ = zVelocity, collision = collisionDisabled
                --     })
                -- end
                -- return 1 -- Indicate suspicion for adaptive timing (optional)
            end
        end
    else
        -- Ground Z not found. This can happen legitimately when very high up (aircraft)
        -- or potentially when noclipping far out of bounds or under the map.
        -- Avoid false positives by adding context checks.
        if GetVehiclePedIsIn(playerPed, false) == 0 and currentPos.z > 1000 then -- Example: Check if on foot and very high altitude.
             -- Log(("[%s Detector] Ground Z not found for player on foot at high altitude (Z=%.1f)."):format(DetectorName, currentPos.z), 3)
        end
        -- Further checks could involve interior checks or distance from known map boundaries.
    end

    return 0 -- Suspicion score (0 = no suspicion)
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
        -- Add any noclip-specific state if needed in the future
    }
end

-- Return the Detector table for the registry.
return Detector
