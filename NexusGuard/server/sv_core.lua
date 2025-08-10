--[[
    NexusGuard Core Module (server/sv_core.lua)

    Purpose:
    - Provides the central API initialization and management
    - Handles module loading and dependency injection
    - Manages the lifecycle of the anti-cheat system
    - Provides a unified interface for other resources to interact with NexusGuard

    Dependencies:
    - All other NexusGuard modules
    - Config table from config.lua

    Usage:
    - Required by server/globals.lua
    - Initializes and manages all other modules
    - Provides API functions for external resources
]]

local Core = {
    -- Module references
    modules = {},

    -- Module initialization status
    initialized = false,

    -- Version information
    version = {
        major = 1,
        minor = 0,
        patch = 0,
        string = "1.0.0"
    },

    -- Performance metrics
    metrics = {
        startTime = os.time(),
        moduleLoadTimes = {},
        apiCalls = 0,
        lastReset = os.time()
    },

    -- Server-side tracking (merged from server/modules/core.lua)
    PlayerMetrics = {},
    OnlineAdmins = {}
}

-- Local references to required modules (will be set during initialization)
local Utils, Log, Config, Natives, Dependencies

--[[
    Initializes the Core module and loads all required dependencies.

    @param cfg (table): The main Config table
    @param utils (table): The Utils module
    @return (boolean): True if initialization was successful, false otherwise
]]
function Core.Initialize(cfg, utils)
    if Core.initialized then
        return true -- Already initialized
    end

    -- Store references to required modules
    Utils = utils
    Log = Utils.Log
    Config = cfg or {}

    -- Load essential dependencies
    Natives = require('shared/natives')
    Dependencies = require('shared/dependency_manager')

    -- Initialize the dependency manager
    Dependencies.Initialize(Log)

    -- Log initialization
    Log("^2[Core]^7 Initializing NexusGuard Core module...", 2)

    -- Load and initialize all modules
    local startTime = os.clock()
    local success = Core.LoadModules()
    Core.metrics.moduleLoadTime = os.clock() - startTime

    if success then
        Core.initialized = true
        Log(("^2[Core]^7 NexusGuard Core initialized successfully. Version: %s. Modules loaded in %.2f ms"):format(
            Core.version.string, Core.metrics.moduleLoadTime * 1000
        ), 2)
        return true
    else
        Log("^1[Core]^7 Failed to initialize NexusGuard Core module.", 1)
        return false
    end
end

--[[
    Loads and initializes all required modules.

    @return (boolean): True if all modules were loaded successfully, false otherwise
]]
function Core.LoadModules()
    local moduleLoadOrder = {
        "Security",
        "Session",
        "Database",
        "Bans",
        "Discord",
        "Detections",
        "EventHandlers"
    }

    -- Load each module in order
    for _, moduleName in ipairs(moduleLoadOrder) do
        local startTime = os.clock()
        local success, module = pcall(function()
            return require('server/sv_' .. string.lower(moduleName))
        end)

        if not success then
            -- Special case for Detections which is in a subdirectory
            if moduleName == "Detections" then
                success, module = pcall(function()
                    return require('server/modules/detections')
                end)
            end
        end

        if success and module then
            -- Store the module reference
            Core.modules[moduleName] = module

            -- Initialize the module if it has an Initialize function
            if type(module.Initialize) == "function" then
                local initSuccess, err = pcall(function()
                    module.Initialize(Config, Log)
                end)

                if not initSuccess then
                    Log(("^1[Core]^7 Failed to initialize module '%s': %s"):format(moduleName, tostring(err)), 1)
                    return false
                end
            end

            -- Record load time
            Core.metrics.moduleLoadTimes[moduleName] = os.clock() - startTime
            Log(("^2[Core]^7 Loaded module '%s' in %.2f ms"):format(moduleName, (os.clock() - startTime) * 1000), 3)
        else
            Log(("^1[Core]^7 Failed to load module '%s'"):format(moduleName), 1)
            return false
        end
    end

    return true
end

--[[
    Gets a reference to a loaded module.

    @param moduleName (string): The name of the module to get
    @return (table): The module reference, or nil if not found
]]
function Core.GetModule(moduleName)
    return Core.modules[moduleName]
end

--[[
    Gets the current status of the NexusGuard system.

    @return (table): A table containing status information
]]
function Core.GetStatus()
    local status = {
        version = Core.version.string,
        uptime = os.time() - Core.metrics.startTime,
        initialized = Core.initialized,
        modules = {},
        dependencies = Dependencies.status
    }

    -- Collect module status
    for name, module in pairs(Core.modules) do
        status.modules[name] = {
            loaded = module ~= nil,
            hasGetStats = type(module.GetStats) == "function"
        }

        -- Get module stats if available
        if status.modules[name].hasGetStats then
            status.modules[name].stats = module.GetStats()
        end
    end

    return status
end

--[[
    Resets performance metrics.
]]
function Core.ResetMetrics()
    Core.metrics.apiCalls = 0
    Core.metrics.lastReset = os.time()

    -- Reset module metrics if they have a ResetStats function
    for name, module in pairs(Core.modules) do
        if type(module.ResetStats) == "function" then
            module.ResetStats()
        end
    end

    Log("^2[Core]^7 Performance metrics reset.", 3)
end

--[[
    Gets a player's session, delegating to the Session module.

    @param playerId (number): The server ID of the player
    @return (table): The player's session, or nil if not found
]]
function Core.GetSession(playerId)
    if not Core.modules.Session then
        Log("^1[Core]^7 Session module not loaded. Cannot get player session.", 1)
        return nil
    end

    return Core.modules.Session.GetSession(playerId)
end

--[[
    Cleans up a player's session, delegating to the Session module.

    @param playerId (number): The server ID of the player
    @return (boolean): True if the session was cleaned up, false otherwise
]]
function Core.CleanupSession(playerId)
    if not Core.modules.Session then
        Log("^1[Core]^7 Session module not loaded. Cannot cleanup player session.", 1)
        return false
    end

    return Core.modules.Session.CleanupSession(playerId)
end

--[[
    Processes a detection report, delegating to the Detections module.

    @param playerId (number): The server ID of the player
    @param detectionType (string): The type of detection
    @param detectionData (table): The detection data
    @return (boolean): True if the detection was processed, false otherwise
]]
function Core.ProcessDetection(playerId, detectionType, detectionData)
    if not Core.modules.Detections then
        Log("^1[Core]^7 Detections module not loaded. Cannot process detection.", 1)
        return false
    end

    local session = Core.GetSession(playerId)
    if not session then
        Log(("^1[Core]^7 No session found for player %d. Cannot process detection."):format(playerId), 1)
        return false
    end

    return Core.modules.Detections.Process(playerId, detectionType, detectionData, session)
end

-- Export the Core module
return Core
