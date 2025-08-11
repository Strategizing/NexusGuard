--[[
    NexusGuard Server API (sv_api.lua)

    Aggregates core modules and exposes a single exported API table.
    All shared state is provided to modules through dependency injection
    performed by the Core module.
]]

local Utils = require('server/sv_utils')
local Log = Utils.Log or function(msg) print(msg) end

local Core = require('server/sv_core')

local NexusGuardServer = {
    Config = _G.Config or {},
    OnlineAdmins = {},
    Utils = Utils,
    Core = Core
}

if not Core.Initialize(NexusGuardServer.Config, Utils) then
    Log("^1[NexusGuard] CRITICAL: Failed to initialize Core module. NexusGuard may not function correctly.^7", 1)
end

for moduleName, moduleRef in pairs(Core.modules) do
    NexusGuardServer[moduleName] = moduleRef
    Log(("^2[NexusGuard]^7 Module '%s' assigned to API."):format(moduleName), 3)
end

function NexusGuardServer.GetSession(playerId)
    return Core.GetSession(playerId)
end

function NexusGuardServer.CleanupSession(playerId)
    return Core.CleanupSession(playerId)
end

function NexusGuardServer.ProcessDetection(playerId, detectionType, detectionData)
    return Core.ProcessDetection(playerId, detectionType, detectionData)
end

NexusGuardServer.Detections = NexusGuardServer.Detections or {}
function NexusGuardServer.Detections.Store(playerId, detectionType, detectionData)
    if type(detectionData) ~= 'table' then
        detectionData = { value = detectionData, details = {}, clientValidated = false, serverValidated = false }
    else
        detectionData.value = detectionData.value
        detectionData.details = detectionData.details or {}
        detectionData.clientValidated = detectionData.clientValidated or false
        detectionData.serverValidated = detectionData.serverValidated or false
    end

    if NexusGuardServer.Database and NexusGuardServer.Database.StoreDetection then
        return NexusGuardServer.Database.StoreDetection(playerId, detectionType, detectionData)
    end
    return false
end

function NexusGuardServer.GetStatus()
    return Core.GetStatus()
end

exports('GetNexusGuardServerAPI', function()
    Log("GetNexusGuardServerAPI called.", 4)
    return NexusGuardServer
end)

if Citizen then
    Citizen.CreateThread(function()
        Citizen.Wait(500)
        if NexusGuardServer.Database and NexusGuardServer.Database.Initialize and not NexusGuardServer.Database.IsInitialized then
            Log("^3[NexusGuard]^7 Attempting to initialize database module...", 3)
            NexusGuardServer.Database.Initialize()
        end
    end)
end

return NexusGuardServer
