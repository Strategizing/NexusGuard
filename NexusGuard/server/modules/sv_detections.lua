local Detections = {}

local Config, Log, Bans, Discord, Database

-- Initialize references to other modules
function Detections.Initialize(cfg, logFunc, modules)
    Config = cfg or {}
    Log = logFunc or function(...) print(...) end
    modules = modules or {}
    Bans = modules.Bans
    Discord = modules.Discord
    Database = modules.Database
end

-- Basic detection processing
function Detections.Process(playerId, detectionType, detectionData, session)
    if Log then
        Log(("^3[Detections]^7 %s reported for player %d"):format(detectionType, playerId), 3)
    end

    -- store detection in session metrics if available
    if session and session.metrics then
        session.metrics.detections = session.metrics.detections or {}
        table.insert(session.metrics.detections, {
            type = detectionType,
            data = detectionData,
            timestamp = os.time()
        })
    end

    -- persist detection if database module is present
    if Database and Database.StoreDetection then
        Database.StoreDetection(playerId, detectionType, detectionData)
    end

    return true
end

function Detections.GetStats()
    return {}
end

return Detections
