-- EventRegistry Module
-- Standardizes event naming and handling for NexusGuard

local EventRegistry = {}

-- Base prefix for all events to avoid conflicts with other resources
EventRegistry.prefix = "nexusguard"

-- All registered events (Keep this structure for easy access)
EventRegistry.events = {
    -- Security events
    SECURITY_REQUEST_TOKEN = "security:requestToken",
    SECURITY_RECEIVE_TOKEN = "security:receiveToken",

    -- Detection events
    DETECTION_REPORT = "detection:report",
    DETECTION_VERIFY = "detection:verify", -- Note: This event doesn't seem to be used in server_main/client_main

    -- Admin events
    ADMIN_NOTIFICATION = "admin:notification",
    ADMIN_REQUEST_SCREENSHOT = "admin:requestScreenshot",
    ADMIN_SCREENSHOT_TAKEN = "admin:screenshotTaken",

    -- System events
    SYSTEM_ERROR = "system:error",
    SYSTEM_RESOURCE_CHECK = "system:resourceCheck",

    -- Server -> Client State Sync (Added based on client_main usage)
    NEXUSGUARD_POSITION_UPDATE = "server:positionUpdate", -- Renamed for clarity (was client -> server)
    NEXUSGUARD_HEALTH_UPDATE = "server:healthUpdate", -- Renamed for clarity (was client -> server)

    -- Client-Side Only Events (Added based on client_main usage)
    NEXUSGUARD_CHEAT_WARNING = "NexusGuard:CheatWarning" -- Local client warning event
}

-- Get the full prefixed event name
function EventRegistry:GetEventName(eventKey)
    local eventPath = self.events[eventKey]
    if not eventPath then
        print("^1[NexusGuard] Warning: Requested unknown event key '" .. tostring(eventKey) .. "'!^7")
        return nil
    end

    -- Check if the path already contains the prefix (for legacy compatibility if needed)
    if string.find(eventPath, ":", 1, true) then
        -- If it looks like a full path already (e.g., "NexusGuard:CheatWarning"), use it directly
        -- This handles cases where the value in the events table is the full name
        if string.sub(eventPath, 1, #self.prefix) == self.prefix then
             return eventPath
        else
             -- If it has a colon but not the prefix, it might be an error or different prefix scheme
             print("^3[NexusGuard] Warning: Event path '" .. eventPath .. "' for key '" .. eventKey .. "' seems to have a different prefix. Using as-is.^7")
             return eventPath
        end
    else
        -- Otherwise, prepend the standard prefix
        return self.prefix .. ":" .. eventPath
    end
end

-- Register a new event handler with standardized name
-- Note: This is primarily for server-side use or client-side events triggered by server.
-- Client-side handlers for client-triggered events often use AddEventHandler directly.
function EventRegistry:RegisterEvent(eventKey)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        RegisterNetEvent(eventName)
        return eventName
    end
    return nil
end

-- Add handler to an event with standardized name
function EventRegistry:AddEventHandler(eventKey, handler)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        AddEventHandler(eventName, handler)
        return true
    end
    return false
end

-- Trigger a server event with standardized name
function EventRegistry:TriggerServerEvent(eventKey, ...)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        TriggerServerEvent(eventName, ...)
        return true
    end
    print("^1[NexusGuard] Error: Failed to trigger unknown server event key: " .. tostring(eventKey) .. "^7")
    return false
end

-- Trigger a client event with standardized name
function EventRegistry:TriggerClientEvent(eventKey, target, ...)
    local eventName = self:GetEventName(eventKey)
    if eventName then
        TriggerClientEvent(eventName, target, ...)
        return true
    end
     print("^1[NexusGuard] Error: Failed to trigger unknown client event key: " .. tostring(eventKey) .. "^7")
    return false
end

-- Get event documentation (remains mostly the same)
function EventRegistry:GetEventDocumentation()
    local docs = {}
    for key, _ in pairs(self.events) do
        local fullName = self:GetEventName(key)
        if fullName then
            docs[key] = {
                key = key,
                fullEventName = fullName,
                usage = "Use EventRegistry methods (e.g., EventRegistry:AddEventHandler('" .. key .. "', handler))"
            }
        end
    end
    return docs
end

-- Export the local table
return EventRegistry
