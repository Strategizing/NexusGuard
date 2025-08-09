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

-- Initialize the Core module with Config and Utils
if not Core.Initialize(NexusGuardServer.Config, Utils) then
    Log("^1[NexusGuard] CRITICAL: Failed to initialize Core module. NexusGuard may not function correctly.^7", 1)
end

-- Assign all modules from Core to NexusGuardServer for API access
for moduleName, moduleRef in pairs(Core.modules) do
    NexusGuardServer[moduleName] = moduleRef
    Log(("^2[NexusGuard]^7 Module '%s' assigned to API."):format(moduleName), 3)
end

--[[
    Per-player challenge token storage and helpers
    Stores short-lived tokens issued to clients along with their timestamp.
    These tokens are used for an additional validation step on sensitive
    server events.
]]
NexusGuardServer.Security = NexusGuardServer.Security or {}
NexusGuardServer.Security.challengeTokens = {}
NexusGuardServer.Security.usedTimestamps = {}
NexusGuardServer.Security.tokenValidityWindow = (NexusGuardServer.Config.Security
    and NexusGuardServer.Config.Security.TokenValidityWindow) or 60

-- Generates a challenge token for a specific player and stores it
function NexusGuardServer.Security.GenerateChallengeToken(playerId)
    if not playerId then return nil end
    local timestamp = os.time()
    local token
    if lib and lib.crypto and lib.crypto.randomBytes then
        token = lib.crypto.randomBytes(16)
    else
        token = tostring(math.random(100000, 999999)) .. tostring(math.random(100000, 999999))
    end
    NexusGuardServer.Security.challengeTokens[playerId] = {
        token = token,
        timestamp = timestamp
    }
    return token, timestamp
end

-- Validates a challenge token, ensuring timestamps are unique within the window
function NexusGuardServer.Security.ValidateSecurityToken(playerId, token, timestamp)
    if not playerId or not token or not timestamp then return false end

    local record = NexusGuardServer.Security.challengeTokens[playerId]
    if not record or record.token ~= token or record.timestamp ~= timestamp then
        return false
    end

    local now = os.time()
    local window = NexusGuardServer.Security.tokenValidityWindow

    NexusGuardServer.Security.usedTimestamps[playerId] = NexusGuardServer.Security.usedTimestamps[playerId] or {}
    local used = NexusGuardServer.Security.usedTimestamps[playerId]

    -- purge expired timestamps
    for ts in pairs(used) do
        if now - ts > window then
            used[ts] = nil
        end
    end

    -- reject duplicate timestamps within window
    if used[timestamp] then
        return false
    end

    if now - timestamp > window then
        return false
    end

    used[timestamp] = true
    return true
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
