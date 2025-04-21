--[[
    NexusGuard Dependency Manager (shared/dependency_manager.lua)

    Provides centralized management of external dependencies:
    - Checks if required dependencies are available
    - Provides fallback implementations when possible
    - Offers consistent access to dependency functions
    - Handles version compatibility issues
]]

local Natives = require('shared/natives')

local DependencyManager = {
    -- Dependency status tracking
    status = {
        oxmysql = { available = false, version = nil, warning = nil, minVersion = "2.0.0" },
        ox_lib = { available = false, version = nil, warning = nil, minVersion = "2.0.0" },
        screenshot = { available = false, version = nil, warning = nil }
    },

    -- Fallback implementations
    fallbacks = {},

    -- Minimum required versions
    minVersions = {
        ox_lib = "2.0.0",
        oxmysql = "2.0.0"
    }
}

-- Environment detection
local isServer = Natives.IsDuplicityVersion and Natives.IsDuplicityVersion() or false

-- Logging function (will be replaced during initialization)
local Log = function(message, level)
    print("[DependencyManager] " .. tostring(message))
end

-- Helper function to compare version strings
function DependencyManager.CompareVersions(version1, version2)
    -- Convert version strings to tables of numbers
    local function parseVersion(versionStr)
        local versionTable = {}
        for part in string.gmatch(tostring(versionStr), "[^%.]+") do
            table.insert(versionTable, tonumber(part) or 0)
        end
        return versionTable
    end

    local v1 = parseVersion(version1)
    local v2 = parseVersion(version2)

    -- Compare each part of the version
    for i = 1, math.max(#v1, #v2) do
        local num1 = v1[i] or 0
        local num2 = v2[i] or 0

        if num1 > num2 then
            return 1  -- version1 is greater
        elseif num1 < num2 then
            return -1 -- version2 is greater
        end
    end

    return 0 -- versions are equal
end

-- Check if a version meets the minimum requirement
function DependencyManager.IsVersionAtLeast(version, minVersion)
    return DependencyManager.CompareVersions(version, minVersion) >= 0
end

-- Initialize the dependency manager
function DependencyManager.Initialize(logFunction)
    if logFunction and type(logFunction) == "function" then
        Log = logFunction
    end

    -- Check for ox_lib with FiveM-compatible approach
    local success, result = pcall(function()
        -- Try multiple methods to detect ox_lib
        if _G.lib ~= nil then
            return { available = true, source = "global" }
        elseif _G.exports and _G.exports['ox_lib'] then
            return { available = true, source = "export" }
        end
        return { available = false }
    end)

    DependencyManager.status.ox_lib.available = success and result.available or false

    if DependencyManager.status.ox_lib.available then
        -- Try to get version information
        if _G.lib and _G.lib.version then
            DependencyManager.status.ox_lib.version = _G.lib.version

            -- Check if version meets minimum requirement
            local minVersion = DependencyManager.minVersions.ox_lib
            if DependencyManager.IsVersionAtLeast(_G.lib.version, minVersion) then
                Log(
                    "ox_lib detected (version: " ..
                    tostring(_G.lib.version) .. ", source: " .. (result.source or "unknown") .. ")", 3)
            else
                local warningMsg = "^3WARNING: ox_lib version " ..
                    tostring(_G.lib.version) ..
                    " is below the recommended minimum (" .. minVersion .. "). Some features may not work correctly.^7"
                Log(warningMsg, 2)
                DependencyManager.status.ox_lib.warning = "Version below minimum requirement"
            end
        else
            Log("ox_lib detected (version unknown, source: " .. (result.source or "unknown") .. ")", 3)
            DependencyManager.status.ox_lib.warning = "Version unknown"
        end
    else
        Log("^3WARNING: ox_lib not found. Some features will be limited.^7", 2)
    end

    -- Server-only dependency checks
    if isServer then
        -- Check for oxmysql with FiveM-compatible approach
        local mysqlSuccess, mysqlResult = pcall(function()
            if _G.MySQL ~= nil then
                return { available = true, source = "global" }
            elseif _G.exports and _G.exports['oxmysql'] then
                return { available = true, source = "export" }
            end
            return { available = false }
        end)

        DependencyManager.status.oxmysql.available = mysqlSuccess and mysqlResult.available or false

        if DependencyManager.status.oxmysql.available then
            -- Try to get version information (may not be available)
            local version = nil

            -- Try to get version from resource metadata
            if Natives and Natives.GetResourceMetadata then
                version = Natives.GetResourceMetadata('oxmysql', 'version', 0)
                if version and version ~= "" then
                    DependencyManager.status.oxmysql.version = version

                    -- Check if version meets minimum requirement
                    local minVersion = DependencyManager.minVersions.oxmysql
                    if DependencyManager.IsVersionAtLeast(version, minVersion) then
                        Log(
                        "oxmysql detected (version: " ..
                        tostring(version) .. ", source: " .. (mysqlResult.source or "unknown") .. ")", 3)
                    else
                        local warningMsg = "^3WARNING: oxmysql version " ..
                        tostring(version) ..
                        " is below the recommended minimum (" ..
                        minVersion .. "). Some database features may not work correctly.^7"
                        Log(warningMsg, 2)
                        DependencyManager.status.oxmysql.warning = "Version below minimum requirement"
                    end
                else
                    Log("oxmysql detected (version unknown, source: " .. (mysqlResult.source or "unknown") .. ")", 3)
                    DependencyManager.status.oxmysql.warning = "Version unknown"
                end
            else
                Log("oxmysql detected (version unknown, source: " .. (mysqlResult.source or "unknown") .. ")", 3)
                DependencyManager.status.oxmysql.warning = "Version unknown"
            end
        else
            Log("^3WARNING: oxmysql not found. Database features will be disabled.^7", 2)
        end

        -- Check for screenshot-basic
        local resourceState = Natives.GetResourceState('screenshot-basic')
        DependencyManager.status.screenshot.available = resourceState == 'started'
        if DependencyManager.status.screenshot.available then
            Log("screenshot-basic detected", 3)
        else
            Log("^3WARNING: screenshot-basic not found or not started. Screenshot features will be disabled.^7", 2)
        end
    end

    return DependencyManager.status
end

-- Get crypto functions (from ox_lib or fallback)
DependencyManager.Crypto = {
    -- HMAC functions
    hmac = {
        sha256 = function(key, message)
            -- Try to use ox_lib's crypto functions
            if DependencyManager.status.ox_lib.available then
                -- Try global lib first
                if _G.lib and _G.lib.crypto and _G.lib.crypto.hmac and _G.lib.crypto.hmac.sha256 then
                    return _G.lib.crypto.hmac.sha256(key, message)
                end

                -- Try exports as fallback
                if _G.exports and _G.exports['ox_lib'] then
                    local success, result = pcall(function()
                        return _G.exports['ox_lib']:hmacSha256(key, message)
                    end)
                    if success and result then
                        return result
                    end
                end
            end

            -- Fallback implementation (less secure but better than nothing)
            Log("^3WARNING: Using fallback HMAC-SHA256 implementation. Security may be reduced.^7", 2)
            local combinedStr = key .. "::hmac::" .. message

            -- Use FiveM's GetHashKey as a very basic hash function
            if _G.GetHashKey then
                local hash = _G.GetHashKey(combinedStr)
                return string.format("%x", hash)
            end

            -- Last resort fallback
            Log("^1ERROR: No HMAC-SHA256 implementation available.^7", 1)
            return nil
        end
    },

    -- Hash functions
    hash = {
        sha256 = function(data)
            -- Try to use ox_lib's crypto functions
            if DependencyManager.status.ox_lib.available then
                -- Try global lib first
                if _G.lib and _G.lib.crypto and _G.lib.crypto.hash and _G.lib.crypto.hash.sha256 then
                    return _G.lib.crypto.hash.sha256(data)
                end

                -- Try exports as fallback
                if _G.exports and _G.exports['ox_lib'] then
                    local success, result = pcall(function()
                        return _G.exports['ox_lib']:sha256(data)
                    end)
                    if success and result then
                        return result
                    end
                end
            end

            -- Fallback implementation (less secure but better than nothing)
            Log("^3WARNING: Using fallback SHA-256 implementation. Security may be reduced.^7", 2)

            -- Use FiveM's GetHashKey as a very basic hash function
            if _G.GetHashKey then
                local hash = _G.GetHashKey(data)
                return string.format("%x", hash)
            end

            -- Last resort fallback
            Log("^1ERROR: No SHA-256 implementation available.^7", 1)
            return nil
        end
    }
}

-- Get JSON functions (from ox_lib or fallback)
DependencyManager.JSON = {
    encode = function(data)
        -- Try multiple JSON encoding methods in order of preference

        -- 1. Try ox_lib if available
        if DependencyManager.status.ox_lib.available then
            -- Try global lib first
            if _G.lib and _G.lib.json and _G.lib.json.encode then
                local success, result = pcall(function()
                    return _G.lib.json.encode(data)
                end)
                if success and result then
                    return result
                end
            end

            -- Try exports as fallback
            if _G.exports and _G.exports['ox_lib'] then
                local success, result = pcall(function()
                    return _G.exports['ox_lib']:encodeJson(data)
                end)
                if success and result then
                    return result
                end
            end
        end

        -- 2. Try native FiveM json.encode
        if _G.json and _G.json.encode then
            local success, result = pcall(function()
                return _G.json.encode(data)
            end)
            if success and result then
                return result
            end
        end

        -- 3. Last resort: basic table serialization
        Log("^3WARNING: Using fallback JSON encode implementation. Compatibility may be reduced.^7", 2)
        local function basicSerialize(tbl, depth)
            if depth > 10 then return "{\"error\":\"max_depth_exceeded\"}" end -- Prevent infinite recursion

            local result = "{"
            local first = true
            for k, v in pairs(tbl) do
                if not first then result = result .. "," end
                first = false

                -- Key
                result = result .. "\""
                result = result .. tostring(k):gsub("\\", "\\\\")
                    :gsub("\"", "\\\"")
                result = result .. "\":"

                -- Value
                if type(v) == "table" then
                    result = result .. basicSerialize(v, depth + 1)
                elseif type(v) == "string" then
                    result = result .. "\""
                    result = result .. v:gsub("\\", "\\\\")
                        :gsub("\"", "\\\"")
                    result = result .. "\""
                elseif type(v) == "number" then
                    result = result .. tostring(v)
                elseif type(v) == "boolean" then
                    result = result .. (v and "true" or "false")
                else
                    result = result .. "null"
                end
            end
            result = result .. "}"
            return result
        end

        if type(data) == "table" then
            return basicSerialize(data, 0)
        else
            return "{}"
        end
    end,

    decode = function(jsonString)
        -- Try multiple JSON decoding methods in order of preference

        -- 1. Try ox_lib if available
        if DependencyManager.status.ox_lib.available then
            -- Try global lib first
            if _G.lib and _G.lib.json and _G.lib.json.decode then
                local success, result = pcall(function()
                    return _G.lib.json.decode(jsonString)
                end)
                if success and result then
                    return result
                end
            end

            -- Try exports as fallback
            if _G.exports and _G.exports['ox_lib'] then
                local success, result = pcall(function()
                    return _G.exports['ox_lib']:decodeJson(jsonString)
                end)
                if success and result then
                    return result
                end
            end
        end

        -- 2. Try native FiveM json.decode
        if _G.json and _G.json.decode then
            local success, result = pcall(function()
                return _G.json.decode(jsonString)
            end)
            if success and result then
                return result
            end
        end

        -- 3. Last resort: return empty table
        Log("^3WARNING: No JSON decode function available.^7", 2)
        return {}
    end
}

-- Database functions (server-only)
DependencyManager.Database = {
    -- Check if database is available
    IsAvailable = function()
        return isServer and DependencyManager.status.oxmysql.available
    end,

    -- Execute a query with parameters
    Execute = function(query, params, callback)
        if not isServer then
            Log("^1ERROR: Attempted to call Database.Execute from client.^7", 1)
            return false
        end

        if not DependencyManager.status.oxmysql.available then
            Log("^1ERROR: Database.Execute called but oxmysql is not available.^7", 1)
            if callback then callback(false) end
            return false
        end

        if not query then
            Log("^1ERROR: Database.Execute called with nil query.^7", 1)
            if callback then callback(false) end
            return false
        end

        -- Try multiple methods to execute the query
        local success, result = pcall(function()
            -- Try global MySQL object first
            if _G.MySQL and _G.MySQL.Async and _G.MySQL.Async.execute then
                return _G.MySQL.Async.execute(query, params or {}, callback)
            end

            -- Try exports as fallback
            if _G.exports and _G.exports['oxmysql'] then
                if callback then
                    return _G.exports['oxmysql']:execute(query, params or {}, callback)
                else
                    return _G.exports['oxmysql']:execute(query, params or {})
                end
            end

            return false
        end)

        if not success then
            Log("^1ERROR: Database.Execute failed: " .. tostring(result) .. "^7", 1)
            if callback then callback(false) end
            return false
        end

        return result
    end,

    -- Fetch data from database
    Fetch = function(query, params, callback)
        if not isServer then
            Log("^1ERROR: Attempted to call Database.Fetch from client.^7", 1)
            return false
        end

        if not DependencyManager.status.oxmysql.available then
            Log("^1ERROR: Database.Fetch called but oxmysql is not available.^7", 1)
            if callback then callback({}) end
            return false
        end

        if not query then
            Log("^1ERROR: Database.Fetch called with nil query.^7", 1)
            if callback then callback({}) end
            return false
        end

        -- Try multiple methods to fetch data
        local success, result = pcall(function()
            -- Try global MySQL object first
            if _G.MySQL and _G.MySQL.Async and _G.MySQL.Async.fetchAll then
                return _G.MySQL.Async.fetchAll(query, params or {}, callback)
            end

            -- Try exports as fallback
            if _G.exports and _G.exports['oxmysql'] then
                if callback then
                    return _G.exports['oxmysql']:fetch(query, params or {}, callback)
                else
                    return _G.exports['oxmysql']:fetch(query, params or {})
                end
            end

            return false
        end)

        if not success then
            Log("^1ERROR: Database.Fetch failed: " .. tostring(result) .. "^7", 1)
            if callback then callback({}) end
            return false
        end

        return result
    end,

    -- Insert data and get the inserted ID
    Insert = function(query, params, callback)
        if not isServer then
            Log("^1ERROR: Attempted to call Database.Insert from client.^7", 1)
            return false
        end

        if not DependencyManager.status.oxmysql.available then
            Log("^1ERROR: Database.Insert called but oxmysql is not available.^7", 1)
            if callback then callback(0) end
            return false
        end

        if not query then
            Log("^1ERROR: Database.Insert called with nil query.^7", 1)
            if callback then callback(0) end
            return false
        end

        -- Try multiple methods to insert data
        local success, result = pcall(function()
            -- Try global MySQL object first
            if _G.MySQL and _G.MySQL.Async and _G.MySQL.Async.insert then
                return _G.MySQL.Async.insert(query, params or {}, callback)
            end

            -- Try exports as fallback
            if _G.exports and _G.exports['oxmysql'] then
                if callback then
                    return _G.exports['oxmysql']:insert(query, params or {}, callback)
                else
                    return _G.exports['oxmysql']:insert(query, params or {})
                end
            end

            return false
        end)

        if not success then
            Log("^1ERROR: Database.Insert failed: " .. tostring(result) .. "^7", 1)
            if callback then callback(0) end
            return false
        end

        return result
    end,

    -- Single row fetch
    FetchScalar = function(query, params, callback)
        if not isServer then
            Log("^1ERROR: Attempted to call Database.FetchScalar from client.^7", 1)
            return false
        end

        if not DependencyManager.status.oxmysql.available then
            Log("^1ERROR: Database.FetchScalar called but oxmysql is not available.^7", 1)
            if callback then callback(nil) end
            return false
        end

        if not query then
            Log("^1ERROR: Database.FetchScalar called with nil query.^7", 1)
            if callback then callback(nil) end
            return false
        end

        -- Try multiple methods to fetch a scalar
        local success, result = pcall(function()
            -- Try global MySQL object first
            if _G.MySQL and _G.MySQL.Async and _G.MySQL.Async.fetchScalar then
                return _G.MySQL.Async.fetchScalar(query, params or {}, callback)
            end

            -- Try exports as fallback
            if _G.exports and _G.exports['oxmysql'] then
                if callback then
                    return _G.exports['oxmysql']:scalar(query, params or {}, callback)
                else
                    return _G.exports['oxmysql']:scalar(query, params or {})
                end
            end

            return false
        end)

        if not success then
            Log("^1ERROR: Database.FetchScalar failed: " .. tostring(result) .. "^7", 1)
            if callback then callback(nil) end
            return false
        end

        return result
    end
}

-- Screenshot functions (server-only)
DependencyManager.Screenshot = {
    -- Check if screenshot functionality is available
    IsAvailable = function()
        return isServer and DependencyManager.status.screenshot.available
    end,

    -- Request a screenshot from a client
    Request = function(playerId, callback, options)
        if not isServer then
            Log("^1ERROR: Attempted to call Screenshot.Request from client.^7", 1)
            return false
        end

        if not DependencyManager.status.screenshot.available then
            Log("^1ERROR: Screenshot.Request called but screenshot-basic is not available.^7", 1)
            if callback then callback(nil) end
            return false
        end

        if not playerId or playerId <= 0 then
            Log("^1ERROR: Screenshot.Request called with invalid player ID.^7", 1)
            if callback then callback(nil) end
            return false
        end

        -- Default options
        options = options or {}
        options.encoding = options.encoding or 'jpg'
        options.quality = options.quality or 0.85

        -- Request screenshot
        if _G.exports and _G.exports['screenshot-basic'] then
            local success, result = pcall(function()
                return _G.exports['screenshot-basic']:requestClientScreenshot(playerId, {
                    encoding = options.encoding,
                    quality = options.quality
                }, function(err, data)
                    if callback then
                        callback(err and nil or data, err)
                    end
                end)
            end)

            if not success then
                Log("^1ERROR: Screenshot.Request failed: " .. tostring(result) .. "^7", 1)
                if callback then callback(nil, "Screenshot request failed") end
                return false
            end

            return true
        else
            Log("^1ERROR: screenshot-basic exports not available.^7", 1)
            if callback then callback(nil, "Exports not available") end
            return false
        end
    end
}

return DependencyManager
