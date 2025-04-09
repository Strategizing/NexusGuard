ConfigValidator = {}
local defaultConfig = {
    Detectors = {
        godMode = { enabled = true, threshold = 1.5, _type = "table" },
        speedHack = { enabled = true, threshold = 1.5, _type = "table" },
        weaponModification = { enabled = true, _type = "table" },
        teleporting = { enabled = true, threshold = 50.0, _type = "table" },
        noclip = { enabled = true, _type = "table" },
        menuDetection = { enabled = true, _type = "table" },
        resourceInjection = { enabled = true, _type = "table" },
        _type = "table"
    },
    AI = {
        enabled = false,
        modelPath = "ml_models/",
        updateInterval = 86400,
        _type = "table"
    },
    Actions = {
        kickOnSuspicion = true,
        banOnConfirmed = true,
        reportToAdminsOnSuspicion = true,
        _type = "table"
    },
    ScreenCapture = {
        enabled = false,
        includeWithReports = true,
        resolution = "1280x720",
        _type = "table"
    },
    Database = {
        enabled = false,
        historyDuration = 30,
        _type = "table"
    },
    Thresholds = {
        aiDecisionConfidenceThreshold = 0.75,
        weaponDamageMultiplier = 1.5,
        healthRegenerationRate = 2.0,
        _type = "table"
    },
    Discord = {
        enabled = false,
        webhooks = {
            alerts = "",
            bans = "",
            kicks = "",
            warnings = "",
            _type = "table"
        },
        RichPresence = {
            Enabled = false,
            AppId = "",
            UpdateInterval = 60,
            LargeImage = "",
            LargeImageText = "",
            SmallImage = "",
            SmallImageText = "",
            buttons = {
                {label = "", url = ""},
                {label = "", url = ""}
            },
            _type = "table"
        },
        _type = "table"
    },
    BanMessage = "You have been banned from this server.",
    KickMessage = "You have been kicked by the anti-cheat system.",
    AdminGroups = {"admin", "superadmin"},
    Debug = false
}
function ConfigValidator.Apply(config)
    if not config then config={} end
    local function vA(t,s,p) p=p or"" local r={}
        if type(s)~="table"or not s._type then return s end
        r._type=s._type
        for k,v in pairs(s)do if k~="_type"then
            if t and t[k]~=nil then
                if type(t[k])==s._type or k=="_type"then
                    if type(v)=="table"and v._type then r[k]=vA(t[k],v,p.."."..k) else r[k]=t[k] end
                else r[k]=v end
            end
        end end
        return r
    end
    return vA(config,defaultConfig)
end
return ConfigValidator
