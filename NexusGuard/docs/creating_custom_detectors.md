# Creating Custom Detectors for NexusGuard

NexusGuard's modular design allows you to easily create custom detection modules to identify and respond to different types of cheating behavior. This guide will walk you through the process of creating, configuring, and testing your own detector.

## Basic Structure

Each detector is a Lua file placed in the `client/detectors/` directory, following the naming convention `yourdetector_detector.lua`. The detector is responsible for checking for specific cheating behaviors and reporting them to the core NexusGuard system.

## Step-by-Step Guide

### 1. Create a New Detector File

Create a new file in the `client/detectors/` directory with a descriptive name following the pattern `yourdetector_detector.lua`.

### 2. Basic Detector Template

Use this template as a starting point:

```lua
-- Define a unique detector name (used in config.lua to enable/disable)
local DetectorName = "yourdetector"

-- Create the detector table
local Detector = {
    -- Configuration (read from Config)
    enabled = true,
    checkInterval = 1000, -- ms between checks
    
    -- Internal state
    NexusGuard = nil, -- Will be set during initialization
    lastCheck = 0
}

-- Initialize the detector
function Detector.Initialize(nexusGuardInstance, eventRegistry)
    -- Store reference to NexusGuard instance
    Detector.NexusGuard = nexusGuardInstance
    
    -- Read configuration
    local config = Detector.NexusGuard.Config
    if config.Detectors and config.Detectors[DetectorName] ~= nil then
        Detector.enabled = config.Detectors[DetectorName]
    end
    
    if config.Thresholds and config.Thresholds.yourDetectorThreshold then
        Detector.threshold = config.Thresholds.yourDetectorThreshold
    end
    
    -- Additional initialization logic
    -- For example, you might want to register event handlers
    if eventRegistry then
        -- Example: Register for a game event
        -- eventRegistry:AddEventHandler('someEvent', Detector.HandleEvent)
    end
    
    -- Log initialization
    if Detector.NexusGuard.Utils and Detector.NexusGuard.Utils.Log then
        Detector.NexusGuard.Utils.Log("Initialized " .. DetectorName .. " detector", 3)
    end
end

-- Main detection logic
function Detector.Check()
    -- Skip if disabled
    if not Detector.enabled then return end
    
    -- Throttle checks based on interval
    local currentTime = GetGameTimer()
    if currentTime - Detector.lastCheck < Detector.checkInterval then
        return
    end
    Detector.lastCheck = currentTime
    
    -- Your detection logic here
    -- Example:
    local suspiciousValue = YourDetectionFunction()
    if suspiciousValue > Detector.threshold then
        -- Report the detection
        Detector.NexusGuard:ReportCheat(DetectorName, {
            value = suspiciousValue,
            threshold = Detector.threshold,
            details = {
                -- Additional details for server validation
            }
        })
    end
end

-- Optional: Custom event handler
function Detector.HandleEvent(...)
    -- Handle events if you registered any
end

-- Optional: Helper functions
function YourDetectionFunction()
    -- Implement your detection logic
    return 0 -- Return a value to compare against threshold
end

-- Register the detector with NexusGuard
DetectorRegistry.Register(DetectorName, Detector)
```

### 3. Configure Your Detector

Add your detector to the configuration in `config.lua`:

```lua
Config.Detectors = {
    -- Existing detectors...
    yourdetector = true, -- Enable your new detector
}

Config.Thresholds = {
    -- Existing thresholds...
    yourDetectorThreshold = 10.0, -- Set appropriate threshold
}
```

### 4. Implement Detection Logic

Replace the placeholder `YourDetectionFunction()` with your actual detection logic. Here are some common detection patterns:

#### Value Monitoring

Check if a value exceeds normal limits:

```lua
function YourDetectionFunction()
    local playerPed = PlayerPedId()
    local value = GetSomeValue(playerPed)
    return value
end
```

#### State Monitoring

Check for impossible or suspicious states:

```lua
function YourDetectionFunction()
    local playerPed = PlayerPedId()
    local isInVehicle = IsPedInAnyVehicle(playerPed, false)
    local isSwimming = IsPedSwimming(playerPed)
    
    -- Impossible state: swimming while in a vehicle
    if isInVehicle and isSwimming then
        return 100 -- High suspicion value
    end
    
    return 0 -- No suspicion
end
```

#### Pattern Detection

Monitor for patterns over time:

```lua
-- Add to Detector table
Detector.history = {}

function YourDetectionFunction()
    local playerPed = PlayerPedId()
    local currentValue = GetSomeValue(playerPed)
    
    -- Add to history
    table.insert(Detector.history, {
        value = currentValue,
        timestamp = GetGameTimer()
    })
    
    -- Limit history size
    if #Detector.history > 10 then
        table.remove(Detector.history, 1)
    end
    
    -- Analyze pattern
    if #Detector.history >= 3 then
        local suspicionScore = AnalyzePattern(Detector.history)
        return suspicionScore
    end
    
    return 0
end

function AnalyzePattern(history)
    -- Implement pattern analysis
    -- Return suspicion score
    return 0
end
```

### 5. Server-Side Validation

For robust detection, implement server-side validation in `server/modules/sv_detections.lua`:

```lua
-- In the Process function, add a new elseif branch
elseif detectionType == "yourdetector" then
    -- Extract data from the detection report
    local value = tonumber(validatedData.value)
    local threshold = Thresholds.yourDetectorThreshold or 10.0
    
    -- Perform server-side validation
    if value and value > threshold then
        -- Consider player state and context
        local isValid = true
        
        -- Example: Check if player is in a valid state
        if session.metrics.someRelevantState then
            isValid = false
            validatedData.reason = "False positive due to player state"
        end
        
        if isValid then
            validatedData.reason = string.format("Value %.2f exceeded threshold %.2f", value, threshold)
            severity = "Medium" -- Set appropriate severity
        end
    else
        isValid = false
        validatedData.reason = "Value within acceptable range or missing"
    end
    
    validatedData.serverValidated = isValid
```

### 6. Testing Your Detector

1. **Enable Debug Logging**: Set `Config.LogLevel = 4` in `config.lua` to see detailed logs.

2. **Test with Known Behaviors**: Create test scenarios that should trigger your detector.

3. **Check for False Positives**: Test normal gameplay to ensure your detector doesn't trigger incorrectly.

4. **Tune Thresholds**: Adjust thresholds based on testing results.

## Best Practices

1. **Performance**: Keep detection logic lightweight. Use throttling and avoid expensive operations in every frame.

2. **Reliability**: Implement both client and server validation. Don't trust client-side data alone.

3. **Context Awareness**: Consider player state (falling, in vehicle, etc.) to reduce false positives.

4. **Progressive Response**: Start with warnings before taking severe actions like kicks or bans.

5. **Documentation**: Comment your code thoroughly, especially detection logic and thresholds.

## Example: Speed Hack Detector

Here's a simplified example of a speed hack detector:

```lua
local DetectorName = "speedhack"

local Detector = {
    enabled = true,
    checkInterval = 1000,
    NexusGuard = nil,
    lastCheck = 0,
    lastPos = nil,
    lastTime = 0
}

function Detector.Initialize(nexusGuardInstance, eventRegistry)
    Detector.NexusGuard = nexusGuardInstance
    
    local config = Detector.NexusGuard.Config
    if config.Detectors and config.Detectors[DetectorName] ~= nil then
        Detector.enabled = config.Detectors[DetectorName]
    end
    
    Detector.threshold = config.Thresholds.speedHackThreshold or 50.0
    Detector.NexusGuard.Utils.Log("Initialized speedhack detector", 3)
end

function Detector.Check()
    if not Detector.enabled then return end
    
    local currentTime = GetGameTimer()
    if currentTime - Detector.lastCheck < Detector.checkInterval then return end
    Detector.lastCheck = currentTime
    
    local playerPed = PlayerPedId()
    local currentPos = GetEntityCoords(playerPed)
    
    if Detector.lastPos and Detector.lastTime > 0 then
        local timeDiff = (currentTime - Detector.lastTime) / 1000.0
        local distance = #(currentPos - Detector.lastPos)
        local speed = distance / timeDiff
        
        -- Skip checks for teleports or very small time differences
        if timeDiff > 0.1 and distance < 500.0 then
            -- Check if player is in a vehicle
            local inVehicle = IsPedInAnyVehicle(playerPed, false)
            local effectiveThreshold = Detector.threshold
            
            if inVehicle then
                local vehicle = GetVehiclePedIsIn(playerPed, false)
                local vehicleClass = GetVehicleClass(vehicle)
                
                -- Adjust threshold based on vehicle type
                if vehicleClass == 16 then -- Planes
                    effectiveThreshold = Detector.threshold * 3.0
                elseif vehicleClass == 15 then -- Helicopters
                    effectiveThreshold = Detector.threshold * 2.5
                elseif vehicleClass == 7 then -- Super cars
                    effectiveThreshold = Detector.threshold * 2.0
                else
                    effectiveThreshold = Detector.threshold * 1.5
                end
            end
            
            -- Check if speed exceeds threshold
            if speed > effectiveThreshold then
                Detector.NexusGuard:ReportCheat(DetectorName, {
                    value = speed,
                    threshold = effectiveThreshold,
                    details = {
                        inVehicle = inVehicle,
                        distance = distance,
                        timeDiff = timeDiff
                    }
                })
            end
        end
    end
    
    Detector.lastPos = currentPos
    Detector.lastTime = currentTime
end

DetectorRegistry.Register(DetectorName, Detector)
```

## Conclusion

Creating custom detectors allows you to extend NexusGuard's capabilities to address specific cheating behaviors on your server. By following this guide, you can develop effective, reliable detectors that enhance your server's security while minimizing false positives.

Remember that anti-cheat is an ongoing process. Regularly review and update your detectors as new cheating methods emerge and as you gather more data about their effectiveness.
