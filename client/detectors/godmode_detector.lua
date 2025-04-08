local DetectorName = "godMode"
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 5000, -- Default, will be overridden by config if available
    lastCheck = 0,
    state = { -- Local state for this detector if needed
        health = 100
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
    if cfg and cfg.Detectors and cfg.Detectors.godMode and NexusGuard.intervals and NexusGuard.intervals.godMode then
        Detector.interval = NexusGuard.intervals.godMode
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
    local healthRegenThreshold = (cfg and cfg.Thresholds and cfg.Thresholds.healthRegenerationRate) or 2.0

    local ped = PlayerPedId()
    local player = PlayerId()

    -- Safety checks
    if not DoesEntityExist(ped) then return end

    local health = GetEntityHealth(ped)
    local maxHealth = GetPedMaxHealth(ped) -- Use GetPedMaxHealth for accuracy
    local armor = GetPedArmour(ped)

    -- Check for invincibility flag (Client-side check for reference/logging, no report)
    if GetPlayerInvincible(player) then
        -- NOTE: As per Guideline 23, client-side reporting for invincibility flag is removed.
        -- Server can perform this check if needed during health update validation.
        -- if NexusGuard and NexusGuard.ReportCheat then
        --     local details = { reason = "Player invincibility flag enabled" }
        --     NexusGuard:ReportCheat(DetectorName, details)
        -- else
        --     print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: Player invincibility flag enabled (NexusGuard instance unavailable)")
        -- end
    end

    -- Check for abnormal health values (Client-side check for reference/logging, no report)
    if health > maxHealth and health > 200 then -- Keep the > 200 check as a sanity threshold
         -- print("^3[NexusGuard:" .. DetectorName .. "]^7 Client detected abnormal health: " .. health .. "/" .. maxHealth)
         -- No ReportCheat call here, server handles via NEXUSGUARD_HEALTH_UPDATE
    end

    -- Track health regeneration (Client-side check for reference/logging, no report)
    if Detector.state.health < health and health <= maxHealth then -- Only track regeneration up to max health
        local healthIncrease = health - Detector.state.health
        if healthIncrease > healthRegenThreshold then
             -- print("^3[NexusGuard:" .. DetectorName .. "]^7 Client detected abnormal health regeneration: +" .. string.format("%.1f", healthIncrease) .. " HP")
             -- No ReportCheat call here, server handles via NEXUSGUARD_HEALTH_UPDATE
        end
    end

    -- Check for armor anomalies (Client-side check for reference/logging, no report)
    if armor > 100 then -- Standard max armor is 100
         -- print("^3[NexusGuard:" .. DetectorName .. "]^7 Client detected abnormal armor value: " .. armor)
         -- No ReportCheat call here, server handles via NEXUSGUARD_HEALTH_UPDATE
    end -- End of armor check <<<< This end closes the if armor > 100 block

    -- Update local state
    Detector.state.health = health
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
-- We just need to register the detector module.
Citizen.CreateThread(function()
    -- Wait for DetectorRegistry to be available
    while not _G.DetectorRegistry do
        Citizen.Wait(500)
    end
    _G.DetectorRegistry.Register(DetectorName, Detector)
    -- Initialization and starting is now handled by the registry calling the methods on the registered module
end)
