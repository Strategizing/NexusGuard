--[[
    NexusGuard Globals & Server API Definition (globals.lua)

    This script serves as the central hub for defining and exposing the server-side API
    used by NexusGuard's various modules and potentially by external resources.

    Key Responsibilities:
    - Defines the main `NexusGuardServer` table which acts as a namespace.
    - Requires and loads core server-side modules (Utils, Permissions, Security, Bans, Database, EventHandlers, Detections).
    - Assigns the loaded modules as sub-tables within `NexusGuardServer`.
    - Provides access to the shared `Config` table (loaded from config.lua).
    - Manages a central list of `OnlineAdmins`.
    - Implements basic Discord webhook functionality (could be moved to a dedicated module).
    - Exports the `NexusGuardServer` table via `GetNexusGuardServerAPI` for use by other scripts.

    Developer Notes:
    - Most of the actual implementation logic resides within the required module files (e.g., sv_bans.lua, modules/detections.lua).
    - This file primarily acts as an aggregator and exporter.
    - To access NexusGuard functionality from another server script, use:
      `local NexusGuardAPI = exports['NexusGuard']:GetNexusGuardServerAPI()`
      Then access modules like: `NexusGuardAPI.Bans.IsPlayerBanned(...)`
]]

-- External Dependencies (Ensure these resources are started before NexusGuard)
-- - ox_lib: Provides utility functions, including JSON handling (lib.json) and crypto (lib.crypto).
-- - oxmysql: Required for database operations.

-- Main container table for all server-side NexusGuard modules and shared data.
local NexusGuardServer = {
    Config = _G.Config or {}, -- Reference the global Config table loaded from config.lua. Critical for all modules.
    OnlineAdmins = {},        -- Central table to track currently online players with admin privileges. Key = server ID, Value = true.
    -- Sub-tables below will be populated by the required modules:
    Utils = nil,
    Permissions = nil,
    Security = nil,
    Bans = nil,
    Database = nil,
    EventHandlers = nil,
    Detections = nil,
    Discord = nil,            -- Will be loaded from sv_discord.lua
    PlayerSessions = {}       -- Central storage for player session data (replaces local manager in server_main)
}

-- Load required core server-side modules.
-- The order might matter if modules depend on each other during their own initialization.
-- Utils and Permissions are often needed early.
local Utils = require('server/sv_utils')
local Permissions = require('server/sv_permissions')
local Security = require('server/sv_security')
local Bans = require('server/sv_bans')
local Database = require('server/sv_database')
local Session = require('server/sv_session') -- Load the new Session management module
local EventHandlers = require('server/sv_event_handlers')
local Detections = require('server/modules/detections')
local Discord = require('server/sv_discord') -- Load the Discord module

-- Local alias for logging function from the Utils module.
local Log = Utils.Log
if not Log then
    print("^1[NexusGuard] CRITICAL: Logging function (Utils.Log) not found after requiring sv_utils.lua.^7")
    Log = function(msg, level) print(msg) end -- Basic fallback
end

-- Assign the loaded modules to the NexusGuardServer table.
-- This makes their functions accessible via the exported API.
NexusGuardServer.Utils = Utils
NexusGuardServer.Permissions = Permissions
NexusGuardServer.Security = Security
NexusGuardServer.Bans = Bans
NexusGuardServer.Database = Database
NexusGuardServer.Session = Session -- Assign the loaded Session module
NexusGuardServer.EventHandlers = EventHandlers
NexusGuardServer.Detections = Detections
NexusGuardServer.Discord = Discord -- Assign the loaded Discord module

-- Initialize modules that require Config/Log references
if Security and Security.Initialize then
    Security.Initialize(NexusGuardServer.Config, Log)
else
    Log("^1[NexusGuard] CRITICAL: Failed to initialize Security module.^7", 1)
end

if Session and Session.Initialize then
    Session.Initialize(NexusGuardServer.Config, Log)
else
    Log("^1[NexusGuard] CRITICAL: Failed to initialize Session module. Player session tracking may fail.^7", 1)
end

if Discord and Discord.Initialize then
    Discord.Initialize(NexusGuardServer.Config, Log)
else
    Log("^1[NexusGuard] CRITICAL: Failed to initialize Discord module. Discord functions may fail.^7", 1)
end

-- Note: Framework object loading (ESX, QBCore) is now handled within sv_permissions.lua
--       during its initialization phase, as it's primarily used for permission checks.

-- #############################################################################
-- ## Module Logic Placeholders (Actual logic is in required files) ##
-- #############################################################################
-- The sections below are just comments indicating where the logic resides.
-- No actual functions are defined here anymore.

-- ## Bans Module Logic -> See server/sv_bans.lua ##
-- ## Permissions Module Logic -> See server/sv_permissions.lua ##
-- ## Security Module Logic -> See server/sv_security.lua ##
-- ## Detections Module Logic -> See server/modules/detections.lua ##
-- ## Database Module Logic -> See server/sv_database.lua ##
-- ## Event Handlers Module Logic -> See server/sv_event_handlers.lua ##

-- ## Discord Module Logic -> See server/sv_discord.lua ##

-- #############################################################################
-- ## Player Session Management (Integrated into API) ##
-- #############################################################################

-- Gets or creates a session table for a given player ID.
-- Now delegates to the Session module.
function NexusGuardServer.GetSession(playerId)
    if not NexusGuardServer.Session or not NexusGuardServer.Session.GetSession then
        Log("^1[NexusGuard] CRITICAL: Session.GetSession function not found in API! Using legacy session management.^7", 1)
        -- Legacy fallback implementation
        playerId = tonumber(playerId) -- Ensure playerId is a number
        if not playerId or playerId <= 0 then return nil end -- Basic validation

        if not NexusGuardServer.PlayerSessions[playerId] then
            -- Initialize a new session structure if one doesn't exist.
            NexusGuardServer.PlayerSessions[playerId] = {
                metrics = {}, -- Holds various tracking data (position, health, detections, etc.)
            }
        end
        return NexusGuardServer.PlayerSessions[playerId]
    end

    -- Use the new Session module
    return NexusGuardServer.Session.GetSession(playerId)
end

-- Clean up session data when a player drops.
-- Now delegates to the Session module.
function NexusGuardServer.CleanupSession(playerId)
    if not NexusGuardServer.Session or not NexusGuardServer.Session.CleanupSession then
        Log("^1[NexusGuard] CRITICAL: Session.CleanupSession function not found in API! Using legacy session cleanup.^7", 1)
        -- Legacy fallback implementation
        playerId = tonumber(playerId)
        if not playerId or playerId <= 0 then return end

        if NexusGuardServer.PlayerSessions[playerId] then
            NexusGuardServer.PlayerSessions[playerId] = nil -- Remove the session entry.
        end
        return
    end

    -- Use the new Session module
    return NexusGuardServer.Session.CleanupSession(playerId)
end


-- #############################################################################
-- ## Initialization and Exports ##
-- #############################################################################

-- Export the `NexusGuardServer` table, making all its assigned modules and data
-- accessible to other server scripts via `exports['NexusGuard']:GetNexusGuardServerAPI()`.
exports('GetNexusGuardServerAPI', function()
    Log("GetNexusGuardServerAPI called.", 4) -- Debug log when API is requested
    return NexusGuardServer
end)

Log("NexusGuard globals.lua processed. Core modules loaded and API table structured.", 2)

-- Trigger Database Initialization after a short delay.
-- This ensures that the Config table (needed by DB init) is fully loaded and accessible via NexusGuardServer.Config.
Citizen.CreateThread(function()
    Citizen.Wait(500) -- Wait briefly for everything to settle.
    Log("Attempting to initialize database module...", 3)
    if NexusGuardServer.Database and NexusGuardServer.Database.Initialize then
        NexusGuardServer.Database.Initialize() -- Call the Initialize function within the Database module.
    else
        Log("^1[NexusGuard] CRITICAL: Database module or its Initialize function not found in API. Database setup skipped.^7", 1)
    end
end)
