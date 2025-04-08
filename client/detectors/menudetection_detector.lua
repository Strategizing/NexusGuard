--[[
    NexusGuard Menu Keybind Detector (client/detectors/menudetection_detector.lua)

    Purpose:
    - Attempts to detect common cheat menus by checking if specific key combinations,
      often used to open menus, are pressed.

    *** CRITICAL WARNING ***
    This detection method is EXTREMELY UNRELIABLE and easily bypassed.
    - Menus can use ANY keybind.
    - Legitimate resources might use the same keybinds.
    - This detector should be considered a very low-confidence heuristic at best.

    RECOMMENDATION:
    - The primary and most effective method for blocking known cheat menus is to use the
      Resource Verification feature (`Config.Features.resourceVerification`) with `mode = "blacklist"`
      and add the known resource names of cheat menus to the `blacklist` table in `config.lua`.
    - Do NOT rely solely on this keybind detector for menu protection.
]]

local DetectorName = "menuDetection" -- Unique key for this detector
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 100,     -- Check interval (ms). Check frequently for key presses. Overridden by config.
    lastCheck = 0       -- Timestamp of the last check.
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

    Log(("[%s Detector] Initialized. Interval: %dms. WARNING: This detector is unreliable; use resource blacklist primarily.^7"):format(DetectorName, Detector.interval), 2)
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
    Checks if any predefined key combinations are pressed.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available.
    if not NexusGuard then return true end -- Skip check if core instance is missing.

    -- List of common key combinations to check.
    -- Control IDs: https://docs.fivem.net/docs/game-references/controls/
    -- Add/remove combinations cautiously, considering potential conflicts and low reliability.
    local controlsToCheck = {
        -- { name = "HOME + E", justPressed = 213, pressed = 38 }, -- INPUT_FRONTEND_SOCIAL_CLUB + INPUT_PICKUP
        { name = "F5", justPressed = 244 }, -- INPUT_FRONTEND_PAUSE_ALTERNATE
        { name = "Numpad *", justPressed = 243 }, -- INPUT_MULTIPLAYER_INFO
        { name = "Insert", justPressed = 214 }, -- INPUT_FRONTEND_SOCIAL_CLUB_SECONDARY
        -- { name = "F8", justPressed = 212 }, -- INPUT_FRONTEND_CONSOLE (Example - likely conflicts)
        -- Add more combinations here if absolutely necessary, understanding the risks.
    }

    for _, combo in ipairs(controlsToCheck) do
        local trigger = false
        -- Check if it's a combination (one key just pressed, another held down).
        if combo.pressed then
            if IsControlJustPressed(0, combo.justPressed) and IsControlPressed(0, combo.pressed) then
                trigger = true
            end
        -- Check if it's a single key press.
        else
            if IsControlJustPressed(0, combo.justPressed) then
                trigger = true
            end
        end

        -- If a defined combination was triggered, report it.
        if trigger then
            Log(("[%s Detector] Potential menu keybind pressed: %s"):format(DetectorName, combo.name), 1)
            if NexusGuard.ReportCheat then
                local details = {
                    keyCombo = combo.name,
                    controlJustPressed = combo.justPressed,
                    controlPressed = combo.pressed -- Will be nil for single key presses
                }
                -- Report with details. Server-side validation is minimal for this type.
                NexusGuard:ReportCheat(DetectorName, details)
            end
            -- Return false to potentially trigger faster re-checks (adaptive timing in template).
            -- Consider returning true if reporting is sufficient and faster checks aren't needed.
            return false
        end
    end

    -- [[ Future / More Advanced (Difficult) Checks - Guideline 34 ]]
    -- The following ideas are complex and often unreliable in the Lua environment:
    -- 1. Blacklisted Natives: Directly hooking/monitoring arbitrary native calls from Lua is generally
    --    not feasible or allowed by FiveM's Lua runtime for security reasons. Focus should remain
    --    on detecting the *effects* of cheats or the cheat resource itself.
    -- 2. Global Variable Monitoring: Iterating through the global environment (`_G`) to find suspicious
    --    variables added by menus is possible but can be performance-intensive and easily bypassed.
    -- 3. UI/Scaleform Detection: Identifying specific scaleforms used by menus requires knowing the
    --    exact scaleform names and checking if they are active, which is fragile.
    -- 4. Command/Keybind Analysis: Iterating through registered commands or key mappings might reveal
    --    suspicious entries but is complex and potentially slow.

    -- If no suspicious keybinds were detected in this cycle.
    return true
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
    }
end

-- Return the Detector table for the registry.
return Detector
