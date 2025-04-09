--[[
    NexusGuard FiveM Natives Wrapper (shared/natives.lua)

    A lightweight wrapper for FiveM native functions that provides error handling,
    caching for expensive calls, and consistent behavior across the codebase.
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
    isServer = _G.IsDuplicityVersion and _G.IsDuplicityVersion() or false,
    hasCitizen = _G.Citizen ~= nil
}

-- Helper function to safely call natives with error handling
local function safeCall(nativeName, defaultValue, ...)
    if not _G[nativeName] then return defaultValue end

    local success, result = pcall(_G[nativeName], ...)
    return success and result or defaultValue
end

-- Setup cache cleanup if Citizen is available
if env.hasCitizen and _G.Citizen then
    Citizen.CreateThread(function()
        while true do
            Citizen.Wait(cache.config.cleanupInterval)

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
    local defaultValue = _G.vector3 and _G.vector3(0, 0, 0) or {x=0, y=0, z=0}
    if not Natives.DoesEntityExist(entity) then return defaultValue end

    return getCachedOrFetch('entity', entity, function(ent)
        return safeCall('GetEntityCoords', nil, ent)
    end, defaultValue, 100) -- 100ms cache for coords
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

-- Generate common player functions
local playerFunctions = {
    {name = "GetPlayers", default = {}, noPlayerId = true},
    {name = "GetPlayerName", default = "Unknown"},
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
            local r, a = GetAmmoInClip(ped, weaponHash)
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

-- MISC NATIVES

-- Generate common misc functions
local miscFunctions = {
    {name = "GetGameTimer", default = 0, noParams = true},
    {name = "ExecuteCommand", default = false, checkParam = true}
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

return Natives
