--[[
    NexusGuard Server Main Entry Point (server_main.lua)

    This script orchestrates the server-side logic for NexusGuard.
    Responsibilities include:
    - Initializing the server-side components on resource start.
    - Handling core FiveM player events (connecting, dropped).
    - Managing player sessions and associated metrics.
    - Registering and handling network events received from clients via EventRegistry.
    - Performing server-side validation of client data (position, health, etc.).
    - Setting up scheduled tasks (e.g., cleanup).
    - Registering admin commands (ban, unban, getresources).
    - Interacting with other modules (Bans, Detections, Security, Database, Utils, Permissions)
      primarily through the `NexusGuardServer` API table exposed from `globals.lua`.
]]

-- Lua/FiveM Standard Libraries & Globals
-- Access GetPlayerIdentifierByType(), GetPlayerEndpoint(), DropPlayer(), etc.

-- NexusGuard Shared Modules
local EventRegistry = require('shared/event_registry') -- Handles standardized network event names.

-- NexusGuard Server API (from globals.lua)
-- This table provides access to functions and data from other server-side modules.
local NexusGuardServer = exports['NexusGuard']:GetNexusGuardServerAPI()
if not NexusGuardServer then
    print("^1[NexusGuard] CRITICAL: Failed to get NexusGuardServer API from globals.lua. NexusGuard will not function correctly.^7")
    -- Consider stopping the resource if the API is essential.
    return
end

-- Local alias for the logging function from the Utils module via the API.
local Log = NexusGuardServer.Utils.Log
if not Log then
    print("^1[NexusGuard] CRITICAL: Logging function (NexusGuardServer.Utils.Log) not found in API.^7")
    -- Fallback to basic print if logging is unavailable, but indicates an API issue.
    Log = function(msg, level) print(msg) end
end

-- Ensure EventRegistry loaded correctly.
if not EventRegistry then
    Log("^1[NexusGuard] CRITICAL: Failed to load shared/event_registry.lua. Network event handling will fail.^7", 1)
    -- Consider stopping the resource if EventRegistry is crucial.
end

--[[
    Core FiveM Event Handlers
    These handlers hook into built-in FiveM server events.
]]
RegisterNetEvent('onResourceStart') -- Standard event for resource initialization.

-- playerConnecting: Handles initial player connection, deferrals, ban checks, session setup.
AddEventHandler('playerConnecting', function(playerName, setKickReason, deferrals)
    -- Explicitly pass arguments to the handler function for clarity.
    OnPlayerConnecting(playerName, setKickReason, deferrals)
end)

-- playerDropped: Handles player disconnection, saving metrics, cleanup.
AddEventHandler('playerDropped', function(reason)
    -- Explicitly pass arguments to the handler function.
    OnPlayerDropped(reason)
end)

-- explosionEvent: Handles explosion events, passing data to the event handlers module via API.
AddEventHandler('explosionEvent', function(sender, ev)
    local source = tonumber(sender)
    -- Retrieve the player's session data using the local PlayerSessionManager.
    local session = PlayerSessionManager.GetSession(source)
    -- Call the HandleExplosion function from the EventHandlers module via the API, passing the session.
    if NexusGuardServer.EventHandlers and NexusGuardServer.EventHandlers.HandleExplosion then
        NexusGuardServer.EventHandlers.HandleExplosion(sender, ev, session)
    else
        Log(("^1[NexusGuard] HandleExplosion function not found in API for event from sender %s.^7"):format(tostring(sender)), 1)
    end
end)

--[[
    Local State Management
]]
-- Tracks clients that have successfully requested and received a security token.
local ClientsLoaded = {}

--[[
    Player Session Management (Local to server_main.lua)
    Manages temporary data associated with each connected player's session.
    This data is primarily stored in the `metrics` sub-table.
]]
local PlayerSessionManager = {}
PlayerSessionManager.sessions = {} -- Stores session data, keyed by player server ID.

-- Gets or creates a session table for a given player ID.
PlayerSessionManager.GetSession = function(playerId)
    playerId = tonumber(playerId) -- Ensure playerId is a number
    if not playerId or playerId <= 0 then return nil end -- Basic validation

    if not PlayerSessionManager.sessions[playerId] then
        -- Initialize a new session structure if one doesn't exist.
        PlayerSessionManager.sessions[playerId] = {
            metrics = {}, -- Holds various tracking data (position, health, detections, etc.)
            -- Add other session-specific data here if needed (e.g., temporary flags).
        }
        -- Log(("^2[NexusGuard] Created new session for player ID %d.^7"):format(playerId), 3)
    end
    return PlayerSessionManager.sessions[playerId]
end

-- Clean up session data when a player drops. Hooked into the playerDropped event handler below.
local function CleanupPlayerSession(playerId)
    playerId = tonumber(playerId)
    if not playerId or playerId <= 0 then return end

    if PlayerSessionManager.sessions[playerId] then
        -- Log(("^2[NexusGuard] Cleaning up session for player ID %d.^7"):format(playerId), 3)
        PlayerSessionManager.sessions[playerId] = nil -- Remove the session entry.
    end
    ClientsLoaded[playerId] = nil -- Also clear from ClientsLoaded table.
end

--[[
    Resource Initialization Handler (onResourceStart)
    Performs setup tasks when the NexusGuard resource starts.
]]
AddEventHandler('onResourceStart', function(resourceName)
    -- Ensure this runs only for the NexusGuard resource itself.
    if resourceName ~= GetCurrentResourceName() then return end

    -- Double-check that the API table loaded correctly.
    if not NexusGuardServer or not NexusGuardServer.Utils or not NexusGuardServer.Utils.Log then
        print("^1[NexusGuard] CRITICAL: NexusGuardServer API or required modules not loaded correctly during onResourceStart. Initialization aborted.^7")
        return
    end
    Log('^2[NexusGuard]^7 Initializing NexusGuard Anti-Cheat System (Server)...', 2)

    -- Perform Dependency Checks using API references where possible.
    -- Check for oxmysql (MySQL object is global, exposed by oxmysql).
    if not MySQL then
        Log("^1[NexusGuard] CRITICAL: MySQL object not found. Ensure 'oxmysql' is started BEFORE NexusGuard. Disabling database features.^7", 1)
        -- Attempt to disable DB features via Config if accessible through API.
        if NexusGuardServer.Config and NexusGuardServer.Config.Database then
            NexusGuardServer.Config.Database.enabled = false
        end
    end
    -- Check for ox_lib crypto functions (lib is global, exposed by ox_lib).
    if not lib or not lib.crypto or not lib.crypto.hmac then
         Log("^1[NexusGuard] CRITICAL: ox_lib crypto functions not found (lib.crypto.hmac). Ensure 'ox_lib' is started BEFORE NexusGuard and is up-to-date. Security token system will fail.^7", 1)
         -- Consider halting resource start if security is critical and ox_lib is missing.
         -- return
    end

    -- Ensure the Config table loaded from config.lua is accessible via the API table.
    -- _G.Config should have been loaded by `shared_scripts` in fxmanifest.lua.
    NexusGuardServer.Config = _G.Config or {}
    if not _G.Config then
        Log("^1[NexusGuard] CRITICAL: Global Config table not found. Ensure config.lua is loaded correctly via shared_scripts.^7", 1)
    else
        Log("^2[NexusGuard]^7 Configuration table loaded and referenced in API.^7", 2)
    end

    -- Load the initial ban list from the database using the Bans module via API.
    if NexusGuardServer.Bans and NexusGuardServer.Bans.LoadList then
        NexusGuardServer.Bans.LoadList(true) -- `true` forces reload on start.
    else
        Log("^1[NexusGuard] CRITICAL: Bans.LoadList function not found in API! Ban checks will fail.^7", 1)
    end

    -- Setup local scheduled tasks (defined later in this file).
    SetupScheduledTasks()

    -- Register server-side network event handlers using EventRegistry (defined later in this file).
    if EventRegistry then
        RegisterNexusGuardServerEvents()
        Log("^2[NexusGuard]^7 Server network event handlers registered via EventRegistry.^7", 2)
    else
        Log("^1[NexusGuard] CRITICAL: EventRegistry module not loaded! Cannot register server network event handlers. NexusGuard will not function.^7", 1)
    end

    Log("^2[NexusGuard]^7 Server initialization sequence complete.^7", 2)
end)

--[[
    Player Connecting Handler Function (OnPlayerConnecting)
    Handles the player connection handshake, ban checks, and session initialization.
]]
function OnPlayerConnecting(playerName, setKickReason, deferrals)
    local source = source -- Capture the 'source' (player server ID) from the event context.
    -- Basic validation of the source ID.
    if not source or source <= 0 then
        Log("^1[NexusGuard] Invalid source ID in OnPlayerConnecting. Aborting connection.^7", 1)
        deferrals.done("Anti-Cheat Error: Invalid connection source ID.")
        return
    end

    -- Defer the connection to perform asynchronous checks (like database lookups).
    deferrals.defer()
    Citizen.Wait(10) -- Small wait before updating deferral message.
    deferrals.update('Checking your profile against our security database...')

    -- Get player identifiers (license, IP, discord).
    local license = GetPlayerIdentifierByType(source, 'license')
    local ip = GetPlayerEndpoint(source) -- Gets IP:Port string.
    local discord = GetPlayerIdentifierByType(source, 'discord')

    -- Perform Ban Check using the Bans module via API.
    Citizen.Wait(200) -- Allow time for identifiers to be available and potentially for DB query.
    local banned, banReason = false, nil
    if NexusGuardServer.Bans and NexusGuardServer.Bans.IsPlayerBanned then
        -- Call the API function to check bans based on identifiers.
        banned, banReason = NexusGuardServer.Bans.IsPlayerBanned(license, ip, discord)
    else
        Log(("^1[NexusGuard] IsPlayerBanned function missing from API. Cannot check ban status for %s (ID: %d)^7"):format(playerName, source), 1)
        -- Fail-safe: Kick if ban check function is missing? Or allow connection with warning?
        -- deferrals.done("Anti-Cheat Error: Ban check system unavailable.")
        -- return
    end

    -- If banned, reject the connection.
    if banned then
        local banMsg = (NexusGuardServer.Config.BanMessage or "You are banned from this server.") .. " Reason: " .. (banReason or "N/A")
        deferrals.done(banMsg) -- Provide the ban reason to the player.
        Log(("^1[NexusGuard] Connection Rejected: %s (ID: %d, License: %s) is banned. Reason: %s^7"):format(playerName, source, license or "N/A", banReason or "N/A"), 1)
        -- Log ban rejection to Discord if configured.
        if NexusGuardServer.Discord and NexusGuardServer.Discord.Send then
            NexusGuardServer.Discord.Send("Bans", 'Connection Rejected (Banned)', ("Player: %s (ID: %d)\nLicense: %s\nReason: %s"):format(playerName, source, license or "N/A", banReason or "N/A"), NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.bans)
        end
        return -- Stop further processing for banned players.
    end

    -- Check Admin Status using the Permissions module via API.
    local isAdmin = (NexusGuardServer.Permissions and NexusGuardServer.Permissions.IsAdmin and NexusGuardServer.Permissions.IsAdmin(source)) or false

    -- Initialize Player Session using the local PlayerSessionManager.
    local session = PlayerSessionManager.GetSession(source)
    if not session then
        Log(("^1[NexusGuard] CRITICAL: Failed to create session for player %s (ID: %d). Aborting connection.^7"):format(playerName, source), 1)
        deferrals.done("Anti-Cheat Error: Failed to initialize player session.")
        return
    end
    -- Populate the session's metrics table with initial data.
    session.metrics = {
        connectTime = os.time(),
        playerName = playerName,
        license = license,
        ip = ip,
        discord = discord,
        isAdmin = isAdmin,
        warningCount = 0,
        detections = {},          -- Stores details of triggered detections.
        healthHistory = {},       -- Potentially store recent health changes.
        movementSamples = {},     -- Potentially store recent movement data.
        weaponStats = {},         -- Potentially store weapon usage data.
        behaviorProfile = {},     -- Placeholder for more advanced behavioral analysis.
        trustScore = 100.0,       -- Initial trust score.
        securityToken = nil,      -- Will be populated upon successful handshake.
        lastServerPosition = nil, -- Last position received from the client.
        lastServerPositionTimestamp = nil,
        lastServerHealth = nil,   -- Last health received from the client.
        lastServerArmor = nil,
        lastServerHealthTimestamp = nil,
        explosions = {},          -- Track explosion events caused by the player.
        entities = {},            -- Track entities potentially created by the player.
        justSpawned = true,       -- Flag for initial spawn grace period (Guideline 27).
        lastValidPosition = nil   -- Last position deemed valid by server-side checks (Guideline 31).
    }

    -- Set a timeout to clear the 'justSpawned' flag after a grace period (Guideline 27).
    local spawnGracePeriod = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.spawnGracePeriod) or 10000 -- Default 10 seconds
    SetTimeout(spawnGracePeriod, function()
        -- Need to re-fetch the session in case the player dropped during the timeout.
        local currentSession = PlayerSessionManager.GetSession(source)
        if currentSession and currentSession.metrics then
            currentSession.metrics.justSpawned = false
            Log(("^2[NexusGuard]^7 Initial spawn grace period (%dms) ended for %s (ID: %d)^7"):format(spawnGracePeriod, playerName, source), 3)
        end
    end)

    -- Track online admins using the table provided by the API.
    if isAdmin then
        if NexusGuardServer.OnlineAdmins then
            NexusGuardServer.OnlineAdmins[source] = true
            Log(("^2[NexusGuard]^7 Admin connected: %s (ID: %d)^7"):format(playerName, source), 2)
        else
            Log("^1[NexusGuard] CRITICAL: OnlineAdmins table not found in API! Cannot track admin status.^7", 1)
        end
    end

    Log(("^2[NexusGuard]^7 Player connection approved: %s (ID: %d, License: %s)^7"):format(playerName, source, license or "N/A"), 2)
    -- Finalize the deferral, allowing the player to join.
    deferrals.done()
end

--[[
    Player Disconnected Handler Function (OnPlayerDropped)
    Handles cleanup tasks when a player leaves the server.
]]
function OnPlayerDropped(reason)
    local source = source -- Capture the 'source' (player server ID) from the event context.
    if not source or source <= 0 then return end -- Ignore invalid source IDs.

    local playerName = GetPlayerName(source) or ("Unknown Player (" .. source .. ")")
    local session = PlayerSessionManager.GetSession(source) -- Retrieve the player's session data.

    -- Save player metrics/detection data to the database if enabled and session data exists.
    if NexusGuardServer.Config.Database and NexusGuardServer.Config.Database.enabled and session and session.metrics then
        if NexusGuardServer.Database and NexusGuardServer.Database.SavePlayerMetrics then
            -- Call the Database module's function via API to save the data.
            NexusGuardServer.Database.SavePlayerMetrics(source, session.metrics)
        else
            Log(("^1[NexusGuard] SavePlayerMetrics function missing from API. Cannot save session data for %s (ID: %d)^7"):format(playerName, source), 1)
        end
    end

    -- Log disconnection and update admin tracking if applicable.
    if session and session.metrics and session.metrics.isAdmin then
        -- Remove admin from the online admin list via API table.
        if NexusGuardServer.OnlineAdmins then
            NexusGuardServer.OnlineAdmins[source] = nil
            Log(("^2[NexusGuard]^7 Admin disconnected: %s (ID: %d). Reason: %s^7"):format(playerName, source, reason), 2)
        else
            Log("^1[NexusGuard] CRITICAL: OnlineAdmins table not found in API! Cannot update admin status on disconnect.^7", 1)
        end
    else
        Log(("^2[NexusGuard]^7 Player disconnected: %s (ID: %d). Reason: %s^7"):format(playerName, source, reason), 2)
    end

    -- Clean up the player's session data from the local manager.
    CleanupPlayerSession(source)
end

--[[
    Register Server-Side Network Event Handlers Function (RegisterNexusGuardServerEvents)
    Sets up handlers for events triggered by clients, using the EventRegistry for standardized names.
]]
function RegisterNexusGuardServerEvents()
    -- Ensure EventRegistry is available.
    if not EventRegistry then
        Log("^1[NexusGuard] EventRegistry module not loaded. Cannot register standardized server event handlers.^7", 1)
        return
    end

    -- Security Token Request Handler (Client -> Server)
    -- Client requests a token during its initialization.
    EventRegistry:AddEventHandler('SECURITY_REQUEST_TOKEN', function(clientHash)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- Basic validation of the client hash (currently just checks if it's a string).
        if clientHash and type(clientHash) == "string" then
            ClientsLoaded[source] = true -- Mark client as having initiated the handshake.
            -- Generate a security token using the Security module via API.
            local tokenData = NexusGuardServer.Security and NexusGuardServer.Security.GenerateToken and NexusGuardServer.Security.GenerateToken(source)
            if tokenData then
                -- Send the generated token data back to the requesting client.
                EventRegistry:TriggerClientEvent('SECURITY_RECEIVE_TOKEN', source, tokenData)
                Log(("^2[NexusGuard]^7 Secure token sent to %s (ID: %d) via event '%s'^7"):format(playerName, source, EventRegistry:GetEventName('SECURITY_RECEIVE_TOKEN')), 2)
            else
                -- Handle token generation failure (e.g., missing secret key).
                Log(("^1[NexusGuard]^7 Failed to generate secure token for %s (ID: %d). Kicking player.^7"):format(playerName, source), 1)
                DropPlayer(source, "Anti-Cheat initialization failed (Token Generation Error).")
            end
        else
            -- Handle invalid handshake attempt (missing or invalid clientHash).
             Log(("^1[NexusGuard]^7 Invalid or missing client hash received from %s (ID: %d) during token request. Kicking player.^7"):format(playerName, source), 1)
             -- Optionally ban for tampering.
             if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
                 NexusGuardServer.Bans.Execute(source, 'Modified client detected (Invalid Handshake)')
             else
                 DropPlayer(source, "Anti-Cheat validation failed (Client Handshake Error).")
             end
        end
    end)

    -- Detection Report Handler (Client -> Server)
    -- Client reports a potential cheat detection.
    EventRegistry:AddEventHandler('DETECTION_REPORT', function(detectionType, detectionData, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token received with the report.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
            Log(("^1[NexusGuard] Invalid security token received with detection report from %s (ID: %d). Banning player.^7"):format(playerName, source), 1)
            if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
                NexusGuardServer.Bans.Execute(source, 'Invalid security token with detection report')
            else
                DropPlayer(source, "Anti-Cheat validation failed (Invalid Detection Token).")
            end
            return -- Stop processing if token is invalid.
        end

        -- Retrieve the player's session data.
        local session = PlayerSessionManager.GetSession(source)
        if not session then
            Log(("^1[NexusGuard] CRITICAL: Failed to get session for player %s (ID: %d) during DETECTION_REPORT. Aborting processing.^7"):format(playerName, source), 1)
            return
        end

        -- Process the detection using the Detections module via API.
        if NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
             -- Pass the player ID, detection details, and the full session object to the processing function.
             NexusGuardServer.Detections.Process(source, detectionType, detectionData, session)
        else
             Log(("^1[NexusGuard] CRITICAL: Detections.Process function not found in API! Cannot process detection '%s' from %s (ID: %d)^7"):format(tostring(detectionType), playerName, source), 1)
        end
    end)

    -- Resource Verification Handler (Client -> Server) (Guideline 30)
    -- Client sends its list of running resources for verification.
    EventRegistry:AddEventHandler('SYSTEM_RESOURCE_CHECK', function(clientResourcesList, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
            Log(("^1[NexusGuard] Invalid security token received with resource check from %s (ID: %d). Banning player.^7"):format(playerName, source), 1)
            if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
                NexusGuardServer.Bans.Execute(source, 'Invalid security token during resource check')
            else
                DropPlayer(source, "Anti-Cheat validation failed (Resource Check Token).")
            end
            return
        end

        -- Validate the format of the received resource list.
        if type(clientResourcesList) ~= "table" then
            Log(("^1[NexusGuard] Invalid resource list format received from %s (ID: %d). Kicking player.^7"):format(playerName, source), 1)
            DropPlayer(source, "Anti-Cheat validation failed (Invalid Resource List Format).")
            return
        end

        Log(("^3[NexusGuard]^7 Received resource list from %s (ID: %d) (%d resources) via event '%s'^7"):format(playerName, source, #clientResourcesList, EventRegistry:GetEventName('SYSTEM_RESOURCE_CHECK')), 3)

        -- Check if resource verification is enabled in the config.
        local rvConfig = NexusGuardServer.Config and NexusGuardServer.Config.Features and NexusGuardServer.Config.Features.resourceVerification
        if rvConfig and rvConfig.enabled then
            Log(("^3[NexusGuard] Performing resource verification for %s (ID: %d) using '%s' mode...^7"):format(playerName, source, rvConfig.mode or "whitelist"), 3)

            local MismatchedResources = {} -- Stores resources that fail the check.
            local listToCheck = {}        -- The whitelist or blacklist from config.
            local clientResourcesSet = {} -- Convert client list to a set for faster lookups.
            for _, clientRes in ipairs(clientResourcesList) do clientResourcesSet[clientRes] = true end

            local checkMode = rvConfig.mode or "whitelist" -- Default to whitelist if mode is not set.
            -- Load the appropriate list from config based on the mode.
            if checkMode == "whitelist" then
                listToCheck = rvConfig.whitelist or {}
            elseif checkMode == "blacklist" then
                listToCheck = rvConfig.blacklist or {}
            else
                Log(("^1[NexusGuard] Invalid resourceVerification mode '%s' in config. Defaulting to 'whitelist'.^7"):format(checkMode), 1)
                checkMode = "whitelist"
                listToCheck = rvConfig.whitelist or {}
            end
            -- Convert the config list to a set for efficient checking.
            local checkSet = {}
            for _, resName in ipairs(listToCheck) do checkSet[resName] = true end

            -- Perform the check based on the mode.
            if checkMode == "whitelist" then
                -- Check if any client resource is NOT in the whitelist set.
                for clientRes, _ in pairs(clientResourcesSet) do
                    if not checkSet[clientRes] then
                        table.insert(MismatchedResources, clientRes .. " (Not Whitelisted)")
                    end
                end
            elseif checkMode == "blacklist" then
                -- Check if any client resource IS in the blacklist set.
                for clientRes, _ in pairs(clientResourcesSet) do
                    if checkSet[clientRes] then
                        table.insert(MismatchedResources, clientRes .. " (Blacklisted)")
                    end
                end
            end

            -- If mismatches are found, take action.
            if #MismatchedResources > 0 then
                local mismatchDetails = ""
                for i, res in ipairs(MismatchedResources) do mismatchDetails = mismatchDetails .. "\n - " .. res end
                local reason = ("Unauthorized resources detected (%s):%s"):format(checkMode, mismatchDetails)

                Log(("^1[NexusGuard] Resource Mismatch for %s (ID: %d): %s^7"):format(playerName, source, reason), 1)
                -- Log to Discord if configured.
                if NexusGuardServer.Discord and NexusGuardServer.Discord.Send then
                    NexusGuardServer.Discord.Send("general", "Resource Mismatch", ("Player: %s (ID: %d)\nReason: %s"):format(playerName, source, reason), NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.general)
                end
                -- Process this as a detection event.
                local session = PlayerSessionManager.GetSession(source)
                if NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
                    NexusGuardServer.Detections.Process(source, "ResourceMismatch", { mismatched = MismatchedResources, mode = checkMode }, session)
                end
                -- Ban or kick based on config.
                if rvConfig.banOnMismatch then
                    Log(("^1[NexusGuard] Banning player %s (ID: %d) due to resource mismatch.^7"):format(playerName, source), 1)
                    if NexusGuardServer.Bans.Execute then NexusGuardServer.Bans.Execute(source, "Unauthorized resources detected (" .. checkMode .. ")") end
                elseif rvConfig.kickOnMismatch then
                    Log(("^1[NexusGuard] Kicking player %s (ID: %d) due to resource mismatch.^7"):format(playerName, source), 1)
                    DropPlayer(source, "Kicked due to unauthorized resources.")
                end
            else
                -- Log success if verification passes.
                Log(("^2[NexusGuard] Resource check passed for %s (ID: %d)^7"):format(playerName, source), 2)
            end
        else
            -- Log if verification is disabled.
            Log("^3[NexusGuard] Resource verification is disabled in config. Skipping check.^7", 3)
        end
    end)

    -- Client Error Handler (Client -> Server)
    -- Client reports an internal error within one of its detectors.
    EventRegistry:AddEventHandler('SYSTEM_ERROR', function(detectionName, errorMessage, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
            Log(("^1[NexusGuard]^7 Invalid security token received with error report from %s (ID: %d). Ignoring report.^7"):format(playerName, source), 1)
            return -- Ignore report if token is invalid.
        end

        -- Log the reported client error.
        Log(("^3[NexusGuard]^7 Client error reported by %s (ID: %d) in module '%s': %s^7"):format(playerName, source, tostring(detectionName), tostring(errorMessage)), 2)
        -- Log to Discord if configured.
        if NexusGuardServer.Discord and NexusGuardServer.Discord.Send then
            NexusGuardServer.Discord.Send("general", 'Client Error Report', ("Player: %s (ID: %d)\nModule: %s\nError: %s"):format(playerName, source, tostring(detectionName), tostring(errorMessage)), NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.general)
        end
        -- Store the error in the player's session metrics for potential analysis.
        local session = PlayerSessionManager.GetSession(source)
        if session and session.metrics then
            if not session.metrics.clientErrors then session.metrics.clientErrors = {} end
            table.insert(session.metrics.clientErrors, { detection = detectionName, error = errorMessage, time = os.time() })
        end
    end)

     -- Screenshot Taken Handler (Client -> Server)
     -- Client confirms a screenshot was taken and provides the URL.
     EventRegistry:AddEventHandler('ADMIN_SCREENSHOT_TAKEN', function(screenshotUrl, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
             Log(("^1[NexusGuard] Invalid security token received with screenshot confirmation from %s (ID: %d). Banning player.^7"):format(playerName, source), 1)
             if NexusGuardServer.Bans.Execute then NexusGuardServer.Bans.Execute(source, 'Invalid security token with screenshot confirmation') else DropPlayer(source, "Anti-Cheat validation failed (Screenshot Confirmation Token).") end
            return
        end

        -- Log the successful screenshot confirmation and URL.
        Log(("^2[NexusGuard]^7 Received screenshot confirmation from %s (ID: %d): %s^7"):format(playerName, source, screenshotUrl), 2)
        -- Log to Discord if configured.
        if NexusGuardServer.Discord and NexusGuardServer.Discord.Send then
            NexusGuardServer.Discord.Send("general", 'Screenshot Taken & Uploaded', ("Player: %s (ID: %d)\nURL: %s"):format(playerName, source, screenshotUrl), NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.general)
        end
        -- Potentially notify admins that the screenshot is available (e.g., via another Discord message or in-game notification).
        -- Example: NexusGuardServer.Utils.NotifyAdmins(source, "ScreenshotTaken", {url = screenshotUrl}) -- If NotifyAdmins exists in API
    end)

    -- Position Update Handler (Client -> Server) (Guidelines 26, 27, 28, 31, 38)
    -- Client sends periodic position updates for server-side validation (speed, teleport, noclip).
    EventRegistry:AddEventHandler('NEXUSGUARD_POSITION_UPDATE', function(currentPos, clientTimestamp, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
            Log(("^1[NexusGuard] Invalid security token with position update from %s (ID: %d). Banning player.^7"):format(playerName, source), 1)
            if NexusGuardServer.Bans.Execute then NexusGuardServer.Bans.Execute(source, 'Invalid security token with position update') else DropPlayer(source, "Anti-Cheat validation failed (Position Update Token).") end
            return
        end

        -- Retrieve player session and validate data types.
        local session = PlayerSessionManager.GetSession(source)
        if not session or not session.metrics then
            Log(("^1[NexusGuard] Player session or metrics not found for %s (ID: %d) during position update.^7"):format(playerName, source), 1)
            return
        end
        if type(currentPos) ~= "vector3" then
            Log(("^1[NexusGuard] Invalid position data type received from %s (ID: %d). Kicking player.^7"):format(playerName, source), 1)
            DropPlayer(source, "Anti-Cheat validation failed (Invalid Position Data Type).")
            return
        end

        -- Guideline 38: Update Player State in Session Metrics based on server-side natives.
        local ped = GetPlayerPed(source) -- Get the player's ped server-side.
        if ped and ped ~= -1 then -- Check if ped is valid
            session.metrics.isInVehicle = GetVehiclePedIsIn(ped, false) ~= 0
            local velocity = GetEntityVelocity(ped)
            session.metrics.isFalling = IsPedFalling(ped) -- More reliable server-side? Test needed.
            session.metrics.isRagdoll = IsPedRagdoll(ped)
            session.metrics.isSwimming = IsPedSwimming(ped)
            session.metrics.verticalVelocity = velocity.z -- Store current vertical velocity.
            session.metrics.isInParachute = IsPedInParachuteFreeFall(ped) -- Check parachute state.
        else
            -- Reset states if ped is invalid (e.g., during loading screens)
            session.metrics.isInVehicle = false
            session.metrics.isFalling = false
            session.metrics.isRagdoll = false
            session.metrics.isSwimming = false
            session.metrics.verticalVelocity = 0.0
            session.metrics.isInParachute = false
        end

        -- Guideline 27: Skip checks during the initial spawn grace period.
        if session.metrics.justSpawned then
            -- Log(("^3[NexusGuard]^7 Skipping initial position checks for %s (ID: %d) (recently spawned).^7"):format(playerName, source), 3)
            -- Still update the position to prevent large jump detection immediately after grace period ends.
            session.metrics.lastServerPosition = currentPos
            session.metrics.lastServerPositionTimestamp = GetGameTimer()
            session.metrics.lastValidPosition = currentPos -- Assume spawn position is valid initially.
            return
        end

        -- Load relevant thresholds from config via API table.
        local serverSpeedThreshold = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.serverSideSpeedThreshold) or 50.0
        local minTimeDiff = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.minTimeDiffPositionCheck) or 450 -- Minimum time between checks (ms).
        local noclipTolerance = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.noclipTolerance) or 3.0 -- Extra distance tolerance for noclip check.

        -- Perform checks only if enough time has passed since the last check (Guideline 28).
        if session.metrics.lastServerPosition and session.metrics.lastServerPositionTimestamp then
            local lastPos = session.metrics.lastServerPosition
            local lastTimestamp = session.metrics.lastServerPositionTimestamp
            local currentServerTimestamp = GetGameTimer()
            local timeDiffMs = currentServerTimestamp - lastTimestamp

            if timeDiffMs >= minTimeDiff then
                local distance = #(currentPos - lastPos) -- Calculate distance moved.
                local speed = 0.0
                if timeDiffMs > 0 then speed = distance / (timeDiffMs / 1000.0) end -- Calculate speed in m/s.

                -- Guideline 26 & 38: Adjust speed threshold based on player state.
                local effectiveSpeedThreshold = serverSpeedThreshold
                -- Increase threshold significantly if falling, ragdolling, or parachuting.
                if session.metrics.isFalling or session.metrics.isRagdoll or session.metrics.isInParachute or session.metrics.verticalVelocity < -15.0 then -- Added check for high negative vertical velocity
                    effectiveSpeedThreshold = serverSpeedThreshold * 2.5 -- Allow higher speed in these states.
                    -- Log(("^3[NexusGuard]^7 Applying increased speed tolerance (%.1f m/s) due to falling/ragdoll/parachute state for %s^7"):format(effectiveSpeedThreshold, playerName), 3)
                -- Slightly increase threshold if in a vehicle.
                elseif session.metrics.isInVehicle then
                     effectiveSpeedThreshold = serverSpeedThreshold * 1.3 -- Allow slightly higher speed in vehicles.
                end

                -- Check if calculated speed exceeds the effective threshold.
                if speed > effectiveSpeedThreshold then
                    Log(("^1[NexusGuard Server Speed Check]^7 Suspicious speed for %s (ID: %d): %.2f m/s (%.1f km/h). Threshold: %.2f m/s. Dist: %.2fm in %dms. State: Fall=%s, Ragdoll=%s, Parachute=%s, Vehicle=%s, VVel=%.2f^7"):format(
                        playerName, source, speed, speed * 3.6, effectiveSpeedThreshold, distance, timeDiffMs,
                        tostring(session.metrics.isFalling), tostring(session.metrics.isRagdoll), tostring(session.metrics.isInParachute), tostring(session.metrics.isInVehicle), session.metrics.verticalVelocity or 0.0
                    ), 1)
                    -- Process this as a detection event.
                    if NexusGuardServer.Detections.Process then
                        NexusGuardServer.Detections.Process(source, "ServerSpeedCheck", {
                            calculatedSpeed = speed, threshold = effectiveSpeedThreshold, distance = distance, timeDiff = timeDiffMs
                        }, session)
                    end
                else
                    -- Guideline 31: Basic Server-Side Noclip/Teleport Plausibility Check.
                    -- If speed is okay, check if the movement distance is plausible compared to the last *valid* position.
                    -- This is a rudimentary check and prone to false positives without raycasting.
                    if session.metrics.lastValidPosition then
                        local distFromLastValid = #(currentPos - session.metrics.lastValidPosition)
                        -- Calculate max plausible distance based on allowed speed + tolerance.
                        local maxPlausibleDistance = (effectiveSpeedThreshold * (timeDiffMs / 1000.0)) + (noclipTolerance * 2) -- Speed * time + extra buffer.
                        if distFromLastValid > maxPlausibleDistance then
                            -- Log potential issue but avoid flagging yet due to potential inaccuracy.
                            -- Log(("^3[NexusGuard Server Noclip Check]^7 Potential large jump for %s (ID: %d). Dist from last valid: %.2fm > plausible %.2fm in %dms. Requires further validation (raycast). Current Speed: %.2f m/s.^7"):format(playerName, source, distFromLastValid, maxPlausibleDistance, timeDiffMs, speed), 2)
                            -- if NexusGuardServer.Detections.Process then NexusGuardServer.Detections.Process(source, "ServerNoclipCheck", { distance = distFromLastValid, timeDiff = timeDiffMs }, session) end
                        else
                             -- If movement seems plausible relative to last valid position, update last valid position.
                             session.metrics.lastValidPosition = currentPos
                        end
                    else
                        -- Initialize last valid position if it doesn't exist.
                        session.metrics.lastValidPosition = currentPos
                    end
                end
            end
        else
             -- Initialize last valid position on the very first update received.
             session.metrics.lastValidPosition = currentPos
        end
        -- Always update the last known position and timestamp for the next check.
        session.metrics.lastServerPosition = currentPos
        session.metrics.lastServerPositionTimestamp = GetGameTimer()
    end)

    -- Health Update Handler (Client -> Server) (Guidelines 25, 29)
    -- Client sends periodic health/armor updates for server-side validation (god mode, armor limits).
    EventRegistry:AddEventHandler('NEXUSGUARD_HEALTH_UPDATE', function(currentHealth, currentArmor, clientTimestamp, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
            Log(("^1[NexusGuard] Invalid security token with health update from %s (ID: %d). Banning player.^7"):format(playerName, source), 1)
            if NexusGuardServer.Bans.Execute then NexusGuardServer.Bans.Execute(source, 'Invalid security token with health update') else DropPlayer(source, "Anti-Cheat validation failed (Health Update Token).") end
            return
        end

        -- Retrieve player session.
        local session = PlayerSessionManager.GetSession(source)
        if not session or not session.metrics then
            Log(("^1[NexusGuard] Player session or metrics not found for %s (ID: %d) during health update.^7"):format(playerName, source), 1)
            return
        end

        -- Load relevant thresholds from config.
        local serverHealthRegenThreshold = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.serverSideRegenThreshold) or 3.0 -- Max HP regen per second.
        local serverArmorMax = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.serverSideArmorThreshold) or 105.0 -- Max allowed armor value (slight tolerance).

        -- Guideline 29: Check for suspicious health regeneration.
        if session.metrics.lastServerHealth and session.metrics.lastServerHealthTimestamp then
            local lastHealth = session.metrics.lastServerHealth
            local lastTimestamp = session.metrics.lastServerHealthTimestamp
            local currentServerTimestamp = GetGameTimer()
            local timeDiffMs = currentServerTimestamp - lastTimestamp

            -- Check only if health increased and enough time has passed (> 500ms) to avoid noise.
            if currentHealth > lastHealth and timeDiffMs > 500 then
                local healthIncrease = currentHealth - lastHealth
                local regenRate = 0.0
                if timeDiffMs > 0 then regenRate = healthIncrease / (timeDiffMs / 1000.0) end -- Regen rate in HP/sec.

                -- Flag if regen rate exceeds threshold AND the total increase is significant (e.g., > 5 HP).
                -- TODO: Correlate with recent damage events (Guideline 25 - More complex).
                if regenRate > serverHealthRegenThreshold and healthIncrease > 5.0 then
                     Log(("^1[NexusGuard Server Health Check]^7 Suspicious health regeneration for %s (ID: %d): +%.1f HP in %dms (Rate: %.2f HP/s). Threshold: %.2f HP/s.^7"):format(playerName, source, healthIncrease, timeDiffMs, regenRate, serverHealthRegenThreshold), 1)
                     -- Process as a detection event.
                     if NexusGuardServer.Detections.Process then
                         NexusGuardServer.Detections.Process(source, "ServerHealthRegenCheck", {
                             increase = healthIncrease, rate = regenRate, threshold = serverHealthRegenThreshold, timeDiff = timeDiffMs
                         }, session)
                     end
                end
            end
        end

        -- Guideline 25: Check if current armor exceeds the configured maximum threshold.
        if currentArmor > serverArmorMax then
             Log(("^1[NexusGuard Server Armor Check]^7 Suspicious armor level for %s (ID: %d): %.1f (Max Allowed: %.1f).^7"):format(playerName, source, currentArmor, serverArmorMax), 1)
             -- Process as a detection event.
             if NexusGuardServer.Detections.Process then
                 NexusGuardServer.Detections.Process(source, "ServerArmorCheck", {
                     armor = currentArmor, threshold = serverArmorMax
                 }, session)
             end
        end

        -- Update the last known health, armor, and timestamp in the session metrics.
        session.metrics.lastServerHealth = currentHealth
        session.metrics.lastServerArmor = currentArmor
        session.metrics.lastServerHealthTimestamp = GetGameTimer()
    end)

    -- Weapon Clip Size Check Handler (Client -> Server) (Guideline 24)
    -- Client reports current weapon hash and clip count, server validates against config.
    -- Assumes 'NEXUSGUARD_WEAPON_CHECK' is registered in EventRegistry.
    EventRegistry:AddEventHandler('NEXUSGUARD_WEAPON_CHECK', function(weaponHash, clipCount, tokenData)
        local source = source -- Capture player source ID.
        if not source or source <= 0 then return end
        local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

        -- CRITICAL: Validate the security token.
        if not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(source, tokenData) then
            Log(("^1[NexusGuard] Invalid security token with weapon check from %s (ID: %d). Banning player.^7"):format(playerName, source), 1)
            if NexusGuardServer.Bans.Execute then NexusGuardServer.Bans.Execute(source, 'Invalid security token with weapon check') else DropPlayer(source, "Anti-Cheat validation failed (Weapon Check Token).") end
            return
        end

        -- Retrieve player session.
        local session = PlayerSessionManager.GetSession(source)
        if not session or not session.metrics then
            Log(("^1[NexusGuard] Player session or metrics not found for %s (ID: %d) during weapon check.^7"):format(playerName, source), 1)
            return
        end

        -- Get the configured base clip size for this weapon hash from config.
        local baseClipSize = NexusGuardServer.Config.WeaponBaseClipSize and NexusGuardServer.Config.WeaponBaseClipSize[weaponHash]

        -- Perform check only if a base size is configured for this weapon.
        if baseClipSize then
            -- Allow a small tolerance (e.g., +1 for a potentially chambered round, though config should ideally account for this).
            local clipTolerance = (NexusGuardServer.Config.Thresholds and NexusGuardServer.Config.Thresholds.weaponClipTolerance) or 1
            local maxAllowedClip = baseClipSize + clipTolerance

            -- Check if the reported clip count exceeds the maximum allowed.
            if clipCount > maxAllowedClip then
                Log(("^1[NexusGuard Server Weapon Check]^7 Suspicious clip size for %s (ID: %d): Weapon %s, Reported Clip %d, Base Size %d, Max Allowed %d^7"):format(playerName, source, tostring(weaponHash), clipCount, baseClipSize, maxAllowedClip), 1)
                -- Process as a detection event.
                if NexusGuardServer.Detections.Process then
                    NexusGuardServer.Detections.Process(source, "ServerWeaponClipCheck", {
                        weaponHash = weaponHash,
                        reportedClip = clipCount,
                        baseClip = baseClipSize,
                        maxAllowed = maxAllowedClip
                    }, session)
                end
            end
        else
            -- Log if no base size is configured (optional, can be spammy).
            -- Log(string.format("^3[NexusGuard]^7 No base clip size configured for weapon %s. Skipping server-side clip check for player %s.^7", tostring(weaponHash), playerName), 3)
        end
    end)

    Log("^2[NexusGuard] Standardized server network event handlers registration complete.^7", 2)
end

--[[
    Scheduled Tasks Setup Function (SetupScheduledTasks)
    Sets up periodic background tasks for maintenance.
]]
function SetupScheduledTasks()
    -- Periodic cleanup thread.
    Citizen.CreateThread(function()
        while true do
            -- Wait for a configured interval (e.g., 1 minute).
            local cleanupInterval = (NexusGuardServer.Config.CleanupInterval or 60000) -- Default 60 seconds
            Citizen.Wait(cleanupInterval)

            -- Call cleanup functions from relevant modules via API.
            -- Example: Cleanup old detection history from database.
            if NexusGuardServer.Database and NexusGuardServer.Database.CleanupDetectionHistory then
                NexusGuardServer.Database.CleanupDetectionHistory()
            end
            -- Example: Cleanup expired security tokens from cache.
            if NexusGuardServer.Security and NexusGuardServer.Security.CleanupTokenCache then
                NexusGuardServer.Security.CleanupTokenCache()
            end
            -- Add other cleanup tasks here (e.g., old session data if not handled on drop).
        end
    end)
    Log("^2[NexusGuard] Scheduled cleanup tasks initialized.^7", 2)

    -- Placeholder for other potential scheduled tasks (e.g., AI model updates - currently removed).
end

--[[
    Admin Commands
    Registers commands for administrative actions related to NexusGuard.
]]

-- Command: /nexusguard_getresources
-- Purpose: Provides admins with a formatted list of currently running resources,
--          useful for configuring the resource verification whitelist.
-- Access: Restricted to admins (checked via Permissions module API).
RegisterCommand('nexusguard_getresources', function(source, args, rawCommand)
    -- Disallow execution from server console.
    if source == 0 then print("[NexusGuard] This command must be run by an in-game player."); return end
    -- Check admin permissions using the Permissions module via API.
    if not NexusGuardServer.Permissions or not NexusGuardServer.Permissions.IsAdmin or not NexusGuardServer.Permissions.IsAdmin(source) then
        TriggerClientEvent('chat:addMessage', source, { color = {255, 0, 0}, multiline = true, args = {"NexusGuard", "You do not have permission to use this command."} })
        Log(("^1[NexusGuard] Permission denied for /nexusguard_getresources by player %s (ID: %d)^7"):format(GetPlayerName(source), source), 1)
        return
    end

    Log(("^2[NexusGuard] Admin %s (ID: %d) requested resource list.^7"):format(GetPlayerName(source), source), 2)
    -- Get all resources and filter for started ones.
    local resources = {}
    local numResources = GetNumResources()
    for i = 0, numResources - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName and GetResourceState(resourceName) == 'started' then
            table.insert(resources, resourceName)
        end
    end
    table.sort(resources) -- Sort alphabetically for readability.

    -- Format the output list as a Lua table string for easy copying into config.lua.
    local output = "--- Running Resources for Whitelist ---\n{\n"
    for _, resName in ipairs(resources) do
        output = output .. "    \"" .. resName .. "\",\n" -- Add each resource name quoted and comma-separated.
    end
    if #resources > 0 then
        output = string.sub(output, 1, #output - 2) -- Remove the last comma and newline.
    end
    output = output .. "\n}\n--- Copy the list above (including braces) into Config.Features.resourceVerification.whitelist ---"

    -- Send the formatted list to the admin's chat.
    TriggerClientEvent('chat:addMessage', source, { color = {0, 255, 0}, multiline = true, args = {"NexusGuard Resources", output} })
    -- Also print to server console for logging.
    print(("[NexusGuard] Generated resource list for admin %s (ID: %d):\n%s"):format(GetPlayerName(source), source, output))
end, true) -- `true` restricts the command to ACE principals with `command.nexusguard_getresources` permission (or admins if default ACE setup).

-- Command: /nexusguard_ban
-- Purpose: Allows admins to ban players directly via command.
-- Usage: /nexusguard_ban [target_player_id] [duration_seconds] [reason]
--        Duration 0 or omitted = permanent ban.
-- Access: Restricted to admins.
RegisterCommand('nexusguard_ban', function(sourceCmd, args, rawCommand)
    local adminSource = tonumber(sourceCmd)
    -- Disallow execution from server console.
    if adminSource == 0 then Log("The /nexusguard_ban command cannot be run from the server console.", 1); return end
    -- Check admin permissions.
    if not NexusGuardServer.Permissions or not NexusGuardServer.Permissions.IsAdmin or not NexusGuardServer.Permissions.IsAdmin(adminSource) then
        TriggerClientEvent('chat:addMessage', adminSource, { color = {255, 0, 0}, multiline = true, args = {"NexusGuard", "Permission denied."} })
        return
    end

    -- Parse arguments.
    local targetId = tonumber(args[1])
    local duration = tonumber(args[2]) or 0 -- Default to 0 (permanent) if not provided or invalid number.
    local reason = table.concat(args, " ", 3) or "Banned by Admin Command" -- Combine remaining args for reason.

    -- Validate target player ID.
    if not targetId or not GetPlayerName(targetId) then -- Check if ID is valid and player is online.
        TriggerClientEvent('chat:addMessage', adminSource, { color = {255, 200, 0}, multiline = true, args = {"NexusGuard", "Invalid or offline target player ID."} })
        return
    end

    local adminName = GetPlayerName(adminSource)
    Log(("^1[NexusGuard] Admin %s (ID: %d) is banning player ID %d (Duration: %ds, Reason: %s)^7"):format(adminName, adminSource, targetId, duration, reason), 1)

    -- Execute the ban using the Bans module via API.
    if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
        NexusGuardServer.Bans.Execute(targetId, reason, adminName, duration)
        -- Provide confirmation to the admin.
        TriggerClientEvent('chat:addMessage', adminSource, { color = {0, 255, 0}, multiline = true, args = {"NexusGuard", ("Ban command executed for player %s (ID: %d)."):format(GetPlayerName(targetId), targetId)} })
    else
        -- Handle error if ban function is missing from API.
        Log("^1[NexusGuard] CRITICAL: Bans.Execute function not found in API! Cannot execute ban command.^7", 1)
        TriggerClientEvent('chat:addMessage', adminSource, { color = {255, 0, 0}, multiline = true, args = {"NexusGuard", "Error: Ban function is unavailable."} })
    end
end, true) -- Restricted command.

-- Command: /nexusguard_unban
-- Purpose: Allows admins to remove bans based on player identifiers.
-- Usage: /nexusguard_unban [license|ip|discord] [identifier_value]
-- Access: Restricted to admins.
RegisterCommand('nexusguard_unban', function(sourceCmd, args, rawCommand)
    local adminSource = tonumber(sourceCmd)
    -- Disallow execution from server console.
    if adminSource == 0 then Log("The /nexusguard_unban command cannot be run from the server console.", 1); return end
    -- Check admin permissions.
    if not NexusGuardServer.Permissions or not NexusGuardServer.Permissions.IsAdmin or not NexusGuardServer.Permissions.IsAdmin(adminSource) then
        TriggerClientEvent('chat:addMessage', adminSource, { color = {255, 0, 0}, multiline = true, args = {"NexusGuard", "Permission denied."} })
        return
    end

    -- Parse arguments.
    local idType = args[1] -- Should be 'license', 'ip', or 'discord'.
    local idValue = args[2] -- The actual identifier string.

    -- Validate arguments.
    if not idType or not idValue or not table.find({"license", "ip", "discord"}, string.lower(idType)) then
        TriggerClientEvent('chat:addMessage', adminSource, { color = {255, 200, 0}, multiline = true, args = {"NexusGuard", "Usage: /nexusguard_unban [license|ip|discord] [identifier_value]"} })
        return
    end
    idType = string.lower(idType) -- Normalize type to lowercase.

    local adminName = GetPlayerName(adminSource)
    Log(("^2[NexusGuard] Admin %s (ID: %d) is attempting to unban identifier type '%s' with value '%s'^7"):format(adminName, adminSource, idType, idValue), 2)

    -- Execute the unban using the Bans module via API.
    if NexusGuardServer.Bans and NexusGuardServer.Bans.Unban then
        -- The Unban function is likely asynchronous (database operation).
        -- It should ideally return success status and a message.
        local success, message = NexusGuardServer.Bans.Unban(idType, idValue, adminName)
        local color = success and {0, 255, 0} or {255, 200, 0} -- Green for success, yellow/orange for failure/not found.
        -- Send feedback message to the admin. Use SetTimeout if Unban is async and doesn't have its own callback/feedback.
        -- SetTimeout(500, function() -- Example delay if needed
            TriggerClientEvent('chat:addMessage', adminSource, { color = color, multiline = true, args = {"NexusGuard", message or "Unban command processed."} })
        -- end)
    else
        -- Handle error if unban function is missing from API.
        Log("^1[NexusGuard] CRITICAL: Bans.Unban function not found in API! Cannot execute unban command.^7", 1)
        TriggerClientEvent('chat:addMessage', adminSource, { color = {255, 0, 0}, multiline = true, args = {"NexusGuard", "Error: Unban function is unavailable."} })
    end
end, true) -- Restricted command.
