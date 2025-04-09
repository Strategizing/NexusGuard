# Natives Wrapper Documentation

## Overview

The Natives Wrapper provides a safe and consistent way to call FiveM native functions in the NexusGuard anti-cheat framework. It handles error checking, provides fallbacks, and ensures that native calls don't crash the script when they fail.

## Features

- **Error Handling**: Catches errors from native calls and provides graceful fallbacks
- **Consistent Interface**: Provides a unified interface for all native functions
- **Performance Monitoring**: Can be extended to include performance monitoring for native calls
- **Cross-Environment Compatibility**: Works in both client and server environments

## API Reference

### Native Function Calls

All FiveM native functions are available through the Natives wrapper with the same name and parameters as the original functions. The difference is that the wrapper provides error handling and consistent return values.

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
local Natives = ModuleLoader.Load('shared/natives')

-- Get player name (safe, won't crash if player doesn't exist)
local playerName = Natives.GetPlayerName(playerId)

-- Get entity coordinates (safe, returns nil if entity doesn't exist)
local coords = Natives.GetEntityCoords(entityId)

-- Check if we're on the server
local isServer = Natives.IsDuplicityVersion()
```

### Error Handling

When a native function call fails or throws an error, the wrapper will:
1. Log the error (if configured to do so)
2. Return `nil` instead of crashing the script
3. Optionally provide a fallback value

## Best Practices

1. **Always use the Natives wrapper**: This ensures consistent error handling and prevents script crashes.

2. **Check return values**: Always check if the return value is nil before using it.
   ```lua
   local coords = Natives.GetEntityCoords(entityId)
   if coords then
       -- Use the coordinates
   else
       -- Handle the error case
   end
   ```

3. **Use with conditional checks**: Combine with conditional operators for cleaner code.
   ```lua
   local playerName = Natives.GetPlayerName(playerId) or "Unknown Player"
   ```

4. **Avoid redundant error handling**: The wrapper already handles errors, so you don't need to use pcall around native calls.

## Example: Safe Entity Manipulation

```lua
local ModuleLoader = require('shared/module_loader')
local Natives = ModuleLoader.Load('shared/natives')

function SafeDeleteEntity(entity)
    if entity and Natives.DoesEntityExist(entity) then
        Natives.DeleteEntity(entity)
        return true
    end
    return false
end

function GetSafeCoordinates(entity)
    if not entity then return nil end
    
    local coords = Natives.GetEntityCoords(entity)
    if not coords then
        -- Fallback to default coordinates or get from another source
        return {x = 0.0, y = 0.0, z = 0.0}
    end
    
    return coords
end
```

## Troubleshooting

### Native Function Not Working

If a native function is not working as expected:
1. Check if the function exists in the FiveM natives documentation
2. Verify you're using the correct parameters
3. Check if the function is available in your current environment (client/server)

### Performance Issues

If you're experiencing performance issues:
1. Minimize the number of native calls in tight loops
2. Cache results of expensive native calls when possible
3. Use the performance manager to monitor native call performance

### Missing Natives

If a native function is missing from the wrapper:
1. The function will still work through Lua's metatable handling
2. Consider adding specific handling for important natives that need custom error handling

## Advanced: Extending the Natives Wrapper

You can extend the Natives wrapper to add custom behavior for specific natives:

```lua
-- Add custom handling for a specific native
Natives._customHandlers = Natives._customHandlers or {}
Natives._customHandlers.GetPlayerName = function(playerId)
    -- Custom pre-processing
    if not playerId or playerId < 0 then
        return "Invalid Player"
    end
    
    -- Call the original native with error handling
    local success, result = pcall(function()
        return GetPlayerName(playerId)
    end)
    
    -- Custom post-processing
    if not success or not result or result == "" then
        return "Unknown Player"
    end
    
    return result
end
```
