--[[
    NexusGuard Detector Registry (shared/detector_registry.lua)

    Purpose:
    - Manages the lifecycle of individual client-side detection modules (detectors).
    - Provides functions to register, start, and stop detectors.
    - Creates and manages the execution threads for active detectors.
    - Relies on the main `NexusGuardInstance` (from client_main.lua) being set via `SetNexusGuardInstance`
      to access shared functionality like `SafeDetect` and `Config`.

    Usage (Internal to NexusGuard):
    - Exposed globally as `_G.DetectorRegistry`.
    - `client_main.lua` calls `SetNexusGuardInstance` during initialization.
    - Individual detector files (e.g., `client/detectors/godmode_detector.lua`) typically call
      `_G.DetectorRegistry.Register(DetectorName, Detector)` at the end of their script.
    - `client_main.lua` calls `StartEnabledDetectors` (which calls `Start`) to activate detectors based on config.
    - `StopAll` is called automatically when the resource stops.

    Developer Notes:
    - This script runs on both client and server, but its primary functionality (thread creation, instance usage)
      is relevant only on the client. The `isServer` check is currently unused but could be added for guards.
    - Detectors are expected to follow a standard structure (see `detector_template.lua`), including
      `Initialize`, `Start`, `Stop`, `Check`, `interval`, and `active` properties.
]]

local isServer = IsDuplicityVersion() -- Check if running on server (currently unused)

local DetectorRegistry = {
    detectors = {},        -- Stores registered detector info: { name = "name", detector = detectorTable, ... }
    activeThreads = {},    -- Stores active Citizen thread IDs for each running detector, keyed by name.
    nexusGuardInstance = nil -- Holds the reference to the main NexusGuard client instance.
}
-- REMOVED: _G.DetectorRegistry = DetectorRegistry -- Avoid global assignment

--[[
    Sets the reference to the main NexusGuard client instance.
    Crucial for allowing the registry and detectors to access shared config, state, and functions (like SafeDetect).
    Called by `client_main.lua` during its initialization.
    @param instance (table): The NexusGuardInstance table from client_main.lua.
]]
function DetectorRegistry:SetNexusGuardInstance(instance)
    if not instance then
        print("^1[NexusGuard:Registry] Error: Invalid NexusGuard instance provided to SetNexusGuardInstance.^7")
        return
    end
    -- Log if overwriting, which might indicate an issue in initialization order.
    if self.nexusGuardInstance then
         print("^3[NexusGuard:Registry] Warning: NexusGuard instance was already set. Overwriting. Check initialization flow.^7")
    end
    self.nexusGuardInstance = instance
    print("^2[NexusGuard:Registry]^7 Main NexusGuard client instance reference set.")
end

--[[
    Internal helper function to create and manage the execution thread for a detector.
    Uses the detector's configured `interval` and calls its `Check` function via `SafeDetect`.
    @param detectorInfo (table): The internal registry entry for the detector.
    @return (number | nil): The Citizen thread ID if created successfully, otherwise nil.
]]
local function CreateDetectorThread(detectorInfo)
    local detectorName = detectorInfo.name
    local detector = detectorInfo.detector
    local baseInterval = detector.interval or 1000 -- Base interval if not specified by detector.
    local interval = baseInterval

    -- Ensure the main NexusGuard instance is available (needed for SafeDetect).
    if not DetectorRegistry.nexusGuardInstance then
         print(("^1[NexusGuard:Registry] CRITICAL Error: NexusGuard instance not set. Cannot start detector thread for '%s'.^7"):format(detectorName))
         detector.active = false -- Ensure detector is marked inactive.
         return nil -- Indicate thread creation failure.
    end
    -- Ensure the SafeDetect function exists on the instance.
    if not DetectorRegistry.nexusGuardInstance.SafeDetect then
        print(("^1[NexusGuard:Registry] CRITICAL Error: SafeDetect function not found on NexusGuard instance. Cannot start detector thread for '%s'.^7"):format(detectorName))
        detector.active = false
        return nil
    end

    local adaptiveEnabled = DetectorRegistry.nexusGuardInstance.Config
        and DetectorRegistry.nexusGuardInstance.Config.Performance
        and DetectorRegistry.nexusGuardInstance.Config.Performance.adaptiveChecking
    local playerId = PlayerId and PlayerId() or 0

    local function updateInterval()
        if adaptiveEnabled and DetectorRegistry.nexusGuardInstance.ComputeAdaptiveInterval then
            interval = DetectorRegistry.nexusGuardInstance:ComputeAdaptiveInterval(baseInterval, playerId)
        else
            interval = baseInterval
        end
    end
    updateInterval()

    -- If a thread reference already exists, clear it. The old thread should terminate based on the `detector.active` flag.
    if DetectorRegistry.activeThreads[detectorName] then
        print(("^3[NexusGuard:Registry] Warning: Existing thread reference found for '%s' before creating new one. Clearing old reference.^7"):format(detectorName))
        DetectorRegistry.activeThreads[detectorName] = nil
    end

    -- Create the Citizen thread for the detector's loop.
    local threadId = Citizen.CreateThread(function()
        print(("^2[NexusGuard:%s]^7 Detector thread started (Interval: %dms).^7"):format(detectorName, interval))
        -- Loop continues as long as the detector's `active` flag is true.
        while detector.active do
            local currentTime = GetGameTimer()

            -- Check if enough time has passed since the last execution based on the detector's interval.
            if currentTime - (detector.lastCheck or 0) >= interval then
                -- Execute the detector's Check function safely using the wrapper from the main instance.
                local result = DetectorRegistry.nexusGuardInstance:SafeDetect(detector.Check, detectorName)
                detector.lastCheck = currentTime -- Update last execution time.

                if adaptiveEnabled then
                    if type(result) == "number" then
                        DetectorRegistry.nexusGuardInstance:AdjustSuspicion(playerId, result)
                    elseif result == false then
                        DetectorRegistry.nexusGuardInstance:AdjustSuspicion(playerId, 1)
                    else
                        DetectorRegistry.nexusGuardInstance:AdjustSuspicion(playerId, -0.1)
                    end
                    updateInterval()
                end
            end

            -- Calculate wait time: Use a base minimum (e.g., 50ms) but don't exceed the interval or a reasonable max (e.g., 1000ms).
            -- This prevents tight loops for very short intervals while still being responsive.
            local waitTime = math.max(50, math.min(interval, 1000))
            Citizen.Wait(waitTime)
        end
        -- Loop exited because detector.active became false.
        print(("^2[NexusGuard:%s]^7 Detector thread stopped.^7"):format(detectorName))
        DetectorRegistry.activeThreads[detectorName] = nil -- Clean up the thread reference in the registry.
    end)

    DetectorRegistry.activeThreads[detectorName] = threadId -- Store the new thread ID.
    return threadId -- Return the ID.
end

--[[
    Registers a detector module with the registry.
    Called by individual detector files.
    @param name (string): The unique name/key for the detector (used in config).
    @param detector (table): The detector module table, containing Check, Start, Stop, interval, etc.
    @return (boolean): True if registration was successful, false otherwise.
]]
function DetectorRegistry:Register(name, detector)
    if not name or not detector or type(detector) ~= "table" then
        print("^1[NexusGuard:Registry] Error: Invalid arguments provided to Register. Requires name (string) and detector (table).^7")
        return false
    end
    if self.detectors[name] then
        print(("^3[NexusGuard:Registry] Warning: Detector '%s' is already registered. Overwriting previous registration.^7"):format(name))
    end

    -- Store detector info, including references to its core methods for easier access.
    self.detectors[name] = {
        name = name,
        detector = detector,
        initialize = detector.Initialize, -- Optional: Called by client_main before Start
        start = detector.Start,           -- Optional: Called by registry to activate detector
        stop = detector.Stop,             -- Optional: Called by registry to deactivate detector
        getStatus = detector.GetStatus,   -- Optional: Called by registry to get custom status info
        check = detector.Check            -- Required: The main detection logic function
    }
    -- Initialize default state if missing
    detector.active = detector.active or false
    detector.lastCheck = detector.lastCheck or 0
    detector.interval = detector.interval or 1000 -- Default interval if not set

    print(("^2[NexusGuard:Registry]^7 Registered detector: %s^7"):format(name))
    return true
end

--[[
    Starts a registered detector by name.
    Calls the detector's Start method (if available) and creates its execution thread.
    @param name (string): The name of the detector to start.
    @return (boolean): True if the detector was started successfully, false otherwise.
]]
function DetectorRegistry:Start(name)
    local detectorInfo = self.detectors[name]
    if not detectorInfo then print(("^1[NexusGuard:Registry] Error: Cannot start unknown detector: '%s'^7"):format(name)); return false end
    -- Prevent starting if thread reference exists (might indicate improper stop).
    if self.activeThreads[name] then print(("^3[NexusGuard:Registry] Warning: Cannot start detector '%s', thread reference already exists. Stop it first or check for cleanup issues.^7"):format(name)); return false end
    -- Prevent starting if already marked active.
    if detectorInfo.detector.active then print(("^3[NexusGuard:Registry] Warning: Detector '%s' is already marked as active.^7"):format(name)); return false end

    -- Call the detector's own Start function, if it exists.
    -- This function is responsible for setting `detector.active = true`.
    local startSuccess = true
    if detectorInfo.start and type(detectorInfo.start) == "function" then
        -- Consider passing the NexusGuard instance if detectors need it during Start.
        -- startSuccess, _ = pcall(detectorInfo.start, self.nexusGuardInstance)
        startSuccess, _ = pcall(detectorInfo.start) -- Call Start safely
    else
        -- If no Start function, assume default behavior is to just become active.
        detectorInfo.detector.active = true
    end

    -- Verify that the Start function succeeded and set the detector to active.
    if not startSuccess or not detectorInfo.detector.active then
        print(("^1[NexusGuard:Registry] Error: Detector '%s' failed to start or did not set itself active.^7"):format(name))
        detectorInfo.detector.active = false -- Ensure it's marked inactive on failure.
        return false
    end

    -- Ensure the detector has a valid Check function before creating the thread.
    if not detectorInfo.check or type(detectorInfo.check) ~= "function" then
        print(("^1[NexusGuard:Registry] Error: Detector '%s' is missing a valid Check() function. Cannot start execution thread.^7"):format(name))
        -- Attempt to call Stop for cleanup if Check is missing.
        if detectorInfo.stop and type(detectorInfo.stop) == "function" then pcall(detectorInfo.stop) end
        detectorInfo.detector.active = false
        return false
    end

    -- Create the execution thread using the helper function.
    local threadCreated = CreateDetectorThread(detectorInfo)
    if threadCreated then
        print(("^2[NexusGuard:Registry]^7 Detector '%s' started successfully.^7"):format(name))
        return true
    else
        -- Thread creation failed (likely due to missing NexusGuard instance or SafeDetect).
        print(("^1[NexusGuard:Registry] Error: Failed to create execution thread for detector '%s'.^7"):format(name))
        -- Attempt cleanup via Stop method.
        if detectorInfo.stop and type(detectorInfo.stop) == "function" then pcall(detectorInfo.stop) end
        detectorInfo.detector.active = false
        return false
    end
end

--[[
    Stops a running detector by name.
    Calls the detector's Stop method (if available), which should set `detector.active = false`.
    The execution thread monitors this flag and terminates itself.
    @param name (string): The name of the detector to stop.
    @return (boolean): True if the stop signal was sent successfully, false otherwise.
]]
function DetectorRegistry:Stop(name)
    local detectorInfo = self.detectors[name]
    if not detectorInfo then print(("^1[NexusGuard:Registry] Error: Cannot stop unknown detector: '%s'^7"):format(name)); return false end
    if not detectorInfo.detector.active then print(("^3[NexusGuard:Registry] Info: Detector '%s' is already inactive.^7"):format(name)); return true end -- Already stopped

    -- Call the detector's own Stop function, if it exists.
    -- This function is responsible for cleanup and setting `detector.active = false`.
    local stopSuccess = true
    if detectorInfo.stop and type(detectorInfo.stop) == "function" then
        -- Consider passing the NexusGuard instance if detectors need it during Stop.
        -- stopSuccess, _ = pcall(detectorInfo.stop, self.nexusGuardInstance)
        stopSuccess, _ = pcall(detectorInfo.stop) -- Call Stop safely
    else
        -- If no Stop function, default behavior is to just mark as inactive.
        detectorInfo.detector.active = false
    end

    -- Log errors if Stop failed or didn't set the active flag correctly.
    if not stopSuccess then
        print(("^1[NexusGuard:Registry] Error: Detector '%s' Stop() method failed. Forcing inactive flag.^7"):format(name))
        detectorInfo.detector.active = false -- Force inactive if Stop errored.
    elseif detectorInfo.detector.active then
         -- This indicates an issue in the detector's Stop implementation.
         print(("^1[NexusGuard:Registry] Error: Detector '%s' Stop() method did not set detector.active to false. Forcing inactive flag.^7"):format(name))
         detectorInfo.detector.active = false -- Force inactive if Stop didn't.
    end

    -- The thread checks `detector.active` and will terminate itself.
    -- The thread reference is cleared within the thread function upon termination.
    print(("^2[NexusGuard:Registry]^7 Stop signal sent to detector '%s'. Thread will terminate.^7"):format(name))
    return true
end

--[[
    Starts all detectors that are registered and marked as enabled in the NexusGuard Config.
    Called by `client_main.lua` after detectors are registered and the NexusGuard instance is set.
]]
function DetectorRegistry:StartEnabledDetectors()
    -- Ensure the main instance is set (needed to access Config).
    if not self.nexusGuardInstance then print("^1[NexusGuard:Registry] Error: NexusGuard instance not set. Cannot start enabled detectors.^7"); return end
    local cfg = self.nexusGuardInstance.Config -- Get config from the instance.
    if not cfg or not cfg.Detectors then print("^1[NexusGuard:Registry] Error: Config or Config.Detectors not found via NexusGuard instance. Cannot auto-start detectors.^7"); return end

    print("^2[NexusGuard:Registry]^7 Starting enabled detectors based on config...")
    for name, isEnabled in pairs(cfg.Detectors) do
        if isEnabled then
            -- Check if the detector is actually registered before trying to start.
            if self.detectors[name] then
                Citizen.Wait(50) -- Small delay between starting detectors.
                self:Start(name) -- Call the registry's Start function.
            else
                print(("^3[NexusGuard:Registry] Warning: Detector '%s' is enabled in config but was not registered. Skipping start.^7"):format(name))
            end
        -- else -- Optional log for disabled detectors
            -- print(("^3[NexusGuard:Registry]^7 Detector '%s' disabled in config.^7"):format(name))
        end
    end
    print("^2[NexusGuard:Registry]^7 Finished attempting to start enabled detectors.")
end

--[[
    Retrieves the status of all registered detectors.
    Combines the registry's view (thread running) with the detector's own status (if GetStatus method exists).
    @return (table): A table mapping detector names to their status information.
]]
function DetectorRegistry:GetAllStatuses()
    local statuses = {}
    for name, detectorInfo in pairs(self.detectors) do
        -- Start with the basic active flag from the detector itself.
        local currentStatus = { active = detectorInfo.detector.active or false }
        -- If the detector provides a GetStatus function, call it and merge the results.
        if detectorInfo.getStatus and type(detectorInfo.getStatus) == "function" then
            local success, moduleStatus = pcall(detectorInfo.getStatus)
            if success and type(moduleStatus) == "table" then
                for k, v in pairs(moduleStatus) do
                    -- Avoid overwriting the core 'active' flag unless the module explicitly sets it.
                    if k ~= 'active' or type(v) == 'boolean' then
                        currentStatus[k] = v
                    end
                end
            elseif not success then
                 print(("^1[NexusGuard:Registry] Error calling GetStatus for detector '%s': %s^7"):format(name, tostring(moduleStatus)))
            end
        end
        -- Add whether the registry currently holds a thread ID for this detector.
        currentStatus.threadRunning = (self.activeThreads[name] ~= nil)
        statuses[name] = currentStatus
    end
    return statuses
end

--[[
    Stops all currently active detectors.
    Intended for use during resource shutdown.
]]
function DetectorRegistry.StopAll()
    print("^2[NexusGuard:Registry]^7 Stopping all active detectors...")
    local count = 0
    for name, detectorInfo in pairs(DetectorRegistry.detectors) do
        -- Check the detector's active flag.
        if detectorInfo.detector.active then
            DetectorRegistry:Stop(name) -- Call the registry's Stop function.
            count = count + 1
        end
    end
    print(("^2[NexusGuard:Registry]^7 Stop signal sent to %d active detector(s).^7"):format(count))
end

--[[
    Resource Stop Handler
    Ensures all detector threads are signaled to stop when the NexusGuard resource stops.
]]
AddEventHandler('onResourceStop', function(resourceName)
    -- Only run if the NexusGuard resource itself is stopping.
    if resourceName == GetCurrentResourceName() then
        print("^2[NexusGuard:Registry]^7 Resource stopping. Initiating StopAll detectors.^7")
        DetectorRegistry.StopAll()
    end
end)

-- Note: Initialization logic (like StartEnabledDetectors) is no longer called directly within this file.
-- It's expected to be called from client_main.lua after the NexusGuard instance is set.

-- Return the registry table so it can be used as a module
return DetectorRegistry
