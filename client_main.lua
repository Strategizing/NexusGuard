--[[
    NexusGuard Client
    Advanced anti-cheat detection system for FiveM
    Version: 0.6.9
]]

-- Ensure JSON library is available (e.g., from oxmysql or another resource)
local json = json or _G.json

-- Load the Event Registry module
local EventRegistry = require('shared/event_registry')
if not EventRegistry then
    print("^1[NexusGuard] CRITICAL: Failed to load shared/event_registry.lua. Event handling will fail.^7")
    -- Optionally, add logic to prevent the rest of the script from running
end

-- Safer environment detection without potentially breaking Citizen
local isDebugEnvironment = type(Citizen) ~= "table" or type(Citizen.CreateThread) ~= "function"

    -- Debug compatibility layer
    if isDebugEnvironment then
        print("^3[DEBUG]^7 Debug environment detected, loading compatibility layer")

        -- Only create stubs if they don't exist
        RegisterNetEvent = RegisterNetEvent or function(eventName) return eventName end

        Citizen = Citizen or {
            CreateThread = function(callback)
                if type(callback) == "function" then callback() end
            end,
            Wait = function(ms) end
        }

        vector3 = vector3 or function(x, y, z)
            local v = {x = x or 0, y = y or 0, z = z or 0}
            -- Add metatable for vector operations and tostring
            return setmetatable(v, {
                __add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end,
                __sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end,
                __unm = function(a) return vector3(-a.x, -a.y, -a.z) end,
                __mul = function(a, b)
                    if type(a) == "number" then
                        return vector3(a * b.x, a * b.y, a * b.z)
                    elseif type(b) == "number" then
                        return vector3(a.x * b, a.y * b, a.z * b)
                    end
                end,
                __len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end,
                __tostring = function(a) return string.format("(%f, %f, %f)", a.x, a.y, a.z) end
            })
        end

        GetGameTimer = GetGameTimer or function() return math.floor(os.clock() * 1000) end
    end

    -- Register required events using the loaded EventRegistry module
    -- Note: onClientResourceStart is a built-in event, doesn't need registry
    if EventRegistry then
        -- Register server-sent events that this client needs to listen for
        EventRegistry:RegisterEvent('SECURITY_RECEIVE_TOKEN')
        EventRegistry:RegisterEvent('ADMIN_NOTIFICATION')
        EventRegistry:RegisterEvent('ADMIN_REQUEST_SCREENSHOT')
        EventRegistry:RegisterEvent('NEXUSGUARD_POSITION_UPDATE') -- Server -> Client position updates (if server sends them)
        EventRegistry:RegisterEvent('NEXUSGUARD_HEALTH_UPDATE') -- Server -> Client health updates (if server sends them)

        -- Register the local warning event name for consistency, though handled locally via AddEventHandler below
        -- We still use RegisterNetEvent here because it's triggered locally, not via the registry module's Trigger methods.
        local cheatWarningEventName = EventRegistry:GetEventName('NEXUSGUARD_CHEAT_WARNING')
        if cheatWarningEventName then
            RegisterNetEvent(cheatWarningEventName)
            print("^2[NexusGuard] Registered local event: " .. cheatWarningEventName .. "^7", 3)
        else
            print("^1[NexusGuard] CRITICAL: Could not get event name for NEXUSGUARD_CHEAT_WARNING from EventRegistry.^7")
        end
    else
        -- EventRegistry module failed to load earlier.
        print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot register required network events.^7")
    end

    --[[
        NexusGuard Core Class
        Central management for all anti-cheat functionality
    ]]
    local NexusGuard = {
        -- Security
        securityToken = nil,

        -- Module status tracking (potentially redundant if registry handles status)
        moduleStatus = {},

        -- Player state tracking (some state might move to specific detectors)
        state = {
            position = vector3(0, 0, 0),
            health = 100,
            armor = 0,
            lastPositionUpdate = GetGameTimer(),
            lastTeleport = GetGameTimer(),
            movementSamples = {},
            weaponStats = {}
        },

        -- Alert flags
        flags = {
            suspiciousActivity = false,
            warningIssued = false
        },

        -- Discord rich presence
        richPresence = {
            appId = nil,
            updateInterval = 60000,
            serverName = "Protected Server",
            lastUpdate = 0
        },

        -- Resource monitoring (state handled by detector)
        resources = {
            lastCheck = 0,
            whitelist = {}
        },

        -- System state
        initialized = false,
        -- Note: Version is defined in fxmanifest.lua

        -- List of detector files to load
        detectorFiles = {
            { name = "godmode", path = "client/detectors/godmode_detector.lua" },
            { name = "menudetection", path = "client/detectors/menudetection_detector.lua" },
            { name = "noclip", path = "client/detectors/noclip_detector.lua" },
            { name = "resourcemonitor", path = "client/detectors/resourcemonitor_detector.lua" },
            { name = "speedhack", path = "client/detectors/speedhack_detector.lua" },
            { name = "teleport", path = "client/detectors/teleport_detector.lua" },
            { name = "vehicle", path = "client/detectors/vehicle_detector.lua" },
            { name = "weaponmod", path = "client/detectors/weaponmod_detector.lua" },
            -- Add new detector entries here
        }
    }

    --[[
        Safe Detection Wrapper (Called by detector threads)
        Wraps detection methods with error handling to prevent crashes
        (Called by DetectorRegistry's CreateDetectorThread)
    ]]
    function NexusGuard:SafeDetect(detectionFn, detectionName)
        local success, err = pcall(detectionFn) -- Call the detector's Check function directly

        if not success then
            print("^1[NexusGuard]^7 Error in " .. detectionName .. " detection: " .. tostring(err))

            -- Report critical errors to server if they occur frequently
            if not self.errors then self.errors = {} end
            if not self.errors[detectionName] then
                self.errors[detectionName] = {count = 0, firstSeen = GetGameTimer()}
            end

            self.errors[detectionName].count = self.errors[detectionName].count + 1

            -- If errors persist, notify server
            if self.errors[detectionName].count > 5 and
               GetGameTimer() - self.errors[detectionName].firstSeen < 60000 then
                if self.securityToken then -- Check if token exists (should be a table now)
                    -- Use EventRegistry if available
                    if EventRegistry then
                        -- Send the error details and the security token table
                        EventRegistry:TriggerServerEvent('SYSTEM_ERROR', detectionName, tostring(err), self.securityToken)
                    else
                        -- TriggerServerEvent("NexusGuard:ClientError", detectionName, tostring(err), self.securityToken) -- Fallback removed
                        print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot report client error to server.^7")
                    end
                end

                -- Reset error counter to prevent spam
                self.errors[detectionName].count = 0
                self.errors[detectionName].firstSeen = GetGameTimer()
            end
        end
    end

    --[[
        Core Anti-Cheat Initialization
    ]]
    function NexusGuard:Initialize()
        -- Prevent duplicate initialization
        if self.initialized then return end

        Citizen.CreateThread(function()
            -- Wait for scripts to load (Config, Registry etc.)
            Citizen.Wait(1000)

            -- Wait for network session to become active
            local sessionStartTime = GetGameTimer()
            local timeout = 30000 -- 30 second timeout

            while not NetworkIsSessionActive() do
                Citizen.Wait(100)
                -- Check for timeout
                if GetGameTimer() - sessionStartTime > timeout then
                    print("^1[NexusGuard]^7 Warning: NetworkIsSessionActive() timed out")
                    break
                end
            end

            print('^2[NexusGuard]^7 Initializing protection system...')

            -- Generate unique client hash for verification (Note: This hash isn't securely validated currently)
            local clientHash = GetCurrentResourceName() .. "-" .. math.random(100000, 999999)

            -- Request security token from server
            if EventRegistry then
                EventRegistry:TriggerServerEvent('SECURITY_REQUEST_TOKEN', clientHash)
            else
                -- TriggerServerEvent('NexusGuard:RequestSecurityToken', clientHash) -- Fallback removed
                print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot request security token.^7")
            end

            -- Allow time for token receipt
            Citizen.Wait(2000)

            -- Start auxiliary protection modules (like Rich Presence)
            self:StartProtectionModules()

            -- Load and start detectors directly
            self:StartDetectors()

            -- Start periodic position and health update thread
            Citizen.CreateThread(function()
                local positionUpdateInterval = 5000 -- ms (e.g., every 5 seconds)
                while true do
                    Citizen.Wait(positionUpdateInterval)
                    -- Only send updates if initialized and token is valid
                    if self.initialized and self.securityToken and type(self.securityToken) == "table" then
                        self:SendPositionUpdate()
                        self:SendHealthUpdate() -- Add health update call
                    end
                end
            end)
            print('^2[NexusGuard]^7 Position update thread started.')

            self.initialized = true
            print('^2[NexusGuard]^7 Core protection system initialized')
        end) -- Add missing end for Citizen.CreateThread
    end

    --[[
        Load and Start Detectors
        Loads detector files, initializes them, and starts enabled ones.
    ]]
    function NexusGuard:StartDetectors()
        print("^2[NexusGuard]^7 Loading and starting detectors...")
        if not Config or not Config.Detectors then
            print("^1[NexusGuard] CRITICAL: Config.Detectors not found. Cannot start detectors.^7")
            return
        end

        for _, fileInfo in ipairs(self.detectorFiles) do
            local detectorName = fileInfo.name
            local filePath = fileInfo.path
            local isEnabled = Config.Detectors[detectorName]

            if isEnabled == nil then
                print("^3[NexusGuard] Warning: Detector '" .. detectorName .. "' not found in Config.Detectors. Assuming disabled.^7")
                isEnabled = false
            end

            if isEnabled then
                print("^2[NexusGuard]^7 Loading detector: " .. detectorName .. " from " .. filePath)
                local success, detectorModule = pcall(require, filePath)

                if success and type(detectorModule) == "table" then
                    -- Initialize the detector, passing the NexusGuard instance
                    if detectorModule.Initialize and type(detectorModule.Initialize) == "function" then
                        local initSuccess, initErr = pcall(detectorModule.Initialize, self)
                        if not initSuccess then
                            print("^1[NexusGuard] Error initializing detector '" .. detectorName .. "': " .. tostring(initErr) .. "^7")
                            goto continue -- Skip starting if init failed
                        end
                    else
                        print("^3[NexusGuard] Warning: Detector '" .. detectorName .. "' is missing an Initialize function.^7")
                    end

                    -- Start the detector's main loop/thread
                    if detectorModule.Start and type(detectorModule.Start) == "function" then
                         local startSuccess, startErr = pcall(detectorModule.Start) -- Start should create its own thread
                         if not startSuccess then
                             print("^1[NexusGuard] Error starting detector '" .. detectorName .. "': " .. tostring(startErr) .. "^7")
                         else
                             print("^2[NexusGuard]^7 Detector '" .. detectorName .. "' started.")
                         end
                    else
                        print("^1[NexusGuard] Error: Enabled detector '" .. detectorName .. "' is missing a Start function. Cannot activate.^7")
                    end
                elseif not success then
                    print("^1[NexusGuard] CRITICAL Error loading detector file '" .. filePath .. "': " .. tostring(detectorModule) .. "^7")
                else
                    print("^1[NexusGuard] CRITICAL Error: Detector file '" .. filePath .. "' did not return a table.^7")
                end
            else
                 print("^3[NexusGuard]^7 Detector '" .. detectorName .. "' disabled in config.")
            end
            ::continue:: -- Lua goto label for skipping
            Citizen.Wait(50) -- Small delay between loading detectors
        end
        print("^2[NexusGuard]^7 Detector loading and starting process complete.")
    end

    --[[
        Protection Module Management
        Initializes features like Rich Presence.
    ]]
    function NexusGuard:StartProtectionModules()
        print("^2[NexusGuard]^7 Starting auxiliary modules (e.g., Rich Presence)...")
        self:InitializeRichPresence()
        -- Other non-detector modules could be started here
        print("^2[NexusGuard]^7 Auxiliary modules initialization process completed.")
    end


    --[[
        Rich Presence Management
        Handles Discord integration
    ]]
    function NexusGuard:InitializeRichPresence()
        -- Ensure Config and necessary sub-tables exist
        if not Config or not Config.Discord or not Config.Discord.RichPresence then
            print("^3[NexusGuard] Rich Presence configuration missing or incomplete. Skipping initialization.^7")
            return
        end

        local rpConfig = Config.Discord.RichPresence
        if not rpConfig.Enabled then
            print("^3[NexusGuard] Rich Presence disabled in config.^7")
            return
        end

        if not rpConfig.AppId or rpConfig.AppId == "" or rpConfig.AppId == "1234567890" then
            print("^1[NexusGuard] Rich Presence enabled but AppId is missing, empty, or default in config. Rich Presence will not function.^7")
            return -- Don't start update thread if AppId is invalid
        end

        -- Set AppId only if valid
        SetDiscordAppId(rpConfig.AppId)
        print("^2[NexusGuard] Rich Presence AppId set: " .. rpConfig.AppId .. "^7")

        -- Set up presence update thread
        Citizen.CreateThread(function()
            while true do
                -- Check config again inside loop in case it changes dynamically or resource restarts
                local currentRpConfig = Config and Config.Discord and Config.Discord.RichPresence
                -- Also check if AppId is still valid (in case config was reloaded badly)
                if not currentRpConfig or not currentRpConfig.Enabled or not currentRpConfig.AppId or currentRpConfig.AppId == "" or currentRpConfig.AppId == "1234567890" then
                    print("^3[NexusGuard] Rich Presence disabled or AppId invalid, stopping update thread.^7")
                    ClearDiscordPresence() -- Clear presence if disabled
                    break -- Exit the loop
                end

                -- Update presence only if enabled and AppId is valid
                self:UpdateRichPresence()
                local interval = (currentRpConfig.UpdateInterval or 60) * 1000
                Citizen.Wait(interval)
            end
        end)
        print("^2[NexusGuard] Rich Presence update thread started.^7")
    end

    --[[
        Update Rich Presence
        Updates Discord status with player info
    ]]
    function NexusGuard:UpdateRichPresence()
        -- Re-check config validity within the update function itself
        if not Config or not Config.Discord or not Config.Discord.RichPresence then return end
        local rpConfig = Config.Discord.RichPresence
        if not rpConfig.Enabled or not rpConfig.AppId or rpConfig.AppId == "" or rpConfig.AppId == "1234567890" then return end

        -- Clear previous actions before setting new ones
        ClearDiscordPresenceAction(0)
        ClearDiscordPresenceAction(1)

        -- Set rich presence assets if configured
        if rpConfig.largeImageKey and rpConfig.largeImageKey ~= "" then
            SetDiscordRichPresenceAsset(rpConfig.largeImageKey)
            SetDiscordRichPresenceAssetText(rpConfig.LargeImageText or "") -- Use configured text or empty string
        else
            ClearDiscordRichPresenceAsset() -- Clear asset if not configured
        end
        if rpConfig.smallImageKey and rpConfig.smallImageKey ~= "" then
            SetDiscordRichPresenceAssetSmall(rpConfig.smallImageKey)
            SetDiscordRichPresenceAssetSmallText(rpConfig.SmallImageText or "") -- Use configured text or empty string
        else
            ClearDiscordRichPresenceAssetSmall() -- Clear small asset if not configured
        end

        -- Set action buttons
        if rpConfig.buttons then
            for i, button in ipairs(rpConfig.buttons) do
                if button.label and button.label ~= "" and button.url and button.url ~= "" and i <= 2 then -- Discord allows max 2 buttons
                    SetDiscordRichPresenceAction(i - 1, button.label, button.url)
                end
            end
        end

        -- Set rich presence text
        local playerName = GetPlayerName(PlayerId())
        local serverId = GetPlayerServerId(PlayerId())
        local ped = PlayerPedId()
        local health = GetEntityHealth(ped) - 100 -- Assuming 100 is base health
        if health < 0 then health = 0 end

        local coords = GetEntityCoords(ped)
        local streetHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
        local streetName = (streetHash ~= 0 and GetStreetNameFromHashKey(streetHash)) or "Unknown Location"

        -- Format presence text (Example - Consider making this configurable)
        local details = string.format("ID: %s | HP: %s%%", serverId, health) -- Top line
        local state = string.format("%s | %s", playerName, streetName) -- Bottom line

        -- Use SetDiscordRichPresence() for details and SetDiscordRichPresenceState() for state
        SetDiscordRichPresence(details)
        SetDiscordRichPresenceState(state)
    end

    --[[
        Send Position Update
        Sends current player position to the server for validation
    ]]
    function NexusGuard:SendPositionUpdate()
        -- Skip if not initialized or no security token
        if not self.initialized or not self.securityToken or type(self.securityToken) ~= "table" then
            -- print("^3[NexusGuard] SendPositionUpdate skipped: Not initialized or no valid security token.^7") -- Reduce log spam
            return
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then return end

        local currentPos = GetEntityCoords(ped)
        local currentTimestamp = GetGameTimer() -- Use game timer for consistency

        -- Send position data and token table to server
        if EventRegistry then
            -- NOTE: The event key 'NEXUSGUARD_POSITION_UPDATE' was potentially ambiguous.
            -- In event_registry.lua, it's now mapped to 'server:positionUpdate' assuming it's data *sent to* the server.
            -- If this event is meant to be received *from* the server, the key/handler needs adjustment.
            -- Assuming it's Client -> Server for now based on function name "SendPositionUpdate".
            EventRegistry:TriggerServerEvent('NEXUSGUARD_POSITION_UPDATE', currentPos, currentTimestamp, self.securityToken)
        else
            print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot send position update to server.^7")
        end
    end

    --[[
        Send Health Update
        Sends current player health and armor to the server for validation
    ]]
    function NexusGuard:SendHealthUpdate()
        -- Skip if not initialized or no security token
        if not self.initialized or not self.securityToken or type(self.securityToken) ~= "table" then
            return
        end

        local ped = PlayerPedId()
        if not DoesEntityExist(ped) then return end

        local currentHealth = GetEntityHealth(ped)
        local currentArmor = GetPedArmour(ped)
        local currentTimestamp = GetGameTimer()

        -- Send health/armor data and token table to server
        if EventRegistry then
            -- Similar note as Position Update: Assuming Client -> Server based on function name.
            EventRegistry:TriggerServerEvent('NEXUSGUARD_HEALTH_UPDATE', currentHealth, currentArmor, currentTimestamp, self.securityToken)
        else
            print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot send health update to server.^7")
        end
    end

    --[[
        Cheat Reporting (Called by Detectors)
        Sends detection info to server
    ]]
    function NexusGuard:ReportCheat(type, details)
        -- Skip if not initialized or no security token (token should be a table)
        if not self.initialized or not self.securityToken or type(self.securityToken) ~= "table" then
            print("^3[NexusGuard] ReportCheat skipped: Not initialized or no valid security token.^7")
            return
        end

        -- First detection issues a local warning
        if not self.flags.warningIssued then
            self.flags.suspiciousActivity = true
            self.flags.warningIssued = true
            -- Trigger local warning event using the name from the registry
            local cheatWarningEventName = EventRegistry and EventRegistry:GetEventName('NEXUSGUARD_CHEAT_WARNING')
            if cheatWarningEventName then
                TriggerEvent(cheatWarningEventName, type, details)
            else
                print("^1[NexusGuard] CRITICAL: Could not get event name for NEXUSGUARD_CHEAT_WARNING. Cannot trigger local warning.^7")
                -- Fallback to old name if absolutely necessary, but indicates registry issue
                TriggerEvent("NexusGuard:CheatWarning", type, details)
            end
        else
            -- Report subsequent detections to server, sending the token table
            if EventRegistry then
                EventRegistry:TriggerServerEvent('DETECTION_REPORT', type, details, self.securityToken)
            else
                -- EventRegistry is required for server communication.
                print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot report detection to server.^7")
            end
        end
    end

    --[[
        Event Handlers
    ]]
    -- Use EventRegistry for handlers where possible
    local receiveTokenEvent = (EventRegistry and EventRegistry:GetEventName('SECURITY_RECEIVE_TOKEN')) -- Use local variable and colon syntax
    if receiveTokenEvent then
        AddEventHandler(receiveTokenEvent, function(tokenData)
            -- Expecting a table { timestamp = ..., signature = ... }
            if not tokenData or type(tokenData) ~= "table" or not tokenData.timestamp or not tokenData.signature then
                print("^1[NexusGuard] Received invalid security token data structure from server.^7")
                -- Consider requesting again or handling error
                return
            end
            NexusGuard.securityToken = tokenData -- Store the entire table
            print("^2[NexusGuard] Security handshake completed via " .. receiveTokenEvent .. "^7")
        end)
    else
        -- This error should ideally be caught earlier if EventRegistry failed to load
        if EventRegistry then
             print("^1[NexusGuard] CRITICAL: Could not get event name for SECURITY_RECEIVE_TOKEN from EventRegistry.^7")
        else
             print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded, cannot register SECURITY_RECEIVE_TOKEN handler.^7")
        end
    end

    -- Handler for the local warning event (uses name retrieved from registry)
    local cheatWarningEventName = EventRegistry and EventRegistry:GetEventName('NEXUSGUARD_CHEAT_WARNING') or "NexusGuard:CheatWarning" -- Fallback name if registry failed
    AddEventHandler(cheatWarningEventName, function(type, details)
        -- Use chat resource if available and configured
        if Config and Config.Actions and Config.Actions.notifyPlayer and exports.chat then
            -- Ensure details is a string or convert it safely
            local detailStr = type(details) == "table" and (json and json.encode(details) or "details") or tostring(details or "details")
            exports.chat:addMessage({
                color = { 255, 0, 0 }, -- Red
                multiline = true,
                args = {
                    "[NexusGuard Warning]",
                    "Suspicious activity detected! Type: ^*" .. type .. "^r. Details: ^*" .. detailStr .. "^r. Further violations may result in action."
                }
            })
        elseif Config and Config.Actions and Config.Actions.notifyPlayer then
            -- Fallback print if chat resource isn't available but notification is enabled
            print("^1[NexusGuard Warning] Suspicious activity detected! Type: " .. type .. ". Further violations may result in action.^7")
        end
        -- Note: This warning is purely client-side informational based on the first ReportCheat call.
    end)

    -- Handler for screenshot request from server
    local requestScreenshotEvent = (EventRegistry and EventRegistry:GetEventName('ADMIN_REQUEST_SCREENSHOT')) or "nexusguard:requestScreenshot" -- Fallback name if registry failed
    AddEventHandler(requestScreenshotEvent, function()
        if not NexusGuard.initialized then print("^3[NexusGuard] Screenshot requested but core is not initialized.^7") return end

        -- Check if screenshot feature and dependency are enabled/available
        if not Config or not Config.ScreenCapture or not Config.ScreenCapture.enabled then
            print("^3[NexusGuard] Screenshot requested but feature is disabled in config.^7")
            return
        end
        if not exports['screenshot-basic'] then
            print("^1[NexusGuard] Screenshot requested but 'screenshot-basic' resource/export not found. Ensure it's started.^7")
            return
        end

        -- Ensure webhookURL is configured
        local webhookURL = Config.ScreenCapture.webhookURL
        if not webhookURL or webhookURL == "" then
            print("^1[NexusGuard] Screenshot requested but Config.ScreenCapture.webhookURL is not configured.^7")
            return
        end

        -- Take screenshot and send to webhook
        exports['screenshot-basic']:requestScreenshotUpload(
            webhookURL,
            'files[]', -- Standard field name for screenshot-basic uploads
            function(data)
                if not data then
                    print("^1[NexusGuard] Screenshot upload failed (no data returned). Check webhook URL and resource status.^7")
                    return
                end

                -- Ensure JSON library is available for decoding the response
                if not json then
                    print("^1[NexusGuard] JSON library not available for screenshot callback. Cannot process response.^7")
                    return
                end

                local success, resp = pcall(json.decode, data)
                if success and resp and resp.attachments and resp.attachments[1] and resp.attachments[1].url then
                    local screenshotUrl = resp.attachments[1].url
                    print("^2[NexusGuard] Screenshot uploaded successfully: " .. screenshotUrl .. "^7")
                    -- Report screenshot taken back to server, sending the token table
                    if EventRegistry then
                        EventRegistry:TriggerServerEvent('ADMIN_SCREENSHOT_TAKEN', screenshotUrl, NexusGuard.securityToken)
                    else
                        print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot report screenshot taken to server.^7")
                    end
                else
                    -- Log the raw response if decoding fails or structure is unexpected
                    print("^1[NexusGuard] Failed to decode screenshot response or response structure invalid. Raw response: " .. tostring(data) .. "^7")
                    -- Optionally report failure back to server
                    -- TriggerServerEvent('nexusguard:screenshotFailed', NexusGuard.securityToken)
                end
            end
        )
        print("^2[NexusGuard] Screenshot requested and upload initiated.^7")
    end)

    -- Initialize on resource start
    AddEventHandler('onClientResourceStart', function(resourceName)
        if GetCurrentResourceName() ~= resourceName then return end
        -- Allow Config and other shared scripts to load first
        Citizen.Wait(500)
        NexusGuard:Initialize()
        -- NexusGuard.RegisterDetectors() -- This function is replaced by StartDetectors called within Initialize
    end)
