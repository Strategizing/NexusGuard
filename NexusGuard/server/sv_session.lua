--[[
    NexusGuard Session Management Module (server/sv_session.lua)

    Purpose:
    - Provides centralized management of player sessions and associated metrics
    - Tracks player state, position, health, and other metrics for detection validation
    - Handles session cleanup for disconnected players
    - Maintains a comprehensive record of player behavior for pattern analysis

    Dependencies:
    - `server/sv_utils.lua` (for logging)
    - Global `Config` table

    Usage:
    - Required by `globals.lua` and exposed via the `NexusGuardServer.Session` API table
    - `GetSession` is called to retrieve or create a player's session
    - `UpdateActivity` is called to mark a player's session as active
    - `CleanupSession` is called when a player disconnects
    - `PeriodicCleanup` is called by a scheduled task to clean up stale sessions
]]

local Utils = require('server/sv_utils') -- Load the utils module for logging
local Natives = require('shared/natives')                 -- Load the natives wrapper
local Dependencies = require('shared/dependency_manager') -- Load the dependency manager
local Log -- Local alias for Log, set during Initialize

-- Local reference to the Config table, set during Initialize
local Config = nil

local SessionManager = {
    -- Central storage for all player sessions
    -- Key: Player server ID (number)
    -- Value: Session data table (see CreateSession for structure)
    sessions = {},

    -- Configuration values (overridden by config during Initialize)
    cleanupInterval = 300000, -- Default cleanup interval: 5 minutes (ms)
    inactivityTimeout = 600,  -- Default inactivity timeout: 10 minutes (seconds)
    spawnGracePeriod = 5000   -- Default spawn grace period: 5 seconds (ms)
}

--[[
    Initialization Function
    Called by globals.lua after loading modules.
    Sets local references to Config and Log.
    Reads configuration values.

    @param cfg (table): The main Config table.
    @param logFunc (function): The logging function (Utils.Log).
]]
function SessionManager.Initialize(cfg, logFunc)
    Config = cfg or {} -- Store config reference
    Log = logFunc or function(...) print("[SessionManager Fallback Log]", ...) end -- Store log function reference

    -- Initialize the dependency manager
    Dependencies.Initialize(Log)
    -- Read configurable values, using defaults if not present in config
    SessionManager.cleanupInterval = (Config.Performance and Config.Performance.SessionCleanupIntervalMs) or SessionManager.cleanupInterval
    SessionManager.inactivityTimeout = (Config.Performance and Config.Performance.SessionInactivityTimeoutSec) or SessionManager.inactivityTimeout
    SessionManager.spawnGracePeriod = (Config.Thresholds and Config.Thresholds.spawnGracePeriod) or SessionManager.spawnGracePeriod

    Log(("^2[SessionManager]^7 Initialized. Cleanup Interval: %dms, Inactivity Timeout: %ds, Spawn Grace: %dms"):format(
        SessionManager.cleanupInterval, SessionManager.inactivityTimeout, SessionManager.spawnGracePeriod
    ), 3)
end

--[[
    Creates a new session for a player.
    Initializes all metrics and state tracking fields.

    @param playerId (number): The server ID of the player.
    @return (table): The newly created session object.
]]
local function CreateSession(playerId)
    if not playerId or playerId <= 0 then
        Log("^1[SessionManager] Attempted to create session with invalid player ID.^7", 1)
        return nil
    end

    local playerName = Natives.GetPlayerName(playerId) or ("Unknown (" .. tostring(playerId) .. ")")

    -- Get player identifiers using the natives wrapper
    local identifiers = {}

    -- Try to get identifiers from the player
    local success, result = pcall(function()
        return Natives.GetPlayerIdentifiers(playerId)
    end)

    if success and result then
        identifiers = result
    end

    -- Fallback for specific identifiers if needed
    local license = identifiers.license
    local ip = Natives.GetPlayerEndpoint(playerId)
    local discord = identifiers.discord
    local steam = identifiers.steam
    local session = {
        playerId = playerId,
        playerName = playerName,
        identifiers = {
            license = license,
            ip = ip,
            discord = discord,
            steam = steam
        },
        connectTime = os.time(),
        lastActivity = os.time(),
        metrics = {
            -- Trust and detection metrics
            trustScore = 100.0,
            warningCount = 0,
            detections = {},
            detectionCounts = {},

            -- Health and movement tracking
            healthHistory = {},
            movementSamples = {},
            lastServerPosition = nil,
            lastServerPositionTimestamp = nil,
            lastServerHealth = nil,
            lastServerArmor = nil,
            lastServerHealthTimestamp = nil,
            lastValidPosition = nil,

            -- Player state flags
            justSpawned = true,
            isInVehicle = false,
            isFalling = false,
            isRagdoll = false,
            isSwimming = false,
            verticalVelocity = 0.0,
            isInParachute = false,
            justTeleported = false,

            -- Weapon and entity tracking
            weaponStats = {},
            explosions = {},
            entities = {},

            -- Behavioral analysis
            behaviorProfile = {}
        }
    }

    -- Set a timeout to clear the 'justSpawned' flag after the grace period
    Natives.SetTimeout(SessionManager.spawnGracePeriod, function()
        local currentSession = SessionManager.GetSession(playerId)
        if currentSession and currentSession.metrics then
            currentSession.metrics.justSpawned = false
            Log(("^2[SessionManager]^7 Initial spawn grace period (%dms) ended for %s (ID: %d)^7"):format(
                SessionManager.spawnGracePeriod, playerName, playerId), 3)
        end
    end)

    Log(("^2[SessionManager]^7 Created new session for %s (ID: %d)^7"):format(playerName, playerId), 3)
    return session
end

--[[
    Retrieves an existing session or creates a new one if it doesn't exist.

    @param playerId (number): The server ID of the player.
    @return (table): The player's session object.
]]
function SessionManager.GetSession(playerId)
    if not playerId or playerId <= 0 then
        Log("^1[SessionManager] Attempted to get session with invalid player ID.^7", 1)
        return nil
    end

    if not SessionManager.sessions[playerId] then
        SessionManager.sessions[playerId] = CreateSession(playerId)
    end

    return SessionManager.sessions[playerId]
end

--[[
    Updates the last activity timestamp for a player's session.
    Called whenever the player performs an action or sends data to the server.

    @param playerId (number): The server ID of the player.
]]
function SessionManager.UpdateActivity(playerId)
    local session = SessionManager.GetSession(playerId)
    if session then
        session.lastActivity = os.time()
    end
end

--[[
    Updates player state flags in the session metrics.
    Called periodically to keep track of the player's current state.

    @param playerId (number): The server ID of the player.
]]
function SessionManager.UpdatePlayerState(playerId)
    local session = SessionManager.GetSession(playerId)
    if not session or not session.metrics then return end

    local ped = Natives.GetPlayerPed(playerId)
    if not Natives.DoesEntityExist(ped) then return end
    -- Update vehicle state
    session.metrics.isInVehicle = Natives.GetVehiclePedIsIn(ped, false) ~= 0
    -- Update movement state
    local velocity = Natives.GetEntityVelocity(ped)
    session.metrics.isFalling = Natives.IsPedFalling(ped)
    session.metrics.isRagdoll = Natives.IsPedRagdoll(ped)
    session.metrics.isSwimming = Natives.IsPedSwimming(ped)
    session.metrics.verticalVelocity = velocity.z
    session.metrics.isInParachute = Natives.IsPedInParachuteFreeFall(ped)
    -- Additional states that might be useful for detection validation
    session.metrics.isGettingUp = Natives.IsPedGettingUp(ped)
    session.metrics.isClimbing = Natives.IsPedClimbing(ped)
    session.metrics.isVaulting = Natives.IsPedVaulting(ped)
    session.metrics.isJumping = Natives.IsPedJumping(ped)
end

--[[
    Cleans up a player's session when they disconnect.
    Optionally saves metrics to the database if configured.

    @param playerId (number): The server ID of the player.
    @return (boolean): True if the session was found and cleaned up, false otherwise.
]]
function SessionManager.CleanupSession(playerId)
    if not SessionManager.sessions[playerId] then
        return false
    end

    local session = SessionManager.sessions[playerId]
    local playerName = session.playerName or ("Unknown (" .. tostring(playerId) .. ")")

    -- Save metrics to database if configured and available
    if Config.Database and Config.Database.enabled and Dependencies.Database.IsAvailable() then
        -- Try to save metrics using the global API if available
        local success, result = pcall(function()
            if _G.NexusGuardServer and _G.NexusGuardServer.Database and type(_G.NexusGuardServer.Database.SavePlayerMetrics) == "function" then
                return _G.NexusGuardServer.Database.SavePlayerMetrics(playerId, session.metrics)
            end
            return false
        end)

        if not success or not result then
            -- Fallback: Save basic metrics directly using dependency manager
            local playerData = Dependencies.JSON.encode({
                playerId = playerId,
                playerName = session.playerName,
                license = session.identifiers.license,
                connectTime = session.connectTime,
                disconnectTime = os.time(),
                trustScore = session.metrics.trustScore or 100
            })

            Dependencies.Database.Execute(
            "INSERT INTO nexusguard_sessions (player_id, player_data, connect_time, disconnect_time) VALUES (?, ?, ?, ?)",
                {
                    playerId,
                    playerData,
                    session.connectTime,
                    os.time()
                })
        end
    end

    -- Remove the session
    SessionManager.sessions[playerId] = nil
    Log(("^2[SessionManager]^7 Cleaned up session for %s (ID: %d)^7"):format(playerName, playerId), 3)
    return true
end

--[[
    Periodically cleans up stale sessions for players who have disconnected
    or been inactive for too long.
    Called by a scheduled task in server_main.lua.
]]
function SessionManager.PeriodicCleanup()
    local currentTime = os.time()
    local cleanupCount = 0

    for playerId, session in pairs(SessionManager.sessions) do
        -- Check if player is still connected
        if not GetPlayerEndpoint(playerId) then
            SessionManager.CleanupSession(playerId)
            cleanupCount = cleanupCount + 1
        -- Check for inactivity timeout
        elseif (currentTime - session.lastActivity) > SessionManager.inactivityTimeout then
            Log(("^3[SessionManager] Player %s (ID: %d) session timed out due to inactivity (%ds).^7"):format(
                session.playerName or "Unknown", playerId, currentTime - session.lastActivity), 2)
            SessionManager.CleanupSession(playerId)
            cleanupCount = cleanupCount + 1
        end
    end

    if cleanupCount > 0 then
        Log(("^2[SessionManager]^7 Cleaned up %d stale sessions during periodic cleanup.^7"):format(cleanupCount), 3)
    end
end

--[[
    Gets the total count of active sessions.
    Useful for monitoring server load.

    @return (number): The number of active sessions.
]]
function SessionManager.GetActiveSessionCount()
    local count = 0
    for _ in pairs(SessionManager.sessions) do
        count = count + 1
    end
    return count
end

--[[
    Gets a list of all active player IDs with sessions.
    Useful for iterating through all players with sessions.

    @return (table): Array of player IDs with active sessions.
]]
function SessionManager.GetActivePlayerIds()
    local playerIds = {}
    for playerId in pairs(SessionManager.sessions) do
        table.insert(playerIds, playerId)
    end
    return playerIds
end

-- Export the SessionManager table for use in other modules via globals.lua
return SessionManager
