Config = {}

-- General Settings
Config.ServerName = "My Awesome FiveM Server" -- Your server name (You can change this later)
Config.LogLevel = 1 -- Production default
Config.EnableDiscordLogs = false -- DISABLED: Enable Discord webhook logs (Separate from LogLevel)
Config.DiscordWebhook = "" -- Your Discord webhook URL (General logs if specific webhooks below aren't set)
Config.BanMessage = "You have been banned for cheating. Appeal at: discord.gg/yourserver" -- Ban message
Config.KickMessage = "You have been kicked for suspicious activity." -- Kick message

-- Permissions Framework Configuration
-- Set this to match your server's permission system. Affects the IsPlayerAdmin check in globals.lua.
-- Options:
-- "ace"    : Use built-in FiveM ACE permissions (checks group.<group_name> for groups in Config.AdminGroups).
-- "esx"    : Use ESX framework (checks xPlayer.getGroup() against Config.AdminGroups). Requires ESX to be running.
-- "qbcore" : Use QBCore framework (checks QBCore.Functions.HasPermission(playerId, group) for groups in Config.AdminGroups). Requires QBCore to be running.
-- "custom" : Use this if you want to write your own logic directly into the IsPlayerAdmin function in globals.lua.
Config.PermissionsFramework = "ace" -- Default to ACE permissions

Config.AdminGroups = {"admin", "superadmin", "mod"} -- Groups considered admin by the selected framework check (case-sensitive depending on framework)
-- Example ACE groups (default): {"admin", "superadmin", "mod"}
-- Example ESX groups: {"admin", "superadmin"}
-- Example QBCore groups: {"admin", "god"} -- Or other high-level permission groups defined in your QBCore setup

-- #############################################################################
-- ## !! CRITICAL SECURITY CONFIGURATION !! ##
-- #############################################################################
-- ## YOU **MUST** CHANGE THIS VALUE BEFORE STARTING YOUR SERVER! ##
-- ## LEAVING THE DEFAULT VALUE WILL MAKE YOUR SERVER VULNERABLE! ##
-- #############################################################################
-- Generate a long, unique, random string (e.g., using a password manager or online generator like https://www.random.org/strings/).
-- This secret is VITAL for securing communication between the client and server using HMAC-SHA256.
-- **DO NOT SHARE THIS SECRET.** NexusGuard will log a CRITICAL error on startup if this is left as default.
-- Example of a strong secret (DO NOT USE THIS EXAMPLE): "p$z^8@!L#s&G*f@D9j!K3m$n&P@r*T(w"
Config.SecuritySecret = "p$z^8@!L#s&G*f@D9j!K3m$n&P@r*T(w" -- Example of a strong random string

-- Security Token Settings
Config.Security = {
    TokenValidityWindow = 60, -- Seconds a token is considered valid after generation (Default: 60)
    TokenCacheCleanupIntervalMs = 60000, -- Milliseconds between cleaning up expired tokens from the anti-replay cache (Default: 60000 = 1 minute)
    -- Anti-replay protection: token signatures are cached to prevent reuse within the validity window.
}

-- [[ DEPRECATED / PLACEHOLDER SECTIONS REMOVED ]]
-- Config.AutoConfig removed as it was a non-functional placeholder.

-- Detection Thresholds
Config.Thresholds = {
    weaponDamageMultiplier = 1.5, -- Threshold for weapon damage (1.0 = normal)
    speedHackMultiplier = 1.3, -- Speed multiplier threshold (player movement)
    teleportDistance = 75.0, -- Maximum allowed teleport distance (meters) - Lowered slightly
    noclipTolerance = 3.0, -- NoClip detection tolerance
    vehicleSpawnLimit = 5, -- Vehicles spawned per minute
    entitySpawnLimit = 15, -- Entities spawned per minute
    healthRegenerationRate = 2.0, -- Health regeneration rate threshold
    aiDecisionConfidenceThreshold = 0.75, -- AI confidence threshold for automated action

    -- Server-Side Validation Thresholds (Used by server checks, independent of client checks)
    serverSideSpeedThreshold = 50.0, -- Max allowed speed in m/s based on server position checks (Approx 180 km/h). Tune carefully!
    minTimeDiffPositionCheck = 450, -- Minimum time in milliseconds between server-side position checks to calculate speed. Lower values are more sensitive but prone to false positives due to network jitter.
    serverSideRegenThreshold = 3.0, -- Max allowed passive HP regen rate in HP/sec based on server health checks.
    serverSideArmorThreshold = 105.0, -- Max allowed armor value based on server health checks (Allows slight buffer over 100).

    spawnGracePeriod = 5, -- Seconds to ignore speed checks after spawn
    teleportGracePeriod = 3, -- Seconds to ignore position jumps after resource start/teleport
    fallingSpeedMultiplier = 1.5 -- Allow higher speeds when falling
}

-- Server-Side Explosion Checks Configuration
Config.ExplosionChecks = {
    enabled = true, -- Enable server-side explosion checks
    spamTimeWindow = 10, -- Time window in seconds to check for spam
    spamCountThreshold = 5, -- Number of explosions within the window to trigger spam detection
    spamDistanceThreshold = 5.0, -- Max distance (meters) between explosions to be considered part of the same spam cluster
    -- Blacklisted Explosion Types: Add explosion type IDs that should *always* trigger a detection if caused by a player.
    -- Find type IDs here: https://docs.fivem.net/natives/?_0x11DE73A0D57F3358
    -- Example: 2 = GrenadeLauncher, 3 = StickyBomb, 35 = VALKYRIE_CANNON (often abused)
    blacklistedTypes = {
        -- 2, 3, 35 -- Uncomment and add IDs as needed
    },
    kickOnBlacklisted = false, -- Kick player immediately if they trigger a blacklisted explosion type
    banOnBlacklisted = false -- Ban player immediately if they trigger a blacklisted explosion type
}

-- Severity Scores for Detections (Used for Trust Score calculation)
-- Adjust these values based on how severely you want each detection to impact trust score.
Config.SeverityScores = {
    -- Server-Side Validated Detections
    ServerSpeedCheck = 10,
    ServerHealthRegenCheck = 15,
    ServerArmorCheck = 5,
    ServerWeaponClipCheck = 8,
    BlacklistedExplosion = 25, -- High impact as it's explicitly disallowed
    ExplosionSpam = 12,
    ResourceMismatch = 20, -- High impact as it indicates client modification/tampering

    -- Client-Side Detections (Generally lower confidence unless tuned)
    menuDetection = 5, -- Low impact due to unreliability of keybind checks
    noclip = 15, -- Moderate impact, but prone to false positives without server validation
    godMode = 10, -- Client-side flags can be spoofed, server validation is key
    weaponModification = 7, -- Client-side damage/clip checks are less reliable
    speedHack = 5, -- Client-side speed check is less reliable than server's
    teleporting = 5, -- Client-side teleport check is less reliable than server's

    -- Add other detection types reported by client/server detectors here
    -- e.g., freecam = 3, vehicleModification = 8, etc.

    default = 5 -- Default severity for any detection type not listed
}

-- Server-Side Weapon Base Data (for validation)
-- Add known base values for weapons here. This helps the server validate client reports.
-- Values can vary based on game version/mods. Use natives on a clean client/server to find defaults.
-- Key: Weapon Hash (use GetHashKey("WEAPON_PISTOL") etc.)
Config.WeaponBaseDamage = { -- Base Damage (float)
    [GetHashKey("WEAPON_PISTOL")] = 26.0,
    [GetHashKey("WEAPON_COMBATPISTOL")] = 27.0,
    [GetHashKey("WEAPON_APPISTOL")] = 28.0,
    [GetHashKey("WEAPON_MICROSMG")] = 21.0,
    [GetHashKey("WEAPON_SMG")] = 22.0,
    [GetHashKey("WEAPON_ASSAULTRIFLE")] = 30.0,
    [GetHashKey("WEAPON_CARBINERIFLE")] = 32.0,
    [GetHashKey("WEAPON_SPECIALCARBINE")] = 34.0,
    [GetHashKey("WEAPON_PUMPSHOTGUN")] = 30.0, -- Damage per pellet, often multiple pellets per shot
    [GetHashKey("WEAPON_SNIPERRIFLE")] = 100.0,
    -- Add more weapons as needed...
}
Config.WeaponBaseClipSize = { -- Base Clip Size (integer)
    [GetHashKey("WEAPON_PISTOL")] = 12,
    [GetHashKey("WEAPON_COMBATPISTOL")] = 12,
    [GetHashKey("WEAPON_APPISTOL")] = 18,
    [GetHashKey("WEAPON_MICROSMG")] = 16,
    [GetHashKey("WEAPON_SMG")] = 30,
    [GetHashKey("WEAPON_ASSAULTRIFLE")] = 30,
    [GetHashKey("WEAPON_CARBINERIFLE")] = 30,
    [GetHashKey("WEAPON_SPECIALCARBINE")] = 30,
    [GetHashKey("WEAPON_PUMPSHOTGUN")] = 8,
    [GetHashKey("WEAPON_SNIPERRIFLE")] = 10,
    -- Add more weapons as needed...
}

-- Detection Types
-- These flags enable/disable the *client-side* detector modules.
-- Server-side checks (like speed, health, weapon validation) run based on received events, not these flags.
Config.Detectors = {
    godMode = true,
    speedHack = true,
    weaponModification = true,
    resourceInjection = true,
    explosionSpamming = true,
    objectSpamming = true,
    entitySpawning = true,
    noclip = true,
    freecam = true,
    teleporting = true,
    menuDetection = true,
    vehicleModification = true,
    -- resourceInjection = true, -- Note: Client-side resource injection detection is complex and often unreliable. Focus on server-side verification.
    -- explosionSpamming = true, -- Note: Primarily handled server-side via explosionEvent handler.
    -- objectSpamming = true, -- Note: Requires server-side entity creation monitoring.
    -- entitySpawning = true, -- Note: Requires server-side entity creation monitoring.
    -- freecam = true, -- Note: Freecam detection is notoriously difficult and prone to false positives.
}

-- Action Settings
Config.Actions = {
    kickOnSuspicion = true, -- Kick player when suspicious activity is detected (Keep true)
    banOnConfirmed = true, -- Ban player when cheating is confirmed (Keep true)
    warningThreshold = 2, -- Number of warnings before taking action (Lowered)
    screenshotOnSuspicion = true, -- Take screenshot on suspicious activity (Keep true)
    reportToAdminsOnSuspicion = true, -- Report suspicious activity to online admins (Keep true)
    notifyPlayer = true, -- Notify player they are being monitored (can deter cheaters)
    progressiveResponse = true -- Gradually increase response severity with repeated offenses
}

-- Optional Features
Config.Features = {
    -- [[ DEPRECATED / PLACEHOLDER SECTIONS REMOVED ]]
    -- Config.Features.adminPanel removed (placeholder).
    -- Config.Features.playerReports removed (placeholder).

    resourceVerification = {
        enabled = false, -- DISABLED BY DEFAULT: Verify integrity of client resources. Requires careful configuration if enabled! See README.
        mode = "whitelist", -- "whitelist" (recommended but requires listing ALL essential resources) or "blacklist" (blocks specific known cheat resources).
        -- Whitelist Mode: ONLY resources listed here are allowed. Add ALL essential FiveM, framework (ESX, QBCore), and core server resources.
        whitelist = {
            "chat",
            "spawnmanager",
            "mapmanager",
            "basic-gamemode", -- Example core resource
            "fivem",          -- Core resource
            "hardcap",        -- Core resource
            "rconlog",        -- Core resource
            "sessionmanager", -- Core resource
            GetCurrentResourceName(), -- Always allow the anti-cheat resource itself
            -- !! VERY IMPORTANT !! If using whitelist mode, you MUST add ALL essential resources
            -- for your server here. This includes your framework (e.g., 'es_extended', 'qb-core'),
            -- maps, MLOs, core scripts (chat, spawnmanager, etc.), UI scripts, and any other
            -- resource required for your server to function.
            -- Failure to whitelist essential resources WILL cause players to be kicked/banned incorrectly.
            -- Example: 'es_extended', 'qb-core', 'qb-inventory', 'ox_lib', 'ox_inventory', 'cd_drawtextui'
        },
        -- Blacklist Mode: Resources listed here are DISALLOWED. Useful for blocking known cheat menus.
        blacklist = {
            -- Add known cheat menu resource names here (case-sensitive)
            "LambdaMenu",     -- Example
            "SimpleTrainer",  -- Example
            "menyoo"
        },
        kickOnMismatch = true, -- Kick player if unauthorized resources are detected
        banOnMismatch = false -- Ban player if unauthorized resources are detected (Use with caution)
    },
    performanceOptimization = true, -- Optimize detection methods based on server performance
    autoUpdate = true, -- Check for updates automatically
    compatibilityMode = false -- Enable for older servers with compatibility issues
}

-- Performance Settings
Config.Performance = {
    adaptiveChecking = true, -- Adjust check frequency based on suspicion level
    adaptiveTiming = {
        baseInterval = 1000, -- Base interval used for adaptive calculations
        highRiskMultiplier = 0.5, -- Interval multiplier when suspicion is at maximum
        lowRiskMultiplier = 2.0, -- Interval multiplier when suspicion is zero
        minimumDelay = 200, -- Absolute minimum delay between checks (ms)
        maxSuspicion = 100 -- Maximum suspicion score before clamping
    },
    batchUpdates = true, -- Group position/health updates to reduce network traffic
    optimizeLogging = true, -- Only log important events in production
    smartDetection = true -- Context-aware detection (reduces false positives)
}

-- Client-Side Specific Settings
Config.Client = {
    PositionUpdateInterval = 5000 -- Interval in milliseconds for sending position/health updates to the server. Lower values increase accuracy but also network traffic.
}

-- Detection Intervals (ms) - Control CPU usage
Config.Intervals = {
    speedHack = 2000,
    godMode = 3000,
    noclip = 1500,
    weaponMod = 4000,
    resourceMonitor = 5000,
    menuDetection = 2500
    -- Add more detector intervals
}

-- Database Settings
Config.Database = {
    enabled = true, -- Requires oxmysql
    storeDetectionHistory = true, -- Store all detections in database
    historyDuration = 30, -- Days to keep detection history
    useAsync = true, -- Use async database operations
    tablePrefix = "nexusguard_", -- Prefix for database tables
    backupFrequency = 24 -- Hours between database backups
}

-- Screen Capture Settings
Config.ScreenCapture = {
    enabled = false, -- DISABLED: Requires screenshot-basic and a valid webhookURL
    webhookURL = "", -- !! REQUIRED if enabled !! Discord webhook for screenshots
    quality = "medium", -- Screenshot quality (low, medium, high)
    includeWithReports = true, -- Include screenshots with admin reports
    automaticCapture = true, -- Take periodic screenshots of suspicious players
    storageLimit = 50 -- Maximum number of screenshots to store per player
}

-- Discord Integration
Config.Discord = {
    enabled = false, -- DISABLED: Requires bot implementation and configuration below
    -- #############################################################################
    -- ## Discord Bot Integration (Requires Separate Bot Implementation) ##
    -- #############################################################################
    -- Enabling these features requires you to run a separate Discord bot application
    -- (e.g., using discord.js, discord.py) that interacts with NexusGuard, potentially
    -- via custom events, RCON, or a dedicated API if you build one.
    -- NexusGuard itself only provides basic webhook logging and Rich Presence.
    botToken = "", -- !! REQUIRED for bot features !! Your Discord bot token for your separate bot application.
    guildId = "", -- !! REQUIRED for bot features !! Your Discord server ID where the bot operates.
    botCommandPrefix = "!ac", -- Command prefix your separate bot should listen for.
    inviteLink = "discord.gg/yourserver", -- Discord invite link (used in messages/presence).

    richPresence = {
        enabled = false, -- DISABLED BY DEFAULT: Enable Discord Rich Presence for players.
        appId = "YOUR_DISCORD_APP_ID", -- !! REQUIRED if enabled !! Your Discord Application ID (Create one at discord.com/developers/applications). Replace "1234567890".
        largeImageKey = "logo", -- Large image key (Must be uploaded to Discord App Assets)
        smallImageKey = "shield", -- Small image key (Must be uploaded to Discord App Assets)
        updateInterval = 60, -- How often to update presence (seconds)
        showPlayerCount = true, -- Show current player count in status
        showServerName = true, -- Show server name in status
        showPlayTime = true, -- Show player's time spent on server
        customMessages = { -- Random messages to display in rich presence
            "Secured by NexusGuard",
            "Protected Server",
            "Anti-Cheat Active"
        },
        buttons = { -- Up to 2 buttons that appear on rich presence
            {
                label = "Join Discord",
                url = "discord.gg/yourserver"
            },
            {
                label = "Server Website",
                url = "https://yourserver.com"
            }
        }
    },
    
    bot = {
        status = "Monitoring FiveM server", -- Bot status message
        avatarURL = "", -- URL to bot's avatar image
        embedColor = "#FF0000", -- Default color for embeds
        activityType = "WATCHING", -- PLAYING, WATCHING, LISTENING, STREAMING
        commands = {
            enabled = true,
            restrictToChannels = true, -- Restrict bot commands to specific channels
            commandChannels = {"YOUR_COMMAND_CHANNEL_ID"}, -- !! REQUIRED if restrictToChannels = true !! Channel IDs where your bot commands are allowed. Replace "123456789".
            available = { -- List of commands your separate bot should implement.
                "status", -- Example: Get server status
                "players", -- Example: List online players
                "ban", -- Ban player
                "unban", -- Unban player
                "kick", -- Kick player
                "warn", -- Warn player
                "history", -- View player history
                "screenshot", -- Request player screenshot
                "restart", -- Restart anti-cheat
                "help" -- Show command help
            }
        },
        playerReports = {
            enabled = true,
            requireProof = true, -- Require screenshot/video evidence
            notifyAdmins = true, -- Send notification to admins
            createThreads = true, -- Create thread for each report
            reportCooldown = 300, -- Seconds between player reports
            autoArchiveThreads = 24 -- Hours before auto-archiving threads (0 to disable)
        },
        notifications = {
            playerJoin = true, -- Notify when player joins
            playerLeave = true, -- Notify when player leaves
            suspiciousActivity = true, -- Notify on suspicious activity
            serverStatus = true, -- Server status updates
            anticheatUpdates = true -- Anti-cheat update notifications
        } -- Closing brace for Config.Discord.bot.notifications
        }, -- Closing brace for Config.Discord.bot

        webhookWhitelist = {
            -- Add full Discord webhook URLs that can be used with the specificWebhook parameter
            -- "https://discord.com/api/webhooks/1234567890/abcdef",
        },

        webhooks = {
            general = "", -- General anti-cheat logs (Can be the same as Config.DiscordWebhook)
            bans = "", -- Ban notifications (Can be the same as Config.DiscordWebhook)
            kicks = "", -- Kick notifications
            warnings = "" -- Warning notifications
        } -- Closing brace for Config.Discord.webhooks
    } -- Closing brace for Config.Discord
