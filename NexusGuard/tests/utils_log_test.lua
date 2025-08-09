--[[
    NexusGuard Utils Logging Test (tests/utils_log_test.lua)

    Purpose:
    - Ensures NexusGuard API is reacquired after using fallback
    - Verifies RefreshNexusGuardAPI forces lookup
]]

local Utils = require('shared/utils')

local tests = { passed = 0, failed = 0, total = 0 }

local function test(name, fn)
    tests.total = tests.total + 1
    local ok, err = pcall(fn)
    if ok then
        print(string.format("✓ Test passed: %s", name))
        tests.passed = tests.passed + 1
    else
        print(string.format("✗ Test failed: %s\n  Error: %s", name, err))
        tests.failed = tests.failed + 1
    end
end

-- Test: Reacquires API when it becomes available
test("Reacquires API after fallback", function()
    -- Ensure clean state
    Utils.nexusGuardAPI = nil
    Utils.nexusGuardAPIDummy = nil
    _G.NexusGuard = nil

    local fallbackLogs = {}
    local originalPrint = print
    print = function(...)
        table.insert(fallbackLogs, table.concat({...}, " "))
    end

    -- First log uses fallback
    Utils.Log("fallback")
    assert(#fallbackLogs > 0, "Fallback log should be recorded")

    -- Provide real API
    local apiLogs = {}
    _G.NexusGuard = { Utils = { Log = function(msg) table.insert(apiLogs, msg) end }, Config = {} }

    -- Next log should use real API via reacquisition
    Utils.Log("real")
    assert(#apiLogs > 0, "Real API should capture log")
    assert(Utils.GetNexusGuardAPI() == _G.NexusGuard, "Cached API should be the real API")

    print = originalPrint
end)

-- Test: RefreshNexusGuardAPI forces relookup
test("RefreshNexusGuardAPI forces relookup", function()
    -- Set a dummy API first
    Utils.nexusGuardAPI = { Utils = { Log = function() end }, Config = {} }
    Utils.nexusGuardAPIDummy = true
    _G.NexusGuard = nil

    -- Provide real API and refresh
    local refreshedLogs = {}
    _G.NexusGuard = { Utils = { Log = function(msg) table.insert(refreshedLogs, msg) end }, Config = {} }
    Utils.RefreshNexusGuardAPI()
    Utils.Log("refreshed")

    assert(#refreshedLogs > 0, "Refresh should use real API")
end)

print(string.format("\nTest Summary: %d passed, %d failed, %d total", tests.passed, tests.failed, tests.total))
return tests
