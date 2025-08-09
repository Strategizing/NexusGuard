--[[
    NexusGuard Client Main Entry Point (client_main.lua)

    This script serves as the primary client-side controller for NexusGuard.
    Responsibilities include:
    - Initializing the core NexusGuard logic and state.
    - Loading and managing individual detection modules (detectors).
    - Handling communication with the server via the EventRegistry.
    - Managing client-side features like Discord Rich Presence.
    - Providing core functions used by detectors (e.g., ReportCheat, SafeDetect).
    - Setting up basic event handlers for server communication (token, screenshots).
]]

-- Lua/FiveM Standard Libraries & Globals
-- Access PlayerPedId(), GetEntityCoords(), etc.

-- External Dependencies (Ensure these resources are started before NexusGuard)
-- - ox_lib: Provides utility functions, including JSON handling (lib.json) and crypto (lib.crypto).
-- - oxmysql: (Dependency is server-side, but mentioned for context).
-- - screenshot-basic: Used for the optional screenshot feature.

-- NexusGuard Shared Modules
local EventRegistry = require('shared/event_registry') -- Handles standardized network event names.
-- REMOVED DUPLICATE REQUIRE
if not EventRegistry then
    print("^1[NexusGuard] CRITICAL: Failed to load shared/event_registry.lua. Network event handling will fail.^7")
    -- Consider adding logic here to halt initialization if EventRegistry is crucial and missing.
end

-- Detector Registry Module
local DetectorRegistry = require('shared/detector_registry')
if not DetectorRegistry then
    print("^1[NexusGuard] CRITICAL: Failed to load shared/detector_registry.lua. Detector management will fail.^7")
    -- Consider halting initialization if the registry is crucial.
end


-- Environment Check & Debug Compatibility
-- Attempts to detect if running outside a standard FiveM client environment (e.g., for testing).
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

        -- Register the local warning event name for consistency.
        -- Although triggered locally via TriggerEvent, we register it using RegisterNetEvent
        -- to ensure the AddEventHandler later in this script can catch it.
        local cheatWarningEventName = EventRegistry:GetEventName('NEXUSGUARD_CHEAT_WARNING')
        if cheatWarningEventName then
            RegisterNetEvent(cheatWarningEventName) -- Standard FiveM event registration for local events.
            print("^2[NexusGuard] Registered local event handler target: " .. cheatWarningEventName .. "^7", 3)
        else
            print("^1[NexusGuard] CRITICAL: Could not get event name for NEXUSGUARD_CHEAT_WARNING from EventRegistry.^7")
        end
    else
        -- EventRegistry module failed to load earlier.
        print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot register required network events.^7")
    end

    --[[
        NexusGuard Core Class
        Central management for client-side anti-cheat functionality.
    ]]
    local NexusGuardInstance = {
        -- Security Token: Received from the server for validating client->server communication.
        -- Expected format: { timestamp = ..., signature = ... }
        securityToken = nil,

        -- Player state tracking (some basic state, more complex state often managed by specific detectors)
        state = {
            lastPosition = vector3(0, 0, 0), -- Store the last known position
            lastHealth = 100, -- Store last known health
            armor = 0,
            lastPositionUpdate = GetGameTimer(), -- Timestamp of the last position update sent/checked
            lastHealthUpdate = GetGameTimer(), -- Timestamp of the last health update sent/checked
            lastTeleportCheck = GetGameTimer(), -- Timestamp for teleport detection cooldown/logic
            -- movementSamples = {}, -- Example: Could be used by speedhack detector
            -- weaponStats = {} -- Example: Could be used by weapon mod detector
        },

        -- Alert Flags: Simple flags for managing warning states.
        flags = {
            suspiciousActivity = false, -- General flag, potentially set by various detectors
            warningIssued = false       -- Tracks if the initial local warning has been shown
        },

        -- Discord Rich Presence State (if enabled in config.lua)
        richPresence = {
            appId = nil,            -- Set from Config.Discord.RichPresence.AppId
            updateInterval = 60000, -- Default update interval (ms), configurable
            serverName = "Protected Server", -- Default server name, potentially configurable
            lastUpdate = 0          -- Timestamp of the last presence update
        },

        -- Resource monitoring state is typically handled within its specific detector
        -- resources = { ... }, -- Removed from core state

        -- System State
        initialized = false, -- Flag to indicate if NexusGuard core has finished initializing
        -- Note: Version is defined in fxmanifest.lua and is the source of truth.

        -- List of detector files to load
        detectorFiles = {
            -- Format: { name = "unique_detector_key", path = "path/to/detector.lua" }
            -- The 'name' must match the key used in Config.Detectors in config.lua to enable/disable it.
            { name = "godmode", path = "client/detectors/godmode_detector.lua" },
            { name = "menudetection", path = "client/detectors/menudetection_detector.lua" },
            { name = "noclip", path = "client/detectors/noclip_detector.lua" },
            { name = "resourcemonitor", path = "client/detectors/resourcemonitor_detector.lua" },
            { name = "speedhack", path = "client/detectors/speedhack_detector.lua" },
            { name = "teleport", path = "client/detectors/teleport_detector.lua" },
            { name = "vehicle", path = "client/detectors/vehicle_detector.lua" },
            { name = "weaponmod", path = "client/detectors/weaponmod_detector.lua" },
            -- To add a new detector:
            -- 1. Create the Lua file (e.g., client/detectors/my_detector.lua) following the template.
            -- 2. Add an entry here: { name = "mydetector", path = "client/detectors/my_detector.lua" }
            -- 3. Add `Config.Detectors.mydetector = true` (or false) to config.lua.
        }
    }
    -- Instance is intentionally not assigned to a global; detectors receive it during Initialize.

    --[[
        Safe Detection Wrapper (Called by detector threads)
        Wraps individual detector checks (`Detector.Check()`) with pcall for error handling.
        Prevents a single faulty detector from crashing the entire client script.
        This function is typically called by the DetectorRegistry when running detector threads.
    ]]
    function NexusGuardInstance:SafeDetect(detectionFn, detectionName)
        -- pcall (protected call) executes the function `detectionFn`.
        -- If `detectionFn` runs without errors, `success` is true, and `err` is the return value(s).
        -- If `detectionFn` errors, `success` is false, and `err` is the error message.
        local success, err = pcall(detectionFn)

        if not success then
            print(("^1[NexusGuard] Error executing detector '%s': %s^7"):format(detectionName, tostring(err)))

            -- Basic error throttling: Report persistent errors to the server.
            if not self.errors then self.errors = {} end -- Initialize error tracking table if needed
            local errorInfo = self.errors[detectionName] or { count = 0, firstSeen = GetGameTimer() }
            self.errors[detectionName] = errorInfo -- Store back in case it was newly created

            errorInfo.count = errorInfo.count + 1

            -- If more than 5 errors occur within 60 seconds for the same detector, report to server.
            local errorThreshold = 5
            local errorTimeWindow = 60000 -- milliseconds
            if errorInfo.count > errorThreshold and (GetGameTimer() - errorInfo.firstSeen < errorTimeWindow) then
                print(("^1[NexusGuard] Detector '%s' is persistently failing. Reporting error to server.^7"):format(detectionName))
                if self.securityToken then -- Ensure we have a token to send
                    if EventRegistry then
                        -- Send the error details along with the security token for validation server-side.
                        EventRegistry:TriggerServerEvent('SYSTEM_ERROR', detectionName, tostring(err), self.securityToken)
                    else
                        print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot report client error to server.^7")
                    end
                else
                    print("^3[NexusGuard] Warning: Cannot report persistent detector error to server - security token not yet received.^7")
                end

                -- Reset error counter after reporting to prevent spamming the server.
                errorInfo.count = 0
                errorInfo.firstSeen = GetGameTimer() -- Reset timestamp as well
            elseif GetGameTimer() - errorInfo.firstSeen >= errorTimeWindow then
                 -- Reset count if the time window has passed since the first error in the current batch
                 errorInfo.count = 1
                 errorInfo.firstSeen = GetGameTimer()
            end
        end
    end

    --[[
        Core Anti-Cheat Initialization Function
        Called once when the resource starts (via onClientResourceStart handler).
        Sets up essential components and starts detection loops.
    ]]
    function NexusGuardInstance:Initialize()
        -- Prevent duplicate initialization if the resource is restarted without a full client rejoin.
        if self.initialized then
            print("^3[NexusGuard] Initialization skipped: Already initialized.^7")
            return
        end

        Citizen.CreateThread(function()
            -- Initial delay to allow other resources and shared scripts (like config.lua) to load.
            Citizen.Wait(1000)

            -- Ensure the player's network session is active before proceeding.
            -- This is important for reliable communication with the server.
            print("^2[NexusGuard]^7 Waiting for network session to become active...")
            local sessionStartTime = GetGameTimer()
            local networkTimeout = 30000 -- 30 seconds timeout

            while not NetworkIsSessionActive() do
                Citizen.Wait(100)
                -- Check for timeout to prevent infinite loop if session never activates.
                if GetGameTimer() - sessionStartTime > networkTimeout then
                    print("^1[NexusGuard]^7 Warning: NetworkIsSessionActive() timed out after %dms. Proceeding with initialization, but server communication might fail.^7"):format(networkTimeout)
                    break
                end
            end
            print('^2[NexusGuard]^7 Network session active or timed out. Proceeding...')

            print('^2[NexusGuard]^7 Initializing core protection system...')

            -- Request the security token from the server. This is crucial for validating subsequent client->server events.
            print("^2[NexusGuard]^7 Requesting security token from server...")
            if EventRegistry then
                -- Note: The clientHash sent here is currently basic and not cryptographically secure for client identification.
                -- A more robust system might involve server-generated challenges.
                local clientHash = GetCurrentResourceName() .. "-" .. math.random(100000, 999999)
                EventRegistry:TriggerServerEvent('SECURITY_REQUEST_TOKEN', clientHash)
            else
                print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot request security token.^7")
                -- Initialization might need to halt here if the token is absolutely required early on.
            end

            -- Allow some time for the server to respond with the token.
            -- A more robust approach would wait for the token event handler to set a flag.
            Citizen.Wait(2000)
            if not self.securityToken then
                 print("^3[NexusGuard] Warning: Security token not received after initial wait. Detectors relying on it might fail initially.^7")
            end

            -- Start auxiliary protection modules (e.g., Rich Presence).
            self:StartProtectionModules()

            -- Pass the NexusGuard instance to the DetectorRegistry
            if DetectorRegistry and DetectorRegistry.SetNexusGuardInstance then
                DetectorRegistry:SetNexusGuardInstance(self)
            else
                print("^1[NexusGuard] CRITICAL: DetectorRegistry or SetNexusGuardInstance function not found. Cannot initialize detectors.^7")
            end

            -- Load and start individual detectors based on config.lua settings using the registry module.
            if DetectorRegistry and DetectorRegistry.StartEnabledDetectors then
                DetectorRegistry:StartEnabledDetectors()
            else
                 print("^1[NexusGuard] CRITICAL: DetectorRegistry or StartEnabledDetectors function not found. Cannot start detectors.^7")
            end

            -- Start a periodic thread to send position and health updates to the server.
            Citizen.CreateThread(function()
                -- Use configurable interval, default to 5000ms if not set in Config.Client
                local updateInterval = (Config and Config.Client and Config.Client.PositionUpdateInterval) or 5000
                print('^2[NexusGuard]^7 Position/Health update interval set to: %dms.^7'):format(updateInterval)
                while true do
                    Citizen.Wait(updateInterval)
                    -- Only send updates if core is initialized and we have a valid security token.
                    if self.initialized and self.securityToken and type(self.securityToken) == "table" then
                        self:SendPositionUpdate()
                        self:SendHealthUpdate()
                    end
                end
            end)
            print('^2[NexusGuard]^7 Periodic position/health update thread started.')

            -- Mark initialization as complete.
            self.initialized = true
            print('^2[NexusGuard]^7 Core protection system initialization complete.')
        end)
    end

    --[[
        Load and Start Detectors Function
        Iterates through `self.detectorFiles`, requires the Lua file for enabled detectors,
        registers them with the DetectorRegistry, initializes them, and calls their Start function.
    ]]
    function NexusGuardInstance:StartDetectors()
        print("^2[NexusGuard]^7 Loading and starting detectors...")
        -- Ensure Config table and Config.Detectors sub-table exist.
        if not Config or not Config.Detectors then
            print("^1[NexusGuard] CRITICAL: Config.Detectors table not found in config.lua. Cannot start detectors.^7")
            return
        end

        for _, fileInfo in ipairs(self.detectorFiles) do
            local detectorName = fileInfo.name
            local filePath = fileInfo.path
            -- Check if the detector is explicitly enabled in config.lua.
            local isEnabled = Config.Detectors[detectorName]

            -- Handle cases where a detector listed in detectorFiles is missing from Config.Detectors.
            if isEnabled == nil then
                print(("^3[NexusGuard] Warning: Detector '%s' not found in Config.Detectors. Assuming disabled.^7"):format(detectorName))
                isEnabled = false
            end

            if isEnabled then
                print(("^2[NexusGuard]^7 Loading detector: '%s' from %s^7"):format(detectorName, filePath))
                -- Use pcall to safely require the detector file.
                local success, detectorModule = pcall(require, filePath)

                if success and type(detectorModule) == "table" then
                    -- Register the loaded detector module with the DetectorRegistry module.
                    if DetectorRegistry and type(DetectorRegistry.Register) == "function" then
                        local regSuccess, regErr = pcall(DetectorRegistry.Register, detectorName, detectorModule)
                        if not regSuccess then
                             print(("^1[NexusGuard] Error registering detector '%s' with registry: %s^7"):format(detectorName, tostring(regErr)))
                             goto continue -- Skip this detector if registration fails.
                        else
                             print(("^2[NexusGuard]^7 Detector '%s' registered successfully.^7"):format(detectorName))
                        end
                    else
                        print(("^1[NexusGuard] CRITICAL: DetectorRegistry module or its Register function not found. Cannot register detector '%s'.^7"):format(detectorName))
                        goto continue -- Skip if registry is unavailable.
                    end

                    -- Call the detector's Initialize function if it exists.
                    -- Pass the core NexusGuard instance (self) and the EventRegistry for the detector to use.
                    if detectorModule.Initialize and type(detectorModule.Initialize) == "function" then
                        local initSuccess, initErr = pcall(detectorModule.Initialize, self, EventRegistry)
                        if not initSuccess then
                            print(("^1[NexusGuard] Error initializing detector '%s': %s^7"):format(detectorName, tostring(initErr)))
                            -- Consider unregistering or marking as failed if init fails?
                            goto continue -- Skip starting if initialization failed.
                        end
                    else
                        print(("^3[NexusGuard] Warning: Detector '%s' is missing an Initialize function.^7"):format(detectorName))
                    end

                    -- Call the detector's Start function if it exists.
                    -- This might initiate the detector's main loop or set up its event handlers via the DetectorRegistry.
                    if detectorModule.Start and type(detectorModule.Start) == "function" then
                         local startSuccess, startErr = pcall(detectorModule.Start)
                         if not startSuccess then
                             print(("^1[NexusGuard] Error calling Start for detector '%s': %s^7"):format(detectorName, tostring(startErr)))
                         else
                             print(("^2[NexusGuard]^7 Detector '%s' started.^7"):format(detectorName))
                         end
                    else
                        -- While the DetectorRegistry might handle thread creation, a Start function is still expected for setup.
                        print(("^1[NexusGuard] Error: Enabled detector '%s' is missing a Start function. Cannot activate properly.^7"):format(detectorName))
                    end
                elseif not success then
                    -- Error during `require(filePath)`
                    print(("^1[NexusGuard] CRITICAL Error loading detector file '%s': %s^7"):format(filePath, tostring(detectorModule))) -- detectorModule contains the error message here
                else
                    -- `require` succeeded but didn't return a table (invalid detector structure)
                    print(("^1[NexusGuard] CRITICAL Error: Detector file '%s' did not return a valid module (expected table, got %s).^7"):format(filePath, type(detectorModule)))
                end
            else
                 print(("^3[NexusGuard]^7 Detector '%s' disabled in config.^7"):format(detectorName))
            end
            ::continue:: -- Lua goto label to jump to the next iteration of the loop.
            Citizen.Wait(0) -- Small wait to prevent script execution timeout if many detectors are loaded.
        end
        print("^2[NexusGuard]^7 Detector loading and starting process complete.")
    end

    --[[
        Protection Module Management Function
        Initializes auxiliary features like Discord Rich Presence.
    ]]
    function NexusGuardInstance:StartProtectionModules()
        print("^2[NexusGuard]^7 Starting auxiliary modules (e.g., Rich Presence)...")
        self:InitializeRichPresence()
        -- Add calls to initialize other non-detector modules here if needed.
        print("^2[NexusGuard]^7 Auxiliary modules initialization process completed.")
    end


    --[[
        Rich Presence Management Function
        Initializes Discord Rich Presence based on config.lua settings.
    ]]
    function NexusGuardInstance:InitializeRichPresence()
        -- Check for necessary configuration tables.
        if not Config or not Config.Discord or not Config.Discord.RichPresence then
            print("^3[NexusGuard] Rich Presence configuration missing or incomplete (Config.Discord.RichPresence). Skipping initialization.^7")
            return
        end

        local rpConfig = Config.Discord.RichPresence
        -- Check if Rich Presence is enabled.
        if not rpConfig.Enabled then
            print("^3[NexusGuard] Rich Presence disabled in config.^7")
            return
        end

        -- Validate the Discord Application ID.
        if not rpConfig.AppId or rpConfig.AppId == "" or rpConfig.AppId == "1234567890" then -- Check against common placeholder
            print("^1[NexusGuard] Rich Presence enabled but AppId is missing, empty, or default in config. Rich Presence will not function.^7")
            return -- Don't proceed if AppId is invalid.
        end

        -- Set the Discord Application ID using the native function.
        SetDiscordAppId(rpConfig.AppId)
        print("^2[NexusGuard] Rich Presence AppId set: " .. rpConfig.AppId .. "^7")

        -- Start the background thread to periodically update the presence.
        Citizen.CreateThread(function()
            while true do
                -- Re-check config inside the loop in case the resource is restarted or config reloaded.
                local currentRpConfig = Config and Config.Discord and Config.Discord.RichPresence
                -- Ensure presence is still enabled and AppId is valid.
                if not currentRpConfig or not currentRpConfig.Enabled or not currentRpConfig.AppId or currentRpConfig.AppId == "" or currentRpConfig.AppId == "1234567890" then
                    print("^3[NexusGuard] Rich Presence disabled or AppId invalid during update loop. Stopping thread.^7")
                    ClearDiscordPresence() -- Clear the presence if it's disabled.
                    break -- Exit the update loop.
                end

                -- Call the function to update the presence details.
                self:UpdateRichPresence()

                -- Wait for the configured interval before the next update.
                local interval = (currentRpConfig.UpdateInterval or 60) * 1000 -- Default to 60 seconds if not set.
                Citizen.Wait(interval)
            end
        end)
        print("^2[NexusGuard] Rich Presence update thread started.^7")
    end

    --[[
        Update Rich Presence Function
        Called periodically to update the player's Discord status.
    ]]
    function NexusGuardInstance:UpdateRichPresence()
        -- Double-check config validity before proceeding.
        if not Config or not Config.Discord or not Config.Discord.RichPresence then return end
        local rpConfig = Config.Discord.RichPresence
        if not rpConfig.Enabled or not rpConfig.AppId or rpConfig.AppId == "" or rpConfig.AppId == "1234567890" then return end

        -- Clear previous action buttons before setting new ones.
        ClearDiscordPresenceAction(0)
        ClearDiscordPresenceAction(1)

        -- Set large and small image assets if configured.
        if rpConfig.largeImageKey and rpConfig.largeImageKey ~= "" then
            SetDiscordRichPresenceAsset(rpConfig.largeImageKey)
            -- Set hover text for the large image, default to empty string if not provided.
            SetDiscordRichPresenceAssetText(rpConfig.LargeImageText or "")
        else
            ClearDiscordRichPresenceAsset() -- Clear asset if not configured.
        end
        if rpConfig.smallImageKey and rpConfig.smallImageKey ~= "" then
            SetDiscordRichPresenceAssetSmall(rpConfig.smallImageKey)
            -- Set hover text for the small image, default to empty string if not provided.
            SetDiscordRichPresenceAssetSmallText(rpConfig.SmallImageText or "")
        else
            ClearDiscordRichPresenceAssetSmall() -- Clear small asset if not configured.
        end

        -- Set action buttons (max 2 allowed by Discord).
        if rpConfig.buttons then
            for i, button in ipairs(rpConfig.buttons) do
                -- Ensure button has label and URL, and index is within bounds (0 or 1).
                if button.label and button.label ~= "" and button.url and button.url ~= "" and i <= 2 then
                    SetDiscordRichPresenceAction(i - 1, button.label, button.url)
                end
            end
        end

        -- Gather player and game information for the presence text.
        local playerName = GetPlayerName(PlayerId())
        local serverId = GetPlayerServerId(PlayerId())
        local ped = PlayerPedId()
        local health = GetEntityHealth(ped) - 100 -- Calculate health percentage (assuming 100 base).
        if health < 0 then health = 0 end -- Clamp health at 0.

        local coords = GetEntityCoords(ped)
        local streetName = "Unknown Location" -- Default location text.
        if coords then -- Check if coordinates are valid.
            local streetHash, _ = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
            if streetHash ~= 0 then -- Check if a valid street hash was found.
                streetName = GetStreetNameFromHashKey(streetHash) -- Convert hash to readable name.
            end
        end

        -- Format the presence text lines (consider making templates configurable).
        local detailsText = string.format("ID: %s | HP: %s%%", serverId, health) -- Top line (details).
        local stateText = string.format("%s | %s", playerName, streetName) -- Bottom line (state).

        -- Set the presence text using the appropriate natives.
        SetDiscordRichPresence(detailsText) -- Sets the main details line.
        SetDiscordRichPresenceState(stateText) -- Sets the state line below details.
    end

    --[[
        Send Position Update Function
        Sends the player's current position and timestamp to the server for validation checks (e.g., teleport, speed).
    ]]
    function NexusGuardInstance:SendPositionUpdate()
        -- Prevent sending updates before initialization or without a valid security token.
        if not self.initialized or not self.securityToken or type(self.securityToken) ~= "table" then
            -- print("^3[NexusGuard] SendPositionUpdate skipped: Not initialized or no valid security token.^7") -- Reduce log spam
            return
        end

        local ped = PlayerPedId()
        -- Ensure the player's ped entity exists.
        if not DoesEntityExist(ped) then return end

        local currentPos = GetEntityCoords(ped)
        local currentTimestamp = GetGameTimer() -- Use the game's timer for consistency across client/server if possible.

        -- Update the internal state for potential use by local detectors.
        self.state.lastPosition = currentPos
        self.state.lastPositionUpdate = currentTimestamp

        -- Send position data and the security token table to the server via EventRegistry.
        if EventRegistry then
            -- The event key 'NEXUSGUARD_POSITION_UPDATE' should map to the correct server-side event name
            -- defined in shared/event_registry.lua (e.g., 'nexusguard:server:positionUpdate').
            EventRegistry:TriggerServerEvent('NEXUSGUARD_POSITION_UPDATE', currentPos, currentTimestamp, self.securityToken)
        else
            print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot send position update to server.^7")
        end
    end

    --[[
        Send Health Update Function
        Sends the player's current health, armor, and timestamp to the server for validation (e.g., god mode).
    ]]
    function NexusGuardInstance:SendHealthUpdate()
        -- Prevent sending updates before initialization or without a valid security token.
        if not self.initialized or not self.securityToken or type(self.securityToken) ~= "table" then
            return
        end

        local ped = PlayerPedId()
        -- Ensure the player's ped entity exists.
        if not DoesEntityExist(ped) then return end

        local currentHealth = GetEntityHealth(ped)
        local currentArmor = GetPedArmour(ped)
        local currentTimestamp = GetGameTimer()

        -- Update internal state.
        self.state.lastHealth = currentHealth
        self.state.lastHealthUpdate = currentTimestamp
        -- self.state.lastArmor = currentArmor -- Could store armor too if needed locally

        -- Send health/armor data and the security token table to the server via EventRegistry.
        if EventRegistry then
            -- Similar to position update, ensure 'NEXUSGUARD_HEALTH_UPDATE' maps correctly in event_registry.lua.
            EventRegistry:TriggerServerEvent('NEXUSGUARD_HEALTH_UPDATE', currentHealth, currentArmor, currentTimestamp, self.securityToken)
        else
            print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot send health update to server.^7")
        end
    end

    --[[
        Cheat Reporting Function (Called by Detectors)
        Handles the logic for reporting detected cheats. Issues a local warning on the first offense
        and sends subsequent reports to the server.
    ]]
    function NexusGuardInstance:ReportCheat(detectionType, details)
        -- Prevent reporting before initialization or without a valid security token.
        if not self.initialized or not self.securityToken or type(self.securityToken) ~= "table" then
            print("^3[NexusGuard] ReportCheat skipped: Not initialized or no valid security token.^7")
            return
        end

        -- On the first detection for this client session, issue a local warning only.
        if not self.flags.warningIssued then
            self.flags.suspiciousActivity = true -- Set a general suspicion flag (might be used elsewhere).
            self.flags.warningIssued = true      -- Set the flag indicating the local warning was shown.

            print(("^3[NexusGuard] Local Warning Issued - Type: %s, Details: %s^7"):format(tostring(detectionType), tostring(details)))

            -- Trigger the local event handler (defined below) to display the warning message to the player (e.g., via chat).
            local cheatWarningEventName = EventRegistry and EventRegistry:GetEventName('NEXUSGUARD_CHEAT_WARNING')
            if cheatWarningEventName then
                TriggerEvent(cheatWarningEventName, detectionType, details)
            else
                print("^1[NexusGuard] CRITICAL: Could not get event name for NEXUSGUARD_CHEAT_WARNING. Cannot trigger local warning display.^7")
                -- Fallback to old name only if registry lookup fails, indicating a setup issue.
                TriggerEvent("NexusGuard:CheatWarning", detectionType, details)
            end
        else
            -- For subsequent detections after the initial warning, report directly to the server.
            print(("^1[NexusGuard] Reporting Detection to Server - Type: %s, Details: %s^7"):format(tostring(detectionType), tostring(details)))
            if EventRegistry then
                -- Send the detection type, details, and the security token to the server for verification and action.
                EventRegistry:TriggerServerEvent('DETECTION_REPORT', detectionType, details, self.securityToken)
            else
                -- EventRegistry is essential for server communication.
                print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot report detection to server.^7")
            end
        end
    end

    --[[
        Event Handlers Setup
        Registers handlers for events received from the server or triggered locally.
    ]]

    -- Handler for receiving the security token from the server.
    local receiveTokenEvent = (EventRegistry and EventRegistry:GetEventName('SECURITY_RECEIVE_TOKEN'))
    if receiveTokenEvent then
        AddEventHandler(receiveTokenEvent, function(tokenData)
            -- Validate the structure of the received token data.
            if not tokenData or type(tokenData) ~= "table" or not tokenData.timestamp or not tokenData.signature then
                print("^1[NexusGuard] Received invalid security token data structure from server. Handshake failed.^7")
                NexusGuardInstance.securityToken = nil -- Ensure token is nil if invalid.
                -- Consider requesting again or implementing further error handling.
                return
            end
            -- Store the received token table (containing timestamp and signature).
            NexusGuardInstance.securityToken = tokenData
            print("^2[NexusGuard] Security token received and stored via event: " .. receiveTokenEvent .. "^7")
        end)
    else
        -- Log critical error if the event name couldn't be retrieved (should have been caught earlier if registry failed).
        if EventRegistry then
             print("^1[NexusGuard] CRITICAL: Could not get event name for SECURITY_RECEIVE_TOKEN from EventRegistry. Cannot register handler.^7")
        else
             print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot register SECURITY_RECEIVE_TOKEN handler.^7")
        end
    end

    -- Handler for the locally triggered cheat warning event.
    -- This displays the warning message to the player.
    local cheatWarningEventName = EventRegistry and EventRegistry:GetEventName('NEXUSGUARD_CHEAT_WARNING') or "NexusGuard:CheatWarning" -- Use fallback name only if registry failed.
    AddEventHandler(cheatWarningEventName, function(detectionType, details)
        -- Check config if player notification is enabled.
        if Config and Config.Actions and Config.Actions.notifyPlayer then
            -- Prefer using the 'chat' resource for visibility if available.
            if exports.chat then
                -- Safely convert details to a string for display (handles tables via JSON).
                local detailStr = "N/A"
                if details then
                    if type(details) == "table" then
                        detailStr = (lib and lib.json and lib.json.encode(details)) or "{table data}"
                    else
                        detailStr = tostring(details)
                    end
                end
                -- Format and send the message using chat exports.
                exports.chat:addMessage({
                    color = { 255, 0, 0 }, -- Red color for warnings.
                    multiline = true,
                    args = {
                        "[NexusGuard Warning]", -- Message prefix.
                        ("Suspicious activity detected! Type: ^*%s^r. Details: ^*%s^r. Further violations may result in action."):format(tostring(detectionType), detailStr)
                    }
                })
            else
                -- Fallback to printing in the F8 console if chat resource is unavailable.
                print(("^1[NexusGuard Warning] Suspicious activity detected! Type: %s. Further violations may result in action.^7"):format(tostring(detectionType)))
            end
        end
        -- Note: This handler only displays the warning; the ReportCheat function decides whether to warn or report to server.
    end)

    -- Handler for screenshot request initiated by an admin via the server.
    local requestScreenshotEvent = (EventRegistry and EventRegistry:GetEventName('ADMIN_REQUEST_SCREENSHOT')) or "nexusguard:requestScreenshot" -- Use fallback name only if registry failed.
    AddEventHandler(requestScreenshotEvent, function()
        -- Ensure NexusGuard is initialized before processing.
        if not NexusGuardInstance.initialized then
            print("^3[NexusGuard] Screenshot requested but core is not initialized.^7")
            return
        end

        -- Check if the screenshot feature is enabled in config.lua.
        if not Config or not Config.ScreenCapture or not Config.ScreenCapture.enabled then
            print("^3[NexusGuard] Screenshot requested but feature is disabled in config (Config.ScreenCapture.enabled = false).^7")
            return
        end
        -- Check if the required 'screenshot-basic' resource is available and running.
        if not exports['screenshot-basic'] then
            print("^1[NexusGuard] Screenshot requested but 'screenshot-basic' resource/export not found. Ensure it's installed and started before NexusGuard.^7")
            return
        end

        -- Validate the webhook URL from config.
        local webhookURL = Config.ScreenCapture.webhookURL
        if not webhookURL or webhookURL == "" then
            print("^1[NexusGuard] Screenshot requested but Config.ScreenCapture.webhookURL is not configured in config.lua.^7")
            return
        end

        print("^2[NexusGuard] Screenshot requested by server. Initiating upload via screenshot-basic...^7")
        -- Use the screenshot-basic export to take and upload the screenshot.
        exports['screenshot-basic']:requestScreenshotUpload(
            webhookURL,
            'files[]', -- Default field name expected by screenshot-basic for file uploads.
            function(data) -- Callback function executed after upload attempt.
                -- 'data' contains the response from the webhook (usually Discord's API response as a JSON string).
                if not data then
                    print("^1[NexusGuard] Screenshot upload failed: No data returned from callback. Check webhook URL and Discord permissions.^7")
                    -- Optionally report failure back to server.
                    -- if EventRegistry then EventRegistry:TriggerServerEvent('ADMIN_SCREENSHOT_FAILED', "No data returned", NexusGuardInstance.securityToken) end
                    return
                end

                -- Ensure ox_lib's JSON library is available to decode the response.
                if not lib or not lib.json then
                    print("^1[NexusGuard] ox_lib JSON library (lib.json) not available for screenshot callback. Cannot process response. Ensure ox_lib is started.^7")
                    return
                end

                -- Safely decode the JSON response from the webhook.
                local success, resp = pcall(lib.json.decode, data)
                if success and resp and resp.attachments and resp.attachments[1] and resp.attachments[1].url then
                    -- Successfully decoded and found the attachment URL.
                    local screenshotUrl = resp.attachments[1].url
                    print("^2[NexusGuard] Screenshot uploaded successfully: " .. screenshotUrl .. "^7")
                    -- Report the successful upload and URL back to the server, including the security token.
                    if EventRegistry then
                        EventRegistry:TriggerServerEvent('ADMIN_SCREENSHOT_TAKEN', screenshotUrl, NexusGuardInstance.securityToken)
                    else
                        print("^1[NexusGuard] CRITICAL: EventRegistry module not loaded. Cannot report screenshot taken to server.^7")
                    end
                else
                    -- Decoding failed or the response structure was unexpected.
                    print("^1[NexusGuard] Failed to decode screenshot response or response structure invalid. Raw response: " .. tostring(data) .. "^7")
                    -- Optionally report failure back to server.
                    -- if EventRegistry then EventRegistry:TriggerServerEvent('ADMIN_SCREENSHOT_FAILED', "Response decode failed", NexusGuardInstance.securityToken) end
                end
            end
        )
    end)

    --[[
        Resource Start Handler
        Initializes the NexusGuard core when this resource starts.
    ]]
    AddEventHandler('onClientResourceStart', function(resourceName)
        -- Ensure this handler only runs when the NexusGuard resource itself is starting.
        if GetCurrentResourceName() ~= resourceName then return end

        print("^2[NexusGuard] Resource starting. Waiting briefly for dependencies and shared scripts...^7")
        -- Short delay to allow config.lua and other shared scripts to be loaded and parsed.
        Citizen.Wait(500)

        -- Call the main initialization function.
        NexusGuardInstance:Initialize()
        -- Note: Detector registration/start is now handled within Initialize -> StartDetectors.
    end)
