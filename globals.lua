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
    Discord = {}              -- Basic Discord logic kept here for now.
}

-- Load required core server-side modules.
-- The order might matter if modules depend on each other during their own initialization.
-- Utils and Permissions are often needed early.
local Utils = require('server/sv_utils')
local Permissions = require('server/sv_permissions')
local Security = require('server/sv_security')
local Bans = require('server/sv_bans')
local Database = require('server/sv_database')
local EventHandlers = require('server/sv_event_handlers')
local Detections = require('server/modules/detections')
-- local Discord = require('server/sv_discord') -- Example if Discord logic is moved to its own file.

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
NexusGuardServer.EventHandlers = EventHandlers
NexusGuardServer.Detections = Detections
-- NexusGuardServer.Discord = Discord -- Assign if moved to its own module.

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

-- #############################################################################
-- ## Discord Module (Basic Implementation) ##
-- #############################################################################
-- Simple Discord webhook sender. Could be expanded or moved to sv_discord.lua.
NexusGuardServer.Discord = {
    rateLimits = {} -- Simple table to track last send time per webhook URL.
}

-- Sends a formatted embed message to a Discord webhook.
-- @param category (string): Used to look up category-specific webhook in Config.Discord.webhooks (e.g., "bans", "detections").
-- @param title (string): The title of the embed.
-- @param messageOrData (string|table): The main content (string) or a table of embed fields { {name=string, value=string, inline=bool}, ... }.
-- @param specificWebhook (string, optional): A specific webhook URL to use, overriding category/general config.
function NexusGuardServer.Discord.Send(category, title, messageOrData, specificWebhook)
    local discordConfig = NexusGuardServer.Config and NexusGuardServer.Config.Discord
    -- Check if Discord integration is enabled globally OR if general logging via DiscordWebhook is enabled.
    if not discordConfig or (not discordConfig.enabled and not NexusGuardServer.Config.DiscordWebhook) then return end

    local webhookURL = specificWebhook -- Use specific URL if provided.
    -- If no specific URL, determine the correct webhook based on category or general config.
    if not webhookURL or webhookURL == "" then
        -- Prioritize category-specific webhook from Config.Discord.webhooks.
        if discordConfig.webhooks and category and discordConfig.webhooks[category] and discordConfig.webhooks[category] ~= "" then
            webhookURL = discordConfig.webhooks[category]
        -- Fallback to the general Config.DiscordWebhook if category one isn't set or valid.
        elseif NexusGuardServer.Config.DiscordWebhook and NexusGuardServer.Config.DiscordWebhook ~= "" then
            webhookURL = NexusGuardServer.Config.DiscordWebhook
        else
            -- Log("Discord.Send: No valid webhook URL found for category '" .. tostring(category) .. "' or general config.", 3)
            return -- Exit if no valid webhook URL can be determined.
        end
    end

    -- Ensure required FiveM natives and libraries are available.
    if not PerformHttpRequest then Log("^1[NexusGuard] Error: PerformHttpRequest native not available. Cannot send Discord message.^7", 1); return end
    if not lib or not lib.json then Log("^1[NexusGuard] Error: ox_lib JSON library (lib.json) not available. Cannot send Discord message.^7", 1); return end

    -- Basic Rate Limiting: Prevent spamming a single webhook URL (max 1 message per second).
    local rateLimitKey = webhookURL
    local now = GetGameTimer()
    local rateLimits = NexusGuardServer.Discord.rateLimits -- Access the rate limit table.
    if rateLimits[rateLimitKey] and (now - rateLimits[rateLimitKey] < 1000) then
        -- Log("Discord rate limit hit for webhook: " .. webhookURL, 4) -- Optional debug log
        return -- Skip sending if rate limited.
    end
    rateLimits[rateLimitKey] = now -- Update last send time.

    -- Construct the Discord embed payload based on whether messageOrData is a string or table.
    local embedPayload = {
        ["color"] = discordConfig.embedColors and discordConfig.embedColors[category] or 16711680, -- Use category color or red default.
        ["title"] = "**[NexusGuard] " .. (title or "Alert") .. "**",
        ["footer"] = { ["text"] = "NexusGuard | " .. os.date("%Y-%m-%d %H:%M:%S") }
    }

    if type(messageOrData) == "table" then
        -- New format: Use fields from the table.
        embedPayload.fields = {}
        for _, fieldData in ipairs(messageOrData) do
            -- Ensure value is a string and truncate if necessary.
            local fieldValue = tostring(fieldData.value or "")
            local maxFieldLen = 1000 -- Leave buffer below 1024 limit.
            if #fieldValue > maxFieldLen then
                fieldValue = string.sub(fieldValue, 1, maxFieldLen - 3) .. "..."
            end
            table.insert(embedPayload.fields, {
                name = tostring(fieldData.name or "Field"),
                value = fieldValue,
                inline = fieldData.inline or false
            })
        end
    elseif type(messageOrData) == "string" then
        -- Old format: Use the string as the description.
        local message = messageOrData
        local maxDescLen = 4000 -- Leave buffer below 4096 limit.
        if #message > maxDescLen then
            message = string.sub(message, 1, maxDescLen - 3) .. "..."
        end
        embedPayload.description = message
    else
        -- Fallback if data is neither string nor table.
        embedPayload.description = "Invalid data format received."
    end

    -- Safely encode the payload to JSON.
    local payloadSuccess, payload = pcall(lib.json.encode, { embeds = { embedPayload } }) -- Note: embeds is an array containing the single embed object.
    if not payloadSuccess then Log("^1[NexusGuard] Error encoding Discord payload: " .. tostring(payload) .. "^7", 1); return end

    -- Perform the HTTP request asynchronously.
    local success, err = pcall(PerformHttpRequest, webhookURL, function(errHttp, text, headers)
        -- Callback function to handle the HTTP response.
        -- Discord usually returns 204 No Content on success. 200 OK might also occur.
        if errHttp ~= 204 and errHttp ~= 200 then
             Log(string.format("^1[NexusGuard] Error sending Discord webhook (Callback Status %s): %s^7", tostring(errHttp), text), 1)
        -- else Log("Discord notification sent: " .. title, 3) -- Optional success log (can be spammy).
        end
    end, 'POST', payload, { ['Content-Type'] = 'application/json' }) -- Set method, payload, and headers.

    -- Log if the initial pcall to PerformHttpRequest failed.
    if not success then Log("^1[NexusGuard] Error initiating Discord HTTP request: " .. tostring(err) .. "^7", 1) end
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
