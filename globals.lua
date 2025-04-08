--[[
    NexusGuard Globals & Server-Side Helpers (Refactored)
    Contains shared functions and placeholder implementations, organized into modules.
]]

-- JSON library is expected to be provided by ox_lib (lib.json.encode/decode)
-- local json = _G.json -- REMOVED: Use lib.json directly

-- Main container for server-side logic and data
local NexusGuardServer = {
    API = {},
    Config = _G.Config or {}, -- Still need access to Config loaded from config.lua
    -- PlayerMetrics = _G.PlayerMetrics or {}, -- REMOVED: Metrics are now handled by PlayerSessionManager in server_main and passed as arguments
    BanCache = {},
    BanCacheExpiry = 0,
    BanCacheDuration = 300, -- Cache duration in seconds (5 minutes)
    ESX = nil,
    QBCore = nil,
    Security = {}, -- Logic moved to sv_security.lua
    Detections = {}, -- Logic moved to modules/detections.lua
    Database = {}, -- Logic moved to sv_database.lua
    Discord = {}, -- Logic moved to sv_discord.lua (or kept here if simple)
    EventHandlers = {}, -- Logic moved to sv_event_handlers.lua
    OnlineAdmins = {} -- Central table for online admins
}

-- Load required core modules
local Utils = require('server/sv_utils')
local Permissions = require('server/sv_permissions')
local Security = require('server/sv_security')
local Bans = require('server/sv_bans')
local Database = require('server/sv_database')
local EventHandlers = require('server/sv_event_handlers')
local Detections = require('server/modules/detections') -- Load the existing detections module
-- local Discord = require('server/sv_discord') -- Example if Discord logic is moved

-- Local alias for logging
local Log = Utils.Log

-- Assign loaded modules to the main NexusGuardServer table to expose them via the API
NexusGuardServer.Utils = Utils
NexusGuardServer.Permissions = Permissions
NexusGuardServer.Security = Security
NexusGuardServer.Bans = Bans
NexusGuardServer.Database = Database
NexusGuardServer.EventHandlers = EventHandlers
NexusGuardServer.Detections = Detections
-- NexusGuardServer.Discord = Discord -- Assign if moved to its own module

-- Attempt to load framework objects (This logic is handled in sv_permissions.lua)
-- Citizen.CreateThread(function()
--     Citizen.Wait(500) -- Short delay
--     if GetResourceState('es_extended') == 'started' then
--         local esxExport = exports['es_extended']
--         if esxExport and esxExport.getSharedObject then
--              NexusGuardServer.ESX = esxExport:getSharedObject()
--              Utils.Log("ESX object loaded for permission checks.", 3) -- Use Utils.Log
--         else
--              Utils.Log("es_extended resource found, but could not get SharedObject.", 2) -- Use Utils.Log
--         end
--     end
--     if GetResourceState('qb-core') == 'started' then
--          local qbExport = exports['qb-core']
--          if qbExport and qbExport.GetCoreObject then
--              NexusGuardServer.QBCore = qbExport:GetCoreObject()
--              Utils.Log("QBCore object loaded for permission checks.", 3) -- Use Utils.Log
--          else
--              Utils.Log("qb-core resource found, but could not get CoreObject.", 2) -- Use Utils.Log
--          end
--     end
-- end)

-- #############################################################################
-- ## Bans Module (Logic moved to sv_bans.lua) ##
-- #############################################################################
-- NexusGuardServer.Bans = {} -- Definition moved
-- function NexusGuardServer.Bans.LoadList(forceReload) ... end -- Function moved
-- function NexusGuardServer.Bans.IsPlayerBanned(license, ip, discordId) ... end -- Function moved
-- function NexusGuardServer.Bans.Store(banData) ... end -- Function moved
-- function NexusGuardServer.Bans.Execute(playerId, reason, adminName, durationSeconds) ... end -- Function moved
-- function NexusGuardServer.Bans.Unban(identifierType, identifierValue, adminName) ... end -- Function moved

-- #############################################################################
-- ## Permissions Module (Logic moved to sv_permissions.lua) ##
-- #############################################################################

-- #############################################################################
-- ## Security Module (Logic moved to sv_security.lua) ##
-- #############################################################################

-- #############################################################################
-- ## Detections Module (Logic moved to modules/detections.lua) ##
-- #############################################################################
-- NexusGuardServer.Detections = {} -- Definition moved
-- function NexusGuardServer.Detections.Store(playerId, detectionType, detectionData) ... end -- Function moved to sv_database.lua
-- function NexusGuardServer.Detections.GetSeverity(detectionType) ... end -- Function moved
-- function NexusGuardServer.Detections.IsConfirmedCheat(detectionType, detectionData) ... end -- Function moved
-- function NexusGuardServer.Detections.IsHighRisk(detectionType, detectionData) ... end -- Function moved
-- function NexusGuardServer.Detections.ValidateWeaponDamage(playerId, weaponHash, reportedDamage, targetEntity) ... end -- Function moved
-- function NexusGuardServer.Detections.ValidateVehicleHealth(detectionData) ... end -- Function moved
-- function NexusGuardServer.Detections.Process(playerId, detectionType, detectionData, session) ... end -- Function moved

-- #############################################################################
-- ## Discord Module (Logic kept here for now, could be moved) ##
-- #############################################################################
NexusGuardServer.Discord = {}

function NexusGuardServer.Discord.Send(category, title, message, specificWebhook)
    local discordConfig = NexusGuardServer.Config and NexusGuardServer.Config.Discord
    -- Check if Discord integration is enabled globally OR if general logging is enabled
    if not discordConfig or (not discordConfig.enabled and not NexusGuardServer.Config.EnableDiscordLogs) then return end

    local webhookURL = specificWebhook
    if not webhookURL or webhookURL == "" then
        -- Prioritize specific category webhook
        if discordConfig.webhooks and category and discordConfig.webhooks[category] and discordConfig.webhooks[category] ~= "" then
            webhookURL = discordConfig.webhooks[category]
        -- Fallback to general webhook if category-specific one isn't set
        elseif NexusGuardServer.Config.DiscordWebhook and NexusGuardServer.Config.DiscordWebhook ~= "" then
            webhookURL = NexusGuardServer.Config.DiscordWebhook
        else
            -- Log("Discord.Send: No valid webhook URL found for category '" .. tostring(category) .. "' or general config.", 3)
            return -- No valid webhook URL found
        end
    end

    if not PerformHttpRequest then Log("^1Error: PerformHttpRequest native not available.^7", 1); return end
    if not lib.json then Log("^1Error: ox_lib JSON library (lib.json) not available for SendToDiscord.^7", 1); return end

    -- Basic rate limiting (simple example: max 1 message per second per webhook)
    local rateLimitKey = webhookURL
    local now = GetGameTimer()
    if not NexusGuardServer.Discord.rateLimits then NexusGuardServer.Discord.rateLimits = {} end
    if NexusGuardServer.Discord.rateLimits[rateLimitKey] and (now - NexusGuardServer.Discord.rateLimits[rateLimitKey] < 1000) then
        -- Log("Discord rate limit hit for webhook: " .. webhookURL, 4) -- Debug log
        return
    end
    NexusGuardServer.Discord.rateLimits[rateLimitKey] = now

    -- Truncate message if too long for Discord embed description
    local maxLen = 4000 -- Discord description limit is 4096, leave some buffer
    if #message > maxLen then
        message = string.sub(message, 1, maxLen - 3) .. "..."
    end

    local embed = {{
        ["color"] = 16711680, -- Red default
        ["title"] = "**[NexusGuard] " .. (title or "Alert") .. "**",
        ["description"] = message or "No details provided.",
        ["footer"] = { ["text"] = "NexusGuard | " .. os.date("%Y-%m-%d %H:%M:%S") }
    }}
    local payloadSuccess, payload = pcall(lib.json.encode, { embeds = embed })
    if not payloadSuccess then Log("^1Error encoding Discord payload: " .. tostring(payload) .. "^7", 1); return end

    local success, err = pcall(PerformHttpRequest, webhookURL, function(errHttp, text, headers)
        if errHttp ~= 204 and errHttp ~= 200 then -- Check for non-success status codes
             Log(string.format("^1Error sending Discord webhook (Callback Status %s): %s^7", tostring(errHttp), text), 1)
        -- else Log("Discord notification sent: " .. title, 3) -- Reduce log spam
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
    if not success then Log("^1Error initiating Discord HTTP request: " .. tostring(err) .. "^7", 1) end
end

-- #############################################################################
-- ## Event Handlers Module (Logic moved to sv_event_handlers.lua) ##
-- #############################################################################
-- NexusGuardServer.EventHandlers = {} -- Definition moved
-- function NexusGuardServer.EventHandlers.HandleExplosion(sender, ev, session) ... end -- Function moved
-- function NexusGuardServer.EventHandlers.HandleEntityCreation(entity) ... end -- Function moved
-- function NexusGuardServer.EventHandlers.NotifyAdmins(playerId, detectionType, detectionData) ... end -- Function moved

-- #############################################################################
-- ## Initialization and Exports ##
-- #############################################################################

-- Expose the main server logic table
exports('GetNexusGuardServerAPI', function()
    return NexusGuardServer
end)

Utils.Log("NexusGuard globals refactored and helpers loaded.", 2) -- Use Utils.Log

-- Trigger initial DB load/check after globals are defined
-- Initialize Database after other modules are loaded
Citizen.CreateThread(function()
    Citizen.Wait(500) -- Short delay to ensure Config and API are ready
    if NexusGuardServer.Database and NexusGuardServer.Database.Initialize then
        NexusGuardServer.Database.Initialize()
    else
        Log("^1[NexusGuard] CRITICAL: Database module or Initialize function not found. Database setup skipped.^7", 1)
    end
end)
