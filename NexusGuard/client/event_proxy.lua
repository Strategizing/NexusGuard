--[[
    NexusGuard Client Event Proxy (client/event_proxy.lua)

    Prototype module that encodes event data and dispatches it
    through a controlled server channel. Inspired by GoblinAC's
    proxy architecture, events are packaged with their key,
    arguments, and security token before being sent to the server.
]]

local EventRegistry = require('shared/event_registry')
local Utils = require('shared/utils')

local EventProxy = {}
EventProxy.channel = EventRegistry:GetEventName('PROXY_EVENT')

--- Sends an encoded event to the server through the proxy channel.
-- @param eventKey string: Event key defined in EventRegistry.events.
-- @param args table: Array of arguments to pass with the event.
-- @param token table: Security token for validation.
function EventProxy:TriggerServerEvent(eventKey, args, token)
    if not self.channel or not eventKey then return end
    local payload = {
        eventKey = eventKey,
        args = args or {},
        token = token
    }
    local encoded = Utils.JsonEncode(payload)
    if encoded then
        TriggerServerEvent(self.channel, encoded)
    end
end

return EventProxy
