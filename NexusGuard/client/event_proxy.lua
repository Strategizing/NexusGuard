--[[
    NexusGuard Event Proxy (client/event_proxy.lua)

    Prototype module inspired by GoblinAC's event proxy system. Encodes
    event data and sends it through a controlled channel that validates a
    per-client key on the server before dispatching the real event.
]]

local EventRegistry = require('shared/event_registry')

local EventProxy = {
    key = nil
}

-- Receive the proxy key from the server
RegisterNetEvent('ng_proxy:setKey', function(k)
    EventProxy.key = k
end)

-- Trigger a server event through the proxy channel
function EventProxy:TriggerServer(eventKey, ...)
    if not self.key then
        print(('^1[NexusGuard] Missing proxy key. Event %s not sent.^7'):format(tostring(eventKey)))
        return
    end

    local eventName = EventRegistry:GetEventName(eventKey)
    if not eventName then return end

    local payload = json.encode({ event = eventName, args = { ... } })
    TriggerServerEvent('ng_proxy:trigger', payload, self.key)
end

return EventProxy
