local DetectorName = "noclip" -- Match the key in Config.Detectors
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 1000, -- Default, will be overridden by config if available
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
    if cfg and cfg.Detectors and cfg.Detectors.noclip and NexusGuard.intervals and NexusGuard.intervals.noclip then
        Detector.interval = NexusGuard.intervals.noclip
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
function Detector.Check()
    -- Cache config values locally
    -- Access Config via the stored NexusGuard instance
    local cfg = NexusGuard.Config
    local noclipTolerance = (cfg and cfg.Thresholds and cfg.Thresholds.noclipTolerance) or 3.0

    local ped = PlayerPedId()

    -- Safety checks
    if not DoesEntityExist(ped) then return end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return end -- Ignore if in vehicle
    if IsEntityDead(ped) then return end
    if IsPedInParachuteFreeFall(ped) then return end -- Ignore during parachute
    if IsPedFalling(ped) then return end -- Ignore if falling
    if IsPedJumping(ped) then return end -- Ignore if jumping
    if IsPedClimbing(ped) then return end -- Ignore if climbing
    if IsPedVaulting(ped) then return end -- Ignore if vaulting
    if IsPedDiving(ped) then return end -- Ignore if diving
    if IsPedGettingUp(ped) then return end -- Ignore if getting up
    if IsPedRagdoll(ped) then return end -- Ignore if ragdolling

    local pos = GetEntityCoords(ped)

    -- Ensure valid position
    if not pos or not pos.x then return end

    -- Get ground Z coordinate; use the second parameter `true` for water check as well? Maybe not needed.
    local foundGround, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z, false)

    -- If ground wasn't found nearby, it might indicate being very high up or out of bounds, potentially noclip
    -- However, this can also happen legitimately (e.g., flying high). Need more checks.

    if foundGround then
        local distanceToGround = pos.z - groundZ

        -- Check if player is floating significantly above ground
        if distanceToGround > noclipTolerance then
            -- Check if player is in a legitimate state that might cause floating (already checked many above)
            -- Additional checks: Swimming? Specific animations? (Ejecting check removed as native doesn't exist and other checks cover falling/parachute)
            if not IsPedSwimming(ped) then

                -- Get vertical velocity to determine if player is stationary or moving slowly upwards/downwards in air
                local _, _, zVelocity = table.unpack(GetEntityVelocity(ped)) -- Use table.unpack for clarity
                zVelocity = zVelocity or 0

                -- If player is floating relatively still vertically (not actively falling/rising from jump/explosion)
                if math.abs(zVelocity) < 0.5 then -- Increased tolerance slightly from 0.1
                    -- Check collision status as an additional indicator
                    local collisionDisabled = GetEntityCollisionDisabled(ped)
                    local reportReason = "Floating " .. string.format("%.1f", distanceToGround) .. " units above ground with low vertical velocity (" .. string.format("%.2f", zVelocity) .. ")"
                    if collisionDisabled then
                        reportReason = reportReason .. " and collision disabled"
                    end

                    -- Use the stored NexusGuard instance to report
                    -- NOTE: As per Guideline 31 and the shift towards server authority,
                    -- client-side reporting for noclip is removed. Server-side validation
                    -- in the position update handler should handle this detection.
                    -- if NexusGuard and NexusGuard.ReportCheat then
                    --     local details = {
                    --         reason = reportReason,
                    --         distance = distanceToGround,
                    --         velocityZ = zVelocity,
                    --         collision = collisionDisabled
                    --     }
                    --     NexusGuard:ReportCheat(DetectorName, details)
                    -- else
                    --      print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: " .. reportReason .. " (NexusGuard instance unavailable)")
                    -- end
                end
            end
        end
    else
        -- Ground not found - could be very high up (plane, heli) or potential noclip out of bounds.
        -- Need more context here to avoid false positives. Check altitude, vehicle status again.
        if GetVehiclePedIsIn(ped, false) == 0 and pos.z > 1000 then -- Arbitrary high altitude check for on-foot
             -- Maybe add checks for specific interiors where ground Z might fail?
             -- For now, log potentially suspicious high altitude without ground
             -- print("^3[NexusGuard:" .. DetectorName .. "]^7 Warning: Ground Z not found for player at high altitude Z=" .. pos.z)
        end
    end
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
