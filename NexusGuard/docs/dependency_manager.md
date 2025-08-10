# Dependency Manager Documentation

## Overview

The Dependency Manager is a core component of the NexusGuard framework that handles detection, validation, and fallback mechanisms for external dependencies. It ensures that the framework can operate effectively even when certain dependencies are missing or outdated.

## Features

- **Dependency Detection**: Automatically detects the presence of required dependencies
- **Version Validation**: Checks if installed dependencies meet minimum version requirements
- **Fallback Mechanisms**: Provides fallback implementations for missing dependencies
- **Warning System**: Issues warnings for missing or outdated dependencies
- **Status Reporting**: Provides detailed status information about all dependencies

## API Reference

### `DependencyManager.Initialize(logFunction)`

Initializes the dependency manager and checks for all required dependencies.

**Parameters:**
- `logFunction` (function, optional): A function to use for logging

**Example:**
```lua
DependencyManager.Initialize(function(message, level)
    print("[NexusGuard] " .. message)
end)
```

### `DependencyManager.IsVersionAtLeast(version, minVersion)`

Checks if a version meets the minimum requirement.

**Parameters:**
- `version` (string): The current version to check
- `minVersion` (string): The minimum required version

**Returns:**
- (boolean): True if the version meets or exceeds the minimum requirement, false otherwise

**Example:**
```lua
local isCompatible = DependencyManager.IsVersionAtLeast("2.1.0", "2.0.0") -- Returns true
```

### `DependencyManager.CompareVersions(version1, version2)`

Compares two version strings.

**Parameters:**
- `version1` (string): The first version to compare
- `version2` (string): The second version to compare

**Returns:**
- (number): 1 if version1 is greater, -1 if version2 is greater, 0 if equal

**Example:**
```lua
local result = DependencyManager.CompareVersions("2.1.0", "2.0.0") -- Returns 1
```

### `DependencyManager.GetStatus()`

Returns the status of all dependencies.

**Returns:**
- (table): A table containing the status of all dependencies

**Example:**
```lua
local status = DependencyManager.GetStatus()
for name, info in pairs(status) do
    print(name .. ": " .. (info.available and "Available" or "Missing"))
    if info.version then
        print("  Version: " .. info.version)
    end
    if info.warning then
        print("  Warning: " .. info.warning)
    end
end
```

## Dependency Status

The dependency manager tracks the status of the following dependencies:

### oxmysql

Required for database operations. The dependency manager checks for:
- Availability of the oxmysql resource
- Version compatibility (minimum version: 2.0.0)
- Proper initialization

### ox_lib

Required for various utilities, including the security token system. The dependency manager checks for:
- Availability of the ox_lib resource
- Version compatibility (minimum version: 2.0.0)
- Proper initialization of the crypto module

### screenshot-basic

Required for screenshot functionality. The dependency manager checks for:
- Availability of the screenshot-basic resource

## Fallback Mechanisms

When a dependency is missing, the dependency manager provides fallback implementations:

### oxmysql Fallbacks

If oxmysql is missing, the following fallbacks are provided:
- In-memory storage for bans (limited functionality)
- Disabled detection history
- Disabled session tracking

### ox_lib Fallbacks

If ox_lib is missing, the following fallbacks are provided:
- Basic security token implementation (less secure)
- Simplified notification system

## Best Practices

1. **Always check dependency status before using features**: Use the dependency status to determine if a feature is available.

   ```lua
   local status = DependencyManager.GetStatus()
   if status.oxmysql.available then
       -- Use database features
   else
       -- Use alternative approach
   end
   ```

2. **Handle version warnings**: Check for warnings in the dependency status to identify potential issues.

   ```lua
   local status = DependencyManager.GetStatus()
   if status.ox_lib.warning then
       Utils.Log("Warning for ox_lib: " .. status.ox_lib.warning, Utils.logLevels.WARNING)
   end
   ```

3. **Provide graceful degradation**: Design your code to work with reduced functionality when dependencies are missing.

   ```lua
   function SaveBan(banData)
       local status = DependencyManager.GetStatus()
       if status.oxmysql.available then
           -- Save to database
           return Database.SaveBan(banData)
       else
           -- Save to memory
           return MemoryStorage.SaveBan(banData)
       end
   end
   ```

## Troubleshooting

### Missing Dependencies

If a dependency is reported as missing:

1. Ensure the resource is installed in your server
2. Check that the resource is started before NexusGuard in your server.cfg
3. Verify the resource is working correctly by checking its logs

### Version Compatibility Issues

If a dependency is reported as outdated:

1. Update the dependency to the latest version
2. Check for any breaking changes in the dependency's documentation
3. If you cannot update, consider modifying the minimum version requirement in the dependency manager

### Fallback Limitations

If you're experiencing issues with fallback implementations:

1. Be aware of the limitations of fallbacks (e.g., in-memory storage is not persistent)
2. Consider installing the missing dependency for full functionality
3. Adjust your usage to work within the constraints of the fallback implementation

## Example: Complete Dependency Check

```lua
-- Initialize the dependency manager
DependencyManager.Initialize(Utils.Log)

-- Get the status of all dependencies
local status = DependencyManager.GetStatus()

-- Log the status of each dependency
for name, info in pairs(status) do
    local statusMsg = info.available and "Available" or "Missing"
    local versionMsg = info.version and (" (version: " .. info.version .. ")") or ""
    local warningMsg = info.warning and (" Warning: " .. info.warning) or ""
    
    Utils.Log("%s: %s%s%s", Utils.logLevels.INFO, name, statusMsg, versionMsg, warningMsg)
end

-- Check if we can proceed with full functionality
local canUseDatabase = status.oxmysql.available and not status.oxmysql.warning
local canUseSecureTokens = status.ox_lib.available and not status.ox_lib.warning
local canUseScreenshots = status.screenshot.available

-- Initialize features based on dependency availability
if canUseDatabase then
    Database.Initialize()
else
    Utils.Log("Database features will be limited due to missing or outdated oxmysql", Utils.logLevels.WARNING)
    MemoryStorage.Initialize()
end

if canUseSecureTokens then
    Security.InitializeTokenSystem()
else
    Utils.Log("Using fallback security token system (less secure)", Utils.logLevels.WARNING)
    Security.InitializeFallbackTokenSystem()
end

if canUseScreenshots then
    ScreenCapture.Initialize()
else
    Utils.Log("Screenshot functionality disabled", Utils.logLevels.WARNING)
end
```
