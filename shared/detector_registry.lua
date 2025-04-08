--[[
    Detector Registry (Refactored for Instance Passing)
    Manages the registration, initialization, and execution of client-side detectors.
]]

local isServer = IsDuplicityVersion() -- Check if running on server

local DetectorRegistry = {
    detectors = {},
    activeThreads = {},
    nexusGuardInstance = nil -- Store the NexusGuard instance
}
_G.DetectorRegistry = DetectorRegistry -- Expose globally (Consider removing later if possible)

-- Set the NexusGuard instance (called from client_main)
function DetectorRegistry:SetNexusGuardInstance(instance)
    if not instance then
        print("^1[NexusGuard:Registry] Error: Invalid NexusGuard instance provided.^7")
        return
    end
    if self.nexusGuardInstance then
         print("^3[NexusGuard:Registry] Warning: NexusGuard instance already set. Overwriting.^7")
    end
    self.nexusGuardInstance = instance
    print("^2[NexusGuard:Registry]^7 NexusGuard instance set.")
end

-- Helper function to create the standard detector loop thread
local function CreateDetectorThread(detectorInfo)
    local detectorName = detectorInfo.name
    local detector = detectorInfo.detector
    local interval = detector.interval -- Use the detector's specific interval

    -- Ensure NexusGuard instance is available before creating thread
    if not DetectorRegistry.nexusGuardInstance then
         print("^1[NexusGuard:Registry] CRITICAL Error: NexusGuard instance not set. Cannot start detector thread for '" .. detectorName .. "'.^7")
         detector.active = false -- Ensure it's marked as inactive
         return nil -- Indicate thread creation failure
    end

    -- Cancel existing thread if any (by clearing reference, relying on active flag)
    if DetectorRegistry.activeThreads[detectorName] then
        DetectorRegistry.activeThreads[detectorName] = nil
    end

    local threadId = Citizen.CreateThread(function()
        print("^2[NexusGuard:" .. detectorName .. "]^7 Thread started.")
        while detector.active do -- Check the detector's own active flag
            local currentTime = GetGameTimer()

            -- Only run if enough time has passed
            if currentTime - detector.lastCheck >= interval then
                -- Use the SafeDetect wrapper from the stored NexusGuard core instance
                if DetectorRegistry.nexusGuardInstance.SafeDetect then
                     DetectorRegistry.nexusGuardInstance:SafeDetect(detector.Check, detectorName)
                else
                    -- Fallback or error if SafeDetect is missing (should indicate an issue)
                    print("^1[NexusGuard:Registry] CRITICAL Error: SafeDetect method not found in NexusGuard instance for detector '" .. detectorName .. "'. Stopping thread.^7")
                    detector.active = false -- Stop the loop
                    break
                end
                detector.lastCheck = currentTime
            end

            local waitTime = math.max(50, math.min(interval, 1000))
            Citizen.Wait(waitTime)
        end
        print("^2[NexusGuard:" .. detectorName .. "]^7 Thread stopped.")
        DetectorRegistry.activeThreads[detectorName] = nil -- Clean up thread reference
    end)
    DetectorRegistry.activeThreads[detectorName] = threadId -- Store thread reference
    return threadId -- Return threadId in case it's needed
end

-- Register a new detector
function DetectorRegistry:Register(name, detector)
    if not name or not detector or type(detector) ~= "table" then
        print("^1[NexusGuard:Registry] Error: Invalid arguments provided to Register.^7")
        return false
    end
    if DetectorRegistry.detectors[name] then
        print("^3[NexusGuard:Registry] Warning: Detector '" .. name .. "' is already registered. Overwriting.^7")
    end
    DetectorRegistry.detectors[name] = {
        name = name,
        detector = detector,
        -- Store references to standard methods if they exist
        initialize = detector.Initialize,
        start = detector.Start,
        stop = detector.Stop,
        getStatus = detector.GetStatus,
        check = detector.Check -- Store check function reference
    }
    print("^2[NexusGuard:Registry]^7 Registered detector: " .. name)
    return true
end

-- Start a detector by name
function DetectorRegistry:Start(name)
    local detectorInfo = DetectorRegistry.detectors[name]
    if not detectorInfo then print("^1[NexusGuard:Registry] Error: Cannot start unknown detector: " .. name .. "^7"); return false end
    if DetectorRegistry.activeThreads[name] then print("^3[NexusGuard:Registry] Warning: Detector '" .. name .. "' thread already exists (or wasn't cleaned up).^7"); return false end
    if detectorInfo.detector.active then print("^3[NexusGuard:Registry] Warning: Detector '" .. name .. "' already marked as active.^7"); return false end

    -- Call the detector's Start function (should set detector.active = true)
    local startSuccess = true
    if detectorInfo.start and type(detectorInfo.start) == "function" then
        -- Pass NexusGuard instance to Start if needed (optional pattern)
        -- startSuccess = detectorInfo.start(self.nexusGuardInstance)
        startSuccess = detectorInfo.start() -- Keep original for now
    else
        detectorInfo.detector.active = true -- Default action if no Start method
    end

    if not startSuccess or not detectorInfo.detector.active then
        print("^1[NexusGuard:Registry] Error: Detector '" .. name .. "' failed to start or set itself active.^7")
        detectorInfo.detector.active = false -- Ensure inactive
        return false
    end

    -- Ensure Check function exists
    if not detectorInfo.check or type(detectorInfo.check) ~= "function" then
        print("^1[NexusGuard:Registry] Error: Detector '" .. name .. "' is missing a Check() method. Cannot start thread.^7")
        if detectorInfo.stop and type(detectorInfo.stop) == "function" then detectorInfo.stop() end -- Attempt cleanup
        detectorInfo.detector.active = false
        return false
    end

    -- Create the thread
    local threadCreated = CreateDetectorThread(detectorInfo)
    if threadCreated then
        print("^2[NexusGuard:Registry]^7 Detector '" .. name .. "' started successfully.")
        return true
    else
        print("^1[NexusGuard:Registry] Error: Failed to create thread for detector '" .. name .. "'.^7")
        if detectorInfo.stop and type(detectorInfo.stop) == "function" then detectorInfo.stop() end -- Attempt cleanup
        detectorInfo.detector.active = false
        return false
    end
end

-- Stop a detector by name
function DetectorRegistry:Stop(name)
    local detectorInfo = DetectorRegistry.detectors[name]
    if not detectorInfo then print("^1[NexusGuard:Registry] Error: Cannot stop unknown detector: " .. name .. "^7"); return false end

    -- Signal the detector to stop by calling its Stop method (which should set active = false)
    local stopSuccess = true
    if detectorInfo.stop and type(detectorInfo.stop) == "function" then
        -- Pass NexusGuard instance to Stop if needed (optional pattern)
        -- stopSuccess = detectorInfo.stop(self.nexusGuardInstance)
        stopSuccess = detectorInfo.stop() -- Keep original for now
    else
        detectorInfo.detector.active = false -- Default action if no Stop method
    end

    if not stopSuccess then
        print("^1[NexusGuard:Registry] Error: Detector '" .. name .. "' Stop() method failed. Forcing stop flag.^7")
        detectorInfo.detector.active = false -- Force flag anyway
    elseif detectorInfo.detector.active then
         print("^1[NexusGuard:Registry] Error: Detector '" .. name .. "' Stop() method did not set detector.active to false. Forcing.^7")
         detectorInfo.detector.active = false -- Force flag if Stop didn't
    end

    -- Thread will terminate itself based on the flag. Reference is cleared in the thread function.
    print("^2[NexusGuard:Registry]^7 Stop signal sent to detector '" .. name .. "'.")
    return true
end

-- Start all detectors marked as enabled in Config
function DetectorRegistry:StartEnabledDetectors()
    if not self.nexusGuardInstance then print("^1[NexusGuard:Registry] Error: NexusGuard instance not set. Cannot start detectors.^7"); return end
    local cfg = self.nexusGuardInstance.Config -- Access config via instance
    if not cfg or not cfg.Detectors then print("^1[NexusGuard:Registry] Error: Config or Config.Detectors not found. Cannot auto-start detectors.^7"); return end

    print("^2[NexusGuard:Registry]^7 Starting enabled detectors based on config...")
    for name, _ in pairs(cfg.Detectors) do
        if cfg.Detectors[name] then
            if self.detectors[name] then
                Citizen.Wait(100) -- Small delay
                self:Start(name)
            else
                print("^3[NexusGuard:Registry] Warning: Detector '" .. name .. "' enabled in config but not registered.^7")
            end
        else
            -- print("^3[NexusGuard:Registry]^7 Detector '" .. name .. "' disabled in config.")
        end
    end
end

-- Get status of all detectors
function DetectorRegistry:GetAllStatuses()
    local statuses = {}
    for name, detectorInfo in pairs(self.detectors) do
        local currentStatus = { active = detectorInfo.detector.active or false } -- Start with internal active state
        if detectorInfo.getStatus and type(detectorInfo.getStatus) == "function" then
            local moduleStatus = detectorInfo.getStatus()
            if type(moduleStatus) == "table" then
                for k, v in pairs(moduleStatus) do currentStatus[k] = v end -- Merge status
            end
        end
        currentStatus.threadRunning = self.activeThreads[name] ~= nil -- Add registry's view of thread
        statuses[name] = currentStatus
    end
    return statuses
end

-- Function to stop all detectors (e.g., on resource stop)
function DetectorRegistry.StopAll()
    print("^2[NexusGuard]^7 Stopping all detectors...")
    for name, detectorInfo in pairs(DetectorRegistry.detectors) do
        if detectorInfo.detector.active then
            DetectorRegistry.Stop(name)
        end
    end
    print("^2[NexusGuard]^7 All detectors stopped.")
end

-- Add handler for resource stopping
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        DetectorRegistry.StopAll()
    end
end)

-- Note: Initialization (calling StartEnabledDetectors) should now be triggered
-- from client_main.lua *after* SetNexusGuardInstance is called.
-- The old Initialize function here is removed.

-- Removed server-side exports block from shared script.
