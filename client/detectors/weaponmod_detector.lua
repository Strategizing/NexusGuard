local DetectorName = "weaponModification" -- Match the key in Config.Detectors
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 3000, -- Default, will be overridden by config if available
    lastCheck = 0,
    state = { -- Local state for weapon stats
        weaponStats = {}
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
    if cfg and cfg.Detectors and cfg.Detectors.weaponModification and NexusGuard.intervals and NexusGuard.intervals.weaponModification then
        Detector.interval = NexusGuard.intervals.weaponModification
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
    -- Ensure NexusGuard instance is available
    if not NexusGuard then
        print("^1[NexusGuard:" .. DetectorName .. "] Error: NexusGuard instance not available in Check function.^7")
        return
    end

    -- Cache config values locally
    -- Access Config via the stored NexusGuard instance
    local cfg = NexusGuard.Config
    local damageThresholdMultiplier = (cfg and cfg.Thresholds and cfg.Thresholds.weaponDamageMultiplier) or 1.5
    local clipSizeThresholdMultiplier = 2.0 -- Example: Allow double clip size, make configurable if needed

    local ped = PlayerPedId()

    -- Safety checks
    if not DoesEntityExist(ped) then return end

    local currentWeaponHash = GetSelectedPedWeapon(ped)

    -- Only check if player has a weapon equipped (excluding unarmed)
    if currentWeaponHash ~= GetHashKey("WEAPON_UNARMED") then
        -- Get current weapon stats (use natives that return default values if modified)
        -- Note: Relying solely on client-side natives for default values can be bypassed.
        -- A more robust check would involve server-side validation or comparing against known defaults.
        local currentDamage = GetWeaponDamage(currentWeaponHash) -- This might return the modified value
        local currentClipSize = GetWeaponClipSize(currentWeaponHash) -- This might return the modified value

        -- Get default stats (more reliable if available, otherwise use first seen)
        -- Placeholder: Ideally, load default weapon stats from a config or server event
        local defaultDamage = GetWeaponDamage(currentWeaponHash, true) -- Attempt to get default, may not work reliably
        local defaultClipSize = GetWeaponClipSize(currentWeaponHash) -- Get default clip size (only takes weaponHash)

        -- Initialize weapon stats in local state if not yet recorded
        if not Detector.state.weaponStats[currentWeaponHash] then
            Detector.state.weaponStats[currentWeaponHash] = {
                -- Store first seen values as a baseline if defaults aren't reliable
                baseDamage = defaultDamage or currentDamage,
                baseClipSize = defaultClipSize or currentClipSize,
                firstSeen = GetGameTimer(),
                samples = 1
            }
            -- print("^3[DEBUG:"..DetectorName.."]^7 Initial stats for " .. currentWeaponHash .. ": Dmg=" .. Detector.state.weaponStats[currentWeaponHash].baseDamage .. ", Clip=" .. Detector.state.weaponStats[currentWeaponHash].baseClipSize)
            return -- Don't check on the very first sample
        end

        local storedStats = Detector.state.weaponStats[currentWeaponHash]

        -- Allow a brief learning phase or require multiple samples
        if GetGameTimer() - storedStats.firstSeen < 10000 and storedStats.samples < 3 then
            storedStats.samples = storedStats.samples + 1
            -- Update baseline if defaults were initially unavailable and now seem stable
            if not defaultDamage and currentDamage ~= storedStats.baseDamage then storedStats.baseDamage = currentDamage end
            if not defaultClipSize and currentClipSize ~= storedStats.baseClipSize then storedStats.baseClipSize = currentClipSize end
            return
        end

        -- Compare current damage against the stored baseline/default
        if storedStats.baseDamage > 0 and currentDamage > (storedStats.baseDamage * damageThresholdMultiplier) then
            local details = {
                type = "damage",
                weaponHash = currentWeaponHash,
                detectedValue = currentDamage,
                baselineValue = storedStats.baseDamage,
                clientThreshold = damageThresholdMultiplier
            }
            -- Use the stored NexusGuard instance to report
            -- NOTE: Client-side reporting for damage is removed. Server-side validation should handle this.
            -- if NexusGuard and NexusGuard.ReportCheat then
            --     NexusGuard:ReportCheat(DetectorName, details)
            -- else
            --     print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation (Damage): " .. json.encode(details) .. " (NexusGuard instance unavailable)")
            -- end
        end

        -- Compare current clip size against the stored baseline/default
        if storedStats.baseClipSize > 0 and currentClipSize > (storedStats.baseClipSize * clipSizeThresholdMultiplier) then
             local details = {
                type = "clipSize",
                weaponHash = currentWeaponHash,
                detectedValue = currentClipSize,
                baselineValue = storedStats.baseClipSize,
                clientThreshold = clipSizeThresholdMultiplier
            }
             -- Use the stored NexusGuard instance to report
             -- NOTE: As per Prompt 24, client-side reporting for clip size is removed. Server-side validation should handle this if implemented.
             -- if NexusGuard and NexusGuard.ReportCheat then
             --    NexusGuard:ReportCheat(DetectorName, details)
             -- else
             --    print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation (Clip Size): " .. json.encode(details) .. " (NexusGuard instance unavailable)")
             -- end
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

-- Registration is now handled centrally by client_main.lua
-- The self-registration thread below has been removed.
