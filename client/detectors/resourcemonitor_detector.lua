local DetectorName = "resourceMonitor" -- Using camelCase to match client_main interval key
local ConfigKey = "resourceInjection" -- Key used in Config.Detectors table
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

local Detector = {
    active = false,
    interval = 15000, -- Default, will be overridden by config if available
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
    if cfg and cfg.Detectors and cfg.Detectors[ConfigKey] and NexusGuard.intervals and NexusGuard.intervals.resourceMonitor then
        Detector.interval = NexusGuard.intervals.resourceMonitor
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
    -- Ensure NexusGuard instance and security token are available before sending
    if not NexusGuard or not NexusGuard.securityToken then
        print("^3[NexusGuard:" .. DetectorName .. "]^7 Skipping check, NexusGuard instance or security token not ready.")
        return
    end

    -- Get all currently running resources
    local runningResources = {}
    local resourceCount = GetNumResources()
    for i = 0, resourceCount - 1 do
        local resourceName = GetResourceByFindIndex(i)
        -- Filter out default resources or resources known to be safe if needed
        if resourceName and resourceName ~= GetCurrentResourceName() then -- Don't include self
            table.insert(runningResources, resourceName)
        end
    end

    -- Send the list to the server for verification against a whitelist/blacklist
    -- Use EventRegistry to trigger the server event
    if _G.EventRegistry then
        _G.EventRegistry.TriggerServerEvent('SYSTEM_RESOURCE_CHECK', runningResources, NexusGuard.securityToken)
    else
        print("^1[NexusGuard:" .. DetectorName .. "] CRITICAL: _G.EventRegistry not found. Cannot send resource list to server.^7")
    end

    -- Client-side doesn't typically "detect" injection directly, it reports the state for server validation.
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
    -- Use the ConfigKey ('resourceInjection') for registration
    _G.DetectorRegistry.Register(ConfigKey, Detector)
    -- Initialization and starting is now handled by the registry calling the methods on the registered module
end)
