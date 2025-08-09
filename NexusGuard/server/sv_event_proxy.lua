--[[
    NexusGuard Event Proxy (server/sv_event_proxy.lua)

    Simplified proxy channel that validates a per-client key before
    dispatching events. Inspired by GoblinAC's approach to securing
    TriggerServerEvent calls.
]]

local EventProxy = {}
local activeKeys = {}

local function generateKey()
    return string.format('%x%x', math.random(0, 0xffffff), math.random(0, 0xffffff))
end

AddEventHandler('playerJoining', function()
    local src = source
    local key = generateKey()
    activeKeys[src] = key
    TriggerClientEvent('ng_proxy:setKey', src, key)
end)

AddEventHandler('playerDropped', function()
    activeKeys[source] = nil
end)

RegisterNetEvent('ng_proxy:trigger', function(payload, key)
    local src = source
    if not payload or not key or activeKeys[src] ~= key then
        print(('^1[NexusGuard] Invalid proxy trigger from %s^7'):format(src))
        return
    end

    local data = json.decode(payload or '{}')
    if not data or not data.event then return end

    TriggerEvent(data.event, src, table.unpack(data.args or {}))
end)

return EventProxy
