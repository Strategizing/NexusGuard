--[[
    Vehicle Detection System (Refactored for Registry)
    Monitors for vehicle modifications and performance hacks
]]

local DetectorName = "vehicleModification" -- Match the key in Config.Detectors
local NexusGuard = nil -- Local variable to hold the NexusGuard instance

-- Vehicle data cache to track modifications
local VehicleCache = {}

-- Known top speeds for reference (km/h) - Consider moving to config or shared file if large
local VehicleTopSpeeds = {
    -- Sports cars
    ["adder"] = 220, ["zentorno"] = 230, ["t20"] = 220, ["nero"] = 225, ["nero2"] = 235,
    ["vagner"] = 240, ["deveste"] = 245, ["krieger"] = 240, ["emerus"] = 235, ["furia"] = 230,
    ["vigilante"] = 240,
    -- Motorcycles
    ["bati"] = 210, ["bati2"] = 210, ["hakuchou"] = 215, ["hakuchou2"] = 225, ["shotaro"] = 215,
    -- Default for unknown vehicles
    ["default"] = 200
}

local Detector = {
    active = false,
    interval = 3000, -- Default check interval (ms)
    lastCheck = 0
}

-- Get the vehicle class specific max speed multiplier
local function GetVehicleClassSpeedMultiplier(vehicleClass)
    local classMultipliers = {
        [16] = 2.5, [15] = 1.5, [14] = 1.2, [8] = 1.4, [7] = 1.3, [6] = 1.3, ["default"] = 1.5
    }
    return classMultipliers[vehicleClass] or classMultipliers["default"]
end

-- Calculate the maximum allowed speed for a vehicle based on model and class
local function CalculateMaxAllowedSpeed(model, vehicleClass)
    local modelHash = GetDisplayNameFromVehicleModel(model)
    local modelName = "unknown"
    if modelHash and modelHash ~= "" then modelName = modelHash:lower() end
    local expectedTopSpeed = VehicleTopSpeeds[modelName] or VehicleTopSpeeds["default"]
    local multiplier = GetVehicleClassSpeedMultiplier(vehicleClass)
    return expectedTopSpeed * multiplier
end

-- Initialize the detector
function Detector.Initialize(nexusGuardInstance)
    if not nexusGuardInstance then
        print("^1[NexusGuard:" .. DetectorName .. "] CRITICAL: Failed to receive NexusGuard instance.^7")
        return false
    end
    NexusGuard = nexusGuardInstance
    local cfg = NexusGuard.Config
    -- Use ConfigKey 'vehicleModification' to check if enabled and get interval
    if cfg and cfg.Detectors and cfg.Detectors.vehicleModification and NexusGuard.intervals and NexusGuard.intervals.vehicleModification then
        Detector.interval = NexusGuard.intervals.vehicleModification
    end
    print("^2[NexusGuard:" .. DetectorName .. "]^7 Initialized with interval: " .. Detector.interval .. "ms")
    return true
end

-- Start the detector
function Detector.Start()
    if Detector.active then return false end
    Detector.active = true
    return true
end

-- Stop the detector
function Detector.Stop()
    if not Detector.active then return false end
    Detector.active = false
    return true
end

-- Check for violations
function Detector.Check()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end -- Only check if player is in a vehicle

    local vehicleModel = GetEntityModel(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)

    -- Get current vehicle properties
    local speed = GetEntitySpeed(vehicle) * 3.6 -- Convert to km/h
    local health = GetVehicleEngineHealth(vehicle)
    -- local handling = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce') -- Handling check removed for simplicity/reliability focus
    local maxSpeed = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel') -- Base max speed from handling

    -- Initialize cache entry for this vehicle model if it doesn't exist
    if not VehicleCache[vehicleModel] then
        VehicleCache[vehicleModel] = {
            baseSpeed = maxSpeed, baseHealth = health, -- baseHandling = handling,
            topSpeed = 0, samples = 1, lastCheck = GetGameTimer()
        }
        return -- Wait for more samples
    end

    -- Update tracked top speed if we're going faster
    if speed > VehicleCache[vehicleModel].topSpeed then
        VehicleCache[vehicleModel].topSpeed = speed
    end

    -- Only analyze after we have enough samples
    if VehicleCache[vehicleModel].samples < 5 then
        VehicleCache[vehicleModel].samples = VehicleCache[vehicleModel].samples + 1
        return -- Wait for more samples
    end

    -- Calculate max allowed speed for this vehicle
    local maxAllowedSpeed = CalculateMaxAllowedSpeed(vehicleModel, vehicleClass)

    -- Check for speed modifications
    if speed > maxAllowedSpeed then
        local vehicleName = "Unknown"
        local displayNameHash = GetDisplayNameFromVehicleModel(vehicleModel)
        if displayNameHash and displayNameHash ~= "" then
            vehicleName = GetLabelText(displayNameHash) or displayNameHash
            if vehicleName == "NULL" then vehicleName = displayNameHash end
        end

        local details = {
            reason = "Vehicle speed hack detected",
            speed = math.floor(speed),
            maxAllowed = math.floor(maxAllowedSpeed),
            vehicleName = vehicleName,
            vehicleClass = vehicleClass
        }
        -- Report the cheat using the NexusGuard instance
        if NexusGuard and NexusGuard.ReportCheat then
            NexusGuard:ReportCheat(DetectorName, details)
        else
            print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: " .. details.reason .. " (NexusGuard instance unavailable)")
        end
    end

    -- Check for engine health modifications (simple check > 1000)
    if health > 1000 and not IsVehicleDamaged(vehicle) then
         local details = {
            reason = "Vehicle health modification detected",
            health = math.floor(health)
         }
        if NexusGuard and NexusGuard.ReportCheat then
            NexusGuard:ReportCheat(DetectorName, details)
        else
            print("^1[NexusGuard:" .. DetectorName .. "]^7 Violation: " .. details.reason .. " (NexusGuard instance unavailable)")
        end
    end
end

-- Get detector status
function Detector.GetStatus()
    return {
        active = Detector.active,
        lastCheck = Detector.lastCheck,
        interval = Detector.interval
    }
end

-- Registration is now handled centrally by client_main.lua
-- The self-registration thread has been removed.

return Detector
