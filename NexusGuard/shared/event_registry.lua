--[[
    NexusGuard Event Registry (shared/event_registry.lua)

    Purpose:
    - Provides a centralized definition for all network events used by NexusGuard.
    - Standardizes event names using a consistent prefix (`nexusguard:`) to prevent conflicts.
    - Offers helper functions to get full event names, register handlers, and trigger events,
      ensuring consistency across the client and server scripts.

    Usage:
    - Both client and server scripts should `require('shared/event_registry')`.
    - Use `EventRegistry:GetEventName('EVENT_KEY')` to get the full, prefixed event name string.
    - Use `EventRegistry:AddEventHandler('EVENT_KEY', handlerFunction)` to register handlers.
    - Use `EventRegistry:TriggerServerEvent('EVENT_KEY', ...)` to trigger events towards the server.
    - Use `EventRegistry:TriggerClientEvent('EVENT_KEY', targetPlayer, ...)` to trigger events towards a client.

    Developer Notes:
    - Add new events to the `EventRegistry.events` table below.
    - Use descriptive keys (uppercase snake_case) and paths (lowercase camelCase or snake_case).
    - The path part will be automatically prefixed with `EventRegistry.prefix .. ":"`.
    - For local client-side events (triggered and handled only on the client), you can define the full name
      directly in the `events` table (like `NEXUSGUARD_CHEAT_WARNING`) or use standard `RegisterNetEvent`/`AddEventHandler`.
      Using the registry for local events is mainly for consistency if preferred.
]]

-- Load the natives wrapper using the module loader
local ModuleLoader = require('shared/module_loader')
local Natives = ModuleLoader.Load('shared/natives', true) -- Load as optional to avoid circular dependency

local EventRegistry = {}

-- Base prefix for all NexusGuard network events.
EventRegistry.prefix = "nexusguard" -- e.g., results in "nexusguard:security:requestToken"

--[[
    Event Definitions Table (`EventRegistry.events`)

    Maps internal, readable keys (used in code) to the path component of the event name.
    The full event name is constructed as `prefix:path`.
    Comments indicate the intended direction and purpose.
]]
EventRegistry.events = {
    -- Security Handshake (Client <-> Server)
    SECURITY_REQUEST_TOKEN = "security:requestToken", -- Client -> Server: Client requests a security token upon connection.
    SECURITY_RECEIVE_TOKEN = "security:receiveToken", -- Server -> Client: Server sends the generated security token data back to the client.
    SECURITY_NEW_CHALLENGE = "security:newChallenge", -- Server -> Client: Server issues a new challenge token.

    -- Detection Reporting (Client -> Server)
    DETECTION_REPORT = "detection:report", -- Client -> Server: Client reports a detected violation with details and security token.
    -- DETECTION_VERIFY = "detection:verify", -- Server -> Client: (Currently unused) Potentially for server requesting client re-verification.

    -- Admin Actions (Server -> Client / Client -> Server)
    ADMIN_NOTIFICATION = "admin:notification",       -- Server -> Client: Server sends a notification message specifically to an admin client.
    ADMIN_REQUEST_SCREENSHOT = "admin:requestScreenshot", -- Server -> Client: Server requests the client to take and upload a screenshot.
    ADMIN_SCREENSHOT_TAKEN = "admin:screenshotTaken",   -- Client -> Server: Client confirms screenshot was taken and provides the URL.
    ADMIN_SCREENSHOT_FAILED = "admin:screenshotFailed", -- Client -> Server: Client reports screenshot capture/upload failure.

    -- System Status & Checks (Client -> Server)
    SYSTEM_ERROR = "system:error",             -- Client -> Server: Client reports an internal error (e.g., in a detector).
    SYSTEM_RESOURCE_CHECK = "system:resourceCheck", -- Client -> Server: Client sends its list of running resources for server verification.

    -- Server-Side Validation Data (Client -> Server)
    -- Note: Keys kept similar to original for compatibility, but path indicates direction.
    NEXUSGUARD_POSITION_UPDATE = "client:positionUpdate", -- Client -> Server: Client sends its current position for server-side speed/teleport checks.
    NEXUSGUARD_HEALTH_UPDATE = "client:healthUpdate",   -- Client -> Server: Client sends its current health/armor for server-side god mode/armor checks.
    NEXUSGUARD_WEAPON_CHECK = "client:weaponCheck",    -- Client -> Server: Client sends current weapon/clip info for server-side validation.

    -- Client-Side Only Events (Triggered and Handled Locally on Client)
    -- These don't strictly need the registry but are included for completeness.
    -- The path here is the full event name as it's not prefixed by the standard logic.
    NEXUSGUARD_CHEAT_WARNING = "NexusGuard:CheatWarning" -- Client Local: Triggered by ReportCheat on first offense, handled locally to show a warning message.
}

--[[
    Get the full, prefixed network event name for a given key.
    @param eventKey (string): The key from the `EventRegistry.events` table (e.g., 'SECURITY_REQUEST_TOKEN').
    @return (string | nil): The full event name (e.g., 'nexusguard:security:requestToken') or nil if key not found.
]]
function EventRegistry:GetEventName(eventKey)
    local eventPath = self.events[eventKey]
    if not eventPath then
        print(("^1[NexusGuard EventRegistry] Warning: Requested unknown event key '%s'!^7"):format(tostring(eventKey)))
        return nil
    end

    -- Check if the defined path already contains a colon (':').
    -- This allows defining full event names directly in the table (like for local events).
    if string.find(eventPath, ":", 1, true) then
        -- If it already seems to be a full path (e.g., "NexusGuard:CheatWarning"), use it directly.
        -- This handles cases where the value in the events table is the intended full name.
        -- A basic check ensures it doesn't accidentally use the *wrong* prefix if defined strangely.
        if string.sub(eventPath, 1, #self.prefix + 1) == self.prefix .. ":" then
             return eventPath -- It already has the correct prefix.
        elseif string.find(eventPath, ":", 1, true) then
             -- It has a colon, but not *our* prefix. Assume it's intentional (e.g., local event).
             -- print(("^3[NexusGuard EventRegistry] Info: Event path '%s' for key '%s' seems to be a full name or use a different prefix. Using as-is.^7"):format(eventPath, eventKey))
             return eventPath
        end
        -- Fallthrough should not happen with current logic, but acts as safety.
    end
    -- If no colon was found in the path, prepend the standard prefix.
    return self.prefix .. ":" .. eventPath
end

--[[
    Registers a network event using the standardized name for the given key.
    Primarily useful on the receiving end (server registering client->server events,
    client registering server->client events).
    @param eventKey (string): The key from the `EventRegistry.events` table.
    @return (string | nil): The full event name that was registered, or nil on failure.
]]
function EventRegistry:RegisterEvent(eventKey)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        -- Use Natives wrapper if available, otherwise fall back to direct call
        if Natives and Natives.RegisterNetEvent then
            Natives.RegisterNetEvent(eventName)
        else
            RegisterNetEvent(eventName)
        end
        -- print(("^2[NexusGuard EventRegistry] Registered network event: %s (Key: %s)^7"):format(eventName, eventKey)) -- Optional debug log
        return eventName
    end
    return nil
end

--[[
    Adds an event handler for the standardized event name corresponding to the given key.
    @param eventKey (string): The key from the `EventRegistry.events` table.
    @param handler (function): The function to execute when the event is triggered.
    @return (boolean): True if the handler was added successfully, false otherwise.
]]
function EventRegistry:AddEventHandler(eventKey, handler)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        -- Use Natives wrapper if available, otherwise fall back to direct call
        if Natives and Natives.AddEventHandler then
            Natives.AddEventHandler(eventName, handler)
        else
            AddEventHandler(eventName, handler)
        end
        -- print(("^2[NexusGuard EventRegistry] Added handler for event: %s (Key: %s)^7"):format(eventName, eventKey)) -- Optional debug log
        return true
    end
    print(("^1[NexusGuard EventRegistry] Error: Failed to add handler for unknown event key: %s^7"):format(tostring(eventKey)))
    return false
end

--[[
    Triggers a server event using the standardized name for the given key.
    (Client -> Server communication)
    @param eventKey (string): The key from the `EventRegistry.events` table.
    @param ...: Optional arguments to pass with the event.
    @return (boolean): True if the event was triggered successfully, false otherwise.
]]
function EventRegistry:TriggerServerEvent(eventKey, ...)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        -- Use Natives wrapper if available, otherwise fall back to direct call
        if Natives and Natives.TriggerServerEvent then
            Natives.TriggerServerEvent(eventName, ...)
        else
            TriggerServerEvent(eventName, ...)
        end
        return true
    end
    print(("^1[NexusGuard EventRegistry] Error: Failed to trigger unknown server event key: %s^7"):format(tostring(eventKey)))
    return false
end

--[[
    Triggers a client event using the standardized name for the given key.
    (Server -> Client communication)
    @param eventKey (string): The key from the `EventRegistry.events` table.
    @param target (number): The server ID of the target client (-1 for all clients).
    @param ...: Optional arguments to pass with the event.
    @return (boolean): True if the event was triggered successfully, false otherwise.
]]
function EventRegistry:TriggerClientEvent(eventKey, target, ...)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        -- Use Natives wrapper if available, otherwise fall back to direct call
        if Natives and Natives.TriggerClientEvent then
            Natives.TriggerClientEvent(eventName, target, ...)
        else
            TriggerClientEvent(eventName, target, ...)
        end
        return true
    end
    print(("^1[NexusGuard EventRegistry] Error: Failed to trigger unknown client event key: %s for target %s^7"):format(tostring(eventKey), tostring(target)))
    return false
end

--[[
    (Optional) Get simple documentation for registered events.
    @return (table): A table mapping event keys to their full names and basic usage info.
]]
function EventRegistry:GetEventDocumentation()
    local docs = {}
    for key, path in pairs(self.events) do
        local fullName = self:GetEventName(key) -- Use the function to ensure correct prefixing/handling
        if fullName then
            docs[key] = {
                key = key,
                path_component = path,
                fullEventName = fullName,
                usage_example = ("EventRegistry:AddEventHandler('%s', function(...) end)"):format(key)
                -- Could add direction (Client->Server, Server->Client) based on path or convention
            }
        end
    end
    return docs
end

-- Export the EventRegistry table for use in other scripts via require().
return EventRegistry
