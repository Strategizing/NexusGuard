--[[
    NexusGuard Server Permissions Module (server/sv_permissions.lua)

    Purpose:
    - Determines if a player has administrative privileges within NexusGuard.
    - Supports multiple permission systems (ACE, ESX, QBCore, Custom) based on `Config.PermissionsFramework`.
    - Attempts to load ESX/QBCore framework objects if the respective resources are running.

    Usage:
    - Required by `globals.lua` and exposed via the `NexusGuardServer.Permissions` API table.
    - The `IsAdmin` function is the primary export used by other modules and commands.
]]

local Utils = require('server/sv_utils') -- Load the utils module for logging.
local Log = Utils.Log

local Permissions = {} -- Table to hold the exported functions.
local ESX = nil      -- Placeholder for the ESX Shared Object.
local QBCore = nil   -- Placeholder for the QBCore Core Object.

--[[
    Framework Object Loading Thread
    Attempts to load ESX and QBCore objects shortly after the resource starts.
    This allows the IsAdmin function to use framework-specific checks if configured.
    Runs asynchronously to avoid blocking initialization if frameworks aren't present.
]]
Citizen.CreateThread(function()
    Citizen.Wait(1000) -- Wait a second to give frameworks a chance to load and export their objects.
    -- Check for ESX
    if GetResourceState('es_extended') == 'started' then
        local esxExport = exports['es_extended']
        -- Use the standard method to get the ESX Shared Object.
        if esxExport and esxExport.getSharedObject then
             ESX = esxExport:getSharedObject()
             Log("Permissions: ESX SharedObject loaded successfully.", 3)
        else
             Log("Permissions: es_extended resource is running, but failed to get SharedObject export.", 2)
        end
    end
    -- Check for QBCore
    if GetResourceState('qb-core') == 'started' then
         local qbExport = exports['qb-core']
         -- Use the standard method to get the QBCore Core Object.
         if qbExport and qbExport.GetCoreObject then
             QBCore = qbExport:GetCoreObject()
             Log("Permissions: QBCore CoreObject loaded successfully.", 3)
         else
             Log("Permissions: qb-core resource is running, but failed to get CoreObject export.", 2)
         end
    end
    Log("Permissions: Framework object loading attempt complete.", 3)
end)

--[[
    Checks if a player has admin privileges based on the configured permission framework
    and the admin groups listed in `Config.AdminGroups`.

    @param playerId (number): The server ID of the player to check.
    @return (boolean): True if the player is considered an admin according to the configuration, false otherwise.
]]
function Permissions.IsAdmin(playerId)
    local player = tonumber(playerId)
    -- Basic validation: Ensure player ID is valid and player is likely online.
    if not player or player <= 0 or not GetPlayerName(player) then return false end

    -- Access the global Config table (loaded from config.lua via shared_scripts).
    local cfg = _G.Config
    -- Ensure required config settings are present.
    if not cfg or not cfg.AdminGroups or type(cfg.AdminGroups) ~= 'table' then
        Log("^1Permissions Error: Config.AdminGroups is missing or not a table. Cannot perform admin check.^7", 1)
        return false -- Cannot check without admin groups defined.
    end
    if not cfg.PermissionsFramework then
         Log("^1Permissions Warning: Config.PermissionsFramework not set. Defaulting to 'ace' permission checks.^7", 1)
    end

    -- Determine the permission framework to use from config, defaulting to 'ace'.
    local frameworkSetting = string.lower(cfg.PermissionsFramework or "ace")

    --[[ Internal Helper Functions for Specific Framework Checks ]]

    -- Checks ESX group against Config.AdminGroups.
    local function checkESX()
        if ESX then -- Check if the ESX object was loaded successfully earlier.
            local xPlayer = ESX.GetPlayerFromId(player) -- Get the ESX player object.
            if xPlayer then
                local playerGroup = xPlayer.getGroup() -- Get the player's group name.
                -- Iterate through the admin groups defined in config.
                for _, adminGroup in ipairs(cfg.AdminGroups) do
                    if playerGroup == adminGroup then return true end -- Found a match.
                end
            else
                -- Log a warning if ESX is the configured framework but we couldn't get the player object.
                if frameworkSetting == "esx" then Log(("^1Permissions Warning: Could not get xPlayer object for player %d during ESX admin check.^7"):format(player), 1) end
            end
        else
            -- Log a warning if ESX is configured but the object wasn't loaded.
            if frameworkSetting == "esx" then Log("^1Permissions Warning: Configured for 'esx' but ESX object was not loaded. Ensure es_extended starts before NexusGuard.^7", 1) end
        end
        return false -- Player is not an admin according to ESX check.
    end

    -- Checks QBCore permissions against Config.AdminGroups.
    local function checkQBCore()
        if QBCore then -- Check if the QBCore object was loaded.
            -- Ensure the necessary QBCore function exists before calling it.
            if QBCore.Functions and QBCore.Functions.HasPermission then
                -- Iterate through the admin groups/permissions defined in config.
                for _, adminPermission in ipairs(cfg.AdminGroups) do
                    -- Use QBCore's permission checking function.
                    if QBCore.Functions.HasPermission(player, adminPermission) then return true end -- Found a match.
                end
            else
                -- Log an error if the QBCore permission function is missing.
                Log("^1Permissions Error: QBCore.Functions.HasPermission not found. Cannot check QBCore permissions.^7", 1)
                return false -- Cannot perform check, assume not admin.
            end
        else
            -- Log a warning if QBCore is configured but the object wasn't loaded.
            if frameworkSetting == "qbcore" then Log("^1Permissions Warning: Configured for 'qbcore' but QBCore object was not loaded. Ensure qb-core starts before NexusGuard.^7", 1) end
        end
        return false -- Player is not an admin according to QBCore check.
    end

    -- Checks FiveM's built-in ACE permissions against Config.AdminGroups.
    local function checkACE()
        -- Iterate through the admin groups defined in config.
        for _, adminGroup in ipairs(cfg.AdminGroups) do
            -- Use the IsPlayerAceAllowed native, prefixing the group name with "group.".
            if IsPlayerAceAllowed(player, "group." .. adminGroup) then return true end -- Found a match.
        end
        return false -- Player is not an admin according to ACE check.
    end

    -- Placeholder for custom permission logic.
    local function checkCustom()
        Log("Permissions Info: Config.PermissionsFramework set to 'custom'. Add custom logic to Permissions.IsAdmin in sv_permissions.lua.", 3)
        -- ###########################################################
        -- ## DEVELOPER TODO: Implement Custom Permission Check Logic ##
        -- ###########################################################
        --[[ Example using player identifiers and a hypothetical database check:
        local identifiers = GetPlayerIdentifiers(player)
        local license = nil
        for _, v in ipairs(identifiers) do
            if string.sub(v, 1, string.len("license:")) == "license:" then
                license = v
                break
            end
        end
        if license then
            -- Replace with your actual database query logic
            -- local isCustomAdmin = MySQL.scalar.await('SELECT COUNT(*) FROM your_admin_table WHERE license = ?', {license})
            -- return isCustomAdmin > 0
        end
        ]]
        return false -- Default to false if custom logic is not implemented.
    end

    -- Execute the appropriate check based on the configured frameworkSetting.
    if frameworkSetting == "esx" then
        return checkESX()
    elseif frameworkSetting == "qbcore" then
        return checkQBCore()
    elseif frameworkSetting == "custom" then
        return checkCustom()
    elseif frameworkSetting == "ace" then
        -- Special case for 'ace': Also attempt framework checks if their objects were loaded.
        -- This allows using ACE permissions as a fallback or alongside framework permissions.
        if ESX and checkESX() then return true end      -- Check ESX first if loaded
        if QBCore and checkQBCore() then return true end -- Then check QBCore if loaded
        return checkACE()                               -- Finally, perform the ACE check.
    else
        -- Handle invalid framework setting in config.
        Log(("^1Permissions Warning: Invalid Config.PermissionsFramework value: '%s'. Defaulting to ACE check.^7"):format(frameworkSetting), 1)
        return checkACE() -- Default to ACE check if setting is unrecognized.
    end
end

-- Return the Permissions table containing the IsAdmin function for export via globals.lua.
return Permissions
