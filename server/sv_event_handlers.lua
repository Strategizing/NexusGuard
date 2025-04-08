--[[
    NexusGuard Server-Side Event Handlers Module (server/sv_event_handlers.lua)

    Purpose:
    - Contains specific logic triggered by certain game events (e.g., `explosionEvent`)
      or custom NexusGuard actions (e.g., notifying admins).
    - Acts as a bridge between raw game events and the NexusGuard detection/action system.

    Dependencies:
    - Global `NexusGuardServer` API table (for Config, Utils, Detections, Discord, OnlineAdmins, Bans)
    - Global `EventRegistry` (for triggering client events like admin notifications)
    - `ox_lib` resource (for `lib.json`)

    Usage:
    - Required by `globals.lua` and exposed via the `NexusGuardServer.EventHandlers` API table.
    - Functions are typically called from `server_main.lua`'s event handlers or by other modules like Detections.
]]

local EventHandlers = {}

-- Attempt to get the NexusGuard Server API from globals.lua. Use pcall for safety.
local successAPI, NexusGuardServer = pcall(function() return exports['NexusGuard']:GetNexusGuardServerAPI() end)
if not successAPI or not NexusGuardServer then
    print("^1[NexusGuard EH] CRITICAL: Failed to get NexusGuardServer API. Event Handlers module functionality will be limited or fail.^7")
    -- Create a dummy API structure to prevent immediate errors.
    NexusGuardServer = NexusGuardServer or {
        Config = {},
        Utils = { Log = function(...) print("[NexusGuard EH Fallback Log]", ...) end },
        Detections = {}, Discord = {}, OnlineAdmins = {}, Bans = {}
    }
end

-- Local alias for the logging function.
local Log = NexusGuardServer.Utils.Log

--[[
    Handles the `explosionEvent` game event.
    Performs checks for blacklisted explosion types and explosion spam based on config settings.
    Processes detections via the Detections module API and potentially triggers bans/kicks.

    @param sender (string): The server ID of the player who potentially caused the explosion.
    @param ev (table): Data associated with the explosion event (type, position, etc.).
    @param session (table): The player's session data object (passed from server_main.lua).
]]
function EventHandlers.HandleExplosion(sender, ev, session)
    local source = tonumber(sender)
    -- Validate source ID and ensure session data (especially metrics) is available.
    if not source or source <= 0 or not session or not session.metrics then
        -- Log("^1[EH HandleExplosion] Invalid source or missing session/metrics for player %s.^7", 1, tostring(source)) -- Optional debug log
        return
    end

    -- Check if explosion checks are enabled in config via the API table.
    local explosionCheckCfg = NexusGuardServer.Config and NexusGuardServer.Config.ExplosionChecks
    if not explosionCheckCfg or not explosionCheckCfg.enabled then
        return -- Exit silently if checks are disabled.
    end

    -- Validate the structure of the event data.
    if not ev or ev.explosionType == nil or ev.posX == nil or ev.posY == nil or ev.posZ == nil then
        Log(("^1EH Warning: Received incomplete explosionEvent data from player %d.^7"):format(source), 1)
        return
    end

    local explosionType = ev.explosionType
    local position = vector3(ev.posX, ev.posY, ev.posZ) -- Create vector3 from coordinates.
    local currentTime = os.time() -- Use os.time for storing event time.
    local playerName = GetPlayerName(source) or ("Unknown (" .. source .. ")")

    -- Load configuration values for checks, providing defaults.
    local spamTimeWindow = explosionCheckCfg.spamTimeWindow or 10 -- Time window for spam check (seconds).
    local spamCountThreshold = explosionCheckCfg.spamCountThreshold or 5 -- Max explosions allowed in window.
    local spamDistanceThreshold = explosionCheckCfg.spamDistanceThreshold or 5.0 -- Max distance for grouping explosions in spam check (meters).
    local blacklistedTypes = explosionCheckCfg.blacklistedTypes or {} -- List of disallowed explosion type IDs.
    local kickOnBlacklisted = explosionCheckCfg.kickOnBlacklisted or false -- Kick immediately if blacklisted type used?
    local banOnBlacklisted = explosionCheckCfg.banOnBlacklisted or false -- Ban immediately if blacklisted type used?

    -- Build a set from the blacklist for efficient lookup.
    local blacklistedTypeSet = {}
    for _, typeId in ipairs(blacklistedTypes) do blacklistedTypeSet[typeId] = true end

    -- 1. Blacklist Check: Check if the triggered explosion type is disallowed.
    if blacklistedTypeSet[explosionType] then
        local reason = ("Triggered blacklisted explosion type: %d"):format(explosionType)
        Log(("^1[NexusGuard Server Check] Player %s (ID: %d) %s at %s^7"):format(playerName, source, reason, position), 1)

        -- Process this as a detection event via the Detections API.
        if NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
            NexusGuardServer.Detections.Process(source, "BlacklistedExplosion", { type = explosionType, position = position }, session)
        else Log("^1[NexusGuard EH] Detections.Process API function not found! Cannot process BlacklistedExplosion detection.^7", 1) end

        -- Apply immediate ban or kick if configured, using the Bans API.
        if banOnBlacklisted then
            Log(("^1[NexusGuard] Banning player %s (ID: %d) for using blacklisted explosion type %d.^7"):format(playerName, source, explosionType), 1)
            if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
                -- Provide a clear reason for the ban.
                NexusGuardServer.Bans.Execute(source, reason, "NexusGuard System (Blacklisted Explosion)")
            else Log("^1[NexusGuard EH] Bans.Execute API function not found! Cannot execute ban.^7", 1) end
            return -- Stop further processing if banned.
        elseif kickOnBlacklisted then
            Log(("^1[NexusGuard] Kicking player %s (ID: %d) for using blacklisted explosion type %d.^7"):format(playerName, source, explosionType), 1)
            local kickMsg = NexusGuardServer.Config.KickMessage or "Kicked for suspicious activity (Explosion Type)."
            DropPlayer(source, kickMsg)
            return -- Stop further processing if kicked.
        end
        -- If no immediate action, the spam check below might still catch repeated offenses.
    end

    -- 2. Spam Check: Track recent explosions to detect spamming.
    -- Initialize the explosions list in session metrics if it doesn't exist.
    if not session.metrics.explosions then session.metrics.explosions = {} end
    -- Add the current explosion details to the player's session metrics.
    table.insert(session.metrics.explosions, { type = explosionType, position = position, time = currentTime })

    local recentCount = 0             -- Count of explosions within the time window.
    local recentExplosionsInArea = {} -- List of recent explosions close to the current one.
    local tempExplosions = {}         -- New list to hold only explosions still within the time window.

    -- Iterate backwards through the stored explosions for efficiency.
    for i = #session.metrics.explosions, 1, -1 do
        local explosion = session.metrics.explosions[i]
        -- Check if the explosion occurred within the configured time window.
        if currentTime - explosion.time < spamTimeWindow then
            table.insert(tempExplosions, 1, explosion) -- Keep this explosion (insert at beginning to maintain order).
            recentCount = recentCount + 1
            -- Check if this recent explosion is close to the *current* explosion position.
            if #(position - explosion.position) < spamDistanceThreshold then
                table.insert(recentExplosionsInArea, explosion)
            end
        else
            -- Since explosions are ordered by time, we can stop checking once we find one outside the window.
            break
        end
    end
    -- Update the session metrics to only contain explosions within the time window.
    session.metrics.explosions = tempExplosions

    -- Trigger detection if the total recent count exceeds the threshold,
    -- OR if a significant number occurred very close together (indicating localized spam).
    local spamInAreaCount = #recentExplosionsInArea
    -- Example condition: Flag if total count > threshold OR count in small area > half the threshold.
    if recentCount > spamCountThreshold or spamInAreaCount > (spamCountThreshold / 2) then
        Log(string.format("^1[NexusGuard Server Check]^7 Explosion spam detected for %s (ID: %d). Count: %d in %ds. Count in area (<%.1fm): %d^7",
            playerName, source, recentCount, spamTimeWindow, spamDistanceThreshold, spamInAreaCount), 1)

        -- Process this as an "ExplosionSpam" detection event via the Detections API.
        if NexusGuardServer.Detections and NexusGuardServer.Detections.Process then
            NexusGuardServer.Detections.Process(source, "ExplosionSpam", {
                count = recentCount,
                period = spamTimeWindow,
                areaCount = spamInAreaCount,
                areaDistance = spamDistanceThreshold,
                lastType = explosionType,
                lastPosition = position
            }, session) -- Pass the full session object.
        else Log("^1[NexusGuard EH] Detections.Process API function not found! Cannot process ExplosionSpam detection.^7", 1) end
    end
end

--[[
    Placeholder function for handling entity creation events.
    WARNING: The `entityCreating` event can be heavily spammed and requires
             very careful filtering and implementation to avoid performance issues.
             It's generally recommended to use more specific events if possible.
    @param entity (number): The network ID of the entity being created.
]]
function EventHandlers.HandleEntityCreation(entity)
    -- Placeholder - Requires significant filtering and logic.
    -- Example: Check if entity type is disallowed, check creation rate, etc.
    -- local model = GetEntityModel(entity)
    -- local creator = NetworkGetEntityOwner(entity) -- May not be reliable immediately
    -- Log("Placeholder: HandleEntityCreation called for entity " .. entity .. " Model: " .. model, 4)
end

--[[
    Notifies all currently online admins about a specific detection event.
    Sends a client event ('ADMIN_NOTIFICATION') to each admin player.

    @param playerId (number): The server ID of the player who triggered the detection.
    @param detectionType (string): The type/name of the detection.
    @param detectionData (table): Specific details about the detection event.
]]
function EventHandlers.NotifyAdmins(playerId, detectionType, detectionData)
    local playerName = GetPlayerName(playerId) or ("Unknown (" .. tostring(playerId) .. ")")
    -- Ensure ox_lib JSON library is available for encoding data.
    if not lib or not lib.json then Log("^1[NexusGuard EH] ox_lib JSON library (lib.json) not available for NotifyAdmins. Cannot encode data.^7", 1); return end

    -- Safely encode the detection data for sending in the event.
    local dataString = "N/A"
    local successEncode, result = pcall(lib.json.encode, detectionData)
    if successEncode and type(result) == 'string' then
        dataString = result
    else
        Log(("^1[NexusGuard EH] Failed to encode detectionData for admin notification (Type: %s). Error: %s^7"):format(detectionType, tostring(result)), 1)
        -- Send a simplified version if encoding fails
        detectionData = { error = "Failed to encode details", originalType = detectionType }
    end

    -- Log the notification attempt to the server console.
    Log(('^1[NexusGuard Admin Notify]^7 Player: %s (ID: %d) - Type: %s - Data: %s^7'):format(playerName, playerId, detectionType, dataString), 1)

    -- Access the list of online admins from the NexusGuardServer API table.
    local onlineAdmins = NexusGuardServer.OnlineAdmins or {}
    local adminCount = 0
    for _ in pairs(onlineAdmins) do adminCount = adminCount + 1 end

    -- If no admins are online, log and exit.
    if adminCount == 0 then Log("^3[NexusGuard EH] No admins currently online to notify.^7", 3); return end

    Log(("^2[NexusGuard EH] Notifying %d online admin(s)...^7"):format(adminCount), 2)
    -- Iterate through the online admin IDs.
    for adminId, _ in pairs(onlineAdmins) do
        -- Check if the admin player is still online before sending the event.
        if GetPlayerName(adminId) then
             -- Ensure EventRegistry is available (should be global or required).
             local EventRegistry = _G.EventRegistry -- Assuming global access for simplicity here.
             if EventRegistry and EventRegistry.TriggerClientEvent then
                 -- Trigger the client event for the specific admin.
                 EventRegistry:TriggerClientEvent('ADMIN_NOTIFICATION', adminId, {
                    player = playerName,      -- Name of the player detected
                    playerId = playerId,      -- Server ID of the player detected
                    type = detectionType,     -- Type of detection
                    data = detectionData,     -- Original detection data table (or error placeholder)
                    timestamp = os.time()     -- Server timestamp of the notification
                 })
             else Log("^1[NexusGuard EH] EventRegistry or TriggerClientEvent not found. Cannot send admin notification event.^7", 1) end
        else
            -- If GetPlayerName returns nil, the admin likely disconnected. Remove them from the list.
            Log(("^3[NexusGuard EH] Admin ID %d seems to have disconnected. Removing from online list.^7"):format(adminId), 3)
            if NexusGuardServer.OnlineAdmins then NexusGuardServer.OnlineAdmins[adminId] = nil end
        end
    end
end

-- Export the EventHandlers table containing the functions.
return EventHandlers
