--[[
    Enhanced Vehicle Detection System
    Monitors for vehicle modifications and performance hacks
]]

-- Vehicle data cache to track modifications
local VehicleCache = {}

-- Known top speeds for reference (km/h)
local VehicleTopSpeeds = {
    -- Sports cars
    ["adder"] = 220,
    ["zentorno"] = 230,
    ["t20"] = 220,
    ["nero"] = 225,
    ["nero2"] = 235,
    ["vagner"] = 240,
    ["deveste"] = 245,
    ["krieger"] = 240,
    ["emerus"] = 235,
    ["furia"] = 230,
    ["vigilante"] = 240,
    
    -- Motorcycles
    ["bati"] = 210,
    ["bati2"] = 210,
    ["hakuchou"] = 215,
    ["hakuchou2"] = 225,
    ["shotaro"] = 215,
    
    -- Default for unknown vehicles
    ["default"] = 200
}

-- Get the vehicle class specific max speed multiplier
local function GetVehicleClassSpeedMultiplier(vehicleClass)
    local classMultipliers = {
        [16] = 2.5,  -- Planes (can go very fast)
        [15] = 1.5,  -- Helicopters
        [14] = 1.2,  -- Boats
        [8] = 1.4,   -- Motorcycles
        [7] = 1.3,   -- Super cars
        [6] = 1.3,   -- Sports cars
        -- Default multiplier for other classes
        ["default"] = 1.5
    }
    
    return classMultipliers[vehicleClass] or classMultipliers["default"]
end

-- Calculate the maximum allowed speed for a vehicle based on model and class
local function CalculateMaxAllowedSpeed(model, vehicleClass)
    -- Get model name for vehicle (safely)
    local modelHash = GetDisplayNameFromVehicleModel(model)
    local modelName = "unknown"
    
    if modelHash and modelHash ~= "" then
        modelName = modelHash:lower()
    end
    
    -- Get expected top speed from our database, or use default
    local expectedTopSpeed = VehicleTopSpeeds[modelName] or VehicleTopSpeeds["default"]
    
    -- Get appropriate multiplier based on vehicle class
    local multiplier = GetVehicleClassSpeedMultiplier(vehicleClass)
    
    -- Calculate max allowed speed with some flexibility
    return expectedTopSpeed * multiplier
end

-- Safely report cheats to the anti-cheat system
local function SafeReportCheat(type, details)
    -- Check if the NexusGuard object exists before using it
    if _G.NexusGuard and type(_G.NexusGuard.ReportCheat) == "function" then
        _G.NexusGuard:ReportCheat(type, details)
        return true
    else
        -- Fallback to print for debugging if NexusGuard isn't available
        print("[Vehicle Detector] Would report: " .. type .. " - " .. details)
        return false
    end
end

-- Monitor vehicle modifications
function MonitorVehicleModifications()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end
    
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    
    local vehicleModel = GetEntityModel(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)
    
    -- Get current vehicle properties
    local speed = GetEntitySpeed(vehicle) * 3.6 -- Convert to km/h
    local health = GetVehicleEngineHealth(vehicle)
    local handling = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce')
    local maxSpeed = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')
    
    -- Initialize cache entry for this vehicle model if it doesn't exist
    if not VehicleCache[vehicleModel] then
        VehicleCache[vehicleModel] = {
            baseSpeed = maxSpeed,
            baseHealth = health,
            baseHandling = handling,
            topSpeed = 0,
            samples = 1,
            lastCheck = GetGameTimer()
        }
        return
    end
    
    -- Update tracked top speed if we're going faster
    if speed > VehicleCache[vehicleModel].topSpeed then
        VehicleCache[vehicleModel].topSpeed = speed
    end
    
    -- Only analyze after we have enough samples
    if VehicleCache[vehicleModel].samples < 5 then
        VehicleCache[vehicleModel].samples = VehicleCache[vehicleModel].samples + 1
        return
    end
    
    -- Calculate max allowed speed for this vehicle
    local maxAllowedSpeed = CalculateMaxAllowedSpeed(vehicleModel, vehicleClass)
    
    -- Check for speed modifications
    if speed > maxAllowedSpeed then
        -- Get vehicle name safely
        local vehicleName = "Unknown"
        local displayNameHash = GetDisplayNameFromVehicleModel(vehicleModel)
        if displayNameHash and displayNameHash ~= "" then
            vehicleName = GetLabelText(displayNameHash) or displayNameHash
            if vehicleName == "NULL" then vehicleName = displayNameHash end
        end
        
        -- Prepare detailed detection report
        local detectionDetails = {
            speed = math.floor(speed),
            maxAllowed = math.floor(maxAllowedSpeed),
            vehicleName = vehicleName,
            vehicleClass = vehicleClass
        }
        
        -- Report the cheat safely
        SafeReportCheat("vehiclespeed", 
            "Vehicle speed hack detected: " .. detectionDetails.vehicleName .. 
            " - " .. detectionDetails.speed .. " km/h (Max: " .. detectionDetails.maxAllowed .. " km/h)")
    end
    
    -- Check for engine health modifications
    if health > 1000 and not IsVehicleDamaged(vehicle) then
        -- Report engine health modification safely
        SafeReportCheat("vehiclemod", 
            "Vehicle health modification detected: Engine health " .. 
            math.floor(health) .. "/1000")
    end
end

-- Create thread to run monitor periodically
Citizen.CreateThread(function()
    local nextCheck = 0
    
    while true do
        -- Optimize performance by only checking when needed
        local currentTime = GetGameTimer()
        
        -- Check if it's time to run the detector
        if currentTime >= nextCheck then
            -- Check if the feature is enabled (with safe access)
            if Config and Config.Detectors and Config.Detectors.vehicleModification then
                -- Use pcall to catch any errors that might occur
                local success, error = pcall(MonitorVehicleModifications)
                if not success then
                    print("[Vehicle Detector] Error: " .. tostring(error))
                end
            end
            
            -- Set next check time (3 seconds)
            nextCheck = currentTime + 3000
        end
        
        -- Use adaptive wait to reduce resource usage
        local timeUntilNextCheck = nextCheck - GetGameTimer()
        local waitTime = math.max(1000, math.min(timeUntilNextCheck, 3000))
        
        Citizen.Wait(waitTime)
    end
end)
