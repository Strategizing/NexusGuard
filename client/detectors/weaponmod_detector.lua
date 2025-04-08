--[[
    NexusGuard Weapon Modification Detector (client/detectors/weaponmod_detector.lua)

    Purpose:
    - Monitors the player's currently equipped weapon for potential modifications
      to its damage output or clip size.
    - Compares current weapon stats against a baseline established during a short
      "learning phase" or potentially unreliable default values from natives.

    Note on Reporting & Reliability:
    - Client-side weapon stat natives (`GetWeaponDamage`, `GetWeaponClipSize`) can often
      be hooked or return manipulated values, making client-side detection unreliable.
    - Direct reporting (`NexusGuard:ReportCheat`) based on these checks has been REMOVED.
    - The primary validation should occur server-side. This detector *should* trigger the
      `NEXUSGUARD_WEAPON_CHECK` event (defined in `shared/event_registry.lua`) periodically,
      sending the current weapon hash and clip size to the server (`server/modules/detections.lua`)
      for comparison against configured, authoritative values (`Config.WeaponBaseClipSize`).
      (Currently, this detector doesn't explicitly trigger that event; `client_main.lua` might need adjustment
       or this detector needs modification to send the event instead of just performing local checks).
    - The checks remain here mainly for potential local logging or as a reference.
]]

local DetectorName = "weaponModification" -- Unique key for this detector (matches Config.Detectors key)
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 3000,    -- Default check interval (ms). Overridden by config.
    lastCheck = 0,      -- Timestamp of the last check.
    state = {           -- Local state to store baseline weapon stats.
        weaponStats = {} -- Key: weaponHash, Value: { baseDamage, baseClipSize, firstSeen, samples }
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
    Detector.interval = (cfg and cfg.Intervals and cfg.Intervals[DetectorName]) or Detector.interval

    Log(("[%s Detector] Initialized. Interval: %dms. Note: Detection relies on server-side validation.^7"):format(DetectorName, Detector.interval), 2)
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
    -- Clear previous weapon stats cache on start? Optional.
    -- Detector.state.weaponStats = {}
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
    Checks current weapon's damage and clip size against a baseline.
    NOTE: Does NOT report cheats; relies on server-side validation via NEXUSGUARD_WEAPON_CHECK event.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available.
    if not NexusGuard then return true end -- Skip check if core instance is missing.

    -- Access config thresholds via the stored NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Multiplier for damage check (e.g., 1.5 allows 50% increase over baseline).
    local damageThresholdMultiplier = (cfg and cfg.Thresholds and cfg.Thresholds.weaponDamageMultiplier) or 1.5
    -- Multiplier for clip size check (e.g., 2.0 allows double the baseline clip size). Consider making configurable.
    local clipSizeThresholdMultiplier = (cfg and cfg.Thresholds and cfg.Thresholds.weaponClipMultiplier) or 2.0

    local playerPed = PlayerPedId()

    -- Basic safety check.
    if not DoesEntityExist(playerPed) then return true end

    local currentWeaponHash = GetSelectedPedWeapon(playerPed)

    -- Only perform checks if the player has a weapon equipped (i.e., not unarmed).
    if currentWeaponHash ~= GetHashKey("WEAPON_UNARMED") then

        -- 1. Get Current Weapon Stats using Natives
        -- WARNING: These natives might return modified values if the client is cheating.
        local currentDamage = GetWeaponDamage(currentWeaponHash)
        local currentClipSize = GetMaxAmmoInClip(playerPed, currentWeaponHash, true) -- Use GetMaxAmmoInClip for current capacity

        -- 2. Attempt to Get Default/Baseline Stats
        -- Getting reliable default stats client-side is difficult.
        -- `GetWeaponDamage(hash, true)` is documented but might not work as expected.
        -- `GetWeaponClipSize(hash)` gets the *default* clip size for the weapon type.
        local defaultDamage = GetWeaponDamage(currentWeaponHash, true) -- Attempt to get default damage (reliability varies).
        local defaultClipSize = GetWeaponClipSize(currentWeaponHash) -- Get default clip size for this weapon type.

        -- 3. Initialize or Update Baseline in Local State
        -- If this weapon hasn't been seen before, store its initial stats as a baseline.
        if not Detector.state.weaponStats[currentWeaponHash] then
            Detector.state.weaponStats[currentWeaponHash] = {
                -- Use the potentially unreliable default native result if available, otherwise use the first value seen.
                baseDamage = (defaultDamage and defaultDamage > 0) and defaultDamage or currentDamage,
                baseClipSize = (defaultClipSize and defaultClipSize > 0) and defaultClipSize or currentClipSize,
                firstSeen = GetGameTimer(),
                samples = 1
            }
            -- Log(("[%s Detector] Initial stats for %u: Dmg=%.2f, Clip=%d"):format(
            --     DetectorName, currentWeaponHash, Detector.state.weaponStats[currentWeaponHash].baseDamage, Detector.state.weaponStats[currentWeaponHash].baseClipSize
            -- ), 4) -- Debug log
            return true -- Don't perform checks on the very first sample.
        end

        local storedStats = Detector.state.weaponStats[currentWeaponHash]

        -- 4. Learning Phase (Optional): Wait for a few samples before starting checks.
        local learningDuration = 10000 -- ms (e.g., 10 seconds)
        local requiredSamples = 3
        if GetGameTimer() - storedStats.firstSeen < learningDuration and storedStats.samples < requiredSamples then
            storedStats.samples = storedStats.samples + 1
            -- Potentially update baseline during learning if default values were bad and current values seem stable.
            -- (This logic could be refined or removed depending on trust in initial values).
            -- if not defaultDamage and currentDamage ~= storedStats.baseDamage then storedStats.baseDamage = currentDamage end
            -- if not defaultClipSize and currentClipSize ~= storedStats.baseClipSize then storedStats.baseClipSize = currentClipSize end
            return true -- Continue learning phase.
        end

        -- 5. Perform Client-Side Checks (Primarily for logging/reference, NOT reporting)

        -- Damage Check: Compare current damage to baseline * multiplier.
        if storedStats.baseDamage > 0 and currentDamage > (storedStats.baseDamage * damageThresholdMultiplier) then
            local details = {
                type = "damage", weaponHash = currentWeaponHash, detectedValue = currentDamage,
                baselineValue = storedStats.baseDamage, clientThreshold = damageThresholdMultiplier
            }
            -- Log locally if needed, but DO NOT report. Server validation is required.
            -- Log(("[%s Detector] Client detected potential damage mod: %.2f > %.2f * %.1f"):format(
            --     DetectorName, currentDamage, storedStats.baseDamage, damageThresholdMultiplier
            -- ), 2)
            -- Reporting removed: NexusGuard:ReportCheat(DetectorName, details)
        end

        -- Clip Size Check: Compare current clip size to baseline * multiplier.
        if storedStats.baseClipSize > 0 and currentClipSize > (storedStats.baseClipSize * clipSizeThresholdMultiplier) then
             local details = {
                type = "clipSize", weaponHash = currentWeaponHash, detectedValue = currentClipSize,
                baselineValue = storedStats.baseClipSize, clientThreshold = clipSizeThresholdMultiplier
            }
             -- Log locally if needed, but DO NOT report. Server validation via NEXUSGUARD_WEAPON_CHECK is required.
             -- Log(("[%s Detector] Client detected potential clip size mod: %d > %d * %.1f"):format(
             --    DetectorName, currentClipSize, storedStats.baseClipSize, clipSizeThresholdMultiplier
             -- ), 2)
             -- Reporting removed: NexusGuard:ReportCheat(DetectorName, details)

             -- TODO: This detector should ideally trigger the 'NEXUSGUARD_WEAPON_CHECK' event here,
             -- sending `currentWeaponHash` and `currentClipSize` to the server for validation
             -- against `Config.WeaponBaseClipSize`. Example:
             -- if LocalEventRegistry then -- Assuming EventRegistry is passed during Initialize
             --    LocalEventRegistry:TriggerServerEvent('NEXUSGUARD_WEAPON_CHECK', currentWeaponHash, currentClipSize, NexusGuard.securityToken)
             -- end
        end
    end

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
        -- Could add details from Detector.state.weaponStats if needed for debugging.
    }
end

-- Return the Detector table for the registry.
return Detector
