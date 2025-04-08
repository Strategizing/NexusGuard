-- NexusGuard Anti-Cheat Test Cases
-- This file defines test cases for the anti-cheat system

local function detectCheat(type)
    local detected = false
    for _, detection in ipairs(testResults.detections or {}) do
        if detection.type:lower() == type then
            detected = true
            break
        end
    end
    return detected
end

local function teardownGlobal(originalKey, globalKey)
    if _G[originalKey] then
        _G[globalKey] = _G[originalKey]
    end
end

local testCases = {
    {
        name = "Speed hack detection",
        run = function()
            local detected = detectCheat("speedhack")
            return detected, "Speed hack was " .. (detected and "detected" or "not detected")
        end,
        teardown = function()
            teardownGlobal("_originalGetEntityVelocity", "GetEntityVelocity")
        end,
        expectation = true
    },
    {
        name = "God mode detection",
        setup = function()
            _G._originalGetPlayerInvincible = GetPlayerInvincible
            _G.GetPlayerInvincible = function() return true end
        end,
        run = function()
            TriggerEvent("NexusGuard:DetectGodMode")
            Citizen.Wait(100)
            local detected = detectCheat("godmode")
            return detected, "God mode was " .. (detected and "detected" or "not detected")
        end,
        teardown = function()
            teardownGlobal("_originalGetPlayerInvincible", "GetPlayerInvincible")
        end,
        expectation = true
    },
    {
        name = "Weapon modification detection",
        setup = function()
            _G._originalGetWeaponDamage = GetWeaponDamage
            _G.GetWeaponDamage = function() return 1000.0 end
        end,
        run = function()
            TriggerEvent("NexusGuard:DetectWeaponModification")
            Citizen.Wait(100)
            local detected = detectCheat("weaponmod")
            return detected, "Weapon modification was " .. (detected and "detected" or "not detected")
        end,
        teardown = function()
            teardownGlobal("_originalGetWeaponDamage", "GetWeaponDamage")
        end,
        expectation = true
    }
}

return testCases