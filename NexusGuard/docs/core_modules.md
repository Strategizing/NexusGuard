# NexusGuard Core Modules

This document provides detailed information about the core modules that form the foundation of the NexusGuard anti-cheat framework.

## Module Loader

The Module Loader provides a centralized way to load modules in the NexusGuard framework, handling module caching, circular dependencies, and optional module loading.

### API Reference

#### `ModuleLoader.Load(modulePath, isOptional)`

Loads a module from the specified path.

**Parameters:**
- `modulePath` (string): The path to the module relative to the resource root
- `isOptional` (boolean, optional): If true, the function will return nil instead of throwing an error if the module cannot be loaded

**Returns:**
- The loaded module, or nil if the module cannot be loaded and `isOptional` is true

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local OptionalModule = ModuleLoader.Load('shared/optional_module', true)
```

#### `ModuleLoader.LoadByName(moduleName, isOptional)`

Loads a module by its short name using predefined paths.

**Parameters:**
- `moduleName` (string): The short name of the module (e.g., "utils", "natives")
- `isOptional` (boolean, optional): If true, the function will return nil instead of throwing an error if the module cannot be loaded

**Returns:**
- The loaded module, or nil if the module cannot be loaded and `isOptional` is true

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.LoadByName('utils')
local Natives = ModuleLoader.LoadByName('natives')
```

#### `ModuleLoader.ClearCache()`

Clears the module cache, forcing all modules to be reloaded on the next call to `Load()`.

## Natives Wrapper

The Natives Wrapper provides a safe and consistent way to call FiveM native functions with error handling and fallbacks.

### Key Features

- Error handling for native calls
- Consistent interface for all native functions
- Performance monitoring capabilities
- Cross-environment compatibility (client/server)

### API Reference

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

## Utils Module

The Utils module provides common utility functions used throughout the NexusGuard framework.

### API Reference

#### `Utils.Log(message, level, ...)`

Logs a message with the specified level.

**Parameters:**
- `message` (string): The message to log
- `level` (number, optional): The log level (1=ERROR, 2=WARNING, 3=INFO, 4=DEBUG, 5=TRACE)
- `...` (any, optional): Additional values to format into the message

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')

Utils.Log("Player connected: %s", Utils.logLevels.INFO, playerName)
```

#### `Utils.TableSize(table)`

Returns the number of elements in a table.

**Parameters:**
- `table` (table): The table to count elements in

**Returns:**
- (number): The number of elements in the table

**Example:**
```lua
local count = Utils.TableSize(players)
```

#### `Utils.GetConnectedPlayers()`

Returns a table of all connected players.

**Returns:**
- (table): A table mapping player IDs to player data

**Example:**
```lua
local players = Utils.GetConnectedPlayers()
for id, data in pairs(players) do
    Utils.Log("Player %d: %s", Utils.logLevels.DEBUG, id, data.name)
end
```

#### `Utils.Throttle(func, key, cooldown)`

Throttles a function call to prevent spam.

**Parameters:**
- `func` (function): The function to throttle
- `key` (string, optional): A unique key to identify this throttle
- `cooldown` (number, optional): The cooldown period in milliseconds (default: 1000)

**Returns:**
- The result of the function call, or nil if throttled

**Example:**
```lua
Utils.Throttle(function()
    -- This will only run once per second
    TriggerClientEvent('some:event', -1, 'data')
end, 'broadcast', 1000)
```

## Event Registry

The Event Registry provides a centralized definition for all network events used by NexusGuard, standardizing event names and providing helper functions for event handling.

### API Reference

#### `EventRegistry:GetEventName(eventKey)`

Gets the full event name for a given key.

**Parameters:**
- `eventKey` (string): The key of the event (e.g., "SECURITY_REQUEST_TOKEN")

**Returns:**
- (string): The full event name (e.g., "nexusguard:security:requestToken")

**Example:**
```lua
local eventName = EventRegistry:GetEventName('SECURITY_REQUEST_TOKEN')
```

#### `EventRegistry:AddEventHandler(eventKey, handler)`

Adds an event handler for the specified event.

**Parameters:**
- `eventKey` (string): The key of the event
- `handler` (function): The function to call when the event is triggered

**Example:**
```lua
EventRegistry:AddEventHandler('SECURITY_REQUEST_TOKEN', function(playerId)
    -- Handle the event
end)
```

#### `EventRegistry:TriggerServerEvent(eventKey, ...)`

Triggers a server event with the specified key.

**Parameters:**
- `eventKey` (string): The key of the event
- `...` (any): Additional arguments to pass to the event

**Example:**
```lua
EventRegistry:TriggerServerEvent('DETECTION_REPORT', playerId, detectionType, detectionData)
```

#### `EventRegistry:TriggerClientEvent(eventKey, target, ...)`

Triggers a client event with the specified key.

**Parameters:**
- `eventKey` (string): The key of the event
- `target` (number): The target player ID (-1 for all players)
- `...` (any): Additional arguments to pass to the event

**Example:**
```lua
EventRegistry:TriggerClientEvent('SECURITY_RECEIVE_TOKEN', playerId, token, timestamp)
```

## Performance Manager

The Performance Manager optimizes anti-cheat operations based on server load and performance metrics.

### API Reference

#### `PerformanceManager.MeasureExecution(name, func, ...)`

Measures the execution time of a function.

**Parameters:**
- `name` (string): The name of the operation to measure
- `func` (function): The function to measure
- `...` (any): Arguments to pass to the function

**Returns:**
- The return value of the function

**Example:**
```lua
PerformanceManager.MeasureExecution("CheckPlayer", function(playerId)
    -- Perform expensive checks
    return result
end, playerId)
```

#### `PerformanceManager.BatchUpdates(updates)`

Batches multiple updates to reduce network traffic.

**Parameters:**
- `updates` (table): A table of updates to batch

**Returns:**
- (boolean): True if updates were batched successfully, false otherwise

**Example:**
```lua
PerformanceManager.BatchUpdates({
    { type = "position", target = playerId, data = coords },
    { type = "health", target = playerId, data = health }
})
```

#### `PerformanceManager.IsHighLoad()`

Checks if the system is under high load.

**Returns:**
- (boolean): True if the system is under high load, false otherwise

**Example:**
```lua
if PerformanceManager.IsHighLoad() then
    -- Skip non-critical checks
else
    -- Perform all checks
end
```

## Best Practices

When working with these core modules, follow these best practices:

1. **Use the Module Loader for all imports**: This ensures consistent behavior and proper dependency management.

2. **Always use the Natives Wrapper for native calls**: This prevents script crashes and provides consistent error handling.

3. **Handle optional dependencies gracefully**: Use the optional parameter of the Module Loader to handle missing dependencies.

4. **Follow the event naming conventions**: Use the Event Registry for all network events to maintain consistency.

5. **Consider performance implications**: Use the Performance Manager to optimize resource-intensive operations.

## Example: Using Core Modules Together

```lua
-- Load the module loader
local ModuleLoader = require('shared/module_loader')

-- Load core modules
local Utils = ModuleLoader.Load('shared/utils')
local Natives = ModuleLoader.Load('shared/natives')
local EventRegistry = ModuleLoader.Load('shared/event_registry')
local PerformanceManager = ModuleLoader.Load('shared/performance_manager')

-- Define a function to check player state
local function CheckPlayerState(playerId)
    -- Get player information safely using Natives wrapper
    local ped = Natives.GetPlayerPed(playerId)
    if not ped or ped == 0 then
        Utils.Log("Invalid player ped for ID: %d", Utils.logLevels.WARNING, playerId)
        return false
    end
    
    -- Get player position safely
    local coords = Natives.GetEntityCoords(ped)
    if not coords then
        Utils.Log("Could not get coordinates for player ID: %d", Utils.logLevels.WARNING, playerId)
        return false
    end
    
    -- Check if player is in a valid position
    if coords.z < -100 then
        -- Report suspicious activity
        EventRegistry:TriggerServerEvent('DETECTION_REPORT', playerId, 'INVALID_POSITION', {
            coords = coords,
            timestamp = Natives.GetGameTimer()
        })
        return false
    end
    
    return true
end

-- Use performance manager to measure execution time
PerformanceManager.MeasureExecution("PlayerStateCheck", function()
    -- Get all connected players
    local players = Utils.GetConnectedPlayers()
    
    -- Check each player
    for playerId, _ in pairs(players) do
        CheckPlayerState(playerId)
    end
end)
```
