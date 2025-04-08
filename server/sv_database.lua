--[[
    NexusGuard Database Module (server/sv_database.lua)

    Purpose:
    - Handles all interactions with the MySQL database for NexusGuard.
    - Initializes the database schema defined in `sql/schema.sql`.
    - Stores detection events and player session summaries.
    - Provides functions for cleaning up old detection history.

    Dependencies:
    - `server/sv_utils.lua` (for logging)
    - `oxmysql` resource (provides the global `MySQL` object for database operations)
    - Global `Config` table (for database settings like `enabled`, `historyDuration`)
    - Global `NexusGuardServer` API table (for accessing Config, Utils, Bans)
    - `ox_lib` resource (for `lib.json` used in storing detection data)

    Usage:
    - Required by `globals.lua` and exposed via the `NexusGuardServer.Database` API table.
    - `Initialize` is called once during resource startup (triggered from `globals.lua`).
    - `StoreDetection` is called by the Detections module to log events.
    - `SavePlayerMetrics` is called when a player disconnects to save session summary.
    - `CleanupDetectionHistory` is called periodically by a scheduled task.
]]

local Database = {}

-- Attempt to get the NexusGuard Server API from globals.lua.
-- Use pcall for safety, as load order might cause issues during initial script evaluation.
local successAPI, NexusGuardServer = pcall(function() return exports['NexusGuard']:GetNexusGuardServerAPI() end)
if not successAPI or not NexusGuardServer then
    print("^1[NexusGuard DB] CRITICAL: Failed to get NexusGuardServer API. Database module functionality will be severely limited or fail.^7")
    -- Create a dummy API structure to prevent immediate errors in functions below if the real API failed to load.
    NexusGuardServer = NexusGuardServer or {
        Config = {},
        Utils = { Log = function(...) print("[NexusGuard DB Fallback Log]", ...) end }, -- Basic fallback logger
        Bans = {} -- Dummy Bans table
    }
end

-- Local alias for the logging function from the Utils module (or fallback).
local Log = NexusGuardServer.Utils.Log

--[[
    Initializes the database connection and ensures the required schema exists.
    Reads `sql/schema.sql` and executes the statements.
    Called once during resource startup.
]]
function Database.Initialize()
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    -- Exit if database integration is disabled in the config.
    if not dbConfig or not dbConfig.enabled then
        Log("Database: Integration disabled in config.lua (Config.Database.enabled = false).", 2)
        return
    end
    -- Ensure oxmysql is available.
    if not MySQL then
        Log("^1Database Error: Global MySQL object (from oxmysql) not found. Ensure oxmysql is installed and started before NexusGuard.^7", 1)
        return
    end

    Log("Database: Initializing schema check/creation...", 2)
    -- Load the schema definition file. Use pcall for safety.
    local successLoad, schemaFile = pcall(LoadResourceFile, GetCurrentResourceName(), "sql/schema.sql")
    if not successLoad or not schemaFile then
        Log(("^1Database Error: Could not load sql/schema.sql file. Schema setup aborted. Error: %s^7"):format(tostring(schemaFile)), 1)
        return
    end

    -- Split the schema file into individual SQL statements (separated by ';').
    local statements = {}
    for stmt in string.gmatch(schemaFile, "([^;]+)") do
        stmt = string.gsub(stmt, "^%s+", ""):gsub("%s+$", "") -- Trim whitespace
        if string.len(stmt) > 0 then table.insert(statements, stmt) end
    end

    -- Execute schema statements sequentially. Using MySQL.Sync for simplicity during initialization.
    -- Asynchronous execution here could lead to race conditions if later code depends on tables existing.
    Log(("Database: Executing %d statements from schema.sql..."):format(#statements), 3)
    local errorsOccurred = false
    for i, stmt in ipairs(statements) do
        local success, err = pcall(MySQL.Sync.execute, stmt)
        if not success then
            -- Ignore common errors indicating the schema/alterations already exist.
            local errorString = tostring(err)
            if not string.find(errorString, "Duplicate column name", 1, true) and
               not string.find(errorString, "Duplicate key name", 1, true) and
               not string.find(errorString, "already exists", 1, true) then
                 -- Log only unexpected errors.
                 Log(string.format("^1Database Error: Failed executing schema statement #%d: %s^7", i, errorString), 1)
                 Log(string.format("Failed SQL: %s", stmt), 1) -- Log the failing statement
                 errorsOccurred = true
            -- else -- Optional log for ignored errors
            --    Log(string.format("Database Info: Ignored expected error for schema statement #%d: %s", i, errorString), 4)
            end
        end
    end

    if not errorsOccurred then
        Log("Database: Schema check/creation completed successfully.", 2)
        -- After successful schema setup, force a reload of the ban list cache.
        if NexusGuardServer.Bans and NexusGuardServer.Bans.LoadList then
            Log("Database: Triggering initial ban list load...", 3)
            NexusGuardServer.Bans.LoadList(true) -- `true` forces reload.
        else
            Log("^1Database Warning: Bans module or LoadList function not found in API after DB init. Ban list not loaded.^7", 1)
        end
    else
        Log("^1Database Warning: Errors occurred during database schema setup. Review console logs above. NexusGuard functionality may be affected.^7", 1)
    end
end

--[[
    Cleans up old records from the `nexusguard_detections` table based on `Config.Database.historyDuration`.
    Called periodically by a scheduled task. Uses an asynchronous query.
]]
function Database.CleanupDetectionHistory()
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    -- Exit if DB is disabled, history duration is not set, or is zero/negative.
    if not dbConfig or not dbConfig.enabled or not dbConfig.historyDuration or dbConfig.historyDuration <= 0 then return end
    if not MySQL then Log("^1Database Error: MySQL object not found. Cannot cleanup detection history.^7", 1); return end

    local historyDays = dbConfig.historyDuration
    Log(("Database: Cleaning up detection history older than %d days..."):format(historyDays), 2)
    -- Use pcall for safety with async operation.
    local success, promise = pcall(MySQL.Async.execute,
        -- SQL query to delete records older than the specified interval.
        'DELETE FROM nexusguard_detections WHERE timestamp < DATE_SUB(NOW(), INTERVAL @days DAY)',
        { ['@days'] = historyDays }
    )

    if success and promise then
        -- Handle the promise for logging results/errors.
        promise:next(function(result)
            if result and result.affectedRows and result.affectedRows > 0 then
                Log(("Database: Cleaned up %d old detection records.^7"):format(result.affectedRows), 2)
            -- else -- Optional log if no records were deleted
            --    Log("Database: No old detection records found to clean up.", 3)
            end
        end, function(err)
            Log(string.format("^1Database Error: Failed executing detection history cleanup query: %s^7", tostring(err)), 1)
        end)
    elseif not success then
        -- Log error if initiating the async query failed. 'promise' contains the error here.
        Log(string.format("^1Database Error: Failed to initiate detection history cleanup query: %s^7", tostring(promise)), 1)
    end
end

--[[
    Saves a summary of a player's session metrics to the `nexusguard_sessions` table upon disconnect.
    Uses an asynchronous query.

    @param playerId (number): The server ID of the player whose metrics are being saved.
    @param metrics (table): The metrics data table collected during the player's session
                           (passed from `server_main.lua`'s `OnPlayerDropped`).
]]
function Database.SavePlayerMetrics(playerId, metrics)
    local source = tonumber(playerId)
    if not source or source <= 0 then Log("^1Database Error: Invalid player ID provided to SavePlayerMetrics: " .. tostring(playerId) .. "^7", 1); return end
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    -- Exit if database is disabled.
    if not dbConfig or not dbConfig.enabled then return end
    -- Ensure metrics data is provided.
    if not metrics then Log(("^1Database Warning: Metrics data not provided for player %d on disconnect. Cannot save session summary.^7"):format(source), 1); return end
    -- Ensure oxmysql is available.
    if not MySQL then Log(("^1Database Error: MySQL object not found. Cannot save session metrics for player %d.^7"):format(source), 1); return end

    local playerName = metrics.playerName or GetPlayerName(source) or ("Unknown (" .. source .. ")") -- Use name from metrics if available
    local license = metrics.license or GetPlayerIdentifierByType(source, 'license') -- Use license from metrics if available
    -- Require a license identifier to save the record.
    if not license then Log(("^1Database Warning: Cannot save session metrics for player %s (ID: %d) without license identifier. Skipping save.^7"):format(playerName, source), 1); return end

    -- Extract relevant summary data from the metrics table. Provide defaults if missing.
    local connectTime = metrics.connectTime or os.time() -- Use current time as fallback connect time if missing
    local playTime = math.max(0, os.time() - connectTime) -- Calculate playtime based on connectTime.
    local finalTrustScore = metrics.trustScore or 100.0
    local totalDetections = #(metrics.detections or {}) -- Count entries in the detections sub-table.
    local totalWarnings = metrics.warningCount or 0

    Log(("Database: Saving session summary for player %s (ID: %d)..."):format(playerName, source), 3)
    -- Use pcall for safety with async operation.
    local success, promise = pcall(MySQL.Async.execute,
        -- SQL query to insert the session summary.
        'INSERT INTO nexusguard_sessions (player_name, player_license, connect_time, play_time_seconds, final_trust_score, total_detections, total_warnings) VALUES (@name, @license, FROM_UNIXTIME(@connect), @playtime, @trust, @detections, @warnings)',
        -- Parameters for the query.
        {
            ['@name'] = playerName,
            ['@license'] = license,
            ['@connect'] = connectTime, -- Store Unix timestamp
            ['@playtime'] = playTime,
            ['@trust'] = finalTrustScore,
            ['@detections'] = totalDetections,
            ['@warnings'] = totalWarnings
        }
    )

    if success and promise then
        -- Handle the promise for logging results/errors.
        promise:next(function(result)
            if not result or not result.affectedRows or result.affectedRows <= 0 then
                Log(("^1Database Warning: Saving session summary for player %s (ID: %d) reported 0 affected rows.^7"):format(playerName, source), 1)
            -- else -- Optional success log
            --    Log(("Database: Session summary saved for player %s (ID: %d)."):format(playerName, source), 3)
            end
        end, function(err)
            Log(string.format("^1Database Error: Failed executing session summary save query for player %s (ID: %d): %s^7", playerName, source, tostring(err)), 1)
        end)
    elseif not success then
        -- Log error if initiating the async query failed. 'promise' contains the error here.
        Log(string.format("^1Database Error: Failed to initiate session summary save query for player %s (ID: %d): %s^7", playerName, source, tostring(promise)), 1)
    end
end

--[[
    Stores details of a specific detection event in the `nexusguard_detections` table.
    Called by the Detections module when processing a verified detection.
    Uses an asynchronous query.

    @param playerId (number): The server ID of the player involved in the detection.
    @param detectionType (string): The type/name of the detection (e.g., "ServerSpeedCheck", "ResourceMismatch").
    @param detectionData (table): A table containing specific details about the detection event.
                                  This table will be encoded as a JSON string for storage.
]]
function Database.StoreDetection(playerId, detectionType, detectionData)
    local dbConfig = NexusGuardServer.Config and NexusGuardServer.Config.Database
    -- Exit if database or detection history storage is disabled.
    if not dbConfig or not dbConfig.enabled or not dbConfig.storeDetectionHistory then return end
    -- Ensure oxmysql and ox_lib (for JSON) are available.
    if not MySQL then Log("^1Database Error: MySQL object not found. Cannot store detection event.^7", 1); return end
    if not lib or not lib.json then Log("^1Database Error: ox_lib JSON library (lib.json) not found. Cannot encode detection data for storage.^7", 1); return end

    local source = tonumber(playerId)
    if not source or source <= 0 then Log("^1Database Error: Invalid player ID provided to StoreDetection: " .. tostring(playerId) .. "^7", 1); return end

    local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")
    local license = GetPlayerIdentifierByType(source, 'license')
    -- Require a license identifier to store the record.
    if not license then Log(("^1Database Warning: Cannot store detection event for player %s (ID: %d) without license identifier. Skipping save.^7"):format(playerName, source), 1); return end

    -- Ensure detectionData is a table before attempting JSON encoding.
    if type(detectionData) ~= "table" then
        Log(("^1Database Warning: detectionData provided to StoreDetection was not a table for type '%s'. Wrapping as { raw = ... }.^7"):format(detectionType), 1)
        -- Wrap non-table data in a basic table structure for consistent JSON storage.
        detectionData = { raw = tostring(detectionData) }
    end

    -- Safely encode the detection data table to a JSON string.
    local dataJson = "null" -- Default to SQL NULL string if encoding fails.
    local encodeSuccess, encoded = pcall(lib.json.encode, detectionData)
    if encodeSuccess and type(encoded) == "string" then
        dataJson = encoded
    else
        -- Log error if JSON encoding failed. 'encoded' contains the error message here.
        Log(("^1Database Error: Failed encoding detectionData to JSON for type '%s': %s^7"):format(detectionType, tostring(encoded)), 1)
        -- Consider storing a placeholder error message instead of "null" if preferred.
        -- dataJson = '{"error": "Failed to encode detection details"}'
    end

    -- Log("Database: Storing detection event - Player: %s, Type: %s, Data: %s", 4, playerName, detectionType, dataJson) -- Optional debug log

    -- Execute the asynchronous insert query. Use pcall for safety.
    local success, promise = pcall(MySQL.Async.execute,
        -- SQL query to insert the detection record. NOW() gets the current DB timestamp.
        'INSERT INTO nexusguard_detections (player_name, player_license, detection_type, detection_data, timestamp) VALUES (@name, @license, @type, @data, NOW())',
        -- Parameters for the query.
        {
            ['@name'] = playerName,
            ['@license'] = license,
            ['@type'] = detectionType,
            ['@data'] = dataJson -- Store the JSON string in the detection_data column.
        }
    )

    if success and promise then
        -- Handle the promise for logging results/errors.
        promise:next(function(result)
            if not result or not result.affectedRows or result.affectedRows <= 0 then
                Log(("^1Database Warning: Storing detection event for player %s (Type: %s) reported 0 affected rows.^7"):format(playerName, detectionType), 1)
            -- else -- Optional success log
            --    Log(("Database: Stored detection event for player %s (Type: %s)."):format(playerName, detectionType), 3)
            end
        end, function(err)
            Log(string.format("^1Database Error: Failed executing detection storage query for player %s (Type: %s): %s^7", playerName, detectionType, tostring(err)), 1)
        end)
    elseif not success then
        -- Log error if initiating the async query failed. 'promise' contains the error here.
        Log(string.format("^1Database Error: Failed to initiate detection storage query for player %s (Type: %s): %s^7", playerName, detectionType, tostring(promise)), 1)
    end
end

-- Export the Database table containing the functions.
return Database
