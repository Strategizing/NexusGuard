--[[
    NexusGuard Server-Side Event Handlers Module
    Contains logic for handling specific game or custom events.
]]

local EventHandlers = {}

-- Get the NexusGuard Server API from globals.lua (needed for Config, Utils, Detections, Discord, OnlineAdmins)
-- Use pcall for safety in case globals isn't fully loaded yet when this module is required
local successAPI, NexusGuardServer = pcall(function() return exports['NexusGuard']:GetNexusGuardServerAPI() end)
if not successAPI or not NexusGuardServer then
    print("^1[NexusGuard EH] CRITICAL: Failed to get NexusGuardServer API. Event Handlers module may fail.^7")
    -- Create a dummy API structure to prevent errors in functions below if API failed
    NexusGuardServer = NexusGuardServer or {
        Config = {},
        Utils = { Log = function(...) print(...) end },
        Detections = {},
        Discord = {},
        OnlineAdmins = {}
    }
end

-- Local alias for logging and JSON
local Log = NexusGuardServer.Utils.Log or function(...) print(...) end -- Fallback logger
-- local json = _G.json -- REMOVED: Use lib.json directly

-- Guideline 33: Refine HandleExplosionEvent
-- Accepts the player's session data as the third argument
function EventHandlers.HandleExplosion(sender, ev, session)
    local source = tonumber(sender)
    -- Use the passed session object directly
    if not source or source <= 0 or not session or not session.metrics then
        -- Log("^1[NexusGuard HandleExplosion] Invalid source or missing session/metrics for player " .. tostring(source) .. "^7", 1) -- Optional logging
        return
    end

    -- Check if explosion checks are enabled in config
    local explosionCheckCfg = NexusGuardServer.Config and NexusGuardServer.Config.ExplosionChecks
    if not explosionCheckCfg or not explosionCheckCfg.enabled then
        return -- Exit if checks are disabled
    end

    if not ev or ev.explosionType == nil or ev.posX == nil or ev.posY == nil or ev.posZ == nil then Log("^1Warning: Received incomplete explosionEvent data from " .. source .. "^7", 1); return end

    local explosionType = ev.explosionType
    local position = vector3(ev.posX or 0, ev.posY or 0, ev.posZ or 0)
    local currentTime = os.time()
    local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

    -- Use configured values with defaults
    local spamTimeWindow = explosionCheckCfg.spamTimeWindow or 10 -- seconds
    local spamCountThreshold = explosionCheckCfg.spamCountThreshold or 5
    local spamDistanceThreshold = explosionCheckCfg.spamDistanceThreshold or 5.0 -- meters
    local blacklistedTypes = explosionCheckCfg.blacklistedTypes or {}
    local kickOnBlacklisted = explosionCheckCfg.kickOnBlacklisted or false
    local banOnBlacklisted = explosionCheckCfg.banOnBlacklisted or false

    -- Build the blacklist set for quick lookup
    local blacklistedTypeSet = {}
    for _, typeId in ipairs(blacklistedTypes) do blacklistedTypeSet[typeId] = true end

    -- Check for blacklisted explosion types first
    if blacklistedTypeSet[explosionType] then
        local reason = "Triggered blacklisted explosion type: " .. explosionType
        Log(string.format("^1[NexusGuard Server Check]^7 Player %s (ID: %d) %s at %s^7", playerName, source, reason, position), 1)
        -- Process the detection (useful for logging/trust score) - Ensure Detections API is available
        if NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
            NexusGuardServer.Detections.Process(source, "BlacklistedExplosion", { type = explosionType, position = position }, session)
        else Log("^1[NexusGuard EH] Detections.Process API not found! Cannot process BlacklistedExplosion.^7", 1) end

        -- Apply immediate action if configured - Ensure Bans API is available
        if banOnBlacklisted then
            Log("^1[NexusGuard] Banning player " .. playerName .. " for blacklisted explosion.^7", 1)
            if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
                NexusGuardServer.Bans.Execute(source, reason, "NexusGuard System (Blacklisted Explosion)")
            else Log("^1[NexusGuard EH] Bans.Execute API not found! Cannot ban player.^7", 1) end
            return -- Stop further processing after ban
        elseif kickOnBlacklisted then
            Log("^1[NexusGuard] Kicking player " .. playerName .. " for blacklisted explosion.^7", 1)
            DropPlayer(source, NexusGuardServer.Config.KickMessage or "Kicked for suspicious activity (Explosion).")
            return -- Stop further processing after kick
        end
        -- If no immediate action, spam check below might still catch it if repeated
    end

    -- Refined Spam Check
    if not session.metrics.explosions then session.metrics.explosions = {} end
    table.insert(session.metrics.explosions, { type = explosionType, position = position, time = currentTime })

    local recentCount = 0
    local recentExplosionsInArea = {}
    local tempExplosions = {} -- Keep track of explosions within the time window

    -- Iterate backwards to efficiently prune old explosions and count recent ones
    for i = #session.metrics.explosions, 1, -1 do
        local explosion = session.metrics.explosions[i]
        if currentTime - explosion.time < spamTimeWindow then
            table.insert(tempExplosions, 1, explosion) -- Keep this explosion
            recentCount = recentCount + 1
            -- Check distance from the *current* explosion to other *recent* explosions
            if #(position - explosion.position) < spamDistanceThreshold then
                table.insert(recentExplosionsInArea, explosion)
            end
        else
            -- Stop iterating once we are outside the time window (since they are ordered by time)
            break
        end
    end
    session.metrics.explosions = tempExplosions -- Update the list with only recent explosions

    -- Trigger detection if count exceeds threshold OR if many explosions happened in the same small area
    local spamInAreaCount = #recentExplosionsInArea
    if recentCount > spamCountThreshold or spamInAreaCount > (spamCountThreshold / 2) then -- Example: trigger if > 5 total OR > 2 in same small area
        Log(string.format("^1[NexusGuard Server Check]^7 Explosion spam detected for %s (ID: %d). Count: %d in %ds. Count in area (<%sm): %d^7",
            playerName, source, recentCount, spamTimeWindow, spamDistanceThreshold, spamInAreaCount), 1)
        -- Ensure Detections API is available
        if NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
            NexusGuardServer.Detections.Process(source, "ExplosionSpam", {
                count = recentCount,
                period = spamTimeWindow,
                areaCount = spamInAreaCount,
                areaDistance = spamDistanceThreshold,
                lastType = explosionType,
                lastPosition = position
            }, session) -- Pass session object
        else Log("^1[NexusGuard EH] Detections.Process API not found! Cannot process ExplosionSpam.^7", 1) end
    end
end

function EventHandlers.HandleEntityCreation(entity)
    -- Placeholder - Requires careful implementation and filtering
    -- Log("Placeholder: HandleEntityCreation called for entity " .. entity, 4)
end

function EventHandlers.NotifyAdmins(playerId, detectionType, detectionData)
    local playerName = GetPlayerName(playerId) or ("Unknown (" .. playerId .. ")")
    if not lib.json then Log("^1[NexusGuard] ox_lib JSON library (lib.json) not available for NotifyAdmins.^7", 1); return end

    local dataString = "N/A"
    local successEncode, result = pcall(lib.json.encode, detectionData)
    if successEncode then dataString = result else Log("^1[NexusGuard] Failed to encode detectionData for admin notification.^7", 1) end

    Log('^1[NexusGuard]^7 Admin Notify: ' .. playerName .. ' (ID: ' .. playerId .. ') - ' .. detectionType .. ' - Data: ' .. dataString .. "^7", 1)

    -- Use the OnlineAdmins table from the API
    local onlineAdmins = NexusGuardServer.OnlineAdmins or {}
    local adminCount = 0; for _ in pairs(onlineAdmins) do adminCount = adminCount + 1 end
    if adminCount == 0 then Log("^3[NexusGuard] No admins online to notify.^7", 3); return end

    for adminId, _ in pairs(onlineAdmins) do
        if GetPlayerName(adminId) then
             -- Ensure EventRegistry is available (it's likely global or needs to be passed/required)
             local EventRegistry = _G.EventRegistry -- Assuming global for now
             if EventRegistry and EventRegistry.TriggerClientEvent then
                 EventRegistry:TriggerClientEvent('ADMIN_NOTIFICATION', adminId, {
                    player = playerName, playerId = playerId, type = detectionType,
                    data = detectionData, timestamp = os.time()
                 })
             else Log("^1[NexusGuard EH] EventRegistry or TriggerClientEvent not found. Cannot send admin notification.^7", 1) end
        else
            -- Clean up disconnected admin from the API table
            if NexusGuardServer.OnlineAdmins then NexusGuardServer.OnlineAdmins[adminId] = nil end
        end
    end
end

return EventHandlers
