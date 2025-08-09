--[[
    NexusGuard FiveM Natives Wrapper (shared/natives.lua)

    A comprehensive wrapper for FiveM native functions that provides:
    - Error handling and safe execution
    - Performance optimization through caching
    - Consistent behavior across the codebase
    - Fallbacks for missing or failed native calls
    - Support for both client and server environments
    - Logging for critical native calls

    Usage:
    local Natives = require('shared/natives')
    local playerCoords = Natives.GetEntityCoords(Natives.GetPlayerPed(playerId))
    Natives.SetEntityCoords(ped, x, y, z, ...) -- Will log the call
]]

local Natives = {}

-- Cache configuration
local cache = {
    data = {
        entity = {},
        player = {},
        resource = {}
    },
    config = {
        enabled = true,
        ttl = 5000, -- Time to live: 5 seconds
        cleanupInterval = 10000 -- Cleanup every 10 seconds
    },
    lastCleanup = 0
}

-- Environment detection
local env = {
    isServer = false, -- Will be set correctly below
    hasCitizen = _G.Citizen ~= nil
}

-- Detect if we're on the server side
if _G.IsDuplicityVersion then
    env.isServer = _G.IsDuplicityVersion()
elseif _G.Citizen and _G.Citizen.IsDuplicityVersion then
    env.isServer = _G.Citizen.IsDuplicityVersion()
end
-- Helper function to safely call natives with error handling
local function safeCall(nativeName, defaultValue, ...)
    -- Check if the native exists in the global scope
    local nativeFunc = _G[nativeName]
    if not nativeFunc then
        -- Check if it's a Citizen method (e.g., Citizen.CreateThread)
        if string.find(nativeName, "%.") then
            local parts = {}
            for part in string.gmatch(nativeName, "[^%.]+") do table.insert(parts, part) end
            if #parts == 2 and _G[parts[1]] and type(_G[parts[1]][parts[2]]) == "function" then
                nativeFunc = _G[parts[1]][parts[2]]
            end
        end
    end

    if not nativeFunc then
        -- print(("^1[NexusGuard Natives] Warning: Native '%s' not found.^7"):format(nativeName)) -- Optional warning
        return defaultValue
    end

    local success, result = pcall(nativeFunc, ...)
    if not success then
        -- Log the error but don't spam the console
        if math.random() < 0.1 then -- Only log about 10% of errors to avoid spam
            print(("^1[NexusGuard Natives] Error calling native '%s': %s^7"):format(nativeName, tostring(result)))
        end
    end
    return success and result or defaultValue
end

-- Expose environment check through the wrapper
function Natives.IsDuplicityVersion()
    return safeCall('IsDuplicityVersion', false)
end

-- Helper function for logging critical native calls
local function logCriticalNativeCall(nativeName, ...)
    local source = "Unknown"
    if env.isServer then
        -- On server, 'source' is usually available in the event handler context, not directly here.
        -- We might need to pass it explicitly if server-side monitoring is desired via this wrapper.
        source = "Server Context"
    else
        -- On client, we can get the local player ID.
        local playerId = safeCall('PlayerId', -1)
        source = "Client:" .. tostring(playerId)
    end
    -- Basic logging for now. Could be expanded to send events.
    local args = { ... }
    local argsStr = ""
    for i, v in ipairs(args) do
        argsStr = argsStr .. tostring(v) .. (i < #args and ", " or "")
    end
    print(("^3[NexusGuard Native Monitor]^7 Critical native '%s' called by %s with args: [%s]^7"):format(nativeName,
        source, argsStr))
end
-- Setup cache cleanup if Citizen is available
if env.hasCitizen and _G.Citizen then
    _G.Citizen.CreateThread(function()
        while true do
            _G.Citizen.Wait(cache.config.cleanupInterval)

            local currentTime = safeCall('GetGameTimer', 0)
            cache.lastCleanup = currentTime

            -- Clean up all cache types
            for cacheType, cacheData in pairs(cache.data) do
                for key, entry in pairs(cacheData) do
                    if currentTime - entry.timestamp > cache.config.ttl then
                        cache.data[cacheType][key] = nil
                    end
                end
            end
        end
    end)
end

-- Generic function to get cached data or fetch it
local function getCachedOrFetch(cacheType, key, fetchFunc, defaultValue, ttl)
    if not key or key == 0 then return defaultValue end
    if not cache.config.enabled then return fetchFunc(key) or defaultValue end

    local currentTime = safeCall('GetGameTimer', 0)
    local cacheEntry = cache.data[cacheType][key]

    -- Return from cache if valid
    if cacheEntry and currentTime - cacheEntry.timestamp < (ttl or cache.config.ttl) then
        return cacheEntry.data
    end

    -- Fetch new data
    local result = fetchFunc(key)
    if result ~= nil then
        -- Store in cache
        cache.data[cacheType][key] = {
            data = result,
            timestamp = currentTime
        }
        return result
    end

    return defaultValue
end

-- ENTITY NATIVES

-- Check if an entity exists with error handling
function Natives.DoesEntityExist(entity)
    if not entity or entity == 0 then return false end
    return safeCall('DoesEntityExist', false, entity)
end

-- Get entity coordinates with caching
function Natives.GetEntityCoords(entity)
    local defaultValue = nil
    if not Natives.DoesEntityExist(entity) then return defaultValue end

    return getCachedOrFetch('entity', entity, function(ent)
        return safeCall('GetEntityCoords', nil, ent)
    end, defaultValue, 100) -- 100ms cache for coords
end

-- Specific wrapper for SetEntityCoords to add logging
function Natives.SetEntityCoords(entity, x, y, z, xAxis, yAxis, zAxis, clearArea)
    -- Log the call (only on client for now, as server context is harder to get here)
    if not env.isServer then
        logCriticalNativeCall('SetEntityCoords', entity, x, y, z, xAxis, yAxis, zAxis, clearArea)
    end
    -- Call the actual native
    return safeCall('SetEntityCoords', nil, entity, x, y, z, xAxis, yAxis, zAxis, clearArea)
end
-- Generate common entity functions
local entityFunctions = {
    {name = "GetEntityVelocity", default = function() return _G.vector3 and _G.vector3(0, 0, 0) or {x=0, y=0, z=0} end},
    {name = "GetEntityHeading", default = 0.0},
    {name = "GetEntityRotation", default = function() return _G.vector3 and _G.vector3(0, 0, 0) or {x=0, y=0, z=0} end},
    {name = "GetEntityHealth", default = 0},
    {name = "GetEntityMaxHealth", default = 0},
    {name = "GetEntityModel", default = 0},
    {name = "IsEntityDead", default = false},
    {name = "GetEntitySpeed", default = 0.0}
}

-- Create all entity functions
for _, func in ipairs(entityFunctions) do
    Natives[func.name] = function(entity)
        if not Natives.DoesEntityExist(entity) then
            return type(func.default) == "function" and func.default() or func.default
        end
        return safeCall(func.name, type(func.default) == "function" and func.default() or func.default, entity)
    end
end

-- PLAYER NATIVES

-- Specific wrapper for SetPlayerInvincible to add logging
function Natives.SetPlayerInvincible(playerId, toggle)
    -- Log the call (only on client for now)
    if not env.isServer then
        logCriticalNativeCall('SetPlayerInvincible', playerId, toggle)
    end
    -- Call the actual native
    return safeCall('SetPlayerInvincible', nil, playerId, toggle)
end

-- Specific wrapper for GetPlayerInvincible (no logging needed, just safe call)
function Natives.GetPlayerInvincible(playerId)
    if not playerId or playerId < 1 then return false end
    return safeCall('GetPlayerInvincible', false, playerId)
end
-- Generate common player functions
local playerFunctions = {
    {name = "GetPlayers", default = {}, noPlayerId = true},
    {name = "GetPlayerName", default = nil},
    {name = "GetPlayerPed", default = 0},
    {name = "GetPlayerPing", default = 0},
    {name = "IsPlayerFreeAiming", default = false}
}

-- Create all player functions
for _, func in ipairs(playerFunctions) do
    Natives[func.name] = function(playerId)
        if not func.noPlayerId and (not playerId or playerId < 1) then
            return type(func.default) == "function" and func.default() or func.default
        end

        if func.noPlayerId then
            return safeCall(func.name, type(func.default) == "function" and func.default() or func.default)
        else
            return safeCall(func.name, type(func.default) == "function" and func.default() or func.default, playerId)
        end
    end
end

-- Get player endpoint (IP) - server only
function Natives.GetPlayerEndpoint(playerId)
    if not playerId or not env.isServer then return "" end
    return safeCall('GetPlayerEndpoint', "", playerId)
end

-- Get player identifiers - server only
function Natives.GetPlayerIdentifiers(playerId)
    if not playerId or not env.isServer then return {} end

    return getCachedOrFetch('player', playerId, function(pid)
        local identifiers = {}

        -- Get number of identifiers
        local numIdentifiers = safeCall('GetNumPlayerIdentifiers', 0, pid)
        if numIdentifiers == 0 then return identifiers end

        -- Get each identifier
        for i = 0, numIdentifiers - 1 do
            local identifier = safeCall('GetPlayerIdentifier', nil, pid, i)
            if identifier then
                local idType, idValue = identifier:match("([^:]+):(.+)")
                if idType and idValue then
                    identifiers[idType] = idValue
                else
                    identifiers[i] = identifier
                end
            end
        end

        return identifiers
    end, {})
end

-- PED NATIVES

-- Generate common ped functions
local pedFunctions = {
    {name = "GetPedArmour", default = 0},
    {name = "GetVehiclePedIsIn", default = 0, extraArg = false},
    {name = "GetSelectedPedWeapon", default = 0},
    {name = "IsPedFalling", default = false},
    {name = "IsPedRagdoll", default = false},
    {name = "GetPedParachuteState", default = 0},
    {name = "IsPedSwimming", default = false},
    {name = "IsPedJumping", default = false},
    {name = "IsPedClimbing", default = false},
    { name = "IsPedVaulting",            default = false },
    { name = "IsPedGettingUp",           default = false },
    { name = "IsPedInParachuteFreeFall", default = false },
    {name = "IsPedReloading", default = false},
    {name = "IsPedShooting", default = false}
}

-- Create all ped functions
for _, func in ipairs(pedFunctions) do
    Natives[func.name] = function(ped, ...)
        if not Natives.DoesEntityExist(ped) then
            return type(func.default) == "function" and func.default() or func.default
        end

        if func.extraArg ~= nil then
            return safeCall(func.name, type(func.default) == "function" and func.default() or func.default, ped, func.extraArg)
        else
            return safeCall(func.name, type(func.default) == "function" and func.default() or func.default, ped, ...)
        end
    end
end

-- Special case for GetAmmoInClip which returns multiple values
function Natives.GetAmmoInClip(ped, weaponHash)
    if not Natives.DoesEntityExist(ped) or not weaponHash or weaponHash == 0 then
        return false, 0
    end

    local success, result, ammo = pcall(function()
        if _G.GetAmmoInClip then
            local r, a = _G.GetAmmoInClip(ped, weaponHash)
            return r, a
        end
        return false, 0
    end)

    return success and result or false, success and ammo or 0
end

-- Special case for GetAmmoInPedWeapon
function Natives.GetAmmoInPedWeapon(ped, weaponHash)
    if not Natives.DoesEntityExist(ped) or not weaponHash or weaponHash == 0 then
        return 0
    end

    return safeCall('GetAmmoInPedWeapon', 0, ped, weaponHash)
end

-- VEHICLE NATIVES

-- Get vehicle class
function Natives.GetVehicleClass(vehicle)
    if not Natives.DoesEntityExist(vehicle) then return -1 end
    return safeCall('GetVehicleClass', -1, vehicle)
end

-- RESOURCE NATIVES

-- Generate common resource functions
local resourceFunctions = {
    {name = "GetResourceState", default = "unknown", checkParam = true},
    {name = "GetResourcePath", default = "", checkParam = true},
    {name = "GetResourceByFindIndex", default = nil, checkParam = true, paramType = "number"},
    {name = "LoadResourceFile", default = nil, checkParam = true, extraParam = true}
}

-- Create all resource functions
for _, func in ipairs(resourceFunctions) do
    Natives[func.name] = function(param1, param2)
        if func.checkParam then
            if not param1 then return func.default end
            if func.paramType and type(param1) ~= func.paramType then return func.default end
        end

        if func.extraParam then
            if not param2 then return func.default end
            return safeCall(func.name, func.default, param1, param2)
        else
            return safeCall(func.name, func.default, param1)
        end
    end
end

-- Special case for GetResourceMetadata which has an optional index parameter
function Natives.GetResourceMetadata(resourceName, metadataKey, index)
    if not resourceName or not metadataKey then return nil end
    return safeCall('GetResourceMetadata', nil, resourceName, metadataKey, index or 0)
end

-- RAYCAST NATIVES

-- StartShapeTestRay - Performs a raycast from one point to another
function Natives.StartShapeTestRay(x1, y1, z1, x2, y2, z2, flags, entity, p8)
    if not x1 or not y1 or not z1 or not x2 or not y2 or not z2 then
        return 0
    end

    flags = flags or 1
    entity = entity or 0
    p8 = p8 or 0

    return safeCall('StartShapeTestRay', 0, x1, y1, z1, x2, y2, z2, flags, entity, p8)
end

-- GetShapeTestResult - Gets the result of a raycast
function Natives.GetShapeTestResult(rayHandle)
    if not rayHandle or rayHandle == 0 then
        local zeroVec = Natives.vector3(0, 0, 0)
        return 0, 0, zeroVec, zeroVec, 0
    end

    local success, result = pcall(function()
        if _G.GetShapeTestResult then
            return _G.GetShapeTestResult(rayHandle)
        end
        local zeroVec = Natives.vector3(0, 0, 0)
        return 0, 0, zeroVec, zeroVec, 0
    end)

    if success then
        return result
    else
        local zeroVec = Natives.vector3(0, 0, 0)
        return 0, 0, zeroVec, zeroVec, 0
    end
end
-- MISC NATIVES

-- Vector3 function for consistent vector handling
function Natives.vector3(x, y, z)
    -- Use native vector3 if available
    if _G.vector3 then
        return _G.vector3(x or 0.0, y or 0.0, z or 0.0)
    end

    -- Fallback to table representation
    return { x = x or 0.0, y = y or 0.0, z = z or 0.0 }
end
-- Generate common misc functions
local miscFunctions = {
    {name = "GetGameTimer", default = 0, noParams = true},
    { name = "ExecuteCommand", default = false, checkParam = true },
    { name = "SetTimeout",     default = false, checkParam = true }
}

-- Create all misc functions
for _, func in ipairs(miscFunctions) do
    Natives[func.name] = function(param)
        if func.checkParam and not param then return func.default end

        if func.noParams then
            return safeCall(func.name, func.default)
        else
            return safeCall(func.name, func.default, param)
        end
    end
end

-- Special case for GetConvarInt and GetConvar which have default values
function Natives.GetConvarInt(name, default)
    if not name then return default or 0 end
    return safeCall('GetConvarInt', default or 0, name, default or 0)
end

function Natives.GetConvar(name, default)
    if not name then return default or "" end
    return safeCall('GetConvar', default or "", name, default or "")
end

-- FiveM specific functions
function Natives.AddEventHandler(eventName, callback)
    if not eventName or type(callback) ~= "function" then return false end
    return safeCall('AddEventHandler', false, eventName, callback)
end

function Natives.CreateThread(callback)
    if not callback or type(callback) ~= "function" then return false end
    if not _G.Citizen then return false end
    return safeCall('Citizen.CreateThread', false, callback)
end

function Natives.Wait(ms)
    if not _G.Citizen then return false end
    return safeCall('Citizen.Wait', false, ms or 0)
end

-- Add wrappers for event triggering to potentially add logging/validation later
function Natives.TriggerServerEvent(eventName, ...)
    return safeCall('TriggerServerEvent', nil, eventName, ...)
end

function Natives.TriggerClientEvent(eventName, target, ...)
    return safeCall('TriggerClientEvent', nil, eventName, target, ...)
end

-- Add wrapper for RegisterNetEvent
function Natives.RegisterNetEvent(eventName)
    return safeCall('RegisterNetEvent', nil, eventName)
end
return Natives
