--[[
    FiveM Anti-Cheat Development Compatibility Helper
    This file provides declarations and stubs for FiveM natives
    to improve code editor support and static analysis.
    
    This file should ONLY be included during development,
    not in the actual resource when deployed to a server.
]]

-- Indicate these are global functions for linting tools
---@diagnostic disable: lowercase-global

-- Player-related functions
local function initializePlayerFunctions()
    function GetPlayerPed(playerId) end
    function PlayerId() end
    function PlayerPedId() end
    function GetPlayerName(playerId) end
    function GetPlayers() end
    function GetPlayerEndpoint(playerId) end
    function GetPlayerIdentifierByType(playerId, type) end
    function GetPlayerServerId(playerId) end
end

-- Entity-related functions
local function initializeEntityFunctions()
    function GetEntityCoords(entity) end
    function GetEntityHealth(entity) end
    function GetEntityType(entity) end
    function GetEntitySpeed(entity) end
    function GetEntityModel(entity) end
    function GetEntityVelocity(entity) end
    function DoesEntityExist(entity) end
    function IsEntityDead(entity) end
    function GetEntityCollisionDisabled(entity) end
    function NetworkGetEntityOwner(entity) end
    function NetworkGetNetworkIdFromEntity(entity) end
end

-- Ped functions
function GetPedArmour(ped) end
function GetPedMaxHealth(ped) end
function IsPedInParachuteFreeFall(ped) end
function IsPedFalling(ped) end
function IsPedJumpingOutOfVehicle(ped) end

-- Vehicle functions
function GetVehiclePedIsIn(ped, lastVehicle) end
function GetVehicleModelMaxSpeed(modelHash) end

-- Weapon functions
function GetSelectedPedWeapon(ped) end
function GetWeaponDamage(weaponHash, componentIndex) end
function GetWeaponClipSize(weaponHash) end
function GetHashKey(weaponName) end

-- Control functions
function IsControlJustPressed(inputGroup, control) end

-- Network/Session functions
function NetworkIsSessionActive() end

-- Resource functions
function GetCurrentResourceName() end
function GetNumResources() end
function GetResourceByFindIndex(index) end
function LoadResourceFile(resourceName, fileName) end
function SaveResourceFile(resourceName, fileName, data, dataLength) end

-- Event registration
function RegisterNetEvent(eventName) end
function AddEventHandler(eventName, callback) end
function RegisterServerEvent(eventName) end
function TriggerEvent(eventName, ...) end
function TriggerServerEvent(eventName, ...) end
function TriggerClientEvent(eventName, playerId, ...) end

-- Player state functions
function GetPlayerInvincible(playerId) end
function IsPlayerSwitchInProgress() end
function IsScreenFadedOut() end
function GetGroundZFor_3dCoord(x, y, z, ignoreWater) end

-- Game info functions
function GetGameTimer() end
function GetStreetNameAtCoord(x, y, z) end
function GetStreetNameFromHashKey(hash) end

-- Discord Rich Presence
function SetDiscordAppId(appId) end
function SetDiscordRichPresenceAsset(assetName) end
function SetDiscordRichPresenceAssetText(text) end
function SetDiscordRichPresenceAssetSmall(assetName) end
function SetDiscordRichPresenceAssetSmallText(text) end
function SetRichPresence(text) end
function SetDiscordRichPresenceAction(index, text, url) end

-- Server-specific functions
function GetConvar(varName, default) end
function PerformHttpRequest(url, callback, method, data, headers) end
function DropPlayer(playerId, reason) end
function IsPlayerAceAllowed(playerId, object) end
function SetConvar(varName, value) end
function GetPlayerIdentifiers(playerId) end

-- Exports system (for both client and server)
exports = setmetatable({}, {
    __index = function(_, resourceName)
        return setmetatable({}, {
            __index = function(_, exportName)
                return function(...) end
            end
        })
    end
})

-- Citizen namespace (commonly used for threads and waits)
Citizen = {
    CreateThread = function(callback) end,
    Wait = function(ms) end,
    Trace = function(message) end
}

-- Framework declarations
ESX = {}
QBCore = {}

-- Initialize all functions
initializePlayerFunctions()
initializeEntityFunctions()

---@diagnostic enable: lowercase-global

print("FiveM development compatibility helper loaded")
