--[[
    NexusGuard Server Bans Module
    Handles loading, checking, storing, and executing bans.
]]

local Utils = require('server/sv_utils')
local Log = Utils.Log
local FormatDuration = Utils.FormatDuration

local Bans = {
    BanCache = {},
    BanCacheExpiry = 0,
    BanCacheDuration = 300 -- Default cache duration (seconds)
}

-- Loads the active ban list from the database into the cache
-- @param forceReload boolean: If true, bypasses the cache expiry check.
function Bans.LoadList(forceReload)
    -- Access Config directly
    local dbConfig = _G.Config and _G.Config.Database
    local discordConfig = _G.Config and _G.Config.Discord
    local banCacheDuration = (_G.Config and _G.Config.BanCacheDuration) or Bans.BanCacheDuration -- Use configured or default

    if not dbConfig or not dbConfig.enabled then return end -- DB disabled
    if not MySQL then Log("^1Bans: MySQL object not found.^7", 1); return end

    local currentTime = os.time()
    if not forceReload and Bans.BanCacheExpiry > currentTime then return end -- Cache still valid

    Log("Bans: Loading ban list from database...", 2)
    local success, bans = pcall(MySQL.Async.fetchAll, 'SELECT * FROM nexusguard_bans WHERE expire_date IS NULL OR expire_date > NOW()', {})

    if success and type(bans) == "table" then
        Bans.BanCache = bans
        Bans.BanCacheExpiry = currentTime + banCacheDuration
        Log("Bans: Loaded " .. #Bans.BanCache .. " active bans from database.", 2)
    elseif not success then
        Log(string.format("^1Bans: Error loading bans from database: %s^7", tostring(bans)), 1)
        Bans.BanCache = {}
        Bans.BanCacheExpiry = 0 -- Reset expiry on error
    else
        Log("^1Bans: Received unexpected result while loading bans from database.^7", 1)
        Bans.BanCache = {}
        Bans.BanCacheExpiry = 0
    end
end

-- Checks if any of the player's identifiers match an active ban
-- @param license string: Player's license identifier.
-- @param ip string: Player's IP address.
-- @param discordId string: Player's Discord ID.
-- @return boolean, string: True and reason if banned, false and nil otherwise.
function Bans.IsPlayerBanned(license, ip, discordId)
    local dbConfig = _G.Config and _G.Config.Database
    local banCacheDuration = (_G.Config and _G.Config.BanCacheDuration) or Bans.BanCacheDuration

    -- Reload cache if expired
    if dbConfig and dbConfig.enabled and Bans.BanCacheExpiry <= os.time() then
        Bans.LoadList(false)
    end

    for _, ban in ipairs(Bans.BanCache) do
        local identifiersMatch = false
        if license and ban.license and ban.license == license then identifiersMatch = true end
        if ip and ban.ip and ban.ip == ip then identifiersMatch = true end
        if discordId and ban.discord and ban.discord == discordId then identifiersMatch = true end

        if identifiersMatch then
            return true, ban.reason or "No reason specified"
        end
    end
    return false, nil
end

-- Stores a ban record in the database
-- @param banData table: Table containing ban details (name, license, ip, discord, reason, admin, durationSeconds).
function Bans.Store(banData)
    local dbConfig = _G.Config and _G.Config.Database
    if not dbConfig or not dbConfig.enabled then Log("Bans: Attempted to store ban while Database is disabled.", 3); return end
    if not MySQL then Log("^1Bans: MySQL object not found. Cannot store ban.^7", 1); return end
    if not banData or not banData.license then Log("^1Bans: Cannot store ban without player license identifier.^7", 1); return end

    local expireDate = nil
    if banData.durationSeconds and banData.durationSeconds > 0 then
        expireDate = os.date("!%Y-%m-%d %H:%M:%S", os.time() + banData.durationSeconds)
    end

    local success, result = pcall(MySQL.Async.execute,
        'INSERT INTO nexusguard_bans (name, license, ip, discord, reason, admin, expire_date) VALUES (@name, @license, @ip, @discord, @reason, @admin, @expire_date)',
        {
            ['@name'] = banData.name, ['@license'] = banData.license, ['@ip'] = banData.ip,
            ['@discord'] = banData.discord, ['@reason'] = banData.reason,
            ['@admin'] = banData.admin or "NexusGuard System", ['@expire_date'] = expireDate
        }
    )
    if success then
        if result and result > 0 then
             Log("Bans: Ban for " .. banData.name .. " stored in database.", 2)
             Bans.LoadList(true) -- Force reload ban cache
        else
             Log("^1Bans: Storing ban for " .. banData.name .. " reported 0 affected rows.^7", 1)
        end
    else
        Log(string.format("^1Bans: Error storing ban for %s in database: %s^7", banData.name, tostring(result)), 1)
    end
end

-- Executes a ban on a player (stores ban, drops player, logs)
-- @param playerId number: The server ID of the player to ban.
-- @param reason string: The reason for the ban.
-- @param adminName string: The name of the admin issuing the ban (or system).
-- @param durationSeconds number: Duration of the ban in seconds (0 or nil for permanent).
function Bans.Execute(playerId, reason, adminName, durationSeconds)
    local source = tonumber(playerId)
    if not source or source <= 0 then Log("^1Bans: Invalid player ID provided to Execute: " .. tostring(playerId) .. "^7", 1); return end
    local playerName = GetPlayerName(source)
    if not playerName then Log("^1Bans: Cannot ban player ID: " .. source .. " - Player not found.^7", 1); return end

    local license = GetPlayerIdentifierByType(source, 'license')
    local ip = GetPlayerEndpoint(source)
    local discordId = GetPlayerIdentifierByType(source, 'discord') -- Corrected variable name
    if not license then Log("^1Bans: Could not get license identifier for player " .. source .. ". Ban might be less effective.^7", 1) end

    local banData = {
        name = playerName, license = license, ip = ip and string.gsub(ip, "ip:", "") or nil,
        discord = discordId, reason = reason or "Banned by NexusGuard",
        admin = adminName or "NexusGuard System", durationSeconds = durationSeconds
    }
    Bans.Store(banData) -- Call the local Store function

    local banMessage = (_G.Config and _G.Config.BanMessage) or "You have been banned."
    if durationSeconds and durationSeconds > 0 then
        banMessage = banMessage .. " Duration: " .. FormatDuration(durationSeconds)
    end
    DropPlayer(source, banMessage)
    Log("^1Bans: Banned player: " .. playerName .. " (ID: " .. source .. ") Reason: " .. banData.reason .. "^7", 1)

    -- Send Discord notification if configured
    -- Requires Discord module to be loaded/available
    local Discord = _G.NexusGuardServer and _G.NexusGuardServer.Discord -- Access Discord module via global API table for now
    if Discord and Discord.Send then
        local discordMsg = string.format(
            "**Player Banned**\n**Name:** %s\n**License:** %s\n**IP:** %s\n**Discord:** %s\n**Reason:** %s\n**Admin:** %s",
            playerName, license or "N/A", banData.ip or "N/A", discordId or "N/A", banData.reason, banData.admin
        )
        if durationSeconds and durationSeconds > 0 then discordMsg = discordMsg .. "\n**Duration:** " .. FormatDuration(durationSeconds) end
        local webhook = (_G.Config and _G.Config.Discord and _G.Config.Discord.webhooks and _G.Config.Discord.webhooks.bans)
        Discord.Send("Bans", discordMsg, webhook)
    end
end

-- Unbans a player based on identifier
-- @param identifierType String: "license", "ip", or "discord"
-- @param identifierValue String: The actual identifier value
-- @param adminName String: Name of the admin performing the unban
-- @return boolean, string: True if successful, false + error message otherwise
function Bans.Unban(identifierType, identifierValue, adminName)
    local dbConfig = _G.Config and _G.Config.Database
    if not dbConfig or not dbConfig.enabled then return false, "Database is disabled." end
    if not MySQL then Log("^1Bans: MySQL object not found. Cannot unban.^7", 1); return false, "Database connection error." end
    if not identifierType or not identifierValue then return false, "Identifier type and value required." end

    local fieldName = string.lower(identifierType)
    if fieldName ~= "license" and fieldName ~= "ip" and fieldName ~= "discord" then
        return false, "Invalid identifier type. Use 'license', 'ip', or 'discord'."
    end

    Log("Bans: Attempting to unban identifier: " .. fieldName .. "=" .. identifierValue .. " by " .. (adminName or "System"), 2)

    -- Use async execute for the DELETE operation
    local promise = MySQL.Async.execute(
        'DELETE FROM nexusguard_bans WHERE ' .. fieldName .. ' = @identifier',
        { ['@identifier'] = identifierValue }
    )

    -- Handle the promise result (this part runs asynchronously)
    promise:next(function(result)
        if result and result.affectedRows and result.affectedRows > 0 then
            Log("Bans: Successfully unbanned identifier: " .. fieldName .. "=" .. identifierValue .. ". Rows affected: " .. result.affectedRows, 2)
            Bans.LoadList(true) -- Force reload ban cache
            -- Optionally notify admin/discord
            local Discord = _G.NexusGuardServer and _G.NexusGuardServer.Discord
            if Discord and Discord.Send then
                local webhook = (_G.Config and _G.Config.Discord and _G.Config.Discord.webhooks and _G.Config.Discord.webhooks.bans)
                Discord.Send("Bans", "Identifier Unbanned",
                    "Identifier **" .. fieldName .. ":** `" .. identifierValue .. "` was unbanned by **" .. (adminName or "System") .. "**.",
                    webhook)
            end
        elseif result and result.affectedRows == 0 then
            Log("Bans: Unban attempt for identifier: " .. fieldName .. "=" .. identifierValue .. " found no matching active ban.", 2)
        else
            Log("^1Bans: Error during unban operation for identifier: " .. fieldName .. "=" .. identifierValue .. ". Result: " .. lib.json.encode(result), 1)
        end
    end, function(err)
        Log("^1Bans: Error executing unban query for identifier: " .. fieldName .. "=" .. identifierValue .. ". Error: " .. tostring(err), 1)
    end)

    -- NOTE: Because this uses MySQL.Async, the command handler cannot directly return true/false based on DB result.
    -- It can only confirm the command was received and the async operation started.
    return true, "Unban process initiated. Check server console for details."
end

return Bans
