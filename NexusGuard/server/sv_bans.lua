--[[
    NexusGuard Server Bans Module (server/sv_bans.lua)

    Purpose:
    - Manages player bans, including loading active bans from the database,
      checking connecting players against the ban list, storing new bans,
      and executing ban actions (dropping players, logging).
    - Implements a caching mechanism (`Bans.BanCache`) to reduce database load during connection checks.
    - Uses `oxmysql` for asynchronous database operations.

    Dependencies:
    - `server/sv_utils.lua` (for logging and duration formatting)
    - `oxmysql` resource (provides the global `MySQL` object)
    - Global `Config` table (for database settings, ban messages, cache duration, Discord webhooks)
    - Global `NexusGuardServer` API table (potentially for Discord notifications)
]]

local Utils = require('server/sv_utils')
local Log = Utils.Log
local FormatDuration = Utils.FormatDuration

local Bans = {
    BanCache = {},        -- In-memory cache of active ban records loaded from the database.
    BanCacheExpiry = 0,   -- Timestamp (os.time) when the cache expires and needs reloading.
    BanCacheDuration = 300 -- Default duration cache is valid (seconds). Overridden by Config.BanCacheDuration.
}

--[[
    Loads the active ban list from the `nexusguard_bans` table into the memory cache (`Bans.BanCache`).
    Only loads bans that have not expired.
    Uses a cache duration (`Config.BanCacheDuration`) to avoid frequent database queries.

    @param forceReload (boolean, optional): If true, bypasses the cache expiry check and forces a reload.
]]
function Bans.LoadList(forceReload)
    -- Access global Config for database and cache settings.
    local dbConfig = _G.Config and _G.Config.Database
    local banCacheDuration = (_G.Config and _G.Config.BanCacheDuration) or Bans.BanCacheDuration -- Use configured or default duration.

    -- Exit if database is disabled in config.
    if not dbConfig or not dbConfig.enabled then return end
    -- Ensure oxmysql is available.
    if not MySQL then Log("^1Bans Error: MySQL object (from oxmysql) not found. Cannot load ban list.^7", 1); return end

    local currentTime = os.time()
    -- If not forcing reload, check if the cache is still valid based on expiry time.
    if not forceReload and Bans.BanCacheExpiry > currentTime then
        -- Log("Bans: Cache still valid, skipping database load.", 4) -- Optional debug log
        return
    end

    Log("Bans: Loading active ban list from database...", 2)
    -- Use pcall for safety when calling external library functions.
    -- Select bans where expire_date is NULL (permanent) or in the future.
    local success, bansResult = pcall(MySQL.Async.fetchAll, 'SELECT * FROM nexusguard_bans WHERE expire_date IS NULL OR expire_date > NOW()', {})

    if success and type(bansResult) == "table" then
        Bans.BanCache = bansResult -- Update the cache with the fetched bans.
        Bans.BanCacheExpiry = currentTime + banCacheDuration -- Set the new expiry time.
        Log(("Bans: Loaded %d active ban(s) into cache. Cache valid for %d seconds.^7"):format(#Bans.BanCache, banCacheDuration), 2)
    elseif not success then
        -- Log error if the database query itself failed. 'bansResult' contains the error message here.
        Log(string.format("^1Bans Error: Failed to load bans from database: %s^7", tostring(bansResult)), 1)
        Bans.BanCache = {} -- Clear cache on error.
        Bans.BanCacheExpiry = 0 -- Reset expiry to force reload on next check.
    else
        -- Log error if the query succeeded but didn't return a table (unexpected result).
        Log("^1Bans Error: Received unexpected result type while loading bans from database.^7", 1)
        Bans.BanCache = {}
        Bans.BanCacheExpiry = 0
    end
end

--[[
    Checks if a player is banned based on their identifiers against the cached ban list.
    Checks license, IP address, and Discord ID.

    @param license (string | nil): Player's license identifier (e.g., "license:xxx").
    @param ip (string | nil): Player's IP address (e.g., "ip:xxx.xxx.xxx.xxx").
    @param discordId (string | nil): Player's Discord ID (e.g., "discord:xxx").
    @return (boolean, string | nil): Returns `true` and the ban reason (string) if banned,
                                     otherwise returns `false` and `nil`.
]]
function Bans.IsPlayerBanned(license, ip, discordId)
    local dbConfig = _G.Config and _G.Config.Database

    -- Reload cache if database is enabled and cache has expired.
    if dbConfig and dbConfig.enabled and Bans.BanCacheExpiry <= os.time() then
        Bans.LoadList(false) -- Attempt to reload cache if expired.
    end

    -- Iterate through the cached ban records.
    for _, ban in ipairs(Bans.BanCache) do
        local identifiersMatch = false
        -- Check each identifier if provided and if present in the ban record.
        if license and ban.license and ban.license == license then identifiersMatch = true end
        -- Note: IP bans might be less reliable due to dynamic IPs. Consider config option to disable IP ban checks.
        if ip and ban.ip and ban.ip == ip then identifiersMatch = true end
        if discordId and ban.discord and ban.discord == discordId then identifiersMatch = true end

        -- If any identifier matches, the player is considered banned.
        if identifiersMatch then
            Log(("^1Bans Check: Player matched ban record (ID: %d, Reason: %s) based on identifier match.^7"):format(ban.id, ban.reason or "N/A"), 1)
            return true, ban.reason or "No reason specified"
        end
    end
    -- No matching ban found in the cache.
    return false, nil
end

--[[
    Stores a new ban record in the database using an asynchronous query.
    Also forces a reload of the ban cache upon successful insertion.

    @param banData (table): A table containing ban details:
        - name (string): Player's name at the time of ban.
        - license (string): Player's license identifier (required).
        - ip (string | nil): Player's IP address.
        - discord (string | nil): Player's Discord ID.
        - reason (string): Reason for the ban.
        - admin (string, optional): Name of the admin issuing the ban (defaults to "NexusGuard System").
        - durationSeconds (number, optional): Duration of the ban in seconds (0 or nil for permanent).
]]
function Bans.Store(banData)
    local dbConfig = _G.Config and _G.Config.Database
    -- Exit if database is disabled.
    if not dbConfig or not dbConfig.enabled then Log("Bans Info: Attempted to store ban while Database is disabled in config.", 3); return end
    -- Ensure oxmysql is available.
    if not MySQL then Log("^1Bans Error: MySQL object not found. Cannot store ban.^7", 1); return end
    -- Require at least a license identifier to store a meaningful ban.
    if not banData or not banData.license then Log("^1Bans Error: Cannot store ban - requires at least a license identifier.^7", 1); return end

    -- Calculate expiry date if duration is provided. NULL for permanent bans.
    local expireDate = nil
    if banData.durationSeconds and banData.durationSeconds > 0 then
        -- os.date with "!": uses UTC time. Adjust if local server time is desired.
        expireDate = os.date("!%Y-%m-%d %H:%M:%S", os.time() + banData.durationSeconds)
    end

    -- Use pcall to safely execute the asynchronous database query.
    local success, resultPromise = pcall(MySQL.Async.execute,
        -- SQL query to insert the ban record.
        'INSERT INTO nexusguard_bans (name, license, ip, discord, reason, admin, expire_date) VALUES (@name, @license, @ip, @discord, @reason, @admin, @expire_date)',
        -- Parameters for the query.
        {
            ['@name'] = banData.name or "Unknown",
            ['@license'] = banData.license,
            ['@ip'] = banData.ip, -- Assumes IP is already cleaned (no "ip:")
            ['@discord'] = banData.discord,
            ['@reason'] = banData.reason or "No reason provided",
            ['@admin'] = banData.admin or "NexusGuard System",
            ['@expire_date'] = expireDate
        }
    )

    if success and resultPromise then
        -- Handle the promise returned by MySQL.Async.execute
        resultPromise:next(function(insertResult)
            -- Check if the insert was successful (usually indicated by affectedRows > 0).
            if insertResult and insertResult.affectedRows and insertResult.affectedRows > 0 then
                 Log(("Bans: Ban for %s (License: %s) stored successfully in database.^7"):format(banData.name or "Unknown", banData.license), 2)
                 Bans.LoadList(true) -- Force reload the ban cache immediately after storing a new ban.
            else
                 Log(("^1Bans Warning: Storing ban for %s reported 0 affected rows. Ban might not have been inserted.^7"):format(banData.name or "Unknown"), 1)
            end
        end, function(err)
            -- Handle errors during the asynchronous query execution.
            Log(string.format("^1Bans Error: Failed to execute ban storage query for %s: %s^7", banData.name or "Unknown", tostring(err)), 1)
        end)
    elseif not success then
        -- Handle errors if the pcall to MySQL.Async.execute itself failed. 'resultPromise' contains the error here.
        Log(string.format("^1Bans Error: Failed to initiate ban storage query for %s: %s^7", banData.name or "Unknown", tostring(resultPromise)), 1)
    end
end

--[[
    Executes the full ban process on a player:
    1. Gathers player identifiers.
    2. Stores the ban record in the database via `Bans.Store`.
    3. Drops the player from the server with a ban message.
    4. Logs the ban action to console and potentially Discord.

    @param playerId (number): The server ID of the player to ban.
    @param reason (string, optional): The reason for the ban (defaults to "Banned by NexusGuard").
    @param adminName (string, optional): The name of the admin issuing the ban (defaults to "NexusGuard System").
    @param durationSeconds (number, optional): Duration of the ban in seconds (0 or nil for permanent).
]]
function Bans.Execute(playerId, reason, adminName, durationSeconds)
    local source = tonumber(playerId)
    -- Validate player ID.
    if not source or source <= 0 then Log("^1Bans Error: Invalid player ID provided to Execute: " .. tostring(playerId) .. "^7", 1); return end
    local playerName = GetPlayerName(source)
    -- Ensure player is actually online.
    if not playerName then Log(("^1Bans Error: Cannot execute ban on player ID %d - Player not found online.^7"):format(source), 1); return end

    -- Get player identifiers. License is crucial for effective bans.
    local license = GetPlayerIdentifierByType(source, 'license')
    local ipRaw = GetPlayerEndpoint(source) -- Gets "ip:xxx.xxx.xxx.xxx"
    local discordId = GetPlayerIdentifierByType(source, 'discord')
    if not license then Log(("^1Bans Warning: Could not get license identifier for player %s (ID: %d). Ban might be less effective.^7"):format(playerName, source), 1) end

    -- Prepare data for storing the ban record. Clean the IP address.
    local banData = {
        name = playerName,
        license = license,
        ip = ipRaw and string.gsub(ipRaw, "ip:", "") or nil, -- Remove "ip:" prefix
        discord = discordId,
        reason = reason or "Banned by NexusGuard",
        admin = adminName or "NexusGuard System",
        durationSeconds = durationSeconds
    }
    -- Store the ban record asynchronously.
    Bans.Store(banData)

    -- Construct the ban message shown to the player.
    local banMessage = (_G.Config and _G.Config.BanMessage) or "You have been banned from this server."
    if durationSeconds and durationSeconds > 0 then
        banMessage = banMessage .. " Duration: " .. FormatDuration(durationSeconds) -- Add duration if temporary.
    end
    -- Drop the player from the server with the ban message.
    DropPlayer(source, banMessage)
    -- Log the ban action to the server console.
    Log(("^1Bans: Executed ban on player: %s (ID: %d). Reason: %s. Duration: %s^7"):format(playerName, source, banData.reason, FormatDuration(durationSeconds)), 1)

    -- Send Discord notification if configured.
    -- Access the Discord module via the global API table (assuming it's populated in globals.lua).
    local Discord = _G.NexusGuardServer and _G.NexusGuardServer.Discord
    if Discord and Discord.Send then
        local discordMsg = string.format(
            "**Player Banned**\n**Name:** %s (`%d`)\n**License:** `%s`\n**IP:** `%s`\n**Discord:** `%s`\n**Reason:** %s\n**Admin:** %s",
            playerName, source, license or "N/A", banData.ip or "N/A", discordId or "N/A", banData.reason, banData.admin
        )
        if durationSeconds and durationSeconds > 0 then
            discordMsg = discordMsg .. "\n**Duration:** " .. FormatDuration(durationSeconds)
        else
            discordMsg = discordMsg .. "\n**Duration:** Permanent"
        end
        -- Get the specific webhook URL for bans from config.
        local webhook = (_G.Config and _G.Config.Discord and _G.Config.Discord.webhooks and _G.Config.Discord.webhooks.bans)
        Discord.Send("Bans", "Player Banned", discordMsg, webhook) -- Use category "Bans" and the message.
    end
end

--[[
    Removes bans associated with a specific identifier (license, IP, or Discord) from the database.
    Uses an asynchronous query. The immediate return value only indicates if the process started.

    @param identifierType (string): The type of identifier ("license", "ip", or "discord").
    @param identifierValue (string): The value of the identifier to unban.
    @param adminName (string, optional): Name of the admin performing the unban (for logging).
    @return (boolean, string): Returns `true` and a confirmation message that the process started,
                               or `false` and an error message if input validation fails or DB is unavailable.
                               Does *not* reflect the actual success of the database operation itself due to async nature.
]]
function Bans.Unban(identifierType, identifierValue, adminName)
    local dbConfig = _G.Config and _G.Config.Database
    -- Check prerequisites.
    if not dbConfig or not dbConfig.enabled then return false, "Database is disabled in config." end
    if not MySQL then Log("^1Bans Error: MySQL object not found. Cannot unban.^7", 1); return false, "Database connection error (oxmysql not found)." end
    if not identifierType or not identifierValue then return false, "Identifier type and value are required." end

    -- Validate and normalize the identifier type.
    local fieldName = string.lower(identifierType)
    if fieldName ~= "license" and fieldName ~= "ip" and fieldName ~= "discord" then
        return false, "Invalid identifier type specified. Use 'license', 'ip', or 'discord'."
    end

    Log(("Bans: Admin '%s' initiating unban for identifier type '%s' with value '%s'..."):format(adminName or "System", fieldName, identifierValue), 2)

    -- Use MySQL.Async.execute for the DELETE operation. This returns a promise.
    local promise = MySQL.Async.execute(
        -- Construct query dynamically based on fieldName (ensure fieldName is validated to prevent SQL injection).
        'DELETE FROM nexusguard_bans WHERE ' .. fieldName .. ' = @identifier',
        { ['@identifier'] = identifierValue }
    )

    -- Handle the promise result asynchronously using :next().
    promise:next(function(result)
        -- This code runs *after* the database query completes.
        if result and result.affectedRows and result.affectedRows > 0 then
            Log(("Bans: Successfully unbanned identifier '%s' = '%s'. Rows affected: %d. Initiated by: %s^7"):format(fieldName, identifierValue, result.affectedRows, adminName or "System"), 2)
            Bans.LoadList(true) -- Force reload the ban cache after successful unban.
            -- Optionally notify Discord.
            local Discord = _G.NexusGuardServer and _G.NexusGuardServer.Discord
            if Discord and Discord.Send then
                local webhook = (_G.Config and _G.Config.Discord and _G.Config.Discord.webhooks and _G.Config.Discord.webhooks.bans)
                Discord.Send("Bans", "Identifier Unbanned",
                    ("Identifier **%s:** `%s` was unbanned by **%s**."):format(fieldName, identifierValue, adminName or "System"),
                    webhook)
            end
        elseif result and result.affectedRows == 0 then
            -- Log if no matching ban was found to delete.
            Log(("Bans: Unban attempt for identifier '%s' = '%s' found no matching active ban to remove.^7"):format(fieldName, identifierValue), 2)
        else
            -- Log if the query executed but reported an issue (e.g., 0 affected rows unexpectedly, or other DB info).
            -- Safely encode the result for logging, falling back to tostring on error.
            local successEncode, resultStr = pcall(function() return lib and lib.json and lib.json.encode(result) end)
            if not successEncode or not resultStr then resultStr = tostring(result) end
            -- Drastically simplified log call for diagnostics
            Log("Bans Warning: Unban operation reported unusual result.")
        end
    end, function(err)
        -- This code runs if the database query itself fails.
        Log(("^1Bans Error: Failed to execute unban query for identifier '%s' = '%s'. Error: %s^7"):format(fieldName, identifierValue, tostring(err)), 1)
    end)

    -- IMPORTANT: Because the database operation is asynchronous, this function returns immediately
    -- after *starting* the operation. The return value only confirms the command was received and initiated.
    -- Feedback about the actual success/failure happens later in the promise callback (logged to console/Discord).
    return true, "Unban process initiated. Check server console or Discord for confirmation."
end

-- Export the Bans table containing the functions.
return Bans
