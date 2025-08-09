--[[
    NexusGuard Globals & Server API Definition (globals.lua)

    This script serves as the central hub for defining and exposing the server-side API
    used by NexusGuard's various modules and potentially by external resources.

    Key Responsibilities:
    - Initializes the Core module which manages all other modules
    - Defines the main `NexusGuardServer` table which acts as a namespace
    - Provides access to the shared `Config` table (loaded from config.lua)
    - Exports the `NexusGuardServer` table via `GetNexusGuardServerAPI` for use by other scripts

    Developer Notes:
    - Most of the actual implementation logic resides within the required module files
    - The Core module handles module loading, initialization, and dependency injection
    - To access NexusGuard functionality from another server script, use:
      `local NexusGuardAPI = exports['NexusGuard']:GetNexusGuardServerAPI()`
      Then access modules like: `NexusGuardAPI.Bans.IsPlayerBanned(...)`
]]

-- External Dependencies (Ensure these resources are started before NexusGuard)
-- - ox_lib: Provides utility functions, including JSON handling (lib.json) and crypto (lib.crypto)
-- - oxmysql: Required for database operations
-- - screenshot-basic: Required for screenshot functionality

-- Load the Utils module first (needed for logging)
local Utils = require('server/sv_utils')

-- Local alias for logging function from the Utils module
local Log = Utils.Log
if not Log then
    print("^1[NexusGuard] CRITICAL: Logging function (Utils.Log) not found after requiring sv_utils.lua.^7")
    Log = function(msg, level) print(msg) end -- Basic fallback
end

-- Load the Core module which will handle all other modules
local Core = require('server/sv_core')

-- Main container table for all server-side NexusGuard modules and shared data
local NexusGuardServer = {
    Config = _G.Config or {}, -- Reference the global Config table loaded from config.lua
    OnlineAdmins = {},        -- Central table to track currently online players with admin privileges
    Utils = Utils,            -- Assign Utils module directly since it's already loaded
    Core = Core               -- Assign Core module
}

-- Expose API table early for modules loaded during Core initialization
_G.NexusGuardServer = NexusGuardServer

-- Initialize the Core module with Config and Utils
if not Core.Initialize(NexusGuardServer.Config, Utils) then
    Log("^1[NexusGuard] CRITICAL: Failed to initialize Core module. NexusGuard may not function correctly.^7", 1)
end

-- Assign all modules from Core to NexusGuardServer for API access
for moduleName, moduleRef in pairs(Core.modules) do
    NexusGuardServer[moduleName] = moduleRef
    Log(("^2[NexusGuard]^7 Module '%s' assigned to API."):format(moduleName), 3)
end

-- Load the Permissions module separately (not managed by Core)
local permsOk, Permissions = pcall(require, 'server/sv_permissions')
if permsOk and Permissions then
    NexusGuardServer.Permissions = Permissions
else
    Log("^1[NexusGuard] Warning: Failed to load sv_permissions.lua. Admin checks will be unavailable.^7", 1)
end

-- #############################################################################
-- ## API Functions ##
-- #############################################################################

-- Gets or creates a session table for a given player ID.
-- Delegates to the Core module which handles the Session module.
function NexusGuardServer.GetSession(playerId)
    return Core.GetSession(playerId)
end

-- Clean up session data when a player drops.
-- Delegates to the Core module which handles the Session module.
function NexusGuardServer.CleanupSession(playerId)
    return Core.CleanupSession(playerId)
end

-- Process a detection report.
-- Delegates to the Core module which handles the Detections module.
function NexusGuardServer.ProcessDetection(playerId, detectionType, detectionData)
    return Core.ProcessDetection(playerId, detectionType, detectionData)
end

-- Get the current status of the NexusGuard system.
function NexusGuardServer.GetStatus()
    return Core.GetStatus()
end

-- Check if a player has administrative privileges
function NexusGuardServer.IsPlayerAdmin(playerId)
    if NexusGuardServer.Permissions and NexusGuardServer.Permissions.IsAdmin then
        return NexusGuardServer.Permissions.IsAdmin(playerId)
    end
    return false
end

-- Ban a player using the Bans module
function NexusGuardServer.BanPlayer(playerId, reason, adminName, durationSeconds)
    if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
        return NexusGuardServer.Bans.Execute(playerId, reason, adminName, durationSeconds)
    end
    Log("^1[NexusGuard] Bans.Execute not available. BanPlayer failed.^7", 1)
    return false
end

-- #############################################################################
-- ## Initialization and Exports ##
-- #############################################################################

-- Export the `NexusGuardServer` table, making all its assigned modules and data
-- accessible to other server scripts via `exports['NexusGuard']:GetNexusGuardServerAPI()`.
if _G.exports then
    exports('GetNexusGuardServerAPI', function()
        Log("GetNexusGuardServerAPI called.", 4) -- Debug log when API is requested
        return NexusGuardServer
    end)
else
    Log("^1[NexusGuard] CRITICAL: exports global not available. API will not be exported.^7", 1)
end

Log("^2[NexusGuard]^7 globals.lua processed. Core modules loaded and API table structured.", 2)

-- Trigger Database Initialization after a short delay if not already done by Core.
if _G.Citizen then
    Citizen.CreateThread(function()
        Citizen.Wait(500) -- Wait briefly for everything to settle.

        -- Check if Database module exists but hasn't been initialized
        if NexusGuardServer.Database and NexusGuardServer.Database.Initialize and
            not NexusGuardServer.Database.IsInitialized then
            Log("^3[NexusGuard]^7 Attempting to initialize database module...", 3)
            NexusGuardServer.Database.Initialize() -- Call the Initialize function within the Database module.
        end
    end)
else
    Log("^1[NexusGuard] CRITICAL: Citizen global not available. Database initialization may be delayed.^7", 1)
end

-- Return the API table for modules that require globals.lua directly
return NexusGuardServer
