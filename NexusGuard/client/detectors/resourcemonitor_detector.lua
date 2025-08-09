--[[
    NexusGuard Resource Monitor Detector (client/detectors/resourcemonitor_detector.lua)

    Purpose:
    - Periodically retrieves the list of currently running resources on the client.
    - Sends this list to the server (`SYSTEM_RESOURCE_CHECK` event) for validation.
    - This is a key component for detecting unauthorized injected resources (cheat menus, etc.).

    Operation:
    - The actual detection logic (comparing the client's list against a server-defined
      whitelist or blacklist) happens server-side in `server/modules/detections.lua`.
    - This client-side script is responsible only for gathering and reporting the resource list.

    Dependencies:
    - `NexusGuard` instance (for security token and config access).
    - `EventRegistry` instance (for triggering the server event).
]]

local DetectorName = "resourceMonitor" -- Name used for logging and potentially intervals config.
local ConfigKey = "resourceInjection" -- Key used in `Config.Detectors` to enable/disable this check.
local NexusGuard = nil -- Local reference to the main NexusGuard client instance.
local LocalEventRegistry = nil -- Local reference to the EventRegistry instance.

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 15000,   -- Default check interval (ms). How often to send the resource list. Overridden by config.
    lastCheck = 0       -- Timestamp of the last check.
}

--[[
    Initialization Function
    Called by the DetectorRegistry during startup.
    Stores references to the core NexusGuard and EventRegistry instances.
    Reads configuration settings.

    @param nexusGuardInstance (table): The main NexusGuard client instance.
    @param eventRegistryInstance (table): The shared EventRegistry instance.
]]
function Detector.Initialize(nexusGuardInstance, eventRegistryInstance)
    if not nexusGuardInstance then
        print(("^1[NexusGuard:%s] CRITICAL: Failed to receive NexusGuard instance during initialization.^7"):format(DetectorName))
        return false
    end
    if not eventRegistryInstance then
        print(("^1[NexusGuard:%s] CRITICAL: Failed to receive EventRegistry instance during initialization.^7"):format(DetectorName))
        return false -- Also fail if registry isn't passed.
    end
    NexusGuard = nexusGuardInstance -- Store the core instance reference.
    LocalEventRegistry = eventRegistryInstance -- Store the event registry reference.

    -- Read configuration (interval) via the NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Note: Uses `resourceMonitor` for interval key, but `resourceInjection` for enable/disable key. Ensure consistency or update config.lua.
    Detector.interval = (cfg and cfg.Intervals and cfg.Intervals.resourceMonitor) or Detector.interval

    Log(("[%s Detector] Initialized. Interval: %dms. Enabled via Config.Detectors.%s"):format(DetectorName, Detector.interval, ConfigKey), 3)
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
    Gets the list of running resources and sends it to the server for validation.
]]
function Detector.Check()
    -- Ensure NexusGuard instance and security token are available before sending data.
    if not NexusGuard or not NexusGuard.securityToken then
        -- Log(("^3[NexusGuard:%s] Skipping check, NexusGuard instance or security token not ready.^7"):format(DetectorName), 3) -- Reduce log spam
        return 0 -- Return 0 to avoid rapid re-checks if token isn't ready yet.
    end
    -- Ensure the EventRegistry reference is valid.
    if not LocalEventRegistry then
        print(("^1[NexusGuard:%s] CRITICAL: LocalEventRegistry not found in Check function. Cannot send resource list to server.^7"):format(DetectorName))
        return 0 -- Avoid rapid re-checks on error.
    end

    -- 1. Get List of Running Resources: Use FiveM natives.
    local runningResources = {}
    local resourceCount = GetNumResources()
    for i = 0, resourceCount - 1 do
        local resourceName = GetResourceByFindIndex(i)
        -- Optionally filter out default FiveM resources or known safe ones here if desired,
        -- but generally better to let the server handle filtering based on its list.
        -- Exclude the NexusGuard resource itself from the list sent.
        if resourceName and resourceName ~= "" and resourceName ~= GetCurrentResourceName() then
            table.insert(runningResources, resourceName)
        end
    end

    -- 2. Send Resource List to Server: Trigger the `SYSTEM_RESOURCE_CHECK` event.
    -- Include the security token for server-side validation of the request itself.
    -- Log(("[%s Detector] Sending resource list (%d resources) to server for validation."):format(DetectorName, #runningResources), 4) -- Optional debug log
    LocalEventRegistry:TriggerServerEvent('SYSTEM_RESOURCE_CHECK', runningResources, NexusGuard.securityToken)

    -- This client-side check doesn't "detect" anything itself; it merely reports the current state.
    -- The actual detection (comparison against whitelist/blacklist) happens server-side.
    return 0 -- Indicate check cycle completed successfully.
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
