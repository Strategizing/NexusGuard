--[[
    NexusGuard Shared Utilities (shared/utils.lua)

    Purpose:
    - Provides common utility functions used across the codebase
    - Centralizes error handling, logging, and common operations
    - Implements efficient caching and optimization strategies
    - Provides fallbacks for missing dependencies

    Usage:
    - Require this module in any file that needs utility functions
    - Example: local Utils = require('shared/utils')
]]

local Utils = {}

-- Forward declaration of Natives (will be loaded later)
local Natives = {}

-- Determine if we're running on the server or client
Utils.isServer = _G.IsDuplicityVersion and _G.IsDuplicityVersion() or false

-- Cache for expensive operations
Utils.cache = {
    natives = {}, -- Cache for native call results
    resources = {}, -- Cache for resource information
    players = {}, -- Cache for player information
    lastCleanup = 0, -- Last time the cache was cleaned up
    cleanupInterval = 60000, -- Cleanup interval in ms (1 minute)
}

-- Logging levels
Utils.logLevels = {
    ERROR = 1,
    WARNING = 2,
    INFO = 3,
    DEBUG = 4,
    TRACE = 5
}

-- Current log level (can be changed at runtime)
Utils.currentLogLevel = Utils.logLevels.INFO

-- Get the NexusGuard API (server or client)
function Utils.GetNexusGuardAPI()
    if Utils.nexusGuardAPI then
        return Utils.nexusGuardAPI
    end

    if Utils.isServer then
        -- Server-side: Try to get the API from exports
        local success, api = pcall(function() return exports['NexusGuard']:GetNexusGuardServerAPI() end)
        if success and api then
            Utils.nexusGuardAPI = api
            return api
        end
    else
        -- Client-side: API should be available from _G.NexusGuard
        if _G.NexusGuard then
            Utils.nexusGuardAPI = _G.NexusGuard
            return _G.NexusGuard
        end
    end

    -- Create a dummy API if not found
    local dummyAPI = {
        Config = { Thresholds = {}, SeverityScores = {} },
        Utils = { Log = function(...) print("[NexusGuard Fallback Log]", ...) end }
    }

    Utils.nexusGuardAPI = dummyAPI
    return dummyAPI
end

-- Enhanced logging function with levels and formatting
function Utils.Log(message, level, ...)
    level = level or Utils.logLevels.INFO

    -- Only log if the current log level is high enough
    if level > Utils.currentLogLevel then
        return
    end

    -- Format additional arguments if provided
    if ... then
        message = string.format(message, ...)
    end

    -- Get level prefix
    local prefix = "^7[INFO]^7"
    if level == Utils.logLevels.ERROR then
        prefix = "^1[ERROR]^7"
    elseif level == Utils.logLevels.WARNING then
        prefix = "^3[WARNING]^7"
    elseif level == Utils.logLevels.DEBUG then
        prefix = "^5[DEBUG]^7"
    elseif level == Utils.logLevels.TRACE then
        prefix = "^8[TRACE]^7"
    end

    -- Try to use the NexusGuard logging function if available
    local api = Utils.GetNexusGuardAPI()
    if api and api.Utils and api.Utils.Log then
        api.Utils.Log(prefix .. " " .. message, level)
    else
        -- Fallback to print
        print(prefix .. " " .. message)
    end
end

-- Check if a dependency is available
function Utils.CheckDependency(resourceName)
    if not resourceName then return false end

    -- Check if the resource exists and is started
    if GetResourceState(resourceName) == "started" then
        return true
    end

    return false
end

-- Check if ox_lib is available and get specific components
function Utils.GetOxLib(component)
    if not Utils.CheckDependency('ox_lib') then
        Utils.Log("ox_lib dependency not found or not started", Utils.logLevels.WARNING)
        return nil
    end

    -- Try to access the requested component
    if component then
        if lib and lib[component] then
            return lib[component]
        else
            Utils.Log("ox_lib.%s component not found", Utils.logLevels.WARNING, component)
            return nil
        end
    end

    -- Return the entire lib object
    return lib
end

-- JSON encode with error handling and fallbacks
function Utils.JsonEncode(data)
    -- Try ox_lib first
    local oxLib = Utils.GetOxLib('json')
    if oxLib then
        local success, result = pcall(oxLib.encode, data)
        if success then
            return result
        end
    end

    -- Fallback to json.encode if available
    if json and json.encode then
        local success, result = pcall(json.encode, data)
        if success then
            return result
        end
    end

    -- Last resort: basic serialization for simple tables
    Utils.Log("JSON encoding failed, using basic serialization", Utils.logLevels.WARNING)
    return Utils.SerializeTable(data)
end

-- JSON decode with error handling and fallbacks
function Utils.JsonDecode(jsonString)
    if type(jsonString) ~= "string" then
        return nil
    end

    -- Try ox_lib first
    local oxLib = Utils.GetOxLib('json')
    if oxLib then
        local success, result = pcall(oxLib.decode, jsonString)
        if success then
            return result
        end
    end

    -- Fallback to json.decode if available
    if json and json.decode then
        local success, result = pcall(json.decode, jsonString)
        if success then
            return result
        end
    end

    Utils.Log("JSON decoding failed, returning nil", Utils.logLevels.WARNING)
    return nil
end

-- Basic table serialization (for fallback when JSON encoding fails)
function Utils.SerializeTable(tbl, indent)
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end

    indent = indent or 0
    local result = "{\n"
    local indentStr = string.rep("  ", indent + 1)

    for k, v in pairs(tbl) do
        local key = type(k) == "string" and string.format("%q", k) or tostring(k)
        result = result .. indentStr .. "[" .. key .. "] = "

        if type(v) == "table" then
            result = result .. Utils.SerializeTable(v, indent + 1)
        elseif type(v) == "string" then
            result = result .. string.format("%q", v)
        else
            result = result .. tostring(v)
        end

        result = result .. ",\n"
    end

    return result .. string.rep("  ", indent) .. "}"
end

-- Secure hash function. Returns nil when no cryptographic hash function is available
function Utils.Hash(data, algorithm)
    algorithm = algorithm or "sha256"

    -- Try ox_lib first
    local oxLib = Utils.GetOxLib('crypto')
    if not oxLib or not oxLib.hash then
        Utils.Log("Crypto hashing unavailable - no suitable library found", Utils.logLevels.WARNING)
        return nil
    end

    local success, result = pcall(oxLib.hash, algorithm, data)
    if success then
        return result
    end

    Utils.Log("Crypto hashing failed: %s", Utils.logLevels.WARNING, tostring(result))
    return nil
end

-- Count the number of key/value pairs in a table
function Utils.TableSize(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

-- Get connected players with caching
function Utils.GetConnectedPlayers()
    -- Check cache first
    local currentTime = GetGameTimer()
    if Utils.cache.connectedPlayers and
       (currentTime - (Utils.cache.connectedPlayers.timestamp or 0)) < 2000 then
        return Utils.cache.connectedPlayers.data
    end

    -- Get connected players
    local players = {}
    local playerList = GetPlayers()

    for _, id in ipairs(playerList) do
        local playerId = tonumber(id)
        if playerId then
            players[playerId] = true
        end
    end

    -- Cache the result
    Utils.cache.connectedPlayers = {
        data = players,
        timestamp = currentTime
    }

    return players
end

-- Get player information with caching
function Utils.GetPlayerInfo(playerId)
    if not playerId then return nil end

    -- Check cache first
    if Utils.cache.players[playerId] and
       (GetGameTimer() - Utils.cache.players[playerId].timestamp) < 5000 then
        return Utils.cache.players[playerId].data
    end

    -- Get player information
    local info = {
        name = GetPlayerName(playerId),
        identifiers = {},
        ping = GetPlayerPing(playerId),
        endpoint = GetPlayerEndpoint(playerId)
    }

    -- Get player identifiers
    for i = 0, GetNumPlayerIdentifiers(playerId) - 1 do
        local identifier = GetPlayerIdentifier(playerId, i)
        if identifier then
            local idType, idValue = identifier:match("([^:]+):(.+)")
            if idType and idValue then
                info.identifiers[idType] = idValue
            end
        end
    end

    -- Cache the result
    Utils.cache.players[playerId] = {
        data = info,
        timestamp = GetGameTimer()
    }

    return info
end

-- Clean up caches to prevent memory bloat
function Utils.CleanupCaches()
    local currentTime = GetGameTimer()

    -- Only run cleanup at the specified interval
    if currentTime - Utils.cache.lastCleanup < Utils.cache.cleanupInterval then
        return
    end

    Utils.cache.lastCleanup = currentTime

    -- Clean up player cache
    local connectedPlayers = {}
    for _, id in ipairs(GetPlayers()) do
        connectedPlayers[tonumber(id)] = true
    end

    for playerId, _ in pairs(Utils.cache.players) do
        if not connectedPlayers[playerId] then
            Utils.cache.players[playerId] = nil
        end
    end

    -- Clean up other caches as needed
    -- ...

    Utils.Log("Cache cleanup completed", Utils.logLevels.DEBUG)
end

-- Throttle function calls to prevent spam
local throttledFunctions = {}
function Utils.Throttle(func, key, cooldown)
    key = key or tostring(func)
    cooldown = cooldown or 1000 -- Default 1 second cooldown

    if not throttledFunctions[key] then
        throttledFunctions[key] = {
            lastCall = 0,
            cooldown = cooldown
        }
    end

    local throttleData = throttledFunctions[key]
    local currentTime = GetGameTimer()

    if currentTime - throttleData.lastCall >= throttleData.cooldown then
        throttleData.lastCall = currentTime
        return func()
    end

    return nil, "throttled"
end

-- Measure execution time of a function
function Utils.MeasureExecution(name, func, ...)
    if not name or type(func) ~= "function" then return nil end

    local startTime = GetGameTimer()
    local results = {func(...)}
    local endTime = GetGameTimer()
    local executionTime = endTime - startTime

    Utils.Log("Function '%s' executed in %d ms", Utils.logLevels.DEBUG, name, executionTime)

    return executionTime, table.unpack(results)
end

-- Get a table of all resources with their states
function Utils.GetAllResources()
    -- Check cache first
    local currentTime = GetGameTimer()
    if Utils.cache.resources.timestamp and
       (currentTime - Utils.cache.resources.timestamp) < 10000 then
        return Utils.cache.resources.data
    end

    local resources = {}
    local i = 0
    local resourceName = GetResourceByFindIndex(i)

    while resourceName do
        resources[resourceName] = {
            state = GetResourceState(resourceName),
            path = GetResourcePath(resourceName)
        }

        i = i + 1
        resourceName = GetResourceByFindIndex(i)
    end

    -- Cache the result
    Utils.cache.resources = {
        data = resources,
        timestamp = currentTime
    }

    return resources
end

-- Deep copy a table
function Utils.DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Utils.DeepCopy(orig_key)] = Utils.DeepCopy(orig_value)
        end
        setmetatable(copy, Utils.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Initialize the module
function Utils.Initialize()
    -- Set up periodic cache cleanup
    if Utils.isServer then
        -- Only create the thread on the server to avoid duplicate cleanup
        Citizen.CreateThread(function()
            -- Wait a bit to ensure everything is loaded
            Citizen.Wait(1000)

            -- Periodic cleanup
            while true do
                Utils.CleanupCaches()
                Citizen.Wait(Utils.cache.cleanupInterval)
            end
        end)
    end

    return true
end

-- Call initialize if we're on the server
if Utils.isServer then
    Utils.Initialize()
end

return Utils
