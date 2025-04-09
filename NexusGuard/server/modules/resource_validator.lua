--[[
    NexusGuard Resource Validator (server/modules/resource_validator.lua)
    
    Purpose:
    - Monitors and validates server resources
    - Detects unauthorized changes to critical files
    - Prevents execution of potentially malicious code
    - Maintains resource integrity
    
    Features:
    - Resource hash verification
    - File integrity monitoring
    - Injection detection
    - Suspicious code pattern detection
    - Resource state change tracking
    - Whitelist/blacklist support
]]

-- Load shared modules using the module loader to prevent circular dependencies
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local Natives = ModuleLoader.Load('shared/natives')
local EventRegistry = ModuleLoader.Load('shared/event_registry')

-- Get the NexusGuard Server API
local NexusGuardServer = Utils.GetNexusGuardAPI()
if not NexusGuardServer then
    print("^1[NexusGuard ResourceValidator] CRITICAL: Failed to get NexusGuardServer API. Some functionality will be limited.^7")
    -- Create dummy API to prevent immediate errors
    NexusGuardServer = {
        Config = { Features = { resourceVerification = { enabled = false } } },
        Utils = { Log = function(...) print("[NexusGuard ResourceValidator Fallback Log]", ...) end }
    }
end

-- Shorthand for logging function
local Log = function(...)
    if NexusGuardServer and NexusGuardServer.Utils and NexusGuardServer.Utils.Log then
        NexusGuardServer.Utils.Log(...)
    else
        print("[NexusGuard ResourceValidator]", ...)
    end
end

-- Attempt to load crypto functions from ox_lib
local hasOxLib = pcall(function() return lib and lib.crypto ~= nil end)
local hashFunction = nil

if hasOxLib and lib and lib.crypto and lib.crypto.hash then
    hashFunction = function(data)
        return lib.crypto.hash('sha256', data)
    end
    Log("^2[ResourceValidator]^7 Using ox_lib crypto functions for resource validation", 2)
else
    -- Fallback to a simple hash function if ox_lib is not available
    hashFunction = function(data)
        if not data then return "0" end
        
        local h = 0
        for i = 1, #data do
            h = (h * 31 + string.byte(data, i)) % 2^32
        end
        return tostring(h)
    end
    Log("^3[ResourceValidator]^7 Using fallback hash function for resource validation", 2)
end

-- Resource Validator module
local ResourceValidator = {
    -- Configuration
    scanInterval = 60000, -- 1 minute between full scans
    lastFullScan = 0,
    
    -- Resource tracking
    resourceStates = {},
    knownResources = {},
    resourceHashes = {},
    fileHashes = {},
    dependencies = {},
    
    -- Critical files that should be monitored
    criticalFiles = {
        "fxmanifest.lua",
        "__resource.lua",
        "client/main.lua",
        "server/main.lua",
        "client.lua",
        "server.lua",
        "config.lua"
    },
    
    -- Whitelisted resources that are allowed to change
    whitelistedResources = {
        ["monitor"] = true,
        ["oxmysql"] = true,
        ["ox_lib"] = true,
        ["screenshot-basic"] = true
    },
    
    -- Known injection patterns
    injectionPatterns = {
        "Citizen.CreateThread%s*%(.-TriggerServerEvent.-end%s*%)", -- Suspicious event triggers
        "ExecuteCommand%s*%(", -- Command execution
        "_G%s*%[.-TriggerServerEvent", -- Global table manipulation with events
        "pcall%s*%(.-TriggerServerEvent", -- Protected calls with events
        "load%s*%(.-%)", -- Dynamic code loading
        "assert%s*%(.-%)", -- Assertion with code execution
        "rawget%s*%(.-%)", -- Raw table access
        "rawset%s*%(.-%)", -- Raw table modification
        "debug%.setupvalue" -- Debug library manipulation
    }
}

-- Initialize resource tracking
function ResourceValidator.Initialize()
    Log("^2[ResourceValidator]^7 Initializing resource validation system", 2)
    
    -- Initialize resource tracking tables
    ResourceValidator.resourceStates = {}
    ResourceValidator.knownResources = {}
    ResourceValidator.resourceHashes = {}
    ResourceValidator.fileHashes = {}
    ResourceValidator.dependencies = {}
    
    -- Get all current resources
    local resources = {}
    local i = 0
    local resourceName = Natives.GetResourceByFindIndex(i)

    while resourceName do
        table.insert(resources, resourceName)
        i = i + 1
        resourceName = Natives.GetResourceByFindIndex(i)
    end

    -- Initialize resource states
    for _, name in ipairs(resources) do
        ResourceValidator.resourceStates[name] = Natives.GetResourceState(name)
        ResourceValidator.knownResources[name] = true

        -- Generate initial hashes for critical files
        ResourceValidator.GenerateResourceHashes(name)
        
        -- Track dependencies
        ResourceValidator.dependencies[name] = {}
        ResourceValidator.TrackResourceDependencies(name)
    end
    
    -- Set up state change monitoring
    Natives.AddEventHandler('onResourceStarting', function(resourceName)
        ResourceValidator.OnResourceStateChange(resourceName, 'starting')
    end)
    
    Natives.AddEventHandler('onResourceStart', function(resourceName)
        ResourceValidator.OnResourceStateChange(resourceName, 'started')
    end)
    
    Natives.AddEventHandler('onResourceStop', function(resourceName)
        ResourceValidator.OnResourceStateChange(resourceName, 'stopped')
    end)
    
    -- Schedule periodic full scans
    Natives.CreateThread(function()
        while true do
            Natives.Wait(ResourceValidator.scanInterval)
            ResourceValidator.PerformFullScan()
        end
    end)
    
    return true
end

-- Generate hashes for critical resource files
function ResourceValidator.GenerateResourceHashes(resourceName)
    local resourcePath = Natives.GetResourcePath(resourceName)
    if not resourcePath or resourcePath == "" then return false end
    
    ResourceValidator.fileHashes[resourceName] = {}
    
    -- Check each critical file
    for _, fileName in ipairs(ResourceValidator.criticalFiles) do
        local fileContent = Natives.LoadResourceFile(resourceName, fileName)
        if fileContent then
            local hash = hashFunction(fileContent)
            ResourceValidator.fileHashes[resourceName][fileName] = hash
        end
    end
    
    -- Generate a combined hash for the resource
    local manifestContent = Natives.LoadResourceFile(resourceName, "fxmanifest.lua") or
                           Natives.LoadResourceFile(resourceName, "__resource.lua") or ""
    
    ResourceValidator.resourceHashes[resourceName] = hashFunction(manifestContent)
    
    return true
end

-- Track resource dependencies
function ResourceValidator.TrackResourceDependencies(resourceName)
    ResourceValidator.dependencies[resourceName] = ResourceValidator.dependencies[resourceName] or {}
    
    -- Get dependencies
    local i = 0
    while true do
        local dependencyName = Natives.GetResourceMetadata(resourceName, "dependency_" .. i, 0)
        if not dependencyName then break end
        
        ResourceValidator.dependencies[resourceName][dependencyName] = true
        i = i + 1
    end
    
    -- Check fx_version and game
    local fxVersion = Natives.GetResourceMetadata(resourceName, "fx_version", 0)
    local game = Natives.GetResourceMetadata(resourceName, "game", 0)
    
    if fxVersion then
        ResourceValidator.dependencies[resourceName]["fx_version"] = fxVersion
    end
    
    if game then
        ResourceValidator.dependencies[resourceName]["game"] = game
    end
    
    return true
end

-- Check for suspicious code patterns
function ResourceValidator.CheckForSuspiciousCode(resourceName, fileContent)
    if not fileContent then return false, nil end
    
    -- Check for known injection patterns
    for _, pattern in ipairs(ResourceValidator.injectionPatterns) do
        if string.find(fileContent, pattern) then
            return true, pattern
        end
    end
    
    return false, nil
end

-- Handle resource state changes
function ResourceValidator.OnResourceStateChange(resourceName, newState)
    -- Update resource state
    ResourceValidator.resourceStates[resourceName] = newState
    ResourceValidator.knownResources[resourceName] = true
    
    Log(string.format("^3[ResourceValidator]^7 Resource '%s' state changed to '%s'", resourceName, newState), 3)
    
    -- Skip whitelisted resources
    if ResourceValidator.whitelistedResources[resourceName] then
        Log(string.format("^3[ResourceValidator]^7 Skipping validation for whitelisted resource '%s'", resourceName), 3)
        return
    end
    
    -- Verify resource when starting or started
    if newState == "starting" or newState == "started" then
        Natives.CreateThread(function()
            -- Small delay to ensure the resource is fully loaded
            Natives.Wait(500)
            
            -- Verify resource integrity
            local isValid, reason = ResourceValidator.VerifyResource(resourceName)
            if not isValid then
                Log(string.format("^1[ResourceValidator]^7 Resource '%s' failed validation during %s: %s", 
                    resourceName, newState, reason), 1)
                
                -- Report the detection
                EventRegistry.TriggerEvent("nexusguard:detection", {
                    type = "resource_validation",
                    resourceName = resourceName,
                    reason = reason,
                    state = newState
                })
                
                -- Take action based on configuration
                ResourceValidator.HandleResourceViolation(resourceName, reason, "High")
            else
                -- Generate new hashes for the resource
                ResourceValidator.GenerateResourceHashes(resourceName)
                
                -- Track dependencies
                ResourceValidator.TrackResourceDependencies(resourceName)
            end
        end)
    end
end

-- Perform a full scan of all resources
function ResourceValidator.PerformFullScan()
    Log("^2[ResourceValidator]^7 Performing full resource scan", 3)
    ResourceValidator.lastFullScan = Natives.GetGameTimer()
    
    -- Get all current resources
    local resources = {}
    local i = 0
    local resourceName = Natives.GetResourceByFindIndex(i)
    
    while resourceName do
        table.insert(resources, resourceName)
        i = i + 1
        resourceName = Natives.GetResourceByFindIndex(i)
    end
    
    -- Check for new or removed resources
    local currentResources = {}
    for _, name in ipairs(resources) do
        currentResources[name] = true
        
        -- Check if this is a new resource
        if not ResourceValidator.knownResources[name] then
            Log(string.format("^3[ResourceValidator]^7 Detected new resource: %s", name), 2)
            ResourceValidator.knownResources[name] = true
            ResourceValidator.resourceStates[name] = Natives.GetResourceState(name)
            
            -- Verify the new resource
            local isValid, reason = ResourceValidator.VerifyResource(name)
            if not isValid then
                Log(string.format("^1[ResourceValidator]^7 New resource '%s' failed validation: %s", 
                    name, reason), 1)
                
                -- Report the detection
                EventRegistry.TriggerEvent("nexusguard:detection", {
                    type = "resource_validation",
                    resourceName = name,
                    reason = reason,
                    state = Natives.GetResourceState(name)
                })
            end
        end
    end
    
    -- Verify file integrity for existing resources
    for name, _ in pairs(ResourceValidator.knownResources) do
        -- Skip whitelisted resources
        if ResourceValidator.whitelistedResources[name] then
            goto continue
        end
        
        -- Check if resource still exists
        if not currentResources[name] then
            Log(string.format("^3[ResourceValidator]^7 Resource no longer exists: %s", name), 2)
            ResourceValidator.knownResources[name] = nil
            ResourceValidator.resourceStates[name] = nil
            ResourceValidator.resourceHashes[name] = nil
            ResourceValidator.fileHashes[name] = nil
            ResourceValidator.dependencies[name] = nil
            goto continue
        end
        
        -- Check for file changes
        local hasChanges = false
        local changedFiles = {}
        
        -- Check each critical file
        for fileName, previousHash in pairs(ResourceValidator.fileHashes[name] or {}) do
            if previousHash then
                local fileContent = Natives.LoadResourceFile(name, fileName)
                if fileContent then
                    local currentHash = hashFunction(fileContent)
                    
                    if currentHash ~= previousHash then
                        hasChanges = true
                        table.insert(changedFiles, fileName)
                        
                        -- Check for suspicious code
                        local isSuspicious, pattern = ResourceValidator.CheckForSuspiciousCode(name, fileContent)
                        if isSuspicious then
                            Log(string.format("^1[ResourceValidator]^7 Detected suspicious code in resource '%s' file '%s': %s", 
                                name, fileName, pattern), 1)
                            
                            -- Report the detection
                            EventRegistry.TriggerEvent("nexusguard:detection", {
                                type = "suspicious_code",
                                resourceName = name,
                                fileName = fileName,
                                pattern = pattern,
                                severity = "High"
                            })
                            
                            -- Take action based on configuration
                            ResourceValidator.HandleResourceViolation(name, "suspicious_code:" .. pattern, "High")
                        end
                    end
                else
                    -- File was removed
                    hasChanges = true
                    table.insert(changedFiles, fileName .. " (removed)")
                end
            end
        end
        
        -- Check for new critical files
        for _, fileName in ipairs(ResourceValidator.criticalFiles) do
            if not ResourceValidator.fileHashes[name] or not ResourceValidator.fileHashes[name][fileName] then
                -- Check if file exists now but didn't before
                local fileContent = Natives.LoadResourceFile(name, fileName)
                if fileContent then
                    hasChanges = true
                    table.insert(changedFiles, fileName .. " (added)")
                    
                    -- Generate hash for the new file
                    if not ResourceValidator.fileHashes[name] then
                        ResourceValidator.fileHashes[name] = {}
                    end
                    ResourceValidator.fileHashes[name][fileName] = hashFunction(fileContent)
                    
                    -- Check for suspicious code
                    local isSuspicious, pattern = ResourceValidator.CheckForSuspiciousCode(name, fileContent)
                    if isSuspicious then
                        Log(string.format("^1[ResourceValidator]^7 Detected suspicious code in new file '%s' in resource '%s': %s", 
                            fileName, name, pattern), 1)
                        
                        -- Report the detection
                        EventRegistry.TriggerEvent("nexusguard:detection", {
                            type = "suspicious_code",
                            resourceName = name,
                            fileName = fileName,
                            pattern = pattern,
                            severity = "High"
                        })
                        
                        -- Take action based on configuration
                        ResourceValidator.HandleResourceViolation(name, "suspicious_code:" .. pattern, "High")
                    end
                end
            end
        end
        
        -- Report changes
        if hasChanges then
            local changesStr = table.concat(changedFiles, ", ")
            Log(string.format("^3[ResourceValidator]^7 Detected changes in resource '%s': %s", 
                name, changesStr), 2)
            
            -- Report the detection
            EventRegistry.TriggerEvent("nexusguard:detection", {
                type = "resource_changed",
                resourceName = name,
                changedFiles = changedFiles,
                severity = "Medium"
            })
            
            -- Update hashes
            ResourceValidator.GenerateResourceHashes(name)
        end
        
        ::continue::
    end
end

-- Handle resource violations
function ResourceValidator.HandleResourceViolation(resourceName, violationType, severity)
    -- Get configuration
    local resourceVerification = NexusGuardServer.Config.Features.resourceVerification or {}
    
    -- Take action based on severity and configuration
    if severity == "High" then
        if resourceVerification.stopOnMismatch then
            Log(string.format("^1[ResourceValidator]^7 Stopping resource '%s' due to violation: %s", 
                resourceName, violationType), 1)
            Natives.ExecuteCommand("stop " .. resourceName)
        end
        
        if resourceVerification.banOnMismatch and severity == "High" then
            -- This would require integration with the ban system
            -- For now, just log it
            Log(string.format("^1[ResourceValidator]^7 Resource '%s' would trigger a ban due to: %s", 
                resourceName, violationType), 1)
        end
    end
end

-- Verify a resource's integrity
function ResourceValidator.VerifyResource(resourceName)
    if not Natives.GetResourceState(resourceName) then return false, "invalid_resource_state" end
    
    local resourcePath = Natives.GetResourcePath(resourceName)
    if not resourcePath or resourcePath == "" then return false, "invalid_resource_path" end
    
    -- Check resource metadata
    local resourceMetadata = Natives.GetResourceMetadata(resourceName, "version", 0)
    local isOneSync = Natives.GetConvar("onesync", "off") ~= "off"
    
    -- Verify manifest exists
    local manifestContent = Natives.LoadResourceFile(resourceName, "fxmanifest.lua")
    local legacyManifestContent = Natives.LoadResourceFile(resourceName, "__resource.lua")
    
    if not manifestContent and not legacyManifestContent then
        return false, "missing_manifest"
    end
    
    -- Verify resource dependencies
    local dependencies = {}
    local i = 0
    while true do
        local dependencyName = Natives.GetResourceMetadata(resourceName, "dependency_" .. i, 0)
        if not dependencyName then break end
        
        dependencies[dependencyName] = true
        
        -- Check if dependency is available
        if not Natives.GetResourceState(dependencyName) then
            return false, "missing_dependency:" .. dependencyName
        end
        
        i = i + 1
    end
    
    -- Verify fx_version and game
    local fxVersion = Natives.GetResourceMetadata(resourceName, "fx_version", 0)
    if not fxVersion then
        -- Legacy resources might not have fx_version
        if not legacyManifestContent then
            return false, "missing_fx_version"
        end
    end
    
    local game = Natives.GetResourceMetadata(resourceName, "game", 0)
    if not game and not legacyManifestContent then
        -- Some resources might not specify game
        Log(string.format("^3[ResourceValidator]^7 Resource '%s' does not specify 'game' in manifest", resourceName), 3)
    end
    
    -- Verify critical files exist
    local hasCriticalFiles = false
    for _, fileName in ipairs(ResourceValidator.criticalFiles) do
        if Natives.LoadResourceFile(resourceName, fileName) then
            hasCriticalFiles = true
            break
        end
    end
    
    if not hasCriticalFiles then
        Log(string.format("^3[ResourceValidator]^7 Resource '%s' does not contain any critical files", resourceName), 3)
    end
    
    -- Check for suspicious code in critical files
    for _, fileName in ipairs(ResourceValidator.criticalFiles) do
        local fileContent = Natives.LoadResourceFile(resourceName, fileName)
        if fileContent then
            local isSuspicious, pattern = ResourceValidator.CheckForSuspiciousCode(resourceName, fileContent)
            if isSuspicious then
                return false, "suspicious_code:" .. pattern
            end
        end
    end
    
    return true
end

-- Export the module
return ResourceValidator
