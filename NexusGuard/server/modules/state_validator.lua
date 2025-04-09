--[[
    NexusGuard Enhanced State Validator (server/modules/state_validator.lua)

    Purpose:
    - Tracks and validates player state transitions using FiveM natives
    - Detects impossible or suspicious state changes
    - Maintains historical state data for pattern analysis
    - Provides comprehensive state validation with context awareness
    - Integrates with the detection system for reporting violations

    Key Features:
    - Multi-state history tracking (not just last state)
    - Statistical analysis of player metrics over time
    - Comprehensive state property tracking
    - Impossible state transition detection
    - Context-aware validation (considers game mechanics)
]]

-- Load shared modules using the module loader to prevent circular dependencies
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local Natives = ModuleLoader.Load('shared/natives')
local EventRegistry = ModuleLoader.Load('shared/event_registry')

-- Get the NexusGuard Server API
local NexusGuardServer = Utils.GetNexusGuardAPI()

-- Shorthand for logging function
local Log = Utils.Log

local StateValidator = {
    -- Store multiple historical states per player for pattern analysis
    stateHistory = {},

    -- Track metrics over time for statistical analysis
    playerMetrics = {},

    -- Configuration
    historySize = 10,  -- Number of historical states to keep per player
    cleanupInterval = 60000,  -- Cleanup interval in ms (1 minute)
    lastCleanup = 0,  -- Last cleanup timestamp

    -- Default thresholds (fallbacks if not in Config)
    defaultThresholds = {
        teleportDistance = 75.0,
        healthChangeRate = 5.0,  -- Max health points per second
        armorChangeRate = 5.0,   -- Max armor points per second
        speedLimit = 50.0,       -- Max speed in m/s
        weaponSwitchTime = 500,  -- Min time between weapon switches in ms
        vehicleEntryExitTime = 800,  -- Min time for vehicle entry/exit in ms
        fallingTransitionTime = 200,  -- Min time for falling state transition in ms
        ragdollTransitionTime = 200,  -- Min time for ragdoll state transition in ms
        swimTransitionTime = 500      -- Min time for swim state transition in ms
    }
}

-- Initialize player state tracking
function StateValidator.InitializePlayer(playerId)
    StateValidator.stateHistory[playerId] = {}
    StateValidator.playerMetrics[playerId] = {
        avgSpeed = 0,
        maxSpeed = 0,
        healthChanges = {},
        armorChanges = {},
        weaponSwitches = {},
        stateTransitions = {},
        suspiciousEvents = 0,
        lastUpdate = Natives.GetGameTimer(),
        createdAt = Natives.GetGameTimer()
    }

    Log("Initialized state tracking for player " .. Natives.GetPlayerName(playerId) .. " (ID: " .. playerId .. ")", Utils.logLevels.INFO)
end

-- Cleanup function to remove data for disconnected players
function StateValidator.Cleanup()
    local currentTime = Natives.GetGameTimer()

    -- Only run cleanup at the specified interval
    if currentTime - StateValidator.lastCleanup < StateValidator.cleanupInterval then
        return
    end

    StateValidator.lastCleanup = currentTime

    -- Get connected players using Utils function to avoid direct native calls
    local connectedPlayers = Utils.GetConnectedPlayers()

    -- Remove data for disconnected players
    for playerId, _ in pairs(StateValidator.stateHistory) do
        if not connectedPlayers[playerId] then
            -- Clean up state history
            StateValidator.stateHistory[playerId] = nil

            -- Clean up player metrics
            StateValidator.playerMetrics[playerId] = nil

            -- Clean up state cache
            StateValidator.CleanupPlayerStateCache(playerId)

            Log("Cleaned up state data for disconnected player ID: " .. playerId, Utils.logLevels.DEBUG)
        end
    end
end

-- Cache for player state data to reduce native calls
local playerStateCache = {}

-- Get comprehensive current state using FiveM natives with optimized caching
function StateValidator.GetCurrentState(playerId)
    -- Get player ped with error handling
    local ped = Natives.GetPlayerPed(playerId)
    if not ped or not Natives.DoesEntityExist(ped) then
        Log("Failed to get valid ped for player ID: " .. playerId, Utils.logLevels.WARNING)
        return nil
    end

    -- Initialize cache entry if needed
    if not playerStateCache[playerId] then
        playerStateCache[playerId] = {
            lastUpdate = 0,
            data = {},
            pedId = ped
        }
    end

    local cache = playerStateCache[playerId]
    local currentTime = Natives.GetGameTimer()
    local timeSinceUpdate = currentTime - cache.lastUpdate

    -- If ped changed, invalidate cache
    if cache.pedId ~= ped then
        cache.data = {}
        cache.pedId = ped
        cache.lastUpdate = 0
        timeSinceUpdate = currentTime
    end

    -- Create state object
    local currentState = {}

    -- Get basic entity properties (update every frame)
    currentState.pos = Natives.GetEntityCoords(ped)
    currentState.velocity = Natives.GetEntityVelocity(ped)
    currentState.speed = #currentState.velocity

    -- Get properties that don't need to be updated as frequently
    if timeSinceUpdate > 500 or not cache.data.heading then
        -- Get entity properties
        currentState.heading = Natives.GetEntityHeading(ped)
        currentState.rotation = Natives.GetEntityRotation(ped)

        -- Get health and armor
        currentState.health = Natives.GetEntityHealth(ped)
        currentState.maxHealth = Natives.GetEntityMaxHealth(ped)
        currentState.armor = Natives.GetPedArmour(ped)

        -- Get vehicle state
        currentState.vehicle = Natives.GetVehiclePedIsIn(ped, false)
        currentState.isInVehicle = currentState.vehicle ~= 0

        if currentState.isInVehicle then
            currentState.vehicleClass = Natives.GetVehicleClass(currentState.vehicle)
            currentState.vehicleSpeed = Natives.GetEntitySpeed(currentState.vehicle)
            currentState.vehicleModel = Natives.GetEntityModel(currentState.vehicle)
        else
            currentState.vehicleClass = -1
            currentState.vehicleSpeed = 0.0
            currentState.vehicleModel = 0
        end

        -- Get weapon state
        currentState.weaponHash = Natives.GetSelectedPedWeapon(ped)
        currentState.weaponAmmo = 0
        currentState.weaponClip = 0

        -- Try to get ammo info if we have a valid weapon
        if currentState.weaponHash and currentState.weaponHash ~= 0 then
            local result, currentAmmo = Natives.GetAmmoInClip(ped, currentState.weaponHash)
            currentState.weaponClip = currentAmmo or 0
            currentState.weaponAmmo = Natives.GetAmmoInPedWeapon(ped, currentState.weaponHash) or 0
        end

        -- Update cache timestamp
        cache.lastUpdate = currentTime

        -- Store these values in cache
        for k, v in pairs(currentState) do
            cache.data[k] = v
        end
    else
        -- Use cached values for properties that don't need frequent updates
        for k, v in pairs(cache.data) do
            if k ~= "pos" and k ~= "velocity" and k ~= "speed" then
                currentState[k] = v
            end
        end
    end

    -- Get player state flags (always update these as they change frequently)
    currentState.isFalling = Natives.IsPedFalling(ped)
    currentState.isRagdoll = Natives.IsPedRagdoll(ped)
    currentState.isParachuting = Natives.GetPedParachuteState(ped)
    currentState.isSwimming = Natives.IsPedSwimming(ped)
    currentState.isJumping = Natives.IsPedJumping(ped)
    currentState.isClimbing = Natives.IsPedClimbing(ped)
    currentState.isReloading = Natives.IsPedReloading(ped)
    currentState.isShooting = Natives.IsPedShooting(ped)
    currentState.isAiming = Natives.IsPlayerFreeAiming(playerId)
    currentState.isDead = Natives.IsEntityDead(ped)

    -- Add timestamp
    currentState.timestamp = currentTime

    return currentState
end

-- Clean up player state cache when a player disconnects
function StateValidator.CleanupPlayerStateCache(playerId)
    if playerStateCache[playerId] then
        playerStateCache[playerId] = nil
        Log("Cleaned up state cache for player ID: " .. playerId, Utils.logLevels.DEBUG)
    end
end

-- Add a state to the player's history
function StateValidator.AddStateToHistory(playerId, state)
    if not StateValidator.stateHistory[playerId] then
        StateValidator.InitializePlayer(playerId)
    end

    -- Add the new state to the beginning of the history array
    table.insert(StateValidator.stateHistory[playerId], 1, state)

    -- Trim history to the configured size
    while #StateValidator.stateHistory[playerId] > StateValidator.historySize do
        table.remove(StateValidator.stateHistory[playerId])
    end
end

-- Get thresholds from config or use defaults
function StateValidator.GetThresholds()
    local config = NexusGuardServer.Config or {}
    local thresholds = config.Thresholds or {}

    -- Create a new table with defaults that are overridden by config values if they exist
    local result = {}
    for k, v in pairs(StateValidator.defaultThresholds) do
        result[k] = thresholds[k] or v
    end

    return result
end

-- Update player metrics based on new state
function StateValidator.UpdateMetrics(playerId, currentState, previousState)
    if not StateValidator.playerMetrics[playerId] then
        StateValidator.InitializePlayer(playerId)
    end

    local metrics = StateValidator.playerMetrics[playerId]
    local currentTime = GetGameTimer()

    -- Skip if we don't have a previous state to compare with
    if not previousState then
        metrics.lastUpdate = currentTime
        return
    end

    -- Calculate time delta in seconds
    local timeDelta = (currentTime - metrics.lastUpdate) / 1000.0
    if timeDelta <= 0 then return end  -- Avoid division by zero

    -- Update speed metrics
    metrics.avgSpeed = (metrics.avgSpeed * 0.9) + (currentState.speed * 0.1)  -- Weighted average
    metrics.maxSpeed = math.max(metrics.maxSpeed, currentState.speed)

    -- Track health changes
    if currentState.health ~= previousState.health then
        table.insert(metrics.healthChanges, {
            oldValue = previousState.health,
            newValue = currentState.health,
            delta = currentState.health - previousState.health,
            rate = (currentState.health - previousState.health) / timeDelta,
            timestamp = currentTime
        })

        -- Keep only the last 10 health changes
        while #metrics.healthChanges > 10 do
            table.remove(metrics.healthChanges, 1)
        end
    end

    -- Track armor changes
    if currentState.armor ~= previousState.armor then
        table.insert(metrics.armorChanges, {
            oldValue = previousState.armor,
            newValue = currentState.armor,
            delta = currentState.armor - previousState.armor,
            rate = (currentState.armor - previousState.armor) / timeDelta,
            timestamp = currentTime
        })

        -- Keep only the last 10 armor changes
        while #metrics.armorChanges > 10 do
            table.remove(metrics.armorChanges, 1)
        end
    end

    -- Track weapon switches
    if currentState.weaponHash ~= previousState.weaponHash then
        table.insert(metrics.weaponSwitches, {
            oldWeapon = previousState.weaponHash,
            newWeapon = currentState.weaponHash,
            timestamp = currentTime
        })

        -- Keep only the last 10 weapon switches
        while #metrics.weaponSwitches > 10 do
            table.remove(metrics.weaponSwitches, 1)
        end
    end

    -- Track state transitions
    local stateChanges = {}

    -- Check for various state transitions
    if currentState.isInVehicle ~= previousState.isInVehicle then
        table.insert(stateChanges, {
            type = "vehicle",
            from = previousState.isInVehicle,
            to = currentState.isInVehicle,
            timestamp = currentTime
        })
    end

    if currentState.isFalling ~= previousState.isFalling then
        table.insert(stateChanges, {
            type = "falling",
            from = previousState.isFalling,
            to = currentState.isFalling,
            timestamp = currentTime
        })
    end

    if currentState.isRagdoll ~= previousState.isRagdoll then
        table.insert(stateChanges, {
            type = "ragdoll",
            from = previousState.isRagdoll,
            to = currentState.isRagdoll,
            timestamp = currentTime
        })
    end

    if currentState.isSwimming ~= previousState.isSwimming then
        table.insert(stateChanges, {
            type = "swimming",
            from = previousState.isSwimming,
            to = currentState.isSwimming,
            timestamp = currentTime
        })
    end

    -- Add state changes to the metrics
    for _, change in ipairs(stateChanges) do
        table.insert(metrics.stateTransitions, change)
    end

    -- Keep only the last 20 state transitions
    while #metrics.stateTransitions > 20 do
        table.remove(metrics.stateTransitions, 1)
    end

    -- Update last update timestamp
    metrics.lastUpdate = currentTime
end

-- Validate state transitions for impossible or suspicious changes
function StateValidator.ValidateStateTransition(playerId, currentState, previousState)
    if not previousState then return true end  -- Can't validate without a previous state

    local thresholds = StateValidator.GetThresholds()
    local timeDelta = (currentState.timestamp - previousState.timestamp) / 1000.0  -- Convert to seconds
    if timeDelta <= 0 then return true end  -- Avoid division by zero

    local playerName = GetPlayerName(playerId) or "Unknown"
    local validationResults = {}
    local isValid = true

    -- Check for impossible position changes (teleporting)
    local dist = #(currentState.pos - previousState.pos)
    local speed = dist / timeDelta  -- Speed in meters per second

    -- Context-aware teleport detection
    if speed > thresholds.speedLimit and
       not previousState.isParachuting and
       not currentState.isParachuting and
       not previousState.isDead and
       not currentState.isDead then

        -- Check if player is in a vehicle (allows for higher speeds)
        if not currentState.isInVehicle or speed > thresholds.speedLimit * 3 then
            table.insert(validationResults, {
                valid = false,
                type = "teleport",
                details = {
                    distance = dist,
                    speed = speed,
                    timeDelta = timeDelta,
                    fromPos = previousState.pos,
                    toPos = currentState.pos
                },
                severity = "high"
            })
            isValid = false

            Log(string.format("^1[StateValidator]^7 Detected teleport for %s (ID: %d): %.1f meters in %.2f seconds (%.1f m/s)",
                playerName, playerId, dist, timeDelta, speed), 2)
        end
    end

    -- Check for impossible health changes
    if not previousState.isDead and not currentState.isDead then
        local healthDelta = currentState.health - previousState.health
        local healthRate = healthDelta / timeDelta

        -- Health regeneration too fast (positive change)
        if healthDelta > 0 and healthRate > thresholds.healthChangeRate then
            table.insert(validationResults, {
                valid = false,
                type = "health_regen",
                details = {
                    oldHealth = previousState.health,
                    newHealth = currentState.health,
                    delta = healthDelta,
                    rate = healthRate,
                    timeDelta = timeDelta
                },
                severity = "medium"
            })
            isValid = false

            Log(string.format("^1[StateValidator]^7 Detected suspicious health regeneration for %s (ID: %d): +%d HP in %.2f seconds (%.1f HP/s)",
                playerName, playerId, healthDelta, timeDelta, healthRate), 2)
        end
    end

    -- Check for impossible armor changes
    local armorDelta = currentState.armor - previousState.armor
    local armorRate = armorDelta / timeDelta

    -- Armor increase too fast
    if armorDelta > 0 and armorRate > thresholds.armorChangeRate then
        table.insert(validationResults, {
            valid = false,
            type = "armor_change",
            details = {
                oldArmor = previousState.armor,
                newArmor = currentState.armor,
                delta = armorDelta,
                rate = armorRate,
                timeDelta = timeDelta
            },
            severity = "medium"
        })
        isValid = false

        Log(string.format("^1[StateValidator]^7 Detected suspicious armor change for %s (ID: %d): +%d armor in %.2f seconds (%.1f armor/s)",
            playerName, playerId, armorDelta, timeDelta, armorRate), 2)
    end

    -- Check for impossible weapon switches (too fast)
    if currentState.weaponHash ~= previousState.weaponHash then
        local timeSinceLastSwitch = currentState.timestamp - previousState.timestamp

        if timeSinceLastSwitch < thresholds.weaponSwitchTime then
            table.insert(validationResults, {
                valid = false,
                type = "weapon_switch",
                details = {
                    oldWeapon = previousState.weaponHash,
                    newWeapon = currentState.weaponHash,
                    switchTime = timeSinceLastSwitch
                },
                severity = "low"
            })
            isValid = false

            Log(string.format("^1[StateValidator]^7 Detected suspicious weapon switch for %s (ID: %d): Changed weapons in %d ms",
                playerName, playerId, timeSinceLastSwitch), 2)
        end
    end

    -- Check for impossible vehicle entry/exit (too fast)
    if currentState.isInVehicle ~= previousState.isInVehicle then
        local timeSinceStateChange = currentState.timestamp - previousState.timestamp

        if timeSinceStateChange < thresholds.vehicleEntryExitTime then
            table.insert(validationResults, {
                valid = false,
                type = "vehicle_transition",
                details = {
                    oldState = previousState.isInVehicle,
                    newState = currentState.isInVehicle,
                    transitionTime = timeSinceStateChange
                },
                severity = "low"
            })
            isValid = false

            Log(string.format("^1[StateValidator]^7 Detected suspicious vehicle %s for %s (ID: %d): Transition in %d ms",
                currentState.isInVehicle and "entry" or "exit", playerName, playerId, timeSinceStateChange), 2)
        end
    end

    -- Return validation results
    return isValid, validationResults
end

-- Report a detection to the detection system
function StateValidator.ReportDetection(playerId, detectionType, details, severity)
    -- Get the player's session from the server
    local session = nil
    if NexusGuardServer and NexusGuardServer.GetPlayerSession then
        session = NexusGuardServer.GetPlayerSession(playerId)
    end

    -- Prepare detection data
    local detectionData = {
        value = details.value or 0,
        details = details,
        clientValidated = false,  -- This is a server-side detection
        serverValidated = true
    }

    -- Report the detection using the Detections module
    if NexusGuardServer and NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
        NexusGuardServer.Detections.Process(playerId, detectionType, detectionData, session)
    else
        -- Fallback if Detections module is not available
        Log(string.format("^1[StateValidator]^7 Detection triggered for %s (ID: %d): %s (Severity: %s)",
            GetPlayerName(playerId) or "Unknown", playerId, detectionType, severity), 1)
    end
end

-- Main validation function
function StateValidator.ValidateState(playerId)
    -- Run cleanup periodically
    StateValidator.Cleanup()

    -- Get player ped
    local ped = GetPlayerPed(playerId)
    if not DoesEntityExist(ped) then return false, "invalid_ped" end

    -- Get current state
    local currentState = StateValidator.GetCurrentState(playerId)
    if not currentState then return false, "failed_to_get_state" end

    -- Get previous state if available
    local previousState = nil
    if StateValidator.stateHistory[playerId] and #StateValidator.stateHistory[playerId] > 0 then
        previousState = StateValidator.stateHistory[playerId][1]
    end

    -- Add current state to history
    StateValidator.AddStateToHistory(playerId, currentState)

    -- Update player metrics
    StateValidator.UpdateMetrics(playerId, currentState, previousState)

    -- Validate state transition
    local isValid, validationResults = StateValidator.ValidateStateTransition(playerId, currentState, previousState)

    -- Report any failed validations
    if not isValid and validationResults then
        for _, result in ipairs(validationResults) do
            if not result.valid then
                -- Map validation types to detection types
                local detectionTypeMap = {
                    teleport = "ServerTeleportCheck",
                    health_regen = "ServerHealthRegenCheck",
                    armor_change = "ServerArmorCheck",
                    weapon_switch = "ServerWeaponSwitchCheck",
                    vehicle_transition = "ServerVehicleTransitionCheck"
                }

                -- Map severity levels
                local severityMap = {
                    low = "Low",
                    medium = "Medium",
                    high = "High"
                }

                -- Report the detection
                local detectionType = detectionTypeMap[result.type] or "ServerStateCheck"
                local severity = severityMap[result.severity] or "Medium"

                StateValidator.ReportDetection(playerId, detectionType, result.details, severity)

                -- Increment suspicious events counter
                if StateValidator.playerMetrics[playerId] then
                    StateValidator.playerMetrics[playerId].suspiciousEvents = StateValidator.playerMetrics[playerId].suspiciousEvents + 1
                end
            end
        end
    end

    return isValid, validationResults
end

-- Get player metrics for external use
function StateValidator.GetPlayerMetrics(playerId)
    return StateValidator.playerMetrics[playerId]
end

-- Get player state history for external use
function StateValidator.GetPlayerStateHistory(playerId)
    return StateValidator.stateHistory[playerId]
end

return StateValidator