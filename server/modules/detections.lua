-- Server-Side Detection Processing Module
local Detections = {}

-- Get the NexusGuard Server API from globals.lua
-- We need access to Config, Utils (Log), Bans, Discord etc.
local NexusGuardServer = exports['NexusGuard']:GetNexusGuardServerAPI()
if not NexusGuardServer then
    print("^1[NexusGuard] CRITICAL: Failed to get NexusGuardServer API in detections.lua. Module will not function.^7")
    return Detections -- Return empty table to avoid further errors
end

-- Local alias for logging
local Log = NexusGuardServer.Utils.Log

-- Helper function to validate incoming detection data structure
local function ValidateDetectionData(detectionData)
    if type(detectionData) ~= "table" then
        Log("^1[NexusGuard Validation]^7 Received non-table detection data. Wrapping it.^7", 1)
        return { value = detectionData, clientValidated = false } -- Assume client validation failed if format is wrong
    end
    -- Ensure essential fields exist, even if nil initially
    detectionData.value = detectionData.value -- The primary value reported
    detectionData.details = detectionData.details or {} -- Additional context
    detectionData.clientValidated = detectionData.clientValidated or false -- Did the client detector flag this?
    return detectionData
end

-- Helper function to apply penalties (logging, trust score, actions)
local function ApplyPenalty(playerId, session, detectionType, validatedData, severity)
    local playerName = GetPlayerName(playerId) or ("Unknown (" .. playerId .. ")")
    local reason = validatedData.reason or "No specific reason provided."
    local details = validatedData.details or {}
    local trustImpact = NexusGuardServer.Config.Severity[detectionType] or NexusGuardServer.Config.Severity.default or 5

    Log("^1[NexusGuard Detection]^7 Player: " .. playerName .. " (ID: " .. playerId .. ") | Type: " .. detectionType .. " | Severity: " .. severity .. " | Reason: " .. reason .. " | Details: " .. lib.json.encode(details) .. "^7", 1)

    -- Update Trust Score (ensure metrics exist)
    if session and session.metrics then
        session.metrics.trustScore = math.max(0, (session.metrics.trustScore or 100) - trustImpact)
        Log("^3[NexusGuard Trust]^7 Trust score for " .. playerName .. " reduced by " .. trustImpact .. ". New score: " .. string.format("%.1f", session.metrics.trustScore) .. "^7", 2)
        -- Store detection event
        if not session.metrics.detections then session.metrics.detections = {} end
        table.insert(session.metrics.detections, {
            type = detectionType,
            reason = reason,
            details = details,
            severity = severity,
            trustImpact = trustImpact,
            timestamp = os.time()
        })
    else
         Log("^1[NexusGuard Penalty]^7 Cannot apply trust score penalty for " .. playerName .. " - session or metrics missing.^7", 1)
    end

    -- Discord Notification (using API)
    if NexusGuardServer.Discord and NexusGuardServer.Discord.Send then
        local discordMsg = string.format(
            "**Player:** %s (ID: %d)\n**Detection:** %s\n**Severity:** %s\n**Reason:** %s\n**Details:** `%s`\n**Trust Score:** %.1f (-%d)",
            playerName, playerId, detectionType, severity, reason, lib.json.encode(details), session and session.metrics and session.metrics.trustScore or -1, trustImpact
        )
        NexusGuardServer.Discord.Send("detections", "Suspicious Activity Detected", discordMsg, NexusGuardServer.Config.Discord.webhooks and NexusGuardServer.Config.Discord.webhooks.detections)
    end

    -- Execute Actions (Ban/Kick - using API)
    -- TODO: Implement progressive banning based on trust score / repeated offenses
    local actionConfig = NexusGuardServer.Config.Actions[detectionType] or NexusGuardServer.Config.Actions.default or { kickThreshold = 50, banThreshold = 20 }
    local currentTrust = session and session.metrics and session.metrics.trustScore or 100

    if currentTrust <= actionConfig.banThreshold then
        Log("^1[NexusGuard Action]^7 Trust score (" .. string.format("%.1f", currentTrust) .. ") below ban threshold (" .. actionConfig.banThreshold .. ") for " .. detectionType .. ". Banning " .. playerName .. ".^7", 1)
        if NexusGuardServer.Bans and NexusGuardServer.Bans.Execute then
            NexusGuardServer.Bans.Execute(playerId, "Automatic ban: Triggered " .. detectionType .. " (Trust: " .. string.format("%.1f", currentTrust) .. ")", "NexusGuard System")
        else
             Log("^1[NexusGuard Action]^7 Ban function missing from API. Cannot ban player.^7", 1)
             DropPlayer(playerId, "Kicked by Anti-Cheat (System Error: Ban Function Missing)") -- Fallback kick
        end
    elseif currentTrust <= actionConfig.kickThreshold then
        Log("^1[NexusGuard Action]^7 Trust score (" .. string.format("%.1f", currentTrust) .. ") below kick threshold (" .. actionConfig.kickThreshold .. ") for " .. detectionType .. ". Kicking " .. playerName .. ".^7", 1)
        DropPlayer(playerId, "Kicked by Anti-Cheat: Triggered " .. detectionType .. " (Trust: " .. string.format("%.1f", currentTrust) .. ")")
    end
end

--- Main function to process detection reports from clients or server-side checks
-- @param playerId The source player ID
-- @param detectionType String identifier (e.g., "SpeedHack", "GodMode", "ServerSpeedCheck")
-- @param detectionData Table containing details reported by the client/server check
-- @param session The player's session table (contains metrics, etc.)
function Detections.Process(playerId, detectionType, detectionData, session)
    if not NexusGuardServer or not Log then print("^1[NexusGuard Detections] CRITICAL: API or Log function not available.^7"); return false end -- Basic check

    local playerName = GetPlayerName(playerId) or ("Unknown (" .. playerId .. ")")

    -- 1. Validate Input Data Structure
    local validatedData = ValidateDetectionData(detectionData)
    validatedData.serverValidated = false -- Reset server validation flag for this processing run
    validatedData.reason = validatedData.reason or "Initial report" -- Default reason

    -- 2. Perform Server-Side Validation based on detectionType
    local isValid = false
    local severity = "Low" -- Default severity

    -- Ensure session and metrics are available for validation checks
    if not session or not session.metrics then
        Log("^1[NexusGuard Validation]^7 Cannot validate detection '" .. detectionType .. "' for " .. playerName .. " - Session or metrics data missing.^7", 1)
        -- Decide how to handle this: ignore, flag with low confidence, etc.
        -- For now, we'll log and potentially skip applying penalties.
        return false -- Stop processing if essential data is missing
    end

    -- Access config through the API object
    local Config = NexusGuardServer.Config
    local Thresholds = Config.Thresholds or {}
    local Features = Config.Features or {}

    -- --- Specific Detection Type Validations ---
    if detectionType == "SpeedHack" or detectionType == "ServerSpeedCheck" then
        local speed = tonumber(validatedData.value) or tonumber(validatedData.calculatedSpeed) -- Handle client/server naming
        if speed then
            local threshold = Thresholds.serverSideSpeedThreshold or 50.0
            local effectiveThreshold = threshold
            local reasonSuffix = ""

            -- Adjust threshold based on player state from metrics
            if session.metrics.isFalling or session.metrics.isRagdoll or session.metrics.verticalVelocity < -10.0 then
                effectiveThreshold = threshold * 2.0
                reasonSuffix = " (Adjusted for falling/ragdoll)"
            elseif session.metrics.isInVehicle then
                effectiveThreshold = threshold * 1.2
                reasonSuffix = " (Adjusted for vehicle)"
            end

            if speed > effectiveThreshold then
                isValid = true
                severity = "High"
                validatedData.reason = string.format("Calculated speed %.2f m/s exceeded threshold %.2f m/s%s", speed, effectiveThreshold, reasonSuffix)
                validatedData.details.speed = speed
                validatedData.details.threshold = effectiveThreshold
                validatedData.details.state = { falling=session.metrics.isFalling, ragdoll=session.metrics.isRagdoll, inVehicle=session.metrics.isInVehicle, vertVel=session.metrics.verticalVelocity }
            end
        else
            validatedData.reason = "Invalid speed value received."
            severity = "Info" -- Treat as an info log, not a cheat detection
        end
        validatedData.serverValidated = isValid

    elseif detectionType == "GodMode" or detectionType == "ServerHealthRegenCheck" then
        -- ServerHealthRegenCheck specific data
        local increase = tonumber(validatedData.increase)
        local rate = tonumber(validatedData.rate)
        local regenThreshold = Thresholds.serverSideRegenThreshold or 3.0

        -- GodMode might report differently (e.g., took lethal damage but didn't die) - needs client detector logic refinement
        -- For now, focus on the regen check data if available
        if rate and increase and rate > regenThreshold and increase > 5.0 then -- Use the logic from server_main
             isValid = true
             severity = "Medium"
             validatedData.reason = string.format("Health regeneration rate %.2f HP/s (increase %.1f HP) exceeded threshold %.2f HP/s", rate, increase, regenThreshold)
             validatedData.details.rate = rate
             validatedData.details.increase = increase
             validatedData.details.threshold = regenThreshold
             validatedData.details.timeDiff = validatedData.timeDiff
        else
            -- Placeholder for future GodMode validation (e.g., check health history in metrics)
            -- validatedData.reason = "Basic health regen check passed or insufficient data."
        end
         validatedData.serverValidated = isValid

    elseif detectionType == "ServerArmorCheck" then
        local armor = tonumber(validatedData.armor)
        local maxArmor = Thresholds.serverSideArmorThreshold or 105.0
        if armor and armor > maxArmor then
            isValid = true
            severity = "Medium"
            validatedData.reason = string.format("Armor value %.1f exceeded maximum allowed %.1f", armor, maxArmor)
            validatedData.details.armor = armor
            validatedData.details.threshold = maxArmor
        end
        validatedData.serverValidated = isValid

    elseif detectionType == "Teleport" or detectionType == "Noclip" or detectionType == "ServerNoclipCheck" then
        -- This requires more advanced checks (raycasting, pathfinding) which are planned next.
        -- For now, we can use the basic distance check from server_main if that data was passed.
        local distance = tonumber(validatedData.distance)
        local timeDiff = tonumber(validatedData.timeDiff)
        -- Add a basic check here if distance/timeDiff are provided, but mark severity low due to inaccuracy.
        if distance and timeDiff then
            -- This logic is rudimentary and prone to false positives.
            -- isValid = true -- Don't mark as valid yet
            severity = "Low" -- Keep severity low until better checks are in place
            validatedData.reason = "Potential teleport/noclip detected (basic distance check). Further investigation needed."
            validatedData.details.distance = distance
            validatedData.details.timeDiff = timeDiff
        else
             -- validatedData.reason = "Noclip/Teleport validation requires raycasting (Not Implemented)."
        end
        -- Raycasting Check (Guideline 31 Enhancement)
        local currentPos = validatedData.value or validatedData.details.currentPos -- Get current position from data
        local lastValidPos = session.metrics.lastValidPosition

        -- Ensure we have valid vector3 positions to check
        if type(currentPos) == "vector3" and type(lastValidPos) == "vector3" then
            local distance = #(currentPos - lastValidPos)
            local noclipTolerance = Thresholds.noclipTolerance or 3.0

            -- Only perform raycast if the movement distance is significant enough to warrant a check
            -- but not so large that it's obviously a legitimate respawn/teleport (handle those separately if needed)
            if distance > noclipTolerance and distance < (Thresholds.serverSideSpeedThreshold or 50.0) * 5.0 then -- Avoid checking huge distances likely from admin teleports/respawns
                local sourcePed = GetPlayerPed(playerId)
                local ignoreEntity = sourcePed -- Ignore the player's own ped
                local flags = 7 -- Intersect world, objects, vehicles (adjust flags as needed)

                -- Raycast from slightly above the last valid position towards slightly above the current position
                -- This helps avoid hitting the ground immediately. Adjust Z offset as needed.
                local zOffset = 0.5
                local rayStart = vector3(lastValidPos.x, lastValidPos.y, lastValidPos.z + zOffset)
                local rayEnd = vector3(currentPos.x, currentPos.y, currentPos.z + zOffset)

                -- Start the shape test (synchronous version for simplicity here, consider async if performance becomes an issue)
                -- Note: FiveM natives often return results asynchronously or require waiting.
                -- Using GetShapeTestResult directly might not work reliably without proper handling.
                -- A more robust implementation might involve storing the ray handle and checking in a later tick,
                -- or using a library that simplifies synchronous raycasting if available.
                -- For this example, we'll use the basic structure, assuming direct result retrieval works for demonstration.
                local rayHandle = StartShapeTestRay(rayStart.x, rayStart.y, rayStart.z, rayEnd.x, rayEnd.y, rayEnd.z, flags, ignoreEntity, 7)

                -- WARNING: GetShapeTestResult is often asynchronous. This direct check might be unreliable.
                -- A real implementation needs to handle the async nature, potentially over multiple ticks.
                Citizen.Wait(50) -- Short wait, hoping the result is ready (NOT RELIABLE)
                local didHit, hitPosition, hitNormal, hitEntity = GetShapeTestResult(rayHandle)

                if didHit then
                    -- Check if the hit occurred *before* reaching the destination (within tolerance)
                    local distToHit = #(vector3(hitPosition.x, hitPosition.y, hitPosition.z) - rayStart)
                    local targetDist = #(rayEnd - rayStart)

                    if distToHit < (targetDist - noclipTolerance) then
                        isValid = true
                        severity = "High" -- Noclip/Teleport through objects is serious
                        validatedData.reason = string.format("Raycast detected potential noclip/teleport. Hit obstacle at [%.2f, %.2f, %.2f] while moving from [%.2f, %.2f, %.2f] to [%.2f, %.2f, %.2f].", hitPosition.x, hitPosition.y, hitPosition.z, lastValidPos.x, lastValidPos.y, lastValidPos.z, currentPos.x, currentPos.y, currentPos.z)
                        validatedData.details.raycastHit = true
                        validatedData.details.hitPos = hitPosition
                        validatedData.details.startPos = lastValidPos
                        validatedData.details.endPos = currentPos
                        validatedData.details.hitEntity = hitEntity -- Log the entity hit, if any
                        Log("^1[NexusGuard Raycast]^7 Noclip/Teleport detected for %s (ID: %d). Ray hit entity %s at %.2f, %.2f, %.2f^7", playerName, playerId, tostring(hitEntity), hitPosition.x, hitPosition.y, hitPosition.z)
                    else
                         -- Hit occurred very close to the destination, likely just clipping the edge or landing point.
                         -- Log("^3[NexusGuard Raycast]^7 Raycast hit near destination for %s. Likely valid movement.^7", playerName, 3)
                    end
                else
                    -- Raycast didn't hit anything, movement path seems clear.
                    -- Log("^3[NexusGuard Raycast]^7 Raycast clear for %s.^7", playerName, 3)
                end
            elseif distance >= (Thresholds.serverSideSpeedThreshold or 50.0) * 5.0 then
                 -- Log large distance movements but don't necessarily flag as noclip via raycast here, could be admin action/respawn
                 Log("^3[NexusGuard Raycast]^7 Skipping raycast for %s due to large distance (%.2fm). Likely admin TP or respawn.^7", playerName, distance, 3)
            end
        else
             validatedData.reason = "Noclip/Teleport validation requires valid current and last positions."
        end
        validatedData.serverValidated = isValid -- Update validation status based on raycast result

    elseif detectionType == "WeaponModification" or detectionType == "ServerWeaponClipCheck" then
        local reportedClip = tonumber(validatedData.reportedClip)
        local maxAllowed = tonumber(validatedData.maxAllowed)
        local weaponHash = validatedData.weaponHash

        if reportedClip and maxAllowed and reportedClip > maxAllowed then
            isValid = true
            severity = "High"
            validatedData.reason = string.format("Weapon %s clip size %d exceeded max allowed %d", weaponHash or 'Unknown', reportedClip, maxAllowed)
            validatedData.details.weapon = weaponHash
            validatedData.details.reported = reportedClip
            validatedData.details.allowed = maxAllowed
            validatedData.details.base = validatedData.baseClip
        end
         validatedData.serverValidated = isValid

    elseif detectionType == "ResourceMismatch" then
        -- This detection comes directly from server_main's check, so it's inherently server-validated.
        isValid = true
        severity = "Critical" -- Resource tampering is serious
        validatedData.reason = "Unauthorized client resources detected (" .. (validatedData.mode or "unknown mode") .. ")."
        validatedData.details.mismatched = validatedData.mismatched or {}
        validatedData.serverValidated = isValid -- Mark as validated

    elseif detectionType == "MenuInjection" then
         -- Server-side validation is difficult. Rely heavily on client checks + resource verification.
         -- Consider heuristics: sudden changes in behavior, impossible actions.
         severity = "Critical"
         validatedData.reason = "Client reported potential menu injection."
         -- No reliable server validation possible for this specific event type currently.
         isValid = validatedData.clientValidated -- Trust client report for now, but severity implies action
         validatedData.serverValidated = false -- Explicitly mark as not server-validated

    -- Add more 'elseif' blocks for other detection types as needed

    else
        -- Unknown detection type
        Log("^3[NexusGuard Validation]^7 Received unknown detection type '" .. detectionType .. "' from " .. playerName .. ". Client validated: " .. tostring(validatedData.clientValidated) .. "^7", 2)
        severity = "Info"
        validatedData.reason = "Unknown detection type received."
        isValid = validatedData.clientValidated -- Trust client if unknown type
        validatedData.serverValidated = false -- Cannot validate unknown type
    end

    -- 3. Apply Penalties if Validated
    if isValid then
        ApplyPenalty(playerId, session, detectionType, validatedData, severity)
    else
        -- Log if client flagged but server didn't validate (potential false positive or client-only detection)
        if validatedData.clientValidated then
             Log("^2[NexusGuard Validation]^7 Client flagged '" .. detectionType .. "' for " .. playerName .. ", but server-side validation did not confirm. Reason: " .. (validatedData.reason or "Validation failed or insufficient data") .. "^7", 2)
             -- Optionally apply a very minor trust penalty for client flags not confirmed by server?
             -- ApplyPenalty(playerId, session, detectionType .. "_ClientOnly", validatedData, "Info") -- Example
        end
    end

    return isValid -- Return whether the detection was validated server-side
end


return Detections
