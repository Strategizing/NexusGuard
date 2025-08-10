--[[
    NexusGuard God Mode Detector (client/detectors/godmode_detector.lua)

    Purpose:
    - Performs client-side checks related to player invincibility, health, and armor levels.
    - Primarily acts as a local monitor; relies on server-side validation of data sent via
      the `NEXUSGUARD_HEALTH_UPDATE` event for actual cheat confirmation and action.

    Note on Reporting:
    - This detector previously used `NexusGuard:ReportCheat`. However, client-side health/armor values
      can be easily spoofed. Therefore, reporting has been removed.
    - The server (`server/modules/detections.lua`) now performs validation based on the periodic
      health/armor updates sent by `client_main.lua` (`SendHealthUpdate` function).
    - The checks remain here mainly for potential local logging (currently commented out) or future
      client-side heuristics if needed, but they do not trigger direct anti-cheat actions.
]]

local DetectorName = "godMode" -- Unique key for this detector
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 5000,    -- Default check interval (ms). Overridden by config.
    lastCheck = 0,      -- Timestamp of the last check.
    state = {           -- Local state specific to this detector.
        lastHealth = 100 -- Store the last known health value for regen checks.
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
    -- Use configured interval if found, otherwise keep the default.
    Detector.interval = (cfg and cfg.Intervals and cfg.Intervals[DetectorName]) or Detector.interval

    -- Log initialization status and interval.
    -- Note: The 'active' status is set by the Start function called by the registry.
    Log(("[%s Detector] Initialized. Interval: %dms"):format(DetectorName, Detector.interval), 3)
    return true
end

--[[
    Start Function (Optional but Recommended)
    Called by the DetectorRegistry to activate the detector.
    Sets the `active` flag to true, allowing the check loop (managed by the registry) to run.
]]
function Detector.Start()
    if Detector.active then return false end -- Already active
    Log(("[%s Detector] Starting checks..."):format(DetectorName), 3)
    Detector.active = true
    Detector.lastCheck = 0 -- Reset last check time on start
    -- Initialize state if needed
    local playerPed = PlayerPedId()
    if DoesEntityExist(playerPed) then Detector.state.lastHealth = GetEntityHealth(playerPed) end
    return true -- Indicate successful start
end

--[[
    Stop Function (Optional but Recommended)
    Called by the DetectorRegistry to deactivate the detector.
    Sets the `active` flag to false, causing the check loop to terminate.
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
    Performs local checks for invincibility, abnormal health/armor, and regeneration.
    NOTE: Currently does NOT report cheats; relies on server-side validation of health updates.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available (should always be if initialized correctly).
    if not NexusGuard then
        print(("^1[NexusGuard:%s] Error: NexusGuard instance not available in Check function.^7"):format(DetectorName))
        return true -- Return true to avoid rapid re-checks on error
    end

    -- Access config thresholds via the stored NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Threshold for client-side regen logging (server has its own threshold).
    local healthRegenThreshold = (cfg and cfg.Thresholds and cfg.Thresholds.healthRegenerationRate) or 2.0
    -- Max expected health (server also validates this).
    local maxExpectedHealth = (cfg and cfg.Thresholds and cfg.Thresholds.maxHealthThreshold) or 200 -- Allow slightly above 100 base
    -- Max expected armor (server also validates this).
    local maxExpectedArmor = (cfg and cfg.Thresholds and cfg.Thresholds.maxArmorThreshold) or 100

    local player = PlayerId()
    local playerPed = PlayerPedId()

    -- Basic safety check.
    if not DoesEntityExist(playerPed) then return true end -- Skip check if ped doesn't exist.

    local currentHealth = GetEntityHealth(playerPed)
    local currentMaxHealth = GetPedMaxHealth(playerPed) -- Get the ped's actual max health native.
    local currentArmor = GetPedArmour(playerPed)

    -- 1. Check Invincibility Flag (GetPlayerInvincible)
    -- This native can sometimes be unreliable or bypassed. Server-side checks are more robust.
    -- No ReportCheat call here. Server can perform its own checks if desired.
    if GetPlayerInvincible(player) then
        -- Log(("[%s Detector] Client detected player invincibility flag is ON."):format(DetectorName), 3)
    end

    -- 2. Check for Abnormal Health Values (Exceeding Max Health)
    -- Compare current health against the ped's max health and a configured sanity threshold.
    -- No ReportCheat call here; server validates health updates.
    if currentHealth > currentMaxHealth and currentHealth > maxExpectedHealth then
        -- Log(("[%s Detector] Client detected abnormal health: %d / %d (Max Expected: %d)"):format(DetectorName, currentHealth, currentMaxHealth, maxExpectedHealth), 3)
    end

    -- 3. Track Health Regeneration Rate (Client-side heuristic)
    -- Check if health increased significantly since the last check.
    -- No ReportCheat call here; server validates health updates and regen rates.
    if Detector.state.lastHealth < currentHealth and currentHealth <= currentMaxHealth then -- Only check regen up to max health.
        local healthIncrease = currentHealth - Detector.state.lastHealth
        -- Check against a local threshold (primarily for logging/debugging).
        if healthIncrease > healthRegenThreshold then
             -- Log(("[%s Detector] Client detected high health regeneration: +%.1f HP"):format(DetectorName, healthIncrease), 3)
        end
    end

    -- 4. Check for Abnormal Armor Values
    -- Check if armor exceeds the standard maximum (100).
    -- No ReportCheat call here; server validates armor updates.
    if currentArmor > maxExpectedArmor then
         -- Log(("[%s Detector] Client detected abnormal armor value: %d (Max Expected: %d)"):format(DetectorName, currentArmor, maxExpectedArmor), 3)
    end

    -- Update the detector's local state for the next check.
    Detector.state.lastHealth = currentHealth

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
        interval = Detector.interval,
        lastHealth = Detector.state.lastHealth
    }
end

-- Return the Detector table for the registry.
return Detector
