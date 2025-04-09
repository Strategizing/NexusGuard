--[[
    NexusGuard Module Loader (shared/module_loader.lua)

    A lightweight module loader that prevents circular dependencies and ensures
    modules are only loaded once. Provides a consistent way to load modules
    across the codebase.

    Usage:
    local ModuleLoader = require('shared/module_loader')
    local Utils = ModuleLoader.Load('shared/utils')
    -- or
    local Natives = ModuleLoader.LoadByName('natives')
]]

local ModuleLoader = {
    -- Single cache table for all module states
    cache = {
        loaded = {}, -- Fully loaded modules
        loading = {} -- Modules currently being loaded (for circular dependency detection)
    },

    -- Common module paths mapping
    paths = {
        utils = 'shared/utils',
        natives = 'shared/natives',
        eventRegistry = 'shared/event_registry',
        performanceManager = 'shared/performance_manager',
        stateValidator = 'server/modules/state_validator',
        networkMonitor = 'server/modules/network_monitor',
        resourceValidator = 'server/modules/resource_validator',
        detections = 'server/modules/detections'
    }
}

-- Load a module with circular dependency handling
function ModuleLoader.Load(modulePath, isOptional)
    -- Check if the module is already loaded
    if ModuleLoader.cache.loaded[modulePath] then
        return ModuleLoader.cache.loaded[modulePath]
    end

    -- Check if the module is currently being loaded (circular dependency)
    if ModuleLoader.cache.loading[modulePath] then
        -- Return a proxy object that will be filled in later
        return ModuleLoader.cache.loading[modulePath]
    end

    -- Create a proxy object for circular dependencies
    local proxy = {}
    ModuleLoader.cache.loading[modulePath] = proxy

    -- Try to load the module
    local success, module = pcall(require, modulePath)

    if not success then
        if isOptional then
            -- Just return nil for optional modules that fail to load
            ModuleLoader.cache.loading[modulePath] = nil
            return nil
        else
            -- Log error and return empty table to prevent crashes
            print("^1[ModuleLoader] Failed to load module: " .. modulePath .. " - " .. tostring(module) .. "^7")
            module = {}
        end
    end

    -- Store the loaded module
    ModuleLoader.cache.loaded[modulePath] = module

    -- Fill in the proxy object for circular dependencies
    for k, v in pairs(module) do
        proxy[k] = v
    end

    -- Clear the loading flag
    ModuleLoader.cache.loading[modulePath] = nil

    return module
end

-- Load a module by its short name
function ModuleLoader.LoadByName(moduleName, isOptional)
    local path = ModuleLoader.paths[moduleName]
    if not path then
        if isOptional then
            return nil
        else
            print("^1[ModuleLoader] Unknown module name: " .. moduleName .. "^7")
            return {}
        end
    end

    return ModuleLoader.Load(path, isOptional)
end

-- Clear the module cache
function ModuleLoader.ClearCache()
    ModuleLoader.cache.loaded = {}
    -- Don't clear loading cache during operation to avoid issues
end

-- Get a list of all loaded modules
function ModuleLoader.GetLoadedModules()
    return ModuleLoader.cache.loaded
end

-- Preload commonly used modules
function ModuleLoader.PreloadCommonModules()
    -- Core modules
    ModuleLoader.Load('shared/utils')
    ModuleLoader.Load('shared/natives')
    ModuleLoader.Load('shared/event_registry')
    ModuleLoader.Load('shared/performance_manager')
end

-- Initialize the module loader if in FiveM environment
if _G.Citizen then
    -- Use pcall to avoid errors if Citizen API is not fully available
    pcall(function()
        Citizen.CreateThread(function()
            Citizen.Wait(0) -- Wait one frame to ensure everything is loaded
            ModuleLoader.PreloadCommonModules()
        end)
    end)
end

return ModuleLoader
