--[[
    NexusGuard Discord Module (server/sv_discord.lua)

    Handles sending formatted messages to Discord webhooks.
    Provides rate limiting to avoid spamming Discord's API.
]]

-- NexusGuard Server API (Accessed via the main NexusGuardServer table passed during initialization or globally)
-- We need access to Config and potentially Utils.Log
-- Assuming this module will be required by globals.lua which defines NexusGuardServer

local DiscordModule = {
    rateLimits = {} -- Simple table to track last send time per webhook URL.
}

-- Local reference to Config and Log (will be set during initialization or assumed global access via NexusGuardServer)
local Config = _G.Config or {} -- Fallback, ideally passed or accessed via API
local Log = function(msg, level) print(msg) end -- Basic fallback for Log

-- Function to set the Config and Log references, called from globals.lua after loading Utils
function DiscordModule.Initialize(cfg, logFunc)
    Config = cfg or Config
    Log = logFunc or Log
    Log("Discord module initialized with Config and Log references.", 3)
end

-- Sends a formatted embed message to a Discord webhook.
-- @param category (string): Used to look up category-specific webhook in Config.Discord.webhooks (e.g., "bans", "detections").
-- @param title (string): The title of the embed.
-- @param messageOrData (string|table): The main content (string) or a table of embed fields { {name=string, value=string, inline=bool}, ... }.
-- @param specificWebhook (string, optional): A specific webhook URL to use, overriding category/general config.
function DiscordModule.Send(category, title, messageOrData, specificWebhook)
    local discordConfig = Config and Config.Discord
    -- Check if Discord integration is enabled globally OR if general logging via DiscordWebhook is enabled.
    if not discordConfig or (not discordConfig.enabled and not Config.DiscordWebhook) then return end

    local webhookURL = specificWebhook -- Use specific URL if provided.
    -- If no specific URL, determine the correct webhook based on category or general config.
    if not webhookURL or webhookURL == "" then
        -- Prioritize category-specific webhook from Config.Discord.webhooks.
        if discordConfig.webhooks and category and discordConfig.webhooks[category] and discordConfig.webhooks[category] ~= "" then
            webhookURL = discordConfig.webhooks[category]
        -- Fallback to the general Config.DiscordWebhook if category one isn't set or valid.
        elseif Config.DiscordWebhook and Config.DiscordWebhook ~= "" then
            webhookURL = Config.DiscordWebhook
        else
            -- Log("Discord.Send: No valid webhook URL found for category '" .. tostring(category) .. "' or general config.", 3)
            return -- Exit if no valid webhook URL can be determined.
        end
    end

    -- Ensure required FiveM natives and libraries are available.
    if not PerformHttpRequest then Log("^1[NexusGuard] Error: PerformHttpRequest native not available. Cannot send Discord message.^7", 1); return end
    -- Assuming ox_lib is loaded globally or accessible via lib
    if not lib or not lib.json then Log("^1[NexusGuard] Error: ox_lib JSON library (lib.json) not available. Cannot send Discord message.^7", 1); return end

    -- Basic Rate Limiting: Prevent spamming a single webhook URL (max 1 message per second).
    local rateLimitKey = webhookURL
    local now = GetGameTimer()
    local rateLimits = DiscordModule.rateLimits -- Access the rate limit table within this module.
    if rateLimits[rateLimitKey] and (now - rateLimits[rateLimitKey] < 1000) then
        -- Log("Discord rate limit hit for webhook: " .. webhookURL, 4) -- Optional debug log
        return -- Skip sending if rate limited.
    end
    rateLimits[rateLimitKey] = now -- Update last send time.

    -- Construct the Discord embed payload based on whether messageOrData is a string or table.
    -- Default embed color (Red)
    local embedColor = 16711680
    -- Try to get category-specific color if configured
    if discordConfig.embedColors and discordConfig.embedColors[category] then
        -- Ensure the color is a number, handle hex strings if necessary (basic example)
        local catColor = discordConfig.embedColors[category]
        if type(catColor) == "number" then
            embedColor = catColor
        elseif type(catColor) == "string" and string.sub(catColor, 1, 1) == "#" then
            embedColor = tonumber(string.sub(catColor, 2), 16) or embedColor -- Convert hex to decimal
        end
    end

    local embedPayload = {
        ["color"] = embedColor,
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

-- Return the module table so it can be assigned in globals.lua
return DiscordModule
