--[[
    NexusGuard API Refresh Test (tests/utils_api_refresh_test.lua)

    Purpose:
    - Ensures the NexusGuard API is reacquired when the fallback is cached
    - Confirms RefreshNexusGuardAPI forces a relookup
    - Verifies logging uses the real API once it becomes available
]]

local Utils = require('shared/utils')

local tests = { passed = 0, failed = 0, total = 0 }
local function test(name, func)
    tests.total = tests.total + 1
    local ok, err = pcall(func)
    if ok then
        print(string.format("\226\156\147 Test passed: %s", name))
        tests.passed = tests.passed + 1
    else
        print(string.format("\226\156\151 Test failed: %s\n  Error: %s", name, err))
        tests.failed = tests.failed + 1
    end
end

-- Test: Log uses real API once available
test("Log uses real API once available", function()
    -- Ensure no real API is present
    _G.NexusGuard = nil
    Utils.nexusGuardAPI = nil

    -- Capture fallback log output
    local fallbackLogs = {}
    local originalPrint = print
    print = function(...)
        table.insert(fallbackLogs, table.concat({...}, ' '))
    end

    -- First log call should use fallback
    Utils.Log("fallback")

    -- Provide a real API that records logs
    local realLogs = {}
    _G.NexusGuard = { Utils = { Log = function(msg) table.insert(realLogs, msg) end } }

    -- Second log call should use the real API
    Utils.Log("real")

    -- Restore print
    print = originalPrint

    assert(#fallbackLogs == 1, "Fallback log should have been used once")
    assert(#realLogs == 1, "Real API log should have been used once available")
end)

-- Test: RefreshNexusGuardAPI forces relookup
test("RefreshNexusGuardAPI forces relookup", function()
    _G.NexusGuard = nil
    Utils.nexusGuardAPI = nil

    -- Initial call caches dummy API
    local api1 = Utils.GetNexusGuardAPI()
    assert(api1.__isDummy, "Initial API should be dummy")

    -- Set a new real API and refresh
    local realApi = { Utils = { Log = function() end } }
    _G.NexusGuard = realApi
    Utils.RefreshNexusGuardAPI()
    local api2 = Utils.GetNexusGuardAPI()
    assert(api2 == realApi, "Refresh should update the cached API")
end)

print(string.format("\nTest Summary: %d passed, %d failed, %d total", tests.passed, tests.failed, tests.total))
return tests
