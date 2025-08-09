--[[
    NexusGuard Server Event Proxy (server/sv_event_proxy.lua)

    Receives encoded events from clients, validates the accompanying
    security token, and dispatches whitelisted events to their
    respective handlers. This prototype mirrors the controlled
    channel approach used by GoblinAC.
]]

local ServerUtils = require('server/sv_utils')
local SharedUtils = require('shared/utils')
local EventRegistry = require('shared/event_registry')

local EventProxy = {}
local Log = ServerUtils.Log

local proxyEventName = EventRegistry:RegisterEvent('PROXY_EVENT')

-- Whitelisted events allowed through the proxy channel
local allowedEvents = {
    DETECTION_REPORT = true,
    SYSTEM_ERROR = true,
    SYSTEM_RESOURCE_CHECK = true
}

AddEventHandler(proxyEventName, function(payload)
    local src = source
    local data = SharedUtils.JsonDecode(payload)
    if not data or type(data) ~= 'table' then
        Log("[EventProxy] Received invalid payload from %d", 1, src)
        return
    end

    if not allowedEvents[data.eventKey] then
        Log("[EventProxy] Blocked unauthorized event '%s' from %d", 1, tostring(data.eventKey), src)
        return
    end

    local token = data.token
    if not _G.NexusGuardServer or not NexusGuardServer.Security or not NexusGuardServer.Security.ValidateToken or not NexusGuardServer.Security.ValidateToken(src, token) then
        Log("[EventProxy] Invalid security token for '%s' from %d", 1, data.eventKey, src)
        return
    end

    local eventName = EventRegistry:GetEventName(data.eventKey)
    if not eventName then return end

    local args = data.args or {}
    table.insert(args, token)
    TriggerEvent(eventName, table.unpack(args))
end)

return EventProxy
