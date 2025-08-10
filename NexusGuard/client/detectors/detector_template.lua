--[[
    NexusGuard Detector Template (client/detectors/detector_template.lua)

    Purpose:
    - Provides a basic structure and example for creating new client-side detection modules.
    - Developers should copy this file, rename it (e.g., `my_detector.lua`),
      change `DetectorName`, and implement their specific detection logic in `Detector.Check`.

    Required Structure:
    - `DetectorName` (string): A unique key for this detector. MUST match the key used in `Config.Detectors` and `Config.Intervals` in `config.lua`.
    - `Detector` (table): The main table holding the detector's functions and state.
    - `Detector.Initialize(nexusGuardObj)` (function): Called by `client_main.lua` during startup. Receives the main NexusGuard client instance. Should read config, set up initial state, and potentially start the check loop.
    - `Detector.Check()` (function): Contains the core detection logic. Called periodically by the detector's own loop (started via `Initialize` or `Start`). Should return `true` if check passes, `false` or `nil` if suspicious activity is detected (used for adaptive timing in this template).
    - `return Detector`: The script MUST return the `Detector` table.

    Optional Functions (Used by DetectorRegistry):
    - `Detector.Start()`: Called by the registry when starting the detector. Can be used for setup that needs to happen *after* Initialize but before the first Check. Should set `Detector.active = true`. If omitted, registry assumes active on start.
    - `Detector.Stop()`: Called by the registry when stopping the detector. Should perform cleanup and set `Detector.active = false`. If omitted, registry sets active to false.
    - `Detector.GetStatus()`: Called by the registry to get additional status info beyond just 'active'. Should return a table.

    Accessing Core NexusGuard Functionality:
    - The `NexusGuard` local variable holds the reference to the main client instance passed during `Initialize`.
    - Use `NexusGuard:ReportCheat(DetectorName, detailsTable)` to report detected violations.
    - Access shared config via `NexusGuard.Config` (or `_G.Config`).
    - Access shared state via `NexusGuard.state` (use with caution, prefer local state).
]]

-- Unique name for this detector. MUST match the key in config.lua (e.g., Config.Detectors.template)
local DetectorName = "template"

-- Main table for this detector module
local Detector = {
    active = false,     -- Is the detector currently running its checks? Controlled by Start/Stop.
    lastCheck = 0,      -- Timestamp (GetGameTimer) of the last check execution.
    interval = 1000     -- Default interval (ms) between checks. Overridden by config.
}

-- Local reference to the main NexusGuard client instance (set during Initialize)
local NexusGuard = nil

--[[
    Initialization Function
    Called once by client_main.lua when the detector is loaded.
    - Stores the reference to the main NexusGuard instance.
    - Reads detector-specific configuration (enabled status, interval).
    - Starts the detection loop (`StartChecking` in this template) if enabled.

    @param nexusGuardObj (table): The main NexusGuard client instance from client_main.lua.
    @return (boolean): True if the detector initialized successfully (usually if enabled), false otherwise.
]]
function Detector.Initialize(nexusGuardObj)
    if not nexusGuardObj then
        print(("^1[%s Detector] Error: Invalid NexusGuard instance received during Initialize.^7"):format(DetectorName))
        return false
    end
    NexusGuard = nexusGuardObj -- Store the reference for later use (e.g., in Check).

    -- Read configuration using the DetectorName key.
    -- Use _G.Config directly as it's loaded early. Provide defaults.
    local cfgDetectors = _G.Config and _G.Config.Detectors
    local cfgIntervals = _G.Config and _G.Config.Intervals

    Detector.active = (cfgDetectors and cfgDetectors[DetectorName]) or false -- Default to false if not found/enabled.
    Detector.interval = (cfgIntervals and cfgIntervals[DetectorName]) or Detector.interval -- Use configured interval or default.

    Log(("[%s Detector] Initializing. Enabled: %s, Interval: %dms"):format(DetectorName, tostring(Detector.active), Detector.interval), 3)

    -- If enabled in config, start the checking loop.
    if Detector.active then
        Detector.StartChecking() -- Start the periodic checks.
    end

    return Detector.active -- Return true if enabled and presumably initialized okay.
end

--[[
    Starts the main detection loop thread.
    This template uses an adaptive timing approach based on the return value of Detector.Check().
    Alternatively, this logic could be moved into a Detector.Start() function if using the DetectorRegistry's standard Start/Stop pattern.
]]
function Detector.StartChecking()
    -- Ensure the detector is marked as active before starting the thread.
    if not Detector.active then
        Log(("[%s Detector] Cannot start checking loop, detector is not active.^7"):format(DetectorName), 2)
        return
    end

    Citizen.CreateThread(function()
        Log(("[%s Detector] Check loop started.^7"):format(DetectorName), 3)
        local nextCheck = GetGameTimer() -- Schedule the first check immediately.

        -- Loop continues as long as the detector is active.
        while Detector.active do
            local currentTime = GetGameTimer()
            -- Check if it's time for the next execution.
            if currentTime >= nextCheck then
                -- Execute the core detection logic.
                local checkPassed = Detector.Check() -- Assumes Check() returns true on pass, false/nil on detection.

                -- Adaptive Timing: Schedule next check based on result.
                if type(checkPassed) == "number" and checkPassed > 0 then
                    -- Suspicious activity detected, schedule the next check sooner (e.g., half interval).
                    nextCheck = currentTime + math.floor(Detector.interval * 0.5)
                    Log(("[%s Detector] Suspicion score %d. Next check in %dms.^7"):format(DetectorName, checkPassed, math.floor(Detector.interval * 0.5)), 3)
                else
                    -- Check passed, schedule next check at the normal interval.
                    nextCheck = currentTime + Detector.interval
                end
                Detector.lastCheck = currentTime -- Update last check time *after* running the check.
            end

            -- Wait before the next loop iteration.
            -- Adjust wait time: wait a fraction of the interval, but not excessively long or short.
            local waitTime = math.max(50, math.min(Detector.interval / 4, 500)) -- e.g., wait 1/4 interval, capped between 50ms and 500ms.
            Citizen.Wait(waitTime)
        end
        Log(("[%s Detector] Check loop stopped.^7"):format(DetectorName), 3)
    end)
end

--[[
    Core Detection Logic Function (Placeholder)
    !! DEVELOPER: Implement your specific cheat detection logic here. !!

    - This function is called periodically by the loop in `StartChecking`.
    - Access game state using FiveM natives (e.g., GetEntityCoords, GetEntityHealth, IsControlPressed).
    - Compare current state with previous state or expected values.
    - If suspicious activity is detected:
        - Call `NexusGuard:ReportCheat(DetectorName, { detail1 = value1, ... })` to report it.
          The second argument should be a table containing relevant details about the detection.
        - Return `false` or `nil` to indicate suspicion (used by this template's adaptive timing).
    - If no suspicious activity is detected:
        - Return `true`.

    @return (boolean | nil): `true` if checks pass, `false` or `nil` if suspicious activity is detected.
]]
function Detector.Check()
    -- Example: Check player health (replace with actual logic)
    -- local playerPed = PlayerPedId()
    -- local health = GetEntityHealth(playerPed)
    --
    -- if health > 200 then -- Example threshold
    --     Log(("[%s Detector] Suspicious health detected: %d"):format(DetectorName, health), 1)
    --     -- Report the detection to the core system
    --     NexusGuard:ReportCheat(DetectorName, {
    --         check = "HealthCheck",
    --         value = health,
    --         threshold = 200
    --     })
    --     return 1 -- Indicate suspicion
    -- end

    -- If everything seems normal for this check
    return 0 -- Suspicion score (0 = no suspicion)
end

--[[
    (Optional) Stop Function
    Called by the DetectorRegistry when the detector needs to stop (e.g., resource shutdown).
    Should perform any necessary cleanup and set `Detector.active = false` to stop the check loop.
]]
-- function Detector.Stop()
--     Log(("[%s Detector] Stopping..."):format(DetectorName), 3)
--     Detector.active = false
--     -- Perform any specific cleanup for this detector here.
--     return true -- Indicate successful stop signal
-- end

--[[
    (Optional) GetStatus Function
    Called by the DetectorRegistry to get additional status information beyond just 'active'.
    @return (table): A table containing custom status key-value pairs.
]]
-- function Detector.GetStatus()
--     return {
--         lastCheckTimestamp = Detector.lastCheck,
--         checkInterval = Detector.interval,
--         -- Add any other relevant status info
--     }
-- end

-- Return the Detector table so client_main.lua can require and register it.
return Detector
