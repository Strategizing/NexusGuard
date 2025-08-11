--[[
    NexusGuard Player Metrics Module (server/sv_player_metrics.lua)

    Purpose:
    - Tracks per-player metrics and state in a private table
    - Provides API functions for other modules to query and update metrics
    - Removes reliance on global tables for shared state

    Usage:
    - Loaded and initialized by the Core module
    - Other modules access player metrics through this module's API
]]

local Utils = require('server/sv_utils')

-- Local logger reference, configured during Initialize
local Log

local PlayerMetrics = {
    -- Internal storage for all player metrics keyed by player ID
    data = {}
}

-- Initialize the module and configure logging
function PlayerMetrics.Initialize(cfg, logFunc)
    Log = logFunc or (Utils and Utils.Log) or function(...) print('[PlayerMetrics]', ...) end
    PlayerMetrics.data = {}
end

-- Initialize metrics for a player
function PlayerMetrics.InitializePlayer(playerId)
    PlayerMetrics.data[playerId] = {
        positions = {},           -- Track last N positions for movement validation
        health = {
            current = 200,        -- Default max health
            history = {},         -- Track health changes
            lastDamageTime = 0,   -- Last time player took damage
            lastHealTime = 0      -- Last time player healed
        },
        weapons = {},            -- Track weapon inventory
        detections = {},         -- Track detection history
        trustScore = 100,        -- Start with full trust
        lastSpawn = os.time(),   -- Track spawns for grace periods
        state = {                -- Track player state for context-aware checks
            inVehicle = false,
            isFalling = false,
            isParachuting = false,
            isRagdolling = false
        }
    }
end

-- Retrieve metrics for a player
function PlayerMetrics.Get(playerId)
    return PlayerMetrics.data[playerId]
end

-- Update player position with context
function PlayerMetrics.UpdatePosition(playerId, x, y, z, vx, vy, vz)
    local metrics = PlayerMetrics.data[playerId]
    if not metrics then return end

    -- Update state based on vertical velocity
    metrics.state.isFalling = vz < -5.0

    -- Store new position with timestamp
    local newPos = { x = x, y = y, z = z, time = os.time() }

    -- Keep only last 10 positions
    table.insert(metrics.positions, 1, newPos)
    if #metrics.positions > 10 then
        table.remove(metrics.positions)
    end

    -- Return previous position for teleport detection
    return #metrics.positions > 1 and metrics.positions[2] or newPos
end

-- Track weapon inventory
function PlayerMetrics.UpdateWeapon(playerId, weaponHash, ammoCount)
    local metrics = PlayerMetrics.data[playerId]
    if not metrics then return false end

    -- Check if weapon suddenly appeared
    local hadWeapon = metrics.weapons[weaponHash] ~= nil

    -- Update weapon
    metrics.weapons[weaponHash] = {
        ammo = ammoCount,
        lastUpdated = os.time()
    }

    return hadWeapon
end

-- Record damage events for godmode detection
function PlayerMetrics.RecordDamage(playerId, damage, isFatal)
    local metrics = PlayerMetrics.data[playerId]
    if not metrics then return end

    metrics.health.lastDamageTime = os.time()
    table.insert(metrics.health.history, {
        type = 'damage',
        amount = damage,
        time = metrics.health.lastDamageTime,
        fatal = isFatal or false
    })

    -- Limit history size
    if #metrics.health.history > 20 then
        table.remove(metrics.health.history, 1)
    end
end

-- Clear metrics when a player disconnects
function PlayerMetrics.Clear(playerId)
    PlayerMetrics.data[playerId] = nil
end

return PlayerMetrics

