--[[
    NexusGuard Vehicle Modification Detector (client/detectors/vehicle_detector.lua)

    Purpose:
    - Monitors the player's current vehicle for potential modifications related to
      speed (exceeding calculated limits) and engine health (abnormally high values).

    Checks Performed:
    - Speed Check: Compares the vehicle's current speed against a calculated maximum allowed speed.
      This maximum is derived from a base speed (looked up or default) multiplied by a class-specific multiplier.
    - Health Check: Checks if the vehicle's engine health significantly exceeds the standard maximum (1000).

    Reporting:
    - Unlike some other client-side detectors (speed, noclip, godmode), this one *does* currently use
      `NexusGuard:ReportCheat` to flag potential issues to the server. This is because detecting
      these specific modifications client-side might have slightly higher confidence, though server-side
      validation (e.g., comparing against known vehicle handling data) would still be ideal.

    Dependencies:
    - `NexusGuard` instance (for config access and reporting).
]]

local DetectorName = "vehicleModification" -- Unique key for this detector (matches Config.Detectors key)
local NexusGuard = nil -- Local reference to the main NexusGuard client instance

-- Cache to store baseline vehicle data (currently basic usage)
-- Could be expanded to track handling changes over time.
local VehicleCache = {}

-- Reference table for expected top speeds (km/h).
-- Consider moving this to config.lua for easier customization.
local VehicleTopSpeeds = {
    -- Sports cars
    ["adder"] = 220, ["zentorno"] = 230, ["t20"] = 220, ["nero"] = 225, ["nero2"] = 235,
    ["vagner"] = 240, ["deveste"] = 245, ["krieger"] = 240, ["emerus"] = 235, ["furia"] = 230,
    ["vigilante"] = 240,
    -- Motorcycles
    ["bati"] = 210, ["bati2"] = 210, ["hakuchou"] = 215, ["hakuchou2"] = 225, ["shotaro"] = 215,
    -- Default for vehicles not listed
    ["default"] = 200
}

-- Detector module table
local Detector = {
    active = false,     -- Is the detector currently running? Set by Start/Stop.
    interval = 3000,    -- Default check interval (ms). Overridden by config.
    lastCheck = 0       -- Timestamp of the last check.
}

--[[
    Helper function to get a speed multiplier based on vehicle class.
    Allows different tolerances for different vehicle types (e.g., higher multiplier for supers).
    @param vehicleClass (number): The class ID obtained from `GetVehicleClass`.
    @return (number): The speed multiplier for that class.
]]
local function GetVehicleClassSpeedMultiplier(vehicleClass)
    -- Define multipliers per class ID. Adjust these based on server balance/needs.
    local classMultipliers = {
        [0] = 1.2, [1] = 1.2, [2] = 1.2, [3] = 1.2, [4] = 1.2, [5] = 1.2, [6] = 1.3, -- Compacts, Sedans, SUVs, Coupes, Muscle, Sports Classics
        [7] = 1.3, -- Sports
        [8] = 1.4, -- Super
        [9] = 1.2, -- Motorcycles (Adjust if needed)
        [10]= 1.2, [11]= 1.2, [12]= 1.2, -- Off-road, Industrial, Utility
        [13]= 1.2, -- Vans
        [14]= 1.2, -- Cycles (Shouldn't have high speed anyway)
        [15]= 1.5, -- Boats
        [16]= 2.5, -- Helicopters (Allow high speed)
        [17]= 2.5, -- Planes (Allow high speed)
        [18]= 1.2, -- Service
        [19]= 1.2, -- Emergency
        [20]= 1.2, -- Military
        [21]= 1.2, -- Commercial
        [22]= 1.2, -- Trains
        ["default"] = 1.3 -- Default multiplier for unlisted classes
    }
    return classMultipliers[vehicleClass] or classMultipliers["default"]
end

--[[
    Calculates the maximum allowed speed (km/h) for a vehicle.
    Uses the vehicle's display name to look up a base speed in `VehicleTopSpeeds`,
    then applies a class-specific multiplier.

    @param model (hash): The vehicle model hash from `GetEntityModel`.
    @param vehicleClass (number): The vehicle class ID from `GetVehicleClass`.
    @return (number): The calculated maximum allowed speed in km/h.
]]
local function CalculateMaxAllowedSpeed(model, vehicleClass)
    -- Get the display name hash (game name) of the vehicle model.
    local modelHash = GetDisplayNameFromVehicleModel(model)
    local modelName = "unknown"
    -- Convert hash to lowercase string name for lookup.
    if modelHash and modelHash ~= "" and modelHash ~= "NULL" then modelName = string.lower(GetLabelText(modelHash) or modelHash) end

    -- Look up the base top speed from the reference table, use default if not found.
    local expectedTopSpeed = VehicleTopSpeeds[modelName] or VehicleTopSpeeds["default"]
    -- Get the multiplier for the vehicle's class.
    local multiplier = GetVehicleClassSpeedMultiplier(vehicleClass)
    -- Calculate and return the maximum allowed speed.
    return expectedTopSpeed * multiplier
end

--[[
    Initialization Function
    Called by the DetectorRegistry during startup.
    @param nexusGuardInstance (table): The main NexusGuard client instance.
]]
function Detector.Initialize(nexusGuardInstance)
    if not nexusGuardInstance then
        print(("^1[NexusGuard:%s] CRITICAL: Failed to receive NexusGuard instance.^7"):format(DetectorName))
        return false
    end
    NexusGuard = nexusGuardInstance -- Store the reference.

    -- Read configuration (interval) via the NexusGuard instance.
    local cfg = NexusGuard.Config
    -- Use the correct key 'vehicleModification' for both enable and interval checks.
    Detector.interval = (cfg and cfg.Intervals and cfg.Intervals.vehicleModification) or Detector.interval

    Log(("[%s Detector] Initialized. Interval: %dms"):format(DetectorName, Detector.interval), 3)
    return true
end

--[[
    Start Function
    Called by the DetectorRegistry to activate the detector.
]]
function Detector.Start()
    if Detector.active then return false end -- Already active
    Log(("[%s Detector] Starting checks..."):format(DetectorName), 3)
    Detector.active = true
    Detector.lastCheck = 0
    return true -- Indicate successful start
end

--[[
    Stop Function
    Called by the DetectorRegistry to deactivate the detector.
]]
function Detector.Stop()
    if not Detector.active then return false end -- Already stopped
    Log(("[%s Detector] Stopping checks..."):format(DetectorName), 3)
    Detector.active = false
    return true -- Indicate successful stop signal
end

--[[
    Core Check Function
    Called periodically by the DetectorRegistry's managed thread.
    Checks current vehicle speed and engine health against calculated/expected maximums.
]]
function Detector.Check()
    -- Ensure NexusGuard instance is available.
    if not NexusGuard then return true end -- Skip check if core instance is missing.

    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) then return true end

    -- Only perform checks if the player is currently in a valid vehicle.
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return true end

    local vehicleModel = GetEntityModel(vehicle)
    local vehicleClass = GetVehicleClass(vehicle)

    -- 1. Get Current Vehicle Properties
    local currentSpeedKmh = GetEntitySpeed(vehicle) * 3.6 -- Get speed and convert m/s to km/h.
    local currentEngineHealth = GetVehicleEngineHealth(vehicle)
    -- Handling checks were removed for simplicity; focus on speed and health.
    -- local currentHandlingForce = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveForce')
    -- Base max speed from handling data (often represents theoretical flat ground speed).
    local handlingMaxSpeed = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fInitialDriveMaxFlatVel')

    -- 2. Vehicle Cache (Basic Implementation)
    -- Initialize cache for this model if first time encountered in this session.
    -- The cache currently only stores initial values and tracks top speed observed.
    -- It requires more samples before performing checks.
    if not VehicleCache[vehicleModel] then
        VehicleCache[vehicleModel] = {
            baseSpeed = handlingMaxSpeed, -- Store initial handling max speed
            baseHealth = currentEngineHealth, -- Store initial health
            topSpeed = 0, -- Track highest speed observed
            samples = 1, -- Count checks performed
            lastCheck = GetGameTimer()
        }
        return true -- Skip checks on the first sample.
    end

    local cache = VehicleCache[vehicleModel]

    -- Update the highest speed observed in the cache.
    if currentSpeedKmh > cache.topSpeed then
        cache.topSpeed = currentSpeedKmh
    end

    -- Require a few samples before starting checks to allow speed to stabilize.
    local requiredSamples = 5
    if cache.samples < requiredSamples then
        cache.samples = cache.samples + 1
        return true -- Collect more data before checking.
    end

    -- 3. Perform Checks

    -- Speed Check: Compare current speed against calculated max allowed speed.
    local maxAllowedSpeedKmh = CalculateMaxAllowedSpeed(vehicleModel, vehicleClass)
    if currentSpeedKmh > maxAllowedSpeedKmh then
        local vehicleName = "Unknown"
        local displayNameHash = GetDisplayNameFromVehicleModel(vehicleModel)
        -- Attempt to get a readable vehicle name.
        if displayNameHash and displayNameHash ~= "" and displayNameHash ~= "NULL" then
            vehicleName = GetLabelText(displayNameHash) or displayNameHash -- Use label text or hash if label fails.
        end

        local details = {
            reason = "Vehicle speed potentially exceeds calculated maximum",
            speed = math.floor(currentSpeedKmh),
            maxAllowed = math.floor(maxAllowedSpeedKmh),
            vehicleName = vehicleName,
            vehicleModel = vehicleModel, -- Include model hash
            vehicleClass = vehicleClass
        }
        -- Report this potential issue to the server.
        if NexusGuard.ReportCheat then
            Log(("[%s Detector] Reporting potential speed issue: Speed %.0f km/h > Max %.0f km/h for %s"):format(
                DetectorName, details.speed, details.maxAllowed, details.vehicleName
            ), 1)
            NexusGuard:ReportCheat(DetectorName, details)
            -- Consider returning false for adaptive timing if needed.
        end
    end

    -- Engine Health Check: Check for abnormally high engine health (standard max is 1000).
    -- Also check if the vehicle is actually damaged, as health might be high on a pristine vehicle briefly.
    local healthThreshold = 1000.0 -- Standard max engine health.
    if currentEngineHealth > healthThreshold and IsVehicleDamaged(vehicle) then -- Check only if damaged AND health > 1000
         local details = {
            reason = "Vehicle engine health modification detected",
            health = math.floor(currentEngineHealth),
            threshold = healthThreshold
         }
         -- Report this potential issue to the server.
        if NexusGuard.ReportCheat then
            Log(("[%s Detector] Reporting potential health issue: Health %.0f > Threshold %.0f"):format(
                DetectorName, details.health, details.threshold
            ), 1)
            NexusGuard:ReportCheat(DetectorName, details)
            -- Consider returning false for adaptive timing if needed.
        end
    end

    -- Update last check time in cache (optional, might not be needed here).
    cache.lastCheck = GetGameTimer()

    return true -- Indicate check cycle completed.
end

--[[
    (Optional) GetStatus Function
    Provides current status information for this detector.
    @return (table): Status details.
]]
function Detector.GetStatus()
    return {
        active = Detector.active,
        lastCheck = Detector.lastCheck,
        interval = Detector.interval
        -- Could add details from VehicleCache if needed for debugging.
    }
end

-- Return the Detector table for the registry.
return Detector
