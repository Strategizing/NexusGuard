local Metrics = {}
local Core

-- Initialize references from Core
function Metrics.Initialize(_, _, core)
    Core = core
end

-- Initialize player metrics when they join
function Metrics.InitializePlayer(playerId)
    Core.PlayerMetrics[playerId] = {
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

-- Update player position with context
function Metrics.UpdatePosition(playerId, x, y, z, vx, vy, vz)
    local metrics = Core.PlayerMetrics[playerId]
    if not metrics then return end
    
    -- Update state based on velocity
    metrics.state.isFalling = vz < -5.0
    
    -- Store new position with timestamp
    local newPos = {x = x, y = y, z = z, time = os.time()}
    
    -- Keep only last 10 positions (limited history)
    table.insert(metrics.positions, 1, newPos)
    if #metrics.positions > 10 then
        table.remove(metrics.positions)
    end
    
    -- Return previous position for teleport detection
    return #metrics.positions > 1 and metrics.positions[2] or newPos
end

-- Track weapon inventory
function Metrics.UpdateWeapon(playerId, weaponHash, ammoCount)
    local metrics = Core.PlayerMetrics[playerId]
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
function Metrics.RecordDamage(playerId, damage, isFatal)
    local metrics = Core.PlayerMetrics[playerId]
    if not metrics then return end
    
    metrics.health.lastDamageTime = os.time()
    table.insert(metrics.health.history, {
        type = "damage",
        amount = damage,
        time = metrics.health.lastDamageTime,
        fatal = isFatal or false
    })
    
    -- Limit history size
    if #metrics.health.history > 20 then
        table.remove(metrics.health.history, 1)
    end
end

return Metrics
