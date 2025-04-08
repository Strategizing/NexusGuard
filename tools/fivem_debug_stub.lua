-- FiveM Debug Environment Stub
-- Simulates the FiveM environment for local debugging
-- WARNING: NEVER include this file in production server files

local function initializeDebugEnvironment()
    function GetPlayerPed() return 1 end
    function PlayerId() return 0 end
    function GetEntityCoords() return {x=0, y=0, z=0} end
    function GetEntityHealth() return 200 end
    function GetPedMaxHealth() return 200 end
    function GetPlayerInvincible() return false end
    function GetSelectedPedWeapon() return -1569615261 end
    function GetWeaponDamage() return 10.0 end
    function GetWeaponClipSize() return 30 end
end

local function initializeEventHandlers()
    local eventHandlers = {}

    function RegisterNetEvent(eventName)
        return eventName
    end

    function AddEventHandler(eventName, callback)
        eventHandlers[eventName] = callback
    end

    function TriggerEvent(eventName, ...)
        if eventHandlers[eventName] then
            eventHandlers[eventName](...)
        end
    end
end

if not IsDuplicityVersion and not GetCurrentResourceName then
    print("🔧 Loading FiveM debug environment stub")
    initializeDebugEnvironment()
    initializeEventHandlers()
    print("✅ FiveM debug environment loaded")
else
    print("⚠️ Real FiveM environment detected - debug stub disabled")
end
