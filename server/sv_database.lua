--[[
    NexusGuard Database Module
    Handles interactions with the database (MySQL).
]]

local Database = {}

-- Get the NexusGuard Server API from globals.lua (needed for Config, Utils, Bans)
-- Use pcall for safety in case globals isn't fully loaded yet when this module is required
local successAPI, NexusGuardServer = pcall(function() return exports['NexusGuard']:GetNexusGuardServerAPI() end)
if not successAPI or not NexusGuardServer then
    print("^1[NexusGuard DB] CRITICAL: Failed to get NexusGuardServer API. Database module may fail.^7")
    -- Create a dummy API structure to prevent errors in functions below if API failed
    NexusGuardServer = NexusGuardServer or { Config = {}, Utils = { Log = function(...) print(...) end }, Bans = {} }
end

-- Local alias for logging
local Log = NexusGuardServer.Utils.Log or function(...) print(...) end -- Fallback logger
-- local json = _G.json -- REMOVED: Use lib.json directly

function Database.Initialize()
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled then
        Log("Database integration disabled in config.", 2)
        return
    end
    if not MySQL then
        Log("^1Error: MySQL object not found. Ensure oxmysql is started before NexusGuard.^7", 1)
        return
    end

    Log("Initializing database schema...", 2)
    local successLoad, schemaFile = pcall(LoadResourceFile, GetCurrentResourceName(), "sql/schema.sql")
    if not successLoad or not schemaFile then
        Log("^1Error: Could not load sql/schema.sql file. Error: " .. tostring(schemaFile) .. "^7", 1)
        return
    end

    local statements = {}
    for stmt in string.gmatch(schemaFile, "([^;]+)") do
        stmt = string.gsub(stmt, "^%s+", ""):gsub("%s+$", "")
        if string.len(stmt) > 0 then table.insert(statements, stmt) end
    end

    -- Execute schema statements sequentially using async/await pattern if available,
    -- or a simple loop with pcall for broader compatibility. Using pcall loop here.
    local errorsOccurred = false
    for i, stmt in ipairs(statements) do
        local success, err = pcall(MySQL.Sync.execute, stmt) -- Use Sync for schema setup simplicity
        if not success then
            -- Ignore "Duplicate column name" or "Duplicate key name" or "Table already exists" errors as they are expected if schema is already present
            if not string.find(tostring(err), "Duplicate column name") and not string.find(tostring(err), "Duplicate key name") and not string.find(tostring(err), "already exists") then
                 Log(string.format("^1Error executing schema statement %d: %s^7", i, tostring(err)), 1)
                 errorsOccurred = true
            end
        end
    end

    if not errorsOccurred then
        Log("Database schema check/creation complete.", 2)
        -- Load ban list after schema setup (Ensure Bans API is available)
        if NexusGuardServer.Bans and NexusGuardServer.Bans.LoadList then
            NexusGuardServer.Bans.LoadList(true) -- Force load ban list after schema setup
        else
            Log("^1Warning: Bans API not available after DB init. Ban list not loaded.^7", 1)
        end
    else
        Log("^1Warning: Errors occurred during database schema setup. Check logs above.^7", 1)
    end
end

function Database.CleanupDetectionHistory()
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled or not dbConfig.historyDuration or dbConfig.historyDuration <= 0 then return end
    if not MySQL then Log("^1Error: MySQL object not found. Cannot cleanup detection history.^7", 1); return end

    local historyDays = dbConfig.historyDuration
    Log("Cleaning up detection history older than " .. historyDays .. " days...", 2)
    local success, result = pcall(MySQL.Async.execute,
        'DELETE FROM nexusguard_detections WHERE timestamp < DATE_SUB(NOW(), INTERVAL @days DAY)',
        { ['@days'] = historyDays }
    )
    if success then
        if result and result.affectedRows and result.affectedRows > 0 then Log("Cleaned up " .. result.affectedRows .. " old detection records.", 2) end
    else
        Log(string.format("^1Error cleaning up detection history: %s^7", tostring(result)), 1)
    end
end

-- Function to save player session metrics to the database
-- @param playerId number: The server ID of the player whose metrics should be saved.
-- @param metrics table: The metrics data table for the player session.
function Database.SavePlayerMetrics(playerId, metrics)
    local source = tonumber(playerId)
    if not source or source <= 0 then Log("^1Error: Invalid player ID provided to SavePlayerMetrics: " .. tostring(playerId) .. "^7", 1); return end
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    if not dbConfig or not dbConfig.enabled then return end
    if not metrics then Log("^1Warning: Metrics data not provided for player " .. source .. " on disconnect. Cannot save session.^7", 1); return end
    if not MySQL then Log("^1Error: MySQL object not found. Cannot save session metrics for player " .. source .. ".^7", 1); return end

    local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")
    local license = GetPlayerIdentifierByType(source, 'license')
    if not license then Log("^1Warning: Cannot save metrics for player " .. source .. " without license identifier. Skipping save.^7", 1); return end

    local connectTime = metrics.connectTime or os.time()
    local playTime = math.max(0, os.time() - connectTime)
    local finalTrustScore = metrics.trustScore or 100.0
    local totalDetections = #(metrics.detections or {})
    local totalWarnings = metrics.warningCount or 0

    Log("Saving session metrics for player " .. playerId .. " (" .. playerName .. ")", 3)
    local success, result = pcall(MySQL.Async.execute,
        'INSERT INTO nexusguard_sessions (player_name, player_license, connect_time, play_time_seconds, final_trust_score, total_detections, total_warnings) VALUES (@name, @license, FROM_UNIXTIME(@connect), @playtime, @trust, @detections, @warnings)',
        {
            ['@name'] = playerName, ['@license'] = license, ['@connect'] = connectTime,
            ['@playtime'] = playTime, ['@trust'] = finalTrustScore,
            ['@detections'] = totalDetections, ['@warnings'] = totalWarnings
        }
    )
    if success then
        if not result or not result.affectedRows or result.affectedRows <= 0 then Log("^1Warning: Saving session metrics for player " .. source .. " reported 0 affected rows.^7", 1) end
    else
        Log(string.format("^1Error saving session metrics for player %s: %s^7", source, tostring(result)), 1)
    end
end

-- Function to store detection events in the database (Moved from Detections module in globals)
-- @param playerId number: The server ID of the player.
-- @param detectionType string: The type of detection (e.g., "ServerSpeedCheck").
-- @param detectionData table: A table containing details about the detection.
function Database.StoreDetection(playerId, detectionType, detectionData)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    -- Exit if database or history storage is disabled
    if not dbConfig or not dbConfig.enabled or not dbConfig.storeDetectionHistory then return end
    if not MySQL then Log("^1Error: MySQL object not found. Cannot store detection.^7", 1); return end
    if not lib.json then Log("^1Error: ox_lib JSON library (lib.json) not found. Cannot encode detection data for storage.^7", 1); return end

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
    local encodeSuccess, encoded = pcall(lib.json.encode, detectionData)
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
        if not result or not result.affectedRows or result.affectedRows <= 0 then Log("^1Warning: Storing detection for player " .. source .. " reported 0 affected rows.^7", 1) end
    else
        Log(string.format("^1Error storing detection for player %s (Type: %s): %s^7", source, detectionType, tostring(result)), 1)
    end
end


return Database
