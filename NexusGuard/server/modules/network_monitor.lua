--[[
    NexusGuard Enhanced Network Monitor (server/modules/network_monitor.lua)

    Purpose:
    - Monitors and tracks network event frequencies for each player
    - Detects event spamming and suspicious network activity
    - Provides automatic cleanup of old data
    - Integrates with the detection system for reporting violations

    Key Features:
    - Per-player event frequency tracking
    - Time-windowed analysis
    - Pattern detection for suspicious sequences
    - Automatic data cleanup to prevent memory bloat
    - Configurable thresholds for different event types
]]

-- Load shared modules using the module loader to prevent circular dependencies
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local Natives = ModuleLoader.Load('shared/natives')
local EventRegistry = ModuleLoader.Load('shared/event_registry')

-- Shorthand for event registry functions
local TriggerEvent = function(...)
    if EventRegistry and EventRegistry.TriggerEvent then
        EventRegistry.TriggerEvent(...)
    end
end

-- Get the NexusGuard Server API
local NexusGuardServer = Utils.GetNexusGuardAPI()
if not NexusGuardServer then
    print("^1[NexusGuard NetworkMonitor] CRITICAL: Failed to get NexusGuardServer API. Some functionality will be limited.^7")
    -- Create dummy API to prevent immediate errors
    NexusGuardServer = {
        Config = { Thresholds = {}, SeverityScores = {} },
        Utils = { Log = function(...) print("[NexusGuard NetworkMonitor Fallback Log]", ...) end }
    }
end

-- Shorthand for logging function
local Log = function(...)
    if NexusGuardServer and NexusGuardServer.Utils and NexusGuardServer.Utils.Log then
        NexusGuardServer.Utils.Log(...)
    else
        print(...)
    end
end

local NetworkMonitor = {
    -- Track event counts per player
    eventCounts = {},

    -- Track event patterns per player
    eventPatterns = {},

    -- Track suspicious sequences
    suspiciousSequences = {},

    -- Track resource network usage
    resourceUsage = {},

    -- Timing variables
    lastCleanup = 0,
    cleanupInterval = 60000,  -- 1 minute in ms
    analysisInterval = 30000,  -- 30 seconds in ms
    lastAnalysis = 0,

    -- Default thresholds (fallbacks if not in Config)
    defaultThresholds = {
        eventSpamLimit = 30,           -- Max events of same type per minute
        eventSpamTimeWindow = 60000,   -- Time window for spam detection (1 minute)
        resourceEventLimit = 100,      -- Max events from a resource per minute
        playerEventLimit = 200,        -- Max total events from a player per minute
        suspiciousSequenceThreshold = 3 -- Number of suspicious sequences before flagging
    }
}

-- Get thresholds from config or use defaults
function NetworkMonitor.GetThresholds()
    local config = NexusGuardServer.Config or {}
    local thresholds = config.Thresholds or {}

    -- Create a new table with defaults that are overridden by config values if they exist
    local result = {}
    for k, v in pairs(NetworkMonitor.defaultThresholds) do
        result[k] = thresholds[k] or v
    end

    return result
end

-- Initialize player tracking
function NetworkMonitor.InitializePlayer(playerId)
    local currentTime = Natives.GetGameTimer()

    NetworkMonitor.eventCounts[playerId] = {
        events = {},           -- Counts per event name
        resources = {},        -- Counts per resource name
        totalEvents = 0,       -- Total event count
        lastReset = currentTime,
        timeWindows = {}       -- Time-windowed data for pattern analysis
    }

    NetworkMonitor.eventPatterns[playerId] = {
        sequences = {},        -- Detected event sequences
        lastEvents = {},       -- Last N events for sequence detection
        knownPatterns = {}     -- Known patterns for this player
    }

    Log("Initialized network tracking for player " .. Natives.GetPlayerName(playerId) .. " (ID: " .. playerId .. ")", Utils.logLevels.INFO)
end

-- Cleanup old data to prevent memory bloat
function NetworkMonitor.Cleanup()
    local currentTime = Natives.GetGameTimer()

    -- Only run cleanup at the specified interval
    if currentTime - NetworkMonitor.lastCleanup < NetworkMonitor.cleanupInterval then
        return
    end

    NetworkMonitor.lastCleanup = currentTime

    -- Get connected players using Utils function to avoid direct native calls
    local connectedPlayers = Utils.GetConnectedPlayers()

    -- Remove data for disconnected players
    for playerId, _ in pairs(NetworkMonitor.eventCounts) do
        if not connectedPlayers[playerId] then
            NetworkMonitor.eventCounts[playerId] = nil
            NetworkMonitor.eventPatterns[playerId] = nil
            Log("Cleaned up network data for disconnected player ID: " .. playerId, Utils.logLevels.DEBUG)
        end
    end

    -- Reset counters for connected players if they've been active for a while
    for playerId, data in pairs(NetworkMonitor.eventCounts) do
        if currentTime - data.lastReset > NetworkMonitor.defaultThresholds.eventSpamTimeWindow then
            -- Store the previous window before resetting
            table.insert(data.timeWindows, {
                events = data.events,
                resources = data.resources,
                totalEvents = data.totalEvents,
                startTime = data.lastReset,
                endTime = currentTime
            })

            -- Keep only the last 5 time windows
            while #data.timeWindows > 5 do
                table.remove(data.timeWindows, 1)
            end

            -- Reset counters
            data.events = {}
            data.resources = {}
            data.totalEvents = 0
            data.lastReset = currentTime

            Log(string.format("^3[NetworkMonitor]^7 Reset event counters for player ID: %d", playerId), 3)
        end
    end

    -- Clean up resource usage data older than 5 minutes
    local fiveMinutesAgo = currentTime - (5 * 60 * 1000)
    for resource, data in pairs(NetworkMonitor.resourceUsage) do
        local newData = {}
        for i, entry in ipairs(data) do
            if entry.timestamp > fiveMinutesAgo then
                table.insert(newData, entry)
            end
        end
        NetworkMonitor.resourceUsage[resource] = newData
    end
end

-- Analyze event patterns for suspicious activity
function NetworkMonitor.AnalyzePatterns()
    local currentTime = Natives.GetGameTimer()

    -- Only run analysis at the specified interval
    if currentTime - NetworkMonitor.lastAnalysis < NetworkMonitor.analysisInterval then
        return
    end

    NetworkMonitor.lastAnalysis = currentTime

    -- Define known suspicious sequences
    local suspiciousSequences = {
        {"playerSpawned", "setModel", "giveWeapon", "giveWeapon", "giveWeapon"}, -- Potential modder spawning with weapons
        {"explosion", "explosion", "explosion", "explosion"}, -- Explosion spam
        {"entityCreated", "entityCreated", "entityCreated", "entityCreated"} -- Entity spam
    }

    -- Analyze patterns for each player
    for playerId, data in pairs(NetworkMonitor.eventPatterns) do
        if #data.lastEvents >= 5 then -- Need at least 5 events to analyze
            -- Check for matches with suspicious sequences
            for _, sequence in ipairs(suspiciousSequences) do
                local sequenceLength = #sequence
                if #data.lastEvents >= sequenceLength then
                    local match = true
                    for i = 1, sequenceLength do
                        local eventIndex = #data.lastEvents - sequenceLength + i
                        if data.lastEvents[eventIndex] ~= sequence[i] then
                            match = false
                            break
                        end
                    end

                    if match then
                        -- Found a suspicious sequence
                        table.insert(data.sequences, {
                            sequence = sequence,
                            timestamp = currentTime
                        })

                        -- Check if we've seen this sequence multiple times
                        local sequenceCount = 0
                        for _, seq in ipairs(data.sequences) do
                            if table.concat(seq.sequence, ",") == table.concat(sequence, ",") then
                                sequenceCount = sequenceCount + 1
                            end
                        end

                        -- Report if threshold exceeded
                        local thresholds = NetworkMonitor.GetThresholds()
                        if sequenceCount >= thresholds.suspiciousSequenceThreshold then
                            NetworkMonitor.ReportSuspiciousSequence(playerId, sequence, sequenceCount)
                        end
                    end
                end
            end
        end
    end
end

-- Report a suspicious sequence to the detection system
function NetworkMonitor.ReportSuspiciousSequence(playerId, sequence, count)
    -- Get the player's session from the server
    local session = nil
    if NexusGuardServer and NexusGuardServer.GetPlayerSession then
        session = NexusGuardServer.GetPlayerSession(playerId)
    end

    local thresholds = NetworkMonitor.GetThresholds()
    -- Prepare detection data
    local detectionData = {
        type = "SuspiciousEventSequence",
        detectedValue = count,
        baselineValue = thresholds.suspiciousSequenceThreshold,
        serverValidated = true,
        context = {
            sequence = sequence,
            count = count,
            sequenceString = table.concat(sequence, ",")
        }
    }

    -- Report the detection using the Detections module
    if NexusGuardServer and NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
        NexusGuardServer.Detections.Process(playerId, "SuspiciousEventSequence", detectionData, session)
    else
        -- Fallback if Detections module is not available
        Log(string.format("^1[NetworkMonitor]^7 Suspicious event sequence detected for %s (ID: %d): %s (Count: %d)",
            Natives.GetPlayerName(playerId) or "Unknown", playerId, table.concat(sequence, ","), count), 1)
    end
end

-- Track an event from a specific resource
function NetworkMonitor.TrackResourceEvent(resourceName, eventName)
    local currentTime = Natives.GetGameTimer()

    -- Initialize resource tracking if needed
    if not NetworkMonitor.resourceUsage[resourceName] then
        NetworkMonitor.resourceUsage[resourceName] = {}
    end

    -- Add event to resource usage
    table.insert(NetworkMonitor.resourceUsage[resourceName], {
        event = eventName,
        timestamp = currentTime
    })

    -- Check for resource event spam
    local thresholds = NetworkMonitor.GetThresholds()
    local eventCount = 0
    local oneMinuteAgo = currentTime - 60000

    for _, event in ipairs(NetworkMonitor.resourceUsage[resourceName]) do
        if event.timestamp > oneMinuteAgo then
            eventCount = eventCount + 1
        end
    end

    -- Report excessive resource usage
    if eventCount > thresholds.resourceEventLimit then
        Log(string.format("^1[NetworkMonitor]^7 Resource '%s' triggered excessive events: %d events in the last minute",
            resourceName, eventCount), 1)

        -- Could add more sophisticated handling here, like temporarily blocking the resource
        return false
    end

    return true
end

-- Monitor network events using FiveM's native event system
function NetworkMonitor.TrackEvent(playerId, eventName, resourceName)
    -- Run cleanup and analysis periodically
    NetworkMonitor.Cleanup()
    NetworkMonitor.AnalyzePatterns()

    local currentTime = Natives.GetGameTimer()
    local thresholds = NetworkMonitor.GetThresholds()

    -- Initialize player tracking if needed
    if not NetworkMonitor.eventCounts[playerId] then
        NetworkMonitor.InitializePlayer(playerId)
    end

    -- Initialize event patterns if needed
    if not NetworkMonitor.eventPatterns[playerId] then
        NetworkMonitor.eventPatterns[playerId] = {
            sequences = {},
            lastEvents = {},
            knownPatterns = {}
        }
    end

    local playerData = NetworkMonitor.eventCounts[playerId]
    local patternData = NetworkMonitor.eventPatterns[playerId]

    -- Track event frequency
    playerData.events[eventName] = (playerData.events[eventName] or 0) + 1
    playerData.totalEvents = playerData.totalEvents + 1

    -- Track resource usage if provided
    if resourceName then
        playerData.resources[resourceName] = (playerData.resources[resourceName] or 0) + 1
        NetworkMonitor.TrackResourceEvent(resourceName, eventName)
    end

    -- Add to event sequence for pattern detection
    table.insert(patternData.lastEvents, eventName)
    if #patternData.lastEvents > 10 then
        table.remove(patternData.lastEvents, 1) -- Keep only the last 10 events
    end

    -- Check for event spam (same event type)
    if playerData.events[eventName] > thresholds.eventSpamLimit then
        -- Prepare detection data
        local detectionData = {
            type = "EventSpam",
            detectedValue = playerData.events[eventName],
            baselineValue = thresholds.eventSpamLimit,
            serverValidated = true,
            context = {
                eventName = eventName,
                count = playerData.events[eventName],
                timeframe = currentTime - playerData.lastReset,
                resourceName = resourceName
            }
        }

        -- Report the detection
        if NexusGuardServer and NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
            local session = NexusGuardServer.GetPlayerSession and NexusGuardServer.GetPlayerSession(playerId)
            NexusGuardServer.Detections.Process(playerId, "EventSpam", detectionData, session)
        else
            -- Fallback if Detections module is not available
            Log(string.format("^1[NetworkMonitor]^7 Event spam detected for %s (ID: %d): %s (%d times in %d ms)",
                Natives.GetPlayerName(playerId) or "Unknown", playerId, eventName, playerData.events[eventName],
                currentTime - playerData.lastReset), 1)
        end

        return false
    end

    -- Check for total event spam (all event types)
    if playerData.totalEvents > thresholds.playerEventLimit then
        -- Prepare detection data
        local detectionData = {
            type = "TotalEventSpam",
            detectedValue = playerData.totalEvents,
            baselineValue = thresholds.playerEventLimit,
            serverValidated = true,
            context = {
                totalEvents = playerData.totalEvents,
                timeframe = currentTime - playerData.lastReset,
                topEvents = NetworkMonitor.GetTopEvents(playerId, 5)
            }
        }

        -- Report the detection
        if NexusGuardServer and NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
            local session = NexusGuardServer.GetPlayerSession and NexusGuardServer.GetPlayerSession(playerId)
            NexusGuardServer.Detections.Process(playerId, "TotalEventSpam", detectionData, session)
        else
            -- Fallback if Detections module is not available
            Log(string.format("^1[NetworkMonitor]^7 Total event spam detected for %s (ID: %d): %d events in %d ms",
                Natives.GetPlayerName(playerId) or "Unknown", playerId, playerData.totalEvents,
                currentTime - playerData.lastReset), 1)
        end

        return false
    end

    return true
end

-- Get the top N most frequent events for a player
function NetworkMonitor.GetTopEvents(playerId, maxCount)
    if not NetworkMonitor.eventCounts[playerId] or not NetworkMonitor.eventCounts[playerId].events then
        return {}
    end

    local events = NetworkMonitor.eventCounts[playerId].events
    local result = {}

    -- Convert events table to array for sorting
    for name, eventCount in pairs(events) do
        table.insert(result, {name = name, count = eventCount})
    end

    -- Sort by count (descending)
    table.sort(result, function(a, b) return a.count > b.count end)

    -- Return only the top N events
    local topEvents = {}
    for i = 1, math.min(maxCount, #result) do
        table.insert(topEvents, {name = result[i].name, count = result[i].count})
    end

    return topEvents
end

-- Get network statistics for a player
function NetworkMonitor.GetPlayerStats(playerId)
    if not NetworkMonitor.eventCounts[playerId] then
        return nil
    end

    local data = NetworkMonitor.eventCounts[playerId]
    local currentTime = Natives.GetGameTimer()

    return {
        totalEvents = data.totalEvents,
        uniqueEvents = NetworkMonitor.CountTableKeys(data.events),
        uniqueResources = NetworkMonitor.CountTableKeys(data.resources),
        topEvents = NetworkMonitor.GetTopEvents(playerId, 5),
        timeActive = currentTime - data.lastReset,
        eventsPerMinute = data.totalEvents / ((currentTime - data.lastReset) / 60000)
    }
end

-- Helper function to count table keys
function NetworkMonitor.CountTableKeys(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Register network event handlers
function NetworkMonitor.RegisterEventHandlers()
    -- Register a handler for all network events (if possible in your FiveM version)
    if Natives.AddEventHandler then
        Natives.AddEventHandler('onServerResourceStart', function(resourceName)
            -- When a resource starts, register handlers for its events
            local resource = Natives.GetResourceByFindIndex(0)
            local i = 0

            while resource do
                if resource == resourceName then
                    -- Register handlers for this resource's events
                    local numEvents = Natives.GetNumResourceMetadata(resource, 'server_event')
                    for j = 0, numEvents-1 do
                        local eventName = Natives.GetResourceMetadata(resource, 'server_event', j)
                        if eventName then
                            Natives.RegisterNetEvent(eventName)
                            Natives.AddEventHandler(eventName, function()
                                -- In FiveM, 'source' is a global variable that contains the player ID
                                -- who triggered the event
                                local playerId = _G.source
                                NetworkMonitor.TrackEvent(playerId, eventName, resourceName)
                            end)
                        end
                    end
                    break
                end
                i = i + 1
                resource = Natives.GetResourceByFindIndex(i)
            end
        end)
    end
end

return NetworkMonitor