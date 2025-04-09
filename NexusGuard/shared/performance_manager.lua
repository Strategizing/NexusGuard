--[[
    NexusGuard Enhanced Performance Manager (shared/performance_manager.lua)

    Purpose:
    - Optimizes anti-cheat operations based on server load and performance metrics
    - Implements dynamic check intervals to reduce CPU usage during high load
    - Provides request batching to minimize network traffic
    - Tracks performance metrics for monitoring and analysis
    - Ensures the anti-cheat system remains efficient under various conditions

    Key Features:
    - Dynamic check intervals based on server load
    - Request batching for network optimization
    - Performance metrics tracking
    - Adaptive resource usage
    - Cross-environment compatibility (works on both client and server)
]]

-- Load shared modules using the module loader to prevent circular dependencies
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local Natives = ModuleLoader.Load('shared/natives')
local EventRegistry = ModuleLoader.Load('shared/event_registry')

-- Determine if we're running on the server or client
local isServer = Natives.IsDuplicityVersion and Natives.IsDuplicityVersion() or false

-- Fallback if EventRegistry is not available
if not EventRegistry then
    print("^1[NexusGuard PerformanceManager] WARNING: EventRegistry not found. Using fallback event handling.^7")
    EventRegistry = {
        TriggerServerEvent = function(name, ...)
            if Natives and Natives.TriggerServerEvent then
                Natives.TriggerServerEvent(name, ...)
            else
                TriggerServerEvent(name, ...)
            end
        end,
        TriggerClientEvent = function(name, target, ...)
            if isServer then
                if Natives and Natives.TriggerClientEvent then
                    Natives.TriggerClientEvent(name, target, ...)
                else
                    TriggerClientEvent(name, target, ...)
                end
            end
        end,
        GetEventName = function(_, name) return name end
    }
end

-- Attempt to get the NexusGuard API
local NexusGuardAPI = nil
if isServer then
    -- Server-side: Try to get the API from exports
    local success, api = pcall(function() return exports['NexusGuard']:GetNexusGuardServerAPI() end)
    if success and api then NexusGuardAPI = api end
else
    -- Client-side: API should be available from _G.NexusGuard
    NexusGuardAPI = _G.NexusGuard
end

-- Logging function
local Log = function(...)
    if NexusGuardAPI and NexusGuardAPI.Utils and NexusGuardAPI.Utils.Log then
        NexusGuardAPI.Utils.Log(...)
    else
        print(...)
    end
end

local PerformanceManager = {
    -- Performance metrics
    metrics = {
        cpuTime = {},           -- CPU time used by various operations
        memoryUsage = {},       -- Memory usage of various components
        networkTraffic = {},    -- Network traffic metrics
        checkTimes = {},        -- Time taken by different checks
        lastUpdated = 0,        -- Last time metrics were updated

        -- Server-specific metrics
        serverLoad = 0,         -- Current server load (0.0 to 1.0)
        playerCount = 0,        -- Current player count
        resourceCount = 0,      -- Number of running resources

        -- Client-specific metrics
        fps = 0,                -- Current client FPS
        renderTime = 0,         -- Time spent rendering
        scriptTime = 0          -- Time spent in scripts
    },

    -- Optimization settings
    optimization = {
        lastOptimization = 0, -- Will be set in Initialize
        optimizationInterval = 60000,  -- 1 minute
        minCheckInterval = 1000,       -- Minimum check interval (1 second)
        maxCheckInterval = 10000,      -- Maximum check interval (10 seconds)
        batchSize = 10,                -- Number of updates to batch together
        adaptiveThreshold = 0.8,       -- Server load threshold for adaptive checks
        priorityChecks = {             -- Checks that should always run at higher frequency
            "speedHack",
            "godMode",
            "teleport"
        }
    },

    -- Request batching
    batching = {
        queue = {},             -- Queue of pending updates
        lastBatch = 0,          -- Last time updates were batched
        batchInterval = 1000,   -- Batch interval in ms (1 second)
        maxQueueSize = 100      -- Maximum queue size before forcing a batch
    },

    -- Performance thresholds
    thresholds = {
        highCpuUsage = 0.8,     -- High CPU usage threshold (80%)
        highMemoryUsage = 0.8,  -- High memory usage threshold (80%)
        lowFps = 30,            -- Low FPS threshold
        highNetworkTraffic = 5000 -- High network traffic threshold (5000 bytes/sec)
    }
}

--[[
    Initialize the performance manager.
    @return (boolean): True if initialization was successful, false otherwise.
]]
function PerformanceManager.Initialize()
    -- Initialize metrics
    PerformanceManager.UpdateMetrics()

    -- Set up periodic optimization
    if Natives and Natives.CreateThread then
        Natives.CreateThread(function()
            while true do
                Natives.Wait(PerformanceManager.optimization.optimizationInterval)
                PerformanceManager.OptimizeChecks()
            end
        end)

        -- Set up periodic batching
        Natives.CreateThread(function()
            while true do
                Natives.Wait(PerformanceManager.batching.batchInterval)
                PerformanceManager.ProcessBatchQueue()
            end
        end)

        -- Set up metrics collection
        Natives.CreateThread(function()
            while true do
                Natives.Wait(5000)  -- Update metrics every 5 seconds
                PerformanceManager.UpdateMetrics()
            end
        end)
    else
        -- Fallback for when Natives is not available
        print("^3[PerformanceManager] Warning: Natives not available, using direct Citizen calls^7")
        Citizen.CreateThread(function()
            while true do
                Citizen.Wait(PerformanceManager.optimization.optimizationInterval)
                PerformanceManager.OptimizeChecks()
            end
        end)

        -- Set up periodic batching
        Citizen.CreateThread(function()
            while true do
                Citizen.Wait(PerformanceManager.batching.batchInterval)
                PerformanceManager.ProcessBatchQueue()
            end
        end)

        -- Set up metrics collection
        Citizen.CreateThread(function()
            while true do
                Citizen.Wait(5000)  -- Update metrics every 5 seconds
                PerformanceManager.UpdateMetrics()
            end
        end)
    end

    Log("^2[PerformanceManager]^7 Initialized performance management system", 2)
    return true
end

--[[
    Update performance metrics.
    @return (table): The updated metrics.
]]
function PerformanceManager.UpdateMetrics()
    local metrics = PerformanceManager.metrics

    -- Use Natives wrapper if available, otherwise fall back to direct call
    if Natives and Natives.GetGameTimer then
        metrics.lastUpdated = Natives.GetGameTimer()
    else
        metrics.lastUpdated = GetGameTimer()
    end

    -- Update server-specific metrics
    if isServer then
        -- Get server load
        local serverLoad = 32 -- Default value
        if Natives and Natives.GetConvarInt then
            serverLoad = Natives.GetConvarInt("sv_maxClients", 32)
        elseif GetConvarInt then
            serverLoad = GetConvarInt("sv_maxClients", 32)
        end

        -- Get player count
        local currentPlayers = 0
        if Natives and Natives.GetPlayers then
            local players = Natives.GetPlayers()
            currentPlayers = #players
        elseif Utils and Utils.GetConnectedPlayers then
            local players = Utils.GetConnectedPlayers()
            currentPlayers = Utils.TableSize(players)
        elseif GetPlayers then
            currentPlayers = #GetPlayers()
        end

        metrics.serverLoad = currentPlayers / serverLoad
        metrics.playerCount = currentPlayers

        -- Count resources
        local resourceCount = 0
        local i = 0
        local resourceName = nil

        if Natives and Natives.GetResourceByFindIndex then
            while true do
                resourceName = Natives.GetResourceByFindIndex(i)
                if not resourceName then break end
                resourceCount = resourceCount + 1
                i = i + 1
            end
        elseif GetResourceByFindIndex then
            while true do
                resourceName = GetResourceByFindIndex(i)
                if not resourceName then break end
                resourceCount = resourceCount + 1
                i = i + 1
            end
        end

        metrics.resourceCount = resourceCount
    else
        -- Update client-specific metrics
        if Natives and Natives.GetFrameTime then
            metrics.fps = 1.0 / Natives.GetFrameTime()
        elseif GetFrameTime then
            metrics.fps = 1.0 / GetFrameTime()
        else
            metrics.fps = 60.0 -- Default fallback value
        end

        -- These would require native access that might not be available
        -- metrics.renderTime = ...
        -- metrics.scriptTime = ...
    end

    return metrics
end

--[[
    Optimize check frequencies based on server performance.
    @return (table): A table of adjusted check intervals.
]]
function PerformanceManager.OptimizeChecks()
    -- Use Natives wrapper if available, otherwise fall back to direct call
    if Natives and Natives.GetGameTimer then
        PerformanceManager.optimization.lastOptimization = Natives.GetGameTimer()
    else
        PerformanceManager.optimization.lastOptimization = GetGameTimer()
    end

    -- Get current metrics
    local metrics = PerformanceManager.metrics
    local Config = NexusGuardAPI and NexusGuardAPI.Config or {}
    local Intervals = Config.Intervals or {}

    -- Calculate load factor (higher load = higher factor)
    local loadFactor = 1.0
    if isServer then
        -- Server-side: Use server load
        loadFactor = math.min(2.0, 1.0 + metrics.serverLoad)
    else
        -- Client-side: Use inverse FPS (lower FPS = higher factor)
        local targetFps = 60
        local currentFps = metrics.fps or targetFps
        loadFactor = math.min(2.0, targetFps / math.max(currentFps, 15))
    end

    -- Adjust check intervals based on load factor
    local adjustedIntervals = {}

    -- Process each interval from config
    for checkName, baseInterval in pairs(Intervals) do
        local isPriority = false

        -- Check if this is a priority check
        for _, priorityCheck in ipairs(PerformanceManager.optimization.priorityChecks) do
            if checkName == priorityCheck then
                isPriority = true
                break
            end
        end

        -- Calculate adjusted interval
        local adjustedInterval = baseInterval
        if isPriority then
            -- Priority checks: Increase by at most 50%
            adjustedInterval = math.min(
                PerformanceManager.optimization.maxCheckInterval,
                math.max(baseInterval, baseInterval * (1.0 + (loadFactor - 1.0) * 0.5))
            )
        else
            -- Regular checks: Full adjustment based on load
            adjustedInterval = math.min(
                PerformanceManager.optimization.maxCheckInterval,
                math.max(baseInterval, baseInterval * loadFactor)
            )
        end

        -- Ensure minimum interval
        adjustedInterval = math.max(adjustedInterval, PerformanceManager.optimization.minCheckInterval)

        -- Store adjusted interval
        adjustedIntervals[checkName] = adjustedInterval
    end

    -- Log optimization results
    Log(string.format("^3[PerformanceManager]^7 Optimized check intervals (Load Factor: %.2f)", loadFactor), 3)

    return adjustedIntervals
end

--[[
    Add an update to the batch queue.
    @param updateType (string): The type of update.
    @param target (string/number): The target of the update.
    @param data (any): The update data.
    @return (boolean): True if the update was added to the queue, false otherwise.
]]
function PerformanceManager.QueueUpdate(updateType, target, data)
    if not updateType or not target then return false end

    -- Get current time using Natives wrapper if available
    local currentTime = 0
    if Natives and Natives.GetGameTimer then
        currentTime = Natives.GetGameTimer()
    else
        currentTime = GetGameTimer()
    end

    -- Add to queue
    table.insert(PerformanceManager.batching.queue, {
        type = updateType,
        target = target,
        data = data,
        timestamp = currentTime
    })

    -- Process queue if it's getting too large
    if #PerformanceManager.batching.queue >= PerformanceManager.batching.maxQueueSize then
        PerformanceManager.ProcessBatchQueue()
    end

    return true
end

--[[
    Process the batch queue and send updates.
    @return (number): The number of updates processed.
]]
function PerformanceManager.ProcessBatchQueue()
    local queue = PerformanceManager.batching.queue
    if #queue == 0 then return 0 end

    -- Get current time using Natives wrapper if available
    if Natives and Natives.GetGameTimer then
        PerformanceManager.batching.lastBatch = Natives.GetGameTimer()
    else
        PerformanceManager.batching.lastBatch = GetGameTimer()
    end

    -- Group similar updates
    local batched = {}
    for _, update in ipairs(queue) do
        local key = update.type .. tostring(update.target)
        if not batched[key] then
            batched[key] = {
                type = update.type,
                target = update.target,
                data = {}
            }
        end
        table.insert(batched[key].data, update.data)
    end

    -- Send batched updates
    local updateCount = 0
    for _, batch in pairs(batched) do
        if isServer then
            -- Server sending to clients
            local target = batch.target
            if target == "all" then target = -1 end

            EventRegistry.TriggerClientEvent("BATCH_UPDATE", target, batch)
        else
            -- Client sending to server
            EventRegistry.TriggerServerEvent("BATCH_UPDATE", batch)
        end
        updateCount = updateCount + 1
    end

    -- Clear the queue
    PerformanceManager.batching.queue = {}

    -- Log batch processing
    Log(string.format("^3[PerformanceManager]^7 Processed %d batched updates", updateCount), 3)

    return updateCount
end

--[[
    Measure the execution time of a function.
    @param name (string): The name of the operation to measure.
    @param func (function): The function to measure.
    @param ... (any): Arguments to pass to the function.
    @return (any): The return value of the function.
]]
function PerformanceManager.MeasureExecution(name, func, ...)
    if not name or type(func) ~= "function" then return nil end

    -- Initialize metrics for this operation if not exists
    if not PerformanceManager.metrics.cpuTime[name] then
        PerformanceManager.metrics.cpuTime[name] = {
            total = 0,
            count = 0,
            average = 0,
            max = 0,
            min = 999999
        }
    end

    -- Get timer function
    local getTimer = Natives and Natives.GetGameTimer or GetGameTimer

    -- Measure execution time
    local startTime = getTimer()
    local results = {func(...)}
    local endTime = getTimer()
    local executionTime = endTime - startTime

    -- Update metrics
    local metrics = PerformanceManager.metrics.cpuTime[name]
    metrics.total = metrics.total + executionTime
    metrics.count = metrics.count + 1
    metrics.average = metrics.total / metrics.count
    metrics.max = math.max(metrics.max, executionTime)
    metrics.min = math.min(metrics.min, executionTime)

    -- Log if execution time is unusually high
    if executionTime > 100 then  -- More than 100ms is considered high
        Log(string.format("^3[PerformanceManager]^7 High execution time for '%s': %dms (Avg: %.2fms)",
            name, executionTime, metrics.average), 2)
    end

    return table.unpack(results)
end

--[[
    Get performance metrics.
    @param category (string, optional): The category of metrics to get.
    @return (table): The requested metrics.
]]
function PerformanceManager.GetMetrics(category)
    if category then
        return PerformanceManager.metrics[category] or {}
    else
        return PerformanceManager.metrics
    end
end

--[[
    Check if the system is under high load.
    @return (boolean): True if the system is under high load, false otherwise.
]]
function PerformanceManager.IsHighLoad()
    local metrics = PerformanceManager.metrics

    if isServer then
        -- Server-side: Check server load
        return metrics.serverLoad >= PerformanceManager.thresholds.highCpuUsage
    else
        -- Client-side: Check FPS
        return metrics.fps <= PerformanceManager.thresholds.lowFps
    end
end

--[[
    Batch updates to reduce network traffic.
    @param updates (table): A table of updates to batch.
    @return (boolean): True if updates were batched successfully, false otherwise.
]]
function PerformanceManager.BatchUpdates(updates)
    if not updates or #updates == 0 then return false end

    -- Add all updates to the queue
    for _, update in ipairs(updates) do
        PerformanceManager.QueueUpdate(update.type, update.target, update.data)
    end

    -- Process immediately if enough updates
    if #PerformanceManager.batching.queue >= PerformanceManager.optimization.batchSize then
        PerformanceManager.ProcessBatchQueue()
    end

    return true
end

-- Initialize the performance manager if we're on the server
if isServer then
    if Natives and Natives.CreateThread then
        Natives.CreateThread(function()
            Natives.Wait(1000)  -- Wait for everything to load
            PerformanceManager.Initialize()
        end)
    else
        -- Fallback for when Natives is not available
        Citizen.CreateThread(function()
            Citizen.Wait(1000)  -- Wait for everything to load
            PerformanceManager.Initialize()
        end)
    end
end

-- Return the module
return PerformanceManager