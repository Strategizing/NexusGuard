--[[
    NexusGuard Module Loader Test (tests/module_loader_test.lua)

    Purpose:
    - Tests the functionality of the module loader
    - Ensures modules are loaded correctly
    - Verifies circular dependency handling
    - Tests optional module loading
]]

-- Load the module loader
local ModuleLoader = require('shared/module_loader')

-- Mock modules for testing
local mockModules = {
    ['test/module_a'] = function()
        return {
            name = 'Module A',
            getValue = function() return 'A' end
        }
    end,
    ['test/module_b'] = {
        name = 'Module B',
        getValue = function() return 'B' end,
        getDependencyValue = function()
            local ModuleA = ModuleLoader.Load('test/module_a')
            return ModuleA.getValue()
        end
    },
    ['test/circular_a'] = {
        name = 'Circular A',
        getValue = function() return 'Circular A' end,
        getDependencyValue = function() 
            local CircularB = ModuleLoader.Load('test/circular_b')
            return CircularB.getValue() 
        end
    },
    ['test/circular_b'] = {
        name = 'Circular B',
        getValue = function() return 'Circular B' end,
        getDependencyValue = function()
            local CircularA = ModuleLoader.Load('test/circular_a')
            return CircularA.getValue()
        end
    },
    ['test/function_module'] = function()
        return function()
            return 'Function Module'
        end
    end
}

-- Override the require function for testing
local originalRequire = _G.require
_G.require = function(modulePath)
    if mockModules[modulePath] ~= nil then
        local mod = mockModules[modulePath]
        if type(mod) == 'function' then
            return mod()
        end
        return mod
    end
    return originalRequire(modulePath)
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
    local status, err = pcall(func)
    if status then
        print(string.format("✓ Test passed: %s", name))
        tests.passed = tests.passed + 1
    else
        print(string.format("✗ Test failed: %s\n  Error: %s", name, err))
        tests.failed = tests.failed + 1
    end
end

-- Test: Load a module
test("Load a module", function()
    local moduleA = ModuleLoader.Load('test/module_a')
    assert(moduleA ~= nil, "Module A should be loaded")
    assert(moduleA.name == 'Module A', "Module A should have the correct name")
    assert(moduleA.getValue() == 'A', "Module A should return the correct value")
end)

-- Test: Load a module with dependencies
test("Load a module with dependencies", function()
    local moduleB = ModuleLoader.Load('test/module_b')
    assert(moduleB ~= nil, "Module B should be loaded")
    assert(moduleB.getDependencyValue() == 'A', "Module B should get the correct value from Module A")
end)

-- Test: Handle circular dependencies
test("Handle circular dependencies", function()
    local circularA = ModuleLoader.Load('test/circular_a')
    assert(circularA ~= nil, "Circular Module A should be loaded")
    
    -- This should not cause an infinite loop
    local valueFromB = circularA.getDependencyValue()
    assert(valueFromB == 'Circular B', "Circular Module A should get the correct value from Circular Module B")
    
    local circularB = ModuleLoader.Load('test/circular_b')
    local valueFromA = circularB.getDependencyValue()
    assert(valueFromA == 'Circular A', "Circular Module B should get the correct value from Circular Module A")
end)

-- Test: Load a non-existent module
test("Load a non-existent module", function()
    local nonexistentModule = ModuleLoader.Load('test/nonexistent')
    assert(nonexistentModule == nil, "Non-existent module should return nil")
end)

-- Test: Load an optional module
test("Load an optional module", function()
    local nonexistentModule = ModuleLoader.Load('test/nonexistent', true)
    assert(nonexistentModule == nil, "Optional non-existent module should return nil without error")

    local moduleA = ModuleLoader.Load('test/module_a', true)
    assert(moduleA ~= nil, "Optional existing module should be loaded")
end)

-- Test: Load a module that returns a function
test("Load a module that returns a function", function()
    local funcModule = ModuleLoader.Load('test/function_module')
    assert(type(funcModule) == 'function', "Function module should load as a function")
    assert(funcModule() == 'Function Module', "Function module should return correct value")
end)

-- Test: Module caching
test("Module caching", function()
    local moduleA1 = ModuleLoader.Load('test/module_a')
    local moduleA2 = ModuleLoader.Load('test/module_a')
    assert(moduleA1 == moduleA2, "The same module instance should be returned for multiple loads")
end)

-- Test: Clear cache
test("Clear cache", function()
    local moduleA1 = ModuleLoader.Load('test/module_a')
    ModuleLoader.ClearCache()
    local moduleA2 = ModuleLoader.Load('test/module_a')
    assert(moduleA1 ~= moduleA2, "Different module instances should be returned after clearing cache")
end)

-- Print test summary
print(string.format("\nTest Summary: %d passed, %d failed, %d total", 
    tests.passed, tests.failed, tests.total))

-- Restore the original require function
_G.require = originalRequire

return tests
