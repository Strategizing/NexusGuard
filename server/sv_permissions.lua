--[[
    NexusGuard Server Permissions Module
    Handles admin checks based on configured framework.
]]

local Utils = require('server/sv_utils') -- Load the utils module
local Log = Utils.Log

local Permissions = {}
local ESX = nil
local QBCore = nil

-- Attempt to load framework objects (Needs to run early)
Citizen.CreateThread(function()
    Citizen.Wait(1000) -- Give frameworks time to load
    if GetResourceState('es_extended') == 'started' then
        local esxExport = exports['es_extended']
        if esxExport and esxExport.getSharedObject then
             ESX = esxExport:getSharedObject()
             Log("Permissions: ESX object loaded.", 3)
        else
             Log("Permissions: es_extended resource found, but could not get SharedObject.", 2)
        end
    end
    if GetResourceState('qb-core') == 'started' then
         local qbExport = exports['qb-core']
         if qbExport and qbExport.GetCoreObject then
             QBCore = qbExport:GetCoreObject()
             Log("Permissions: QBCore object loaded.", 3)
         else
             Log("Permissions: qb-core resource found, but could not get CoreObject.", 2)
         end
    end
end)

-- Checks if a player has admin privileges based on Config settings
-- @param playerId number: The server ID of the player.
-- @return boolean: True if the player is considered an admin, false otherwise.
function Permissions.IsAdmin(playerId)
    local player = tonumber(playerId)
    if not player or player <= 0 or not GetPlayerName(player) then return false end

    -- Access Config directly as it's loaded globally early
    local cfg = _G.Config
    if not cfg or not cfg.AdminGroups then
        Log("^1Warning: Config.AdminGroups not found for IsPlayerAdmin check.^7", 1)
        return false
    end
    if not cfg.PermissionsFramework then
         Log("^1Warning: Config.PermissionsFramework not set. Defaulting to 'ace'.^7", 1)
    end

    local frameworkSetting = cfg.PermissionsFramework or "ace"

    -- Define checks locally within the function scope
    local function checkESX()
        if ESX then
            local xPlayer = ESX.GetPlayerFromId(player)
            if xPlayer then
                local playerGroup = xPlayer.getGroup()
                for _, group in ipairs(cfg.AdminGroups) do
                    if playerGroup == group then return true end
                end
            else
                -- Log only if ESX was expected but failed to get player
                if frameworkSetting == "esx" then Log("^1Warning: Could not get xPlayer object for player " .. player .. " in IsPlayerAdmin (ESX check).^7", 1) end
            end
        else
            if frameworkSetting == "esx" then Log("^1Warning: Config.PermissionsFramework set to 'esx' but ESX object was not loaded.^7", 1) end
        end
        return false
    end

    local function checkQBCore()
        if QBCore then
            for _, group in ipairs(cfg.AdminGroups) do
                -- Ensure HasPermission exists before calling
                if QBCore.Functions and QBCore.Functions.HasPermission then
                    if QBCore.Functions.HasPermission(player, group) then return true end
                else
                    Log("^1Warning: QBCore.Functions.HasPermission not found. Cannot check QBCore permissions.^7", 1)
                    return false -- Can't check, assume false
                end
            end
        else
            if frameworkSetting == "qbcore" then Log("^1Warning: Config.PermissionsFramework set to 'qbcore' but QBCore object was not loaded.^7", 1) end
        end
        return false
    end

    local function checkACE()
        for _, group in ipairs(cfg.AdminGroups) do
            if IsPlayerAceAllowed(player, "group." .. group) then return true end
        end
        return false
    end

    local function checkCustom()
        Log("IsPlayerAdmin: Config.PermissionsFramework set to 'custom'. Implement your logic in sv_permissions.lua.", 3)
        -- !! DEVELOPER !!: Add your custom permission check logic here
        return false
    end

    -- Execute the appropriate check based on config
    if frameworkSetting == "esx" then
        return checkESX()
    elseif frameworkSetting == "qbcore" then
        return checkQBCore()
    elseif frameworkSetting == "custom" then
        return checkCustom()
    elseif frameworkSetting == "ace" then
        -- For ACE, also attempt framework checks if objects loaded, as ACE might be a fallback
        if ESX and checkESX() then return true end
        if QBCore and checkQBCore() then return true end
        return checkACE() -- Fallback to pure ACE check
    else
        Log("^1Warning: Invalid Config.PermissionsFramework value: '" .. frameworkSetting .. "'. Defaulting to ACE check.^7", 1)
        return checkACE()
    end
end

-- Return the Permissions table containing the functions
return Permissions
