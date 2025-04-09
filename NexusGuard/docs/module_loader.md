# Module Loader Documentation

## Overview

The Module Loader is a utility that provides a centralized way to load modules in the NexusGuard anti-cheat framework. It handles module caching, circular dependencies, and optional module loading to ensure a robust and efficient module system.

## Features

- **Module Caching**: Modules are cached to prevent multiple loads of the same module
- **Circular Dependency Handling**: Prevents infinite loops when modules depend on each other
- **Optional Module Loading**: Allows modules to be loaded as optional dependencies
- **Error Handling**: Provides graceful error handling for module loading failures

## API Reference

### `ModuleLoader.Load(modulePath, optional)`

Loads a module from the specified path.

**Parameters:**
- `modulePath` (string): The path to the module relative to the resource root
- `optional` (boolean, optional): If true, the function will return nil instead of throwing an error if the module cannot be loaded

**Returns:**
- The loaded module, or nil if the module cannot be loaded and `optional` is true

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local OptionalModule = ModuleLoader.Load('shared/optional_module', true)
```

### `ModuleLoader.ClearCache()`

Clears the module cache, forcing all modules to be reloaded on the next call to `Load()`.

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
ModuleLoader.ClearCache()
```

### `ModuleLoader.GetLoadedModules()`

Returns a list of all currently loaded modules.

**Returns:**
- A table of module paths that have been loaded

**Example:**
```lua
local ModuleLoader = require('shared/module_loader')
local loadedModules = ModuleLoader.GetLoadedModules()
for path, module in pairs(loadedModules) do
    print("Loaded module: " .. path)
end
```

## Best Practices

1. **Use the Module Loader for all module imports**: This ensures consistent behavior and proper dependency management.

2. **Handle optional dependencies gracefully**:
   ```lua
   local OptionalModule = ModuleLoader.Load('path/to/module', true)
   if OptionalModule then
       -- Use the module
   else
       -- Fallback behavior
   end
   ```

3. **Avoid circular dependencies when possible**: While the Module Loader handles circular dependencies, they can make code harder to understand and maintain.

4. **Use relative paths consistently**: Always use paths relative to the resource root to ensure modules can be found regardless of where they are loaded from.

## Example: Module with Dependencies

```lua
-- shared/my_module.lua
local ModuleLoader = require('shared/module_loader')
local Utils = ModuleLoader.Load('shared/utils')
local Config = ModuleLoader.Load('shared/config')
local OptionalModule = ModuleLoader.Load('shared/optional_module', true)

local MyModule = {}

function MyModule.DoSomething()
    Utils.Log("Doing something with config: " .. Config.GetSetting("example"))
    
    if OptionalModule then
        OptionalModule.EnhanceFeature()
    end
end

return MyModule
```

## Troubleshooting

### Module Not Found

If a module cannot be found, check:
1. The path is correct relative to the resource root
2. The module file exists
3. The module is properly returning a value

### Circular Dependency Issues

If you encounter issues with circular dependencies:
1. Restructure your code to eliminate the circular dependency
2. Use the `optional` parameter to break the dependency cycle
3. Move the dependency loading inside functions instead of at the module level

### Performance Concerns

If module loading is impacting performance:
1. Ensure modules are only loaded once and then cached
2. Consider lazy-loading modules only when needed
3. Use the `GetLoadedModules()` function to check if modules are being loaded multiple times
