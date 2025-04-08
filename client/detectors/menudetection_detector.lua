local DetectorName = "menuDetection" -- Match the key in Config.Detectors
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 10000, -- Default, will be overridden by config if available
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
    if cfg and cfg.Detectors and cfg.Detectors.menuDetection and NexusGuard.intervals and NexusGuard.intervals.menuDetection then
        Detector.interval = NexusGuard.intervals.menuDetection
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

-- Check for violations
function Detector.Check()
    -- Basic check for common mod menu key combinations.
    -- WARNING: This method is extremely unreliable and easily bypassed by changing keybinds.
    -- The most effective way to block known menus is by adding their resource names
    -- to the `Config.Features.resourceVerification.blacklist` in config.lua and enabling resource verification.
    -- Relying on keybinds alone is not recommended for serious protection.

    -- Control IDs can be found here: https://docs.fivem.net/docs/game-references/controls/
    local controlsToCheck = {
        -- Example: HOME key (often used with another key) - INPUT_FRONTEND_SOCIAL_CLUB (213)
        { name = "HOME + E", justPressed = 213, pressed = 38 }, -- 38 = INPUT_PICKUP (E)
        -- Example: F5 key (common menu toggle) - INPUT_FRONTEND_PAUSE_ALTERNATE (244)
        { name = "F5", justPressed = 244 },
        -- Example: Numpad * (common menu toggle) - INPUT_MULTIPLAYER_INFO (243)
        { name = "Numpad *", justPressed = 243 },
        -- Example: Insert key (common menu toggle) - INPUT_FRONTEND_SOCIAL_CLUB_SECONDARY (214)
        { name = "Insert", justPressed = 214 },
        -- Add more common combinations if desired, but remember the limitations.
    }

    for _, combo in ipairs(controlsToCheck) do
        local trigger = false
        if combo.pressed then
            -- Check for combination (one just pressed, one held)
            if IsControlJustPressed(0, combo.justPressed) and IsControlPressed(0, combo.pressed) then
                trigger = true
            end
        else
            -- Check for single key press
            if IsControlJustPressed(0, combo.justPressed) then
                trigger = true
            end
        end

        if trigger then
            if NexusGuard and NexusGuard.ReportCheat then
                local details = { keyCombo = combo.name, control1 = combo.justPressed }
                if combo.pressed then details.control2 = combo.pressed end
                NexusGuard:ReportCheat(DetectorName, details)
            else
                print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: Potential mod menu key combination detected (" .. combo.name .. ") (NexusGuard instance unavailable)")
            end
            return -- Report once per check cycle if a combo is found
        end
    end

    -- TODO: Add more sophisticated checks (See comments below - Guideline 34):
    -- 1. Monitor for blacklisted natives frequently used by menus (e.g., drawing natives, certain SET_* natives).
    --    - NOTE: Directly hooking arbitrary native calls from Lua is generally not feasible or reliable in FiveM.
    --    - Focus should be on detecting the *results* of menu actions or the menu resource itself (via resourcemonitor).
    -- 2. Check for suspicious global variable modifications.
    --    - Example: Some menus might set global flags like _SOME_MENU_ACTIVE = true
    -- 3. Look for unexpected UI elements or scaleforms.
    --    - Requires identifying specific scaleforms used by common menus.
    -- 4. Analyze registered commands/keybinds for suspicious patterns.
    --    - Could involve iterating through registered commands/keys, but might be performance-intensive.

    -- Example Placeholder (Guideline 34): Check for a known suspicious global variable
    -- Replace '_SOME_MENU_ACTIVE' with actual variable names if known menus use them.
    -- This is highly specific to the menus you are targeting.
    if _G._SOME_MENU_ACTIVE == true then
        if NexusGuard and NexusGuard.ReportCheat then
            local details = { check = "Suspicious Global Variable", variable = "_SOME_MENU_ACTIVE" }
            NexusGuard:ReportCheat(DetectorName, details)
        else
            print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: Potential mod menu key combination detected (HOME + E) (NexusGuard instance unavailable)")
        end
        return -- Report once per combination press
    end

    -- Example: F5 key (commonly used) - INPUT_FRONTEND_PAUSE_ALTERNATE (244)
    if IsControlJustPressed(0, 244) then
         if NexusGuard and NexusGuard.ReportCheat then
            local details = { keyCombo = "F5", control1 = 244 }
            NexusGuard:ReportCheat(DetectorName, details)
        else
            print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: Potential mod menu key combination detected (F5) (NexusGuard instance unavailable)")
        end
        return
    end

    -- TODO: Add more sophisticated checks:
    -- 1. Monitor for blacklisted natives frequently used by menus (e.g., drawing natives, certain SET_* natives).
    --    - NOTE (Guideline 34): Directly hooking arbitrary native calls from Lua is generally not feasible or reliable in FiveM.
    --    - It often requires external tools or memory manipulation, which NexusGuard aims to detect, not perform.
    --    - Focus should be on detecting the *results* of menu actions or the menu resource itself (via resourcemonitor).
    -- 2. Check for suspicious global variable modifications.
    --    - Example: Some menus might set global flags like _SOME_MENU_ACTIVE = true
    -- 3. Look for unexpected UI elements or scaleforms.
    --    - Requires identifying specific scaleforms used by common menus.
    -- 4. Analyze registered commands/keybinds for suspicious patterns.
    --    - Could involve iterating through registered commands/keys, but might be performance-intensive.

    -- Example Placeholder (Guideline 34): Check for a known suspicious global variable
    -- Replace '_SOME_MENU_ACTIVE' with actual variable names if known menus use them.
    if _G._SOME_MENU_ACTIVE == true then
        if NexusGuard and NexusGuard.ReportCheat then
            local details = { check = "Suspicious Global Variable", variable = "_SOME_MENU_ACTIVE" }
            NexusGuard:ReportCheat(DetectorName, details)
        else
            print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: Potential mod menu detected (Suspicious Global Variable) (NexusGuard instance unavailable)")
        end
        return -- Report once
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
