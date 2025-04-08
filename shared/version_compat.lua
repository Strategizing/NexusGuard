-- VersionCompat Module
-- Manages version compatibility for NexusGuard detectors

VersionCompat = {
    -- Minimum versions required for various detection methods
    requirements = {
        base = "1.0.0",  -- Minimum NexusGuard version
        fivemArtifact = 3622, -- Minimum FiveM artifact version
        
        -- Detection-specific requirements
        detectors = {
            godMode = {
                fivemArtifact = 3622,
                notes = "Requires GetPlayerInvincible native"
            },
            speedHack = {
                fivemArtifact = 3622,
                notes = "Basic speed detection compatible with all versions"
            },
            noclip = {
                fivemArtifact = 3622,
                notes = "Requires GetEntityCollisionDisabled native"
            },
            weaponModification = {
                fivemArtifact = 3622,
                notes = "Requires GetWeaponDamage native"
            },
            vehicleModification = {
                fivemArtifact = 3622,
                notes = "Requires GetVehicleHandlingFloat native"
            },
            teleport = {
                fivemArtifact = 3622,
                notes = "Basic teleport detection compatible with all versions"
            },
            explosionSpamming = {
                fivemArtifact = 3622,
                notes = "Requires explosionEvent handler"
            },
            entitySpawning = {
                fivemArtifact = 3622,
                notes = "Requires entityCreated event"
            },
            menuDetection = {
                fivemArtifact = 4400, -- Higher requirement for this detection
                notes = "Advanced menu detection requires newer natives"
            }
        }
    },
    
    -- Current versions
    current = {
        nexusguard = "1.1.0",
        fivemArtifact = 0 -- Will be populated at runtime
    }
}

-- Check if detector is compatible with current FiveM version
function VersionCompat.IsDetectorCompatible(detector)
    if not VersionCompat.requirements.detectors[detector] then
        return true, "No specific requirements"
    end
    
    local required = VersionCompat.requirements.detectors[detector].fivemArtifact
    if VersionCompat.current.fivemArtifact < required then
        return false, string.format("Requires FiveM artifact %d or higher", required)
    end
    
    return true, "Compatible"
end

-- Get all compatibility information
function VersionCompat.GetCompatibilityInfo()
    local info = {
        compatible = {},
        incompatible = {}
    }
    
    for detector, _ in pairs(VersionCompat.requirements.detectors) do
        local isCompatible, reason = VersionCompat.IsDetectorCompatible(detector)
        if isCompatible then
            info.compatible[detector] = reason
        else
            info.incompatible[detector] = reason
        end
    end
    
    return info
end

-- Initialize current versions
Citizen.CreateThread(function()
    -- Try to get current FiveM version (approximate based on available natives)
    local fivemVersion = GetConvar("version", "unknown")
    
    -- Parse artifact number from version string (e.g., "FXServer-master SERVER v1.0.0.5402 win32")
    local artifactNumber = tonumber(string.match(fivemVersion, "(%d+)%s+win") or "0")
    VersionCompat.current.fivemArtifact = artifactNumber
    
    -- Log compatibility information
    local info = VersionCompat.GetCompatibilityInfo()
    print("^3[NexusGuard] Compatibility check:^7")
    print("^3[NexusGuard] FiveM artifact: " .. VersionCompat.current.fivemArtifact .. "^7")
    
    if next(info.incompatible) ~= nil then
        print("^1[NexusGuard] Warning: Some detectors may not be compatible with your FiveM version:^7")
        for detector, reason in pairs(info.incompatible) do
            print("^1[NexusGuard] - " .. detector .. ": " .. reason .. "^7")
        end
    end
end)
