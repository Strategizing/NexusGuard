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

-- Expose early so modules loaded during Core initialization can reference it
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

-- Store a detection event in the database using a normalized format.
-- Ensures detectionData is always a table with expected fields before persisting.
function NexusGuardServer.Detections.Store(playerId, detectionType, detectionData)
    if type(detectionData) ~= "table" then
        detectionData = { value = detectionData }
    end
    detectionData.value = detectionData.value
    detectionData.details = detectionData.details or {}
    detectionData.clientValidated = detectionData.clientValidated or false
    detectionData.serverValidated = detectionData.serverValidated or false

    if NexusGuardServer.Database and NexusGuardServer.Database.StoreDetection then
        NexusGuardServer.Database.StoreDetection(playerId, detectionType, detectionData)
    end
end

-- Get the current status of the NexusGuard system.
function NexusGuardServer.GetStatus()
    return Core.GetStatus()
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
