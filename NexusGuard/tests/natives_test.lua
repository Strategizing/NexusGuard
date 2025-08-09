--[[
    NexusGuard Natives Wrapper Test (tests/natives_test.lua)

    Purpose:
    - Tests the functionality of the natives wrapper
    - Ensures native functions are properly wrapped
    - Verifies error handling for native calls
    - Tests fallback behavior
]]

-- Load the module loader and natives wrapper
local ModuleLoader = require('shared/module_loader')
local Natives = ModuleLoader.Load('shared/natives')

-- Mock native functions for testing
local mockNatives = {
    GetPlayerName = function(playerId)
        if playerId == 1 then
            return "TestPlayer"
        elseif playerId == 2 then
            return nil -- Simulate a failed native call
        else
            error("Invalid player ID") -- Simulate an error
        end
    end,
    GetEntityCoords = function(entityId)
        if entityId == 1 then
            return {x = 100.0, y = 200.0, z = 300.0}
        elseif entityId == 2 then
            return nil -- Simulate a failed native call
        else
            error("Invalid entity ID") -- Simulate an error
        end
    end,
    IsDuplicityVersion = function()
        return true -- Simulate server-side
    end
    ,
    DoesEntityExist = function(entityId)
        return true
    end
}

-- Override the global native functions for testing
for name, func in pairs(mockNatives) do
    _G[name] = func
end

-- Test results
local tests = {
    passed = 0,
    failed = 0,
    total = 0
}

-- Test function
local function test(name, func)
    tests.total = tests.total + 1
    local status, error = pcall(func)
    if status then
        print(string.format("✓ Test passed: %s", name))
        tests.passed = tests.passed + 1
    else
        print(string.format("✗ Test failed: %s\n  Error: %s", name, error))
        tests.failed = tests.failed + 1
    end
end

-- Test: Native function exists
test("Native function exists", function()
    assert(Natives.GetPlayerName ~= nil, "GetPlayerName should exist in the Natives wrapper")
    assert(Natives.GetEntityCoords ~= nil, "GetEntityCoords should exist in the Natives wrapper")
    assert(Natives.IsDuplicityVersion ~= nil, "IsDuplicityVersion should exist in the Natives wrapper")
end)

-- Test: Successful native call
test("Successful native call", function()
    local playerName = Natives.GetPlayerName(1)
    assert(playerName == "TestPlayer", "GetPlayerName should return the correct value")
    
    local coords = Natives.GetEntityCoords(1)
    assert(coords.x == 100.0, "GetEntityCoords should return the correct x coordinate")
    assert(coords.y == 200.0, "GetEntityCoords should return the correct y coordinate")
    assert(coords.z == 300.0, "GetEntityCoords should return the correct z coordinate")
    
    local isServer = Natives.IsDuplicityVersion()
    assert(isServer == true, "IsDuplicityVersion should return true in this test")
end)

-- Test: Failed native call
test("Failed native call", function()
    local playerName = Natives.GetPlayerName(2)
    assert(playerName == nil, "GetPlayerName should return nil for a failed call")
    
    local coords = Natives.GetEntityCoords(2)
    assert(coords == nil, "GetEntityCoords should return nil for a failed call")
end)

-- Test: Error handling
test("Error handling", function()
    -- These should not throw errors, but return nil instead
    local playerName = Natives.GetPlayerName(3)
    assert(playerName == nil, "GetPlayerName should handle errors and return nil")
    
    local coords = Natives.GetEntityCoords(3)
    assert(coords == nil, "GetEntityCoords should handle errors and return nil")
end)

-- Test: Non-existent native
test("Non-existent native", function()
    -- This should not throw an error, but return nil
    assert(Natives.NonExistentNative == nil, "Non-existent native should be nil")
    
    -- Calling a non-existent native should return nil
    local result = Natives.NonExistentNative and Natives.NonExistentNative() or nil
    assert(result == nil, "Calling a non-existent native should return nil")
end)

-- Print test summary
print(string.format("\nTest Summary: %d passed, %d failed, %d total", 
    tests.passed, tests.failed, tests.total))

-- Clean up the global namespace
for name, _ in pairs(mockNatives) do
    _G[name] = nil
end

return tests
