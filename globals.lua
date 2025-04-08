--[[
    NexusGuard Globals & Server-Side Helpers (Refactored)
    Contains shared functions and placeholder implementations, organized into modules.
]]

-- Ensure JSON library is available (e.g., from oxmysql or another resource)
local json = _G.json -- Use _G.json consistently

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
    -- Utils = {}, -- Moved to sv_utils.lua
    -- Permissions = {}, -- Moved to sv_permissions.lua
    -- Bans = {}, -- Moved to sv_bans.lua
    Security = {},
    Detections = {},
    Database = {},
    Discord = {},
    EventHandlers = {},
    OnlineAdmins = {} -- Moved OnlineAdmins into the API table
}

-- Load required modules
local Utils = require('server/sv_utils') -- Load the new utils module
local Permissions = require('server/sv_permissions') -- Load the new permissions module
local Security = require('server/sv_security') -- Load the new security module
local Bans = require('server/sv_bans') -- Load the new bans module
local Log = Utils.Log -- Keep local alias for convenience
local FormatDuration = Utils.FormatDuration -- Keep local alias for convenience

-- Assign loaded modules to the main table if needed elsewhere (or just use the local variables)
NexusGuardServer.Permissions = Permissions -- Assign the loaded module
NexusGuardServer.Security = Security -- Assign the loaded module
NexusGuardServer.Bans = Bans -- Assign the loaded module

-- Attempt to load framework objects (This logic is now handled in sv_permissions.lua)
-- Citizen.CreateThread(function()
--     Citizen.Wait(1000)
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
-- ## Database Module ##
-- #############################################################################
NexusGuardServer.Database = {}

function NexusGuardServer.Database.Initialize()
    if not NexusGuardServer.Config or not NexusGuardServer.Config.Database or not NexusGuardServer.Config.Database.enabled then
        Utils.Log("Database integration disabled in config.", 2) -- Use Utils.Log
        return
    end
    if not MySQL then
        Utils.Log("^1Error: MySQL object not found. Ensure oxmysql is started before NexusGuard.^7", 1) -- Use Utils.Log
        return
    end

    Utils.Log("Initializing database schema...", 2) -- Use Utils.Log
    local successLoad, schemaFile = pcall(LoadResourceFile, GetCurrentResourceName(), "sql/schema.sql")
    if not successLoad or not schemaFile then
        Utils.Log("^1Error: Could not load sql/schema.sql file. Error: " .. tostring(schemaFile) .. "^7", 1) -- Use Utils.Log
        return
    end

    local statements = {}
    for stmt in string.gmatch(schemaFile, "([^;]+)") do
        stmt = string.gsub(stmt, "^%s+", ""):gsub("%s+$", "")
        if string.len(stmt) > 0 then table.insert(statements, stmt) end
    end

    local function executeNext(index)
        if index > #statements then
            Utils.Log("Database schema check/creation complete.", 2) -- Use Utils.Log
            Bans.LoadList(true) -- Force load ban list after schema setup (Use local Bans)
            return
        end
        executeNext(index + 1)
    end
    executeNext(1)
end

function NexusGuardServer.Database.CleanupDetectionHistory()
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled or not dbConfig.historyDuration or dbConfig.historyDuration <= 0 then return end
    if not MySQL then Utils.Log("^1Error: MySQL object not found. Cannot cleanup detection history.^7", 1); return end -- Use Utils.Log

    local historyDays = dbConfig.historyDuration
    Utils.Log("Cleaning up detection history older than " .. historyDays .. " days...", 2) -- Use Utils.Log
    local success, result = pcall(MySQL.Async.execute,
        'DELETE FROM nexusguard_detections WHERE timestamp < DATE_SUB(NOW(), INTERVAL @days DAY)',
        { ['@days'] = historyDays }
    )
    if success then
        if result and result > 0 then Utils.Log("Cleaned up " .. result .. " old detection records.", 2) end -- Use Utils.Log
    else
        Utils.Log(string.format("^1Error cleaning up detection history: %s^7", tostring(result)), 1) -- Use Utils.Log
    end
end

-- Function to save player session metrics to the database
-- @param playerId number: The server ID of the player whose metrics should be saved.
-- @param metrics table: The metrics data table for the player session.
function NexusGuardServer.Database.SavePlayerMetrics(playerId, metrics) -- Added metrics parameter
    local source = tonumber(playerId)
    if not source or source <= 0 then Utils.Log("^1Error: Invalid player ID provided to SavePlayerMetrics: " .. tostring(playerId) .. "^7", 1); return end -- Use Utils.Log
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled then return end
    -- local metrics = NexusGuardServer.PlayerMetrics and NexusGuardServer.PlayerMetrics[source] -- REMOVED: Using passed parameter
    if not metrics then Utils.Log("^1Warning: Metrics data not provided for player " .. source .. " on disconnect. Cannot save session.^7", 1); return end -- Use Utils.Log
    if not MySQL then Utils.Log("^1Error: MySQL object not found. Cannot save session metrics for player " .. source .. ".^7", 1); return end -- Use Utils.Log

    local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")
    local license = GetPlayerIdentifierByType(source, 'license')
    if not license then Utils.Log("^1Warning: Cannot save metrics for player " .. source .. " without license identifier. Skipping save.^7", 1); return end -- Use Utils.Log

    local connectTime = metrics.connectTime or os.time()
    local playTime = math.max(0, os.time() - connectTime)
    local finalTrustScore = metrics.trustScore or 100.0
    local totalDetections = #(metrics.detections or {})
    local totalWarnings = metrics.warningCount or 0

    Utils.Log("Saving session metrics for player " .. playerId .. " (" .. playerName .. ")", 3) -- Use Utils.Log
    local success, result = pcall(MySQL.Async.execute,
        'INSERT INTO nexusguard_sessions (player_name, player_license, connect_time, play_time_seconds, final_trust_score, total_detections, total_warnings) VALUES (@name, @license, FROM_UNIXTIME(@connect), @playtime, @trust, @detections, @warnings)',
        {
            ['@name'] = playerName, ['@license'] = license, ['@connect'] = connectTime,
            ['@playtime'] = playTime, ['@trust'] = finalTrustScore,
            ['@detections'] = totalDetections, ['@warnings'] = totalWarnings
        }
    )
    if success then
        if not result or result <= 0 then Utils.Log("^1Warning: Saving session metrics for player " .. source .. " reported 0 affected rows.^7", 1) end -- Use Utils.Log
    else
        Utils.Log(string.format("^1Error saving session metrics for player %s: %s^7", source, tostring(result)), 1) -- Use Utils.Log
    end
end

-- #############################################################################
-- ## Bans Module ##
-- #############################################################################
NexusGuardServer.Bans = {}

function NexusGuardServer.Bans.LoadList(forceReload)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled then return end
    if not MySQL then return end

    local currentTime = os.time()
    if not forceReload and NexusGuardServer.BanCacheExpiry > currentTime then return end

    Utils.Log("Loading ban list from database...", 2) -- Use Utils.Log
    local success, bans = pcall(MySQL.Async.fetchAll, 'SELECT * FROM nexusguard_bans WHERE expire_date IS NULL OR expire_date > NOW()', {})
    if success and type(bans) == "table" then
        NexusGuardServer.BanCache = bans
        NexusGuardServer.BanCacheExpiry = currentTime + NexusGuardServer.BanCacheDuration
        Utils.Log("Loaded " .. #NexusGuardServer.BanCache .. " active bans from database.", 2) -- Use Utils.Log
    elseif not success then
        Utils.Log(string.format("^1Error loading bans from database: %s^7", tostring(bans)), 1) -- Use Utils.Log
        NexusGuardServer.BanCache = {}
        NexusGuardServer.BanCacheExpiry = 0
    else
        Utils.Log("^1Warning: Received unexpected result while loading bans from database.^7", 1) -- Use Utils.Log
        NexusGuardServer.BanCache = {}
        NexusGuardServer.BanCacheExpiry = 0
    end
end

function NexusGuardServer.Bans.IsPlayerBanned(license, ip, discordId)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if dbConfig and dbConfig.enabled and NexusGuardServer.BanCacheExpiry <= os.time() then
        NexusGuardServer.Bans.LoadList(false)
    end
    for _, ban in ipairs(NexusGuardServer.BanCache) do
        local identifiersMatch = false
        if license and ban.license and ban.license == license then identifiersMatch = true end
        if ip and ban.ip and ban.ip == ip then identifiersMatch = true end
        if discordId and ban.discord and ban.discord == discordId then identifiersMatch = true end
        if identifiersMatch then return true, ban.reason or "No reason specified" end
    end
    return false, nil
end

function NexusGuardServer.Bans.Store(banData)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled then Utils.Log("Attempted to store ban while Database is disabled.", 3); return end -- Use Utils.Log
    if not MySQL then Utils.Log("^1Error: MySQL object not found. Cannot store ban.^7", 1); return end -- Use Utils.Log
    if not banData or not banData.license then Utils.Log("^1Error: Cannot store ban without player license identifier.^7", 1); return end -- Use Utils.Log

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
             Utils.Log("Ban for " .. banData.name .. " stored in database.", 2) -- Use Utils.Log
             NexusGuardServer.Bans.LoadList(true) -- Force reload ban cache
        else
             Utils.Log("^1Warning: Storing ban for " .. banData.name .. " reported 0 affected rows.^7", 1) -- Use Utils.Log
        end
    else
        Utils.Log(string.format("^1Error storing ban for %s in database: %s^7", banData.name, tostring(result)), 1) -- Use Utils.Log
    end
end

function NexusGuardServer.Bans.Execute(playerId, reason, adminName, durationSeconds)
    local source = tonumber(playerId)
    if not source or source <= 0 then Utils.Log("^1Error: Invalid player ID provided to BanPlayer: " .. tostring(playerId) .. "^7", 1); return end -- Use Utils.Log
    local playerName = GetPlayerName(source)
    if not playerName then Utils.Log("^1Error: Cannot ban player ID: " .. source .. " - Player not found.^7", 1); return end -- Use Utils.Log

    local license = GetPlayerIdentifierByType(source, 'license')
    local ip = GetPlayerEndpoint(source)
    local discord = GetPlayerIdentifierByType(source, 'discord')
    if not license then Utils.Log("^1Warning: Could not get license identifier for player " .. source .. ". Ban might be less effective.^7", 1) end -- Use Utils.Log

    local banData = {
        name = playerName, license = license, ip = ip and string.gsub(ip, "ip:", "") or nil,
        discord = discord, reason = reason or "Banned by NexusGuard",
        admin = adminName or "NexusGuard System", durationSeconds = durationSeconds
    }
    NexusGuardServer.Bans.Store(banData)

    local banMessage = NexusGuardServer.Config.BanMessage or "You have been banned."
    if durationSeconds and durationSeconds > 0 then
        banMessage = banMessage .. " Duration: " .. Utils.FormatDuration(durationSeconds) -- Use Utils.FormatDuration
    end
    DropPlayer(source, banMessage)
    Utils.Log("^1Banned player: " .. playerName .. " (ID: " .. source .. ") Reason: " .. banData.reason .. "^7", 1) -- Use Utils.Log

    if NexusGuardServer.Discord.Send then
        local discordMsg = string.format(
            "**Player Banned**\n**Name:** %s\n**License:** %s\n**IP:** %s\n**Discord:** %s\n**Reason:** %s\n**Admin:** %s",
            playerName, license or "N/A", banData.ip or "N/A", discord or "N/A", banData.reason, banData.admin
        )
        if durationSeconds and durationSeconds > 0 then discordMsg = discordMsg .. "\n**Duration:** " .. Utils.FormatDuration(durationSeconds) end -- Use Utils.FormatDuration
        NexusGuardServer.Discord.Send("Bans", discordMsg, NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.bans)
    end
end

-- Unbans a player based on identifier
-- @param identifierType String: "license", "ip", or "discord"
-- @param identifierValue String: The actual identifier value
-- @param adminName String: Name of the admin performing the unban
-- @return boolean, string: True if successful, false + error message otherwise
function NexusGuardServer.Bans.Unban(identifierType, identifierValue, adminName)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled then return false, "Database is disabled." end
    if not MySQL then Utils.Log("^1Error: MySQL object not found. Cannot unban.^7", 1); return false, "Database connection error." end -- Use Utils.Log
    if not identifierType or not identifierValue then return false, "Identifier type and value required." end

    local fieldName = string.lower(identifierType)
    if fieldName ~= "license" and fieldName ~= "ip" and fieldName ~= "discord" then
        return false, "Invalid identifier type. Use 'license', 'ip', or 'discord'."
    end

    Utils.Log("Attempting to unban identifier: " .. fieldName .. "=" .. identifierValue .. " by " .. (adminName or "System"), 2) -- Use Utils.Log

    -- Use async execute for the DELETE operation
    local promise = MySQL.Async.execute(
        'DELETE FROM nexusguard_bans WHERE ' .. fieldName .. ' = @identifier',
        { ['@identifier'] = identifierValue }
    )

    -- Handle the promise result (this part runs asynchronously)
    promise:next(function(result)
        if result and result.affectedRows and result.affectedRows > 0 then
            Utils.Log("Successfully unbanned identifier: " .. fieldName .. "=" .. identifierValue .. ". Rows affected: " .. result.affectedRows, 2) -- Use Utils.Log
            NexusGuardServer.Bans.LoadList(true) -- Force reload cache
            -- Optionally notify admin/discord
            if NexusGuardServer.Discord.Send then
                NexusGuardServer.Discord.Send("Bans", "Identifier Unbanned",
                    "Identifier **" .. fieldName .. ":** `" .. identifierValue .. "` was unbanned by **" .. (adminName or "System") .. "**.",
                    NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.bans)
            end
            -- How to notify the command source? This requires a callback or different structure.
            -- For now, success is logged server-side. Command feedback needs adjustment.
        elseif result and result.affectedRows == 0 then
            Utils.Log("Unban attempt for identifier: " .. fieldName .. "=" .. identifierValue .. " found no matching active ban.", 2) -- Use Utils.Log
            -- Notify admin?
        else
            Utils.Log("^1Error during unban operation for identifier: " .. fieldName .. "=" .. identifierValue .. ". Result: " .. json.encode(result), 1) -- Use Utils.Log
            -- Notify admin?
        end
    end, function(err)
        Utils.Log("^1Error executing unban query for identifier: " .. fieldName .. "=" .. identifierValue .. ". Error: " .. tostring(err), 1) -- Use Utils.Log
        -- Notify admin?
    end)

    -- NOTE: Because this uses MySQL.Async, the command handler cannot directly return true/false based on DB result.
    -- It can only confirm the command was received and the async operation started.
    -- Feedback to the admin in chat will be immediate, not reflecting DB success.
    return true, "Unban process initiated. Check server console for details."
end


-- #############################################################################
-- ## Permissions Module (Moved to sv_permissions.lua) ##
-- #############################################################################
-- The IsAdmin function and its logic have been moved to server/sv_permissions.lua

-- #############################################################################
-- ## Security Module (Moved to sv_security.lua) ##
-- #############################################################################
-- NexusGuardServer.Security = { ... } -- Definition moved
-- function NexusGuardServer.Security.GenerateToken(playerId) ... end -- Function moved
-- function NexusGuardServer.Security.ValidateToken(playerId, tokenData) ... end -- Function moved
-- function NexusGuardServer.Security.CleanupTokenCache() ... end -- Function moved

-- #############################################################################
-- ## Detections Module ##
-- #############################################################################
NexusGuardServer.Detections = {}

-- Function to store detection events in the database (Guideline 36)
-- @param playerId number: The server ID of the player.
-- @param detectionType string: The type of detection (e.g., "ServerSpeedCheck").
-- @param detectionData table: A table containing details about the detection.
function NexusGuardServer.Detections.Store(playerId, detectionType, detectionData)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    -- Exit if database or history storage is disabled
    if not dbConfig or not dbConfig.enabled or not dbConfig.storeDetectionHistory then return end
    if not MySQL then Log("^1Error: MySQL object not found. Cannot store detection.^7", 1); return end
    if not json then Log("^1Error: JSON library not found. Cannot encode detection data for storage.^7", 1); return end

    local source = tonumber(playerId)
    if not source or source <= 0 then Log("^1Error: Invalid player ID provided to StoreDetection: " .. tostring(playerId) .. "^7", 1); return end

    local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")
    local license = GetPlayerIdentifierByType(source, 'license')
    if not license then Log("^1Warning: Cannot store detection for player " .. source .. " without license identifier. Skipping save.^7", 1); return end

    -- Ensure detectionData is a table before encoding
    if type(detectionData) ~= "table" then
        Log("^1Warning: detectionData provided to StoreDetection was not a table for type '" .. detectionType .. "'. Storing as string.^7", 1)
        detectionData = { raw = tostring(detectionData) } -- Wrap non-table data
    end

    -- Safely encode the detection data table to JSON
    local dataJson = "null" -- Default to SQL NULL if encoding fails
    local encodeSuccess, encoded = pcall(json.encode, detectionData)
    if encodeSuccess and type(encoded) == "string" then
        dataJson = encoded
    else
        Log("^1Error encoding detectionData to JSON for type '" .. detectionType .. "': " .. tostring(encoded) .. "^7", 1)
        -- Optionally try encoding with error handling/replacement characters if needed
    end

    -- Log("Storing detection: " .. playerName .. " - " .. detectionType .. " - Data: " .. dataJson, 3) -- Debug log

    -- Execute async insert query
    local success, result = pcall(MySQL.Async.execute,
        'INSERT INTO nexusguard_detections (player_name, player_license, detection_type, detection_data, timestamp) VALUES (@name, @license, @type, @data, NOW())',
        {
            ['@name'] = playerName,
            ['@license'] = license,
            ['@type'] = detectionType,
            ['@data'] = dataJson -- Store the JSON string
        }
    )

    if success then
        if not result or result <= 0 then Log("^1Warning: Storing detection for player " .. source .. " reported 0 affected rows.^7", 1) end
    else
        Log(string.format("^1Error storing detection for player %s (Type: %s): %s^7", source, detectionType, tostring(result)), 1)
    end
end

-- Gets the severity score for a detection type based on Config.SeverityScores (Guideline 43)
-- @param detectionType string: The type of detection.
-- @return number: The severity score for the detection type.
function NexusGuardServer.Detections.GetSeverity(detectionType)
    local severityScores = NexusGuardServer.Config and NexusGuardServer.Config.SeverityScores
    if not severityScores then
        Log("^1Warning: Config.SeverityScores not found. Using default severity 5.^7", 1)
        return 5 -- Return a default if config is missing
    end

    -- Return the score for the specific type, or the default score if not found
    return severityScores[detectionType] or severityScores.default or 5 -- Added extra fallback
end

-- Determines if a detection is considered a confirmed cheat (Guideline 42)
-- @param detectionType string: The type of detection.
-- @param detectionData table: The data associated with the detection.
-- @return boolean: True if considered confirmed, false otherwise.
function NexusGuardServer.Detections.IsConfirmedCheat(detectionType, detectionData)
    -- Primary confirmation: Server-side validation succeeded
    if type(detectionData) == "table" and detectionData.serverValidated then
        return true
    end

    -- Add other detection types that are considered confirmed even without specific server validation
    local confirmedTypes = {
        BlacklistedExplosion = true, -- Blacklisted explosions are always confirmed
        ResourceMismatch = true,     -- Resource mismatches are generally confirmed violations
        -- Add other types here if they are deemed high-confidence client-side detections
        -- e.g., certain menu key combos if you trust them, specific native abuse patterns if implemented
    }
    if confirmedTypes[detectionType] then
        return true
    end

    -- Default to not confirmed
    return false
end

-- Determines if a detection poses a high risk, warranting immediate action like a kick (Guideline 42)
-- @param detectionType string: The type of detection.
-- @param detectionData table: The data associated with the detection.
-- @return boolean: True if considered high risk, false otherwise.
function NexusGuardServer.Detections.IsHighRisk(detectionType, detectionData)
    -- Server-validated detections are generally high risk
    if type(detectionData) == "table" and detectionData.serverValidated then
        return true
    end

    -- Specific detection types considered high risk even without server validation
    local highRiskTypes = {
        ServerSpeedCheck = true, -- Even if client-reported, high speed is risky
        BlacklistedExplosion = true,
        ResourceMismatch = true,
        -- Add other types considered inherently high risk
        -- e.g., noclip (if client-side reporting were re-enabled and trusted)
    }
    if highRiskTypes[detectionType] then
        return true
    end

    -- Detections with high severity scores are also high risk
    if NexusGuardServer.Detections.GetSeverity(detectionType) >= 15 then -- Use >= for threshold
        return true
    end

    -- Default to not high risk
    return false
end

-- Removed IsAdmin function body as it's now in sv_permissions.lua

-- Guideline: Implement ValidateWeaponDamage
function NexusGuardServer.Detections.ValidateWeaponDamage(playerId, weaponHash, reportedDamage, targetEntity)
    local baseDamage = NexusGuardServer.Config.WeaponBaseDamage and NexusGuardServer.Config.WeaponBaseDamage[weaponHash]
    if not baseDamage then
        -- Utils.Log("ValidateWeaponDamage: No base damage configured for weapon hash: " .. weaponHash, 3) -- Use Utils.Log (Optional Debug)
        return false, "No base damage configured" -- Cannot validate if base damage is unknown
    end

    -- Basic validation: Check if reported damage significantly exceeds base damage + reasonable multiplier
    -- TODO: Add more sophisticated checks (headshots, distance falloff, target type modifiers, buffs/debuffs)
    local damageMultiplierThreshold = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.weaponDamageMultiplier) or 1.5
    local maxAllowedDamage = baseDamage * damageMultiplierThreshold

    if reportedDamage > maxAllowedDamage then
        Utils.Log(string.format("^1[NexusGuard Server Check]^7 Player %d reported excessive damage (%s) for weapon %s. Base: %s, Max Allowed: %s^7", -- Use Utils.Log
            playerId, reportedDamage, weaponHash, baseDamage, maxAllowedDamage), 1)
        return true, string.format("Reported damage %.2f exceeds max allowed %.2f (Base: %.2f)", reportedDamage, maxAllowedDamage, baseDamage) -- Return true (suspicious) and reason
    end

    -- Utils.Log(string.format("ValidateWeaponDamage: Player %d damage %s for weapon %s within threshold %s (Base: %s)", -- Use Utils.Log (Optional Debug)
    --     playerId, reportedDamage, weaponHash, maxAllowedDamage, baseDamage), 4) -- Debugging only
    return false, "Damage within threshold" -- Return false (not suspicious) and reason
end

function NexusGuardServer.Detections.ValidateVehicleHealth(detectionData)
    -- Dedicated validation logic for vehicle health
    -- ...new logic...
end

-- Accepts the player's session data as the fourth argument
function NexusGuardServer.Detections.Process(playerId, detectionType, detectionData, session)
    if not playerId or playerId <= 0 or not detectionType then Utils.Log("^1[NexusGuard] Invalid arguments received by ProcessDetection.^7", 1); return end -- Use Utils.Log
    local playerName = GetPlayerName(playerId) or ("Unknown (" .. playerId .. ")")
    local cfg = NexusGuardServer.Config
    -- Use metrics from the passed session object
    local metrics = session and session.metrics

    local dataStrForLog = (json and json.encode(detectionData)) or (type(detectionData) == "string" and detectionData or "{}")
    Utils.Log('^1[NexusGuard]^7 Detection: ' .. playerName .. ' (ID: '..playerId..') - Type: ' .. detectionType .. ' - Data: ' .. dataStrForLog .. "^7", 1) -- Use Utils.Log

    local serverValidated = false
    -- --- Server-Side Validation Checks ---
    if detectionType == "weaponDamage" and type(detectionData) == "table" then
        local isSuspicious, reason = NexusGuardServer.Detections.ValidateWeaponDamage(playerId, detectionData.weaponHash, detectionData.damage, detectionData.targetEntity)
        if isSuspicious then
            serverValidated = true -- Mark as server-validated if validation fails
            detectionData.serverValidationReason = reason -- Add reason to data
            Utils.Log("^1[NexusGuard ProcessDetection]^7 Server validation failed for weaponDamage: " .. reason .. "^7", 1) -- Use Utils.Log
        end
    -- elseif detectionType == "vehicleHealth" then -- Placeholder for future vehicle health validation
    --     NexusGuardServer.Detections.ValidateVehicleHealth(detectionData)
    end

    -- Store detection (pass potentially modified detectionData)
    -- Ensure Store function exists before calling
    if NexusGuardServer.Detections.Store then
        NexusGuardServer.Detections.Store(playerId, detectionType, detectionData)
    else
        Utils.Log("^1[NexusGuard] CRITICAL: StoreDetection function is missing! Cannot save detection history.^7", 1) -- Use Utils.Log
    end

    -- Update metrics
    if metrics then
        if not metrics.detections then metrics.detections = {} end
        table.insert(metrics.detections, { type = detectionType, data = detectionData, timestamp = os.time(), serverValidated = serverValidated })
        local severityImpact = NexusGuardServer.Detections.GetSeverity(detectionType)
        if serverValidated then severityImpact = severityImpact * 1.5 end
        metrics.trustScore = math.max(0, (metrics.trustScore or 100) - severityImpact)
        Utils.Log('^3[NexusGuard]^7 Player ' .. playerName .. ' trust score updated to: ' .. string.format("%.2f", metrics.trustScore) .. "^7", 2) -- Use Utils.Log
    else Utils.Log("^1Warning: PlayerMetrics not found for player " .. playerId .. " during detection processing.^7", 1) end -- Use Utils.Log

    -- Rule-based Actions (Guideline 44: Progressive Response Logic)
    if cfg.Actions then
        -- Ensure helper functions exist before calling
        local confirmed = serverValidated or (NexusGuardServer.Detections.IsConfirmedCheat and NexusGuardServer.Detections.IsConfirmedCheat(detectionType, detectionData)) or false
        local highRisk = (NexusGuardServer.Detections.IsHighRisk and NexusGuardServer.Detections.IsHighRisk(detectionType, detectionData)) or false
        local takeAction = false -- Flag to prevent duplicate actions

        if confirmed then
            -- Increment confirmed cheat count for progressive response
            if metrics then
                metrics.confirmedCheatCount = (metrics.confirmedCheatCount or 0) + 1
                Utils.Log('^3[NexusGuard]^7 Player ' .. playerName .. ' confirmed cheat count: ' .. metrics.confirmedCheatCount .. "^7", 2) -- Use Utils.Log
            end

            -- Check for progressive ban first if enabled
            if cfg.Actions.progressiveResponse and metrics and metrics.confirmedCheatCount > (cfg.Actions.warningThreshold or 2) then
                local banReason = "Progressive Ban Threshold Reached (" .. metrics.confirmedCheatCount .. " confirmed detections)"
                Utils.Log("^1[NexusGuard] Progressive Ban Triggered for " .. playerName .. "^7", 1) -- Use Utils.Log
                NexusGuardServer.Bans.Execute(playerId, banReason)
                takeAction = true
            -- Otherwise, check for immediate ban on confirmed cheat if enabled
            elseif cfg.Actions.banOnConfirmed then
                local banReason = (serverValidated and 'Server-confirmed cheat: ' or 'Confirmed cheat: ') .. detectionType
                Utils.Log("^1[NexusGuard] " .. (serverValidated and 'Server-Confirmed' or 'Confirmed') .. " Cheat Ban Triggered for " .. playerName .. "^7", 1) -- Use Utils.Log
                NexusGuardServer.Bans.Execute(playerId, banReason)
                takeAction = true
            -- If not banning progressively or immediately, consider kicking if configured
            elseif cfg.Actions.kickOnSuspicion then -- Treat confirmed but non-banned as high risk for kick
                 Utils.Log("^1[NexusGuard] Confirmed Cheat Kick Triggered for " .. playerName .. " (Below Ban Threshold)^7", 1) -- Use Utils.Log
                 if cfg.ScreenCapture and cfg.ScreenCapture.enabled and cfg.ScreenCapture.includeWithReports and _G.EventRegistry then _G.EventRegistry.TriggerClientEvent('ADMIN_REQUEST_SCREENSHOT', playerId) end
                 DropPlayer(playerId, cfg.KickMessage or "Kicked for suspicious activity.")
                 takeAction = true
            end
        end

        -- If no action taken yet, check for high-risk kick
        if not takeAction and highRisk and cfg.Actions.kickOnSuspicion then
             Utils.Log("^1[NexusGuard] High Risk Kick Triggered for " .. playerName .. "^7", 1) -- Use Utils.Log
             if cfg.ScreenCapture and cfg.ScreenCapture.enabled and cfg.ScreenCapture.includeWithReports and _G.EventRegistry then _G.EventRegistry.TriggerClientEvent('ADMIN_REQUEST_SCREENSHOT', playerId) end
             DropPlayer(playerId, cfg.KickMessage or "Kicked for suspicious activity.")
             takeAction = true
        end

        -- If any action was taken, return to prevent further processing like admin notifications for the same event
        if takeAction then return end

        -- Screenshot logic (only if no kick/ban occurred)
        if cfg.ScreenCapture and cfg.ScreenCapture.enabled and cfg.ScreenCapture.includeWithReports and (highRisk or confirmed) then
             Utils.Log("^2[NexusGuard] Requesting screenshot for high risk/confirmed detection: " .. playerName .. "^7", 2) -- Use Utils.Log
             -- Check EventRegistry existence again, as it might be needed here if not used above
             if _G.EventRegistry then _G.EventRegistry.TriggerClientEvent('ADMIN_REQUEST_SCREENSHOT', playerId)
             else Utils.Log("^1[NexusGuard] CRITICAL: _G.EventRegistry not found. Cannot request screenshot.^7", 1) end -- Use Utils.Log
        end

        if cfg.Actions.reportToAdminsOnSuspicion and NexusGuardServer.EventHandlers.NotifyAdmins then
            local notifyData = detectionData; if type(notifyData) ~= "table" then notifyData = { clientData = notifyData } end
            notifyData.serverValidated = serverValidated
            NexusGuardServer.EventHandlers.NotifyAdmins(playerId, detectionType, notifyData)
        end
    end

    -- Discord Log
    if NexusGuardServer.Discord.Send then
        local discordData = detectionData; if type(discordData) ~= "table" then discordData = { clientData = discordData } end
        discordData.serverValidated = serverValidated
        local dataStr = (json and json.encode(discordData)) or "{}"
        local alertTitle = (serverValidated and 'Server-Confirmed Detection Alert' or 'Detection Alert')
        NexusGuardServer.Discord.Send("general", alertTitle, playerName .. ' (ID: '..playerId..') - Type: ' .. detectionType .. ' - Data: ' .. dataStr, cfg.Discord.webhooks and cfg.Discord.webhooks.general)
    end
end

-- #############################################################################
-- ## Discord Module ##
-- #############################################################################
NexusGuardServer.Discord = {}

function NexusGuardServer.Discord.Send(category, title, message, specificWebhook)
    local discordConfig = NexusGuardServer.Config and NexusGuardServer.Config.Discord
    if not discordConfig or not discordConfig.enabled then return end

    local webhookURL = specificWebhook
    if not webhookURL then
        if discordConfig.webhooks and category and discordConfig.webhooks[category] and discordConfig.webhooks[category] ~= "" then webhookURL = discordConfig.webhooks[category]
        elseif NexusGuardServer.Config.DiscordWebhook and NexusGuardServer.Config.DiscordWebhook ~= "" then webhookURL = NexusGuardServer.Config.DiscordWebhook
        else return end -- No valid webhook URL found
    end

    if not PerformHttpRequest then Utils.Log("^1Error: PerformHttpRequest native not available.^7", 1); return end -- Use Utils.Log
    if not json then Utils.Log("^1Error: JSON library not available for SendToDiscord.^7", 1); return end -- Use Utils.Log

    local embed = {{ ["color"] = 16711680, ["title"] = "**[NexusGuard] " .. (title or "Alert") .. "**", ["description"] = message or "No details provided.", ["footer"] = { ["text"] = "NexusGuard | " .. os.date("%Y-%m-%d %H:%M:%S") } }}
    local payloadSuccess, payload = pcall(json.encode, { embeds = embed })
    if not payloadSuccess then Utils.Log("^1Error encoding Discord payload: " .. tostring(payload) .. "^7", 1); return end -- Use Utils.Log

    local success, err = pcall(PerformHttpRequest, webhookURL, function(errHttp, text, headers)
        if errHttp then Utils.Log("^1Error sending Discord webhook (Callback): " .. tostring(errHttp) .. "^7", 1) else Utils.Log("Discord notification sent: " .. title, 3) end -- Use Utils.Log
    end, 'POST', payload, { ['Content-Type'] = 'application/json' })
    if not success then Utils.Log("^1Error initiating Discord HTTP request: " .. tostring(err) .. "^7", 1) end -- Use Utils.Log
end

-- #############################################################################
-- ## Event Handlers Module (Server-Side Logic) ##
-- #############################################################################
NexusGuardServer.EventHandlers = {}

-- Guideline 33: Refine HandleExplosionEvent
-- Accepts the player's session data as the third argument
function NexusGuardServer.EventHandlers.HandleExplosion(sender, ev, session)
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

    if not ev or ev.explosionType == nil or ev.posX == nil or ev.posY == nil or ev.posZ == nil then Utils.Log("^1Warning: Received incomplete explosionEvent data from " .. source .. "^7", 1); return end -- Use Utils.Log

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
        Utils.Log(string.format("^1[NexusGuard Server Check]^7 Player %s (ID: %d) %s at %s^7", playerName, source, reason, position), 1) -- Use Utils.Log
        -- Process the detection (useful for logging/trust score)
        NexusGuardServer.Detections.Process(source, "BlacklistedExplosion", { type = explosionType, position = position }, session)

        -- Apply immediate action if configured
        if banOnBlacklisted then
            Utils.Log("^1[NexusGuard] Banning player " .. playerName .. " for blacklisted explosion.^7", 1) -- Use Utils.Log
            NexusGuardServer.Bans.Execute(source, reason, "NexusGuard System (Blacklisted Explosion)")
            return -- Stop further processing after ban
        elseif kickOnBlacklisted then
            Utils.Log("^1[NexusGuard] Kicking player " .. playerName .. " for blacklisted explosion.^7", 1) -- Use Utils.Log
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
        Utils.Log(string.format("^1[NexusGuard Server Check]^7 Explosion spam detected for %s (ID: %d). Count: %d in %ds. Count in area (<%sm): %d^7", -- Use Utils.Log
            playerName, source, recentCount, spamTimeWindow, spamDistanceThreshold, spamInAreaCount), 1)
        NexusGuardServer.Detections.Process(source, "ExplosionSpam", {
            count = recentCount,
            period = spamTimeWindow,
            areaCount = spamInAreaCount,
            areaDistance = spamDistanceThreshold,
            lastType = explosionType,
            lastPosition = position
        })
    end
end

function NexusGuardServer.EventHandlers.HandleEntityCreation(entity)
    -- Placeholder - Requires careful implementation and filtering
    -- Utils.Log("Placeholder: HandleEntityCreation called for entity " .. entity, 4) -- Use Utils.Log
end

function NexusGuardServer.EventHandlers.NotifyAdmins(playerId, detectionType, detectionData)
    local playerName = GetPlayerName(playerId) or ("Unknown (" .. playerId .. ")")
    if not json then Utils.Log("^1[NexusGuard] JSON library not available for NotifyAdmins.^7", 1); return end -- Use Utils.Log

    local dataString = "N/A"
    local successEncode, result = pcall(json.encode, detectionData)
    if successEncode then dataString = result else Utils.Log("^1[NexusGuard] Failed to encode detectionData for admin notification.^7", 1) end -- Use Utils.Log

    Utils.Log('^1[NexusGuard]^7 Admin Notify: ' .. playerName .. ' (ID: ' .. playerId .. ') - ' .. detectionType .. ' - Data: ' .. dataString .. "^7", 1) -- Use Utils.Log

    local adminCount = 0; for _ in pairs(NexusGuardServer.OnlineAdmins or {}) do adminCount = adminCount + 1 end -- Use API table
    if adminCount == 0 then Utils.Log("^3[NexusGuard] No admins online to notify.^7", 3); return end -- Use Utils.Log

    for adminId, _ in pairs(NexusGuardServer.OnlineAdmins or {}) do -- Use API table
        if GetPlayerName(adminId) then
             if _G.EventRegistry then -- EventRegistry is still likely global
                 _G.EventRegistry.TriggerClientEvent('ADMIN_NOTIFICATION', adminId, {
                    player = playerName, playerId = playerId, type = detectionType,
                    data = detectionData, timestamp = os.time()
                 })
             else Utils.Log("^1[NexusGuard] CRITICAL: _G.EventRegistry not found. Cannot send admin notification.^7", 1) end -- Use Utils.Log
        else if NexusGuardServer.OnlineAdmins then NexusGuardServer.OnlineAdmins[adminId] = nil end end -- Clean up disconnected admin using API table
    end
end

-- #############################################################################
-- ## Initialization and Exports ##
-- #############################################################################

-- Expose the main server logic table
exports('GetNexusGuardServerAPI', function()
    return NexusGuardServer
end)

Utils.Log("NexusGuard globals refactored and helpers loaded.", 2) -- Use Utils.Log

-- Trigger initial DB load/check after globals are defined
Citizen.CreateThread(function()
    Citizen.Wait(500) -- Short delay to ensure Config is loaded
    NexusGuardServer.Database.Initialize()
end)
