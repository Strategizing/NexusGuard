# NexusGuard Configuration Guide

This guide provides detailed information on configuring and tuning NexusGuard to optimize its performance and effectiveness for your FiveM server.

## Table of Contents

1. [Basic Configuration](#basic-configuration)
2. [Detection Thresholds](#detection-thresholds)
3. [Server Authority Settings](#server-authority-settings)
4. [Response Actions](#response-actions)
5. [Database Configuration](#database-configuration)
6. [Discord Integration](#discord-integration)
7. [Performance Optimization](#performance-optimization)
8. [Troubleshooting](#troubleshooting)

## Basic Configuration

The main configuration file is `config.lua`. Here are the essential settings you should configure:

```lua
-- General Settings
Config.ServerName = "My Awesome FiveM Server" -- Your server name
Config.LogLevel = 2 -- 1=Error, 2=Info, 3=Debug, 4=Trace
Config.BanMessage = "You have been banned for cheating. Appeal at: discord.gg/yourserver"
Config.KickMessage = "You have been kicked for suspicious activity."

-- Security Settings
Config.SecuritySecret = "CHANGE_THIS_TO_A_LONG_RANDOM_STRING" -- CRITICAL: Change this!

-- Permission Settings
Config.PermissionsFramework = "ace" -- Options: "ace", "esx", "qbcore", "custom"
Config.AdminGroups = {"admin", "superadmin"} -- Admin group names in your framework
```

### Enabling/Disabling Detectors

You can enable or disable individual detection modules:

```lua
Config.Detectors = {
    godmode = true,
    speedhack = true,
    teleport = true,
    noclip = true,
    resourcemonitor = true,
    menudetection = true,
    vehicle = true,
    -- Add your custom detectors here
}
```

## Detection Thresholds

Fine-tune detection sensitivity with these threshold settings:

```lua
Config.Thresholds = {
    -- Speed and Movement
    serverSideSpeedThreshold = 50.0, -- Maximum speed in m/s
    teleportThreshold = 100.0, -- Distance in meters considered a teleport
    teleportGracePeriod = 5, -- Seconds to ignore checks after teleport
    
    -- Health and Armor
    serverSideRegenThreshold = 3.0, -- Maximum health regen rate (HP/sec)
    serverSideArmorThreshold = 105.0, -- Maximum armor value (with tolerance)
    healthDamageToleranceThreshold = 10.0, -- Tolerance for health after damage
    minHealthDamageThreshold = 5.0, -- Minimum damage to consider for godmode detection
    
    -- Weapon and Damage
    weaponDamageMultiplier = 1.5, -- Maximum allowed damage multiplier
    
    -- Timing and Windows
    minTimeDiff = 450, -- Minimum ms between position checks
    godModeDetectionWindow = 60, -- Time window for godmode pattern detection
    
    -- Noclip Detection
    enableNoclipDetection = true,
    noclipTolerance = 3.0, -- Distance tolerance for noclip detection
}
```

### Tuning Guidelines

- **Speed Thresholds**: Start conservative (higher values) and gradually lower them as you confirm there are no false positives.
- **Health Regeneration**: The default of 3.0 HP/sec works well for most servers, but may need adjustment if you have custom health systems.
- **Teleport Distance**: 100.0 meters is a good starting point, but consider your map size and legitimate teleport scripts.

## Server Authority Settings

These settings control how much the server validates client-reported data:

```lua
Config.ServerAuthority = {
    enabled = true,
    validatePosition = true,
    validateHealth = true,
    validateWeapons = true,
    validateResources = true,
    
    -- Advanced settings
    positionUpdateFrequency = 1000, -- ms between position updates
    healthUpdateFrequency = 2000, -- ms between health updates
    resourceCheckFrequency = 30000, -- ms between resource checks
}
```

## Response Actions

Configure how NexusGuard responds to different types of detections:

```lua
Config.Actions = {
    -- Default actions (applied if not specified for a detection type)
    default = {
        warnThreshold = 80, -- Trust score to trigger warnings
        kickThreshold = 50, -- Trust score to trigger kicks
        banThreshold = 20,  -- Trust score to trigger bans
        trustImpact = 10    -- Trust score reduction per detection
    },
    
    -- Detection-specific actions
    godmode = {
        warnThreshold = 70,
        kickThreshold = 40,
        banThreshold = 20,
        trustImpact = 20
    },
    
    speedhack = {
        warnThreshold = 80,
        kickThreshold = 50,
        banThreshold = 30,
        trustImpact = 15
    },
    
    -- Add custom actions for other detection types
}
```

### Progressive Response

The trust score system provides a progressive response mechanism:

1. Players start with a trust score of 100
2. Detections reduce the trust score based on `trustImpact`
3. When trust score falls below thresholds, actions are triggered
4. Trust score persists for the session but resets on reconnect

## Database Configuration

Configure the database for storing bans, detections, and session data:

```lua
Config.Database = {
    enabled = true,
    historyDuration = 30, -- Days to keep detection history
    
    -- Tables (don't change unless you modified schema.sql)
    tables = {
        bans = "nexusguard_bans",
        detections = "nexusguard_detections",
        sessions = "nexusguard_sessions"
    }
}
```

## Discord Integration

Set up Discord integration for notifications and logging:

```lua
Config.Discord = {
    enabled = true,
    
    webhooks = {
        alerts = "https://discord.com/api/webhooks/your_webhook_url",
        bans = "https://discord.com/api/webhooks/your_webhook_url",
        kicks = "https://discord.com/api/webhooks/your_webhook_url",
        warnings = "https://discord.com/api/webhooks/your_webhook_url"
    },
    
    RichPresence = {
        Enabled = true,
        AppId = "your_discord_app_id",
        UpdateInterval = 60,
        LargeImage = "large_image_key",
        LargeImageText = "Playing on My Server",
        SmallImage = "small_image_key",
        SmallImageText = "Protected by NexusGuard",
        buttons = {
            {label = "Join Discord", url = "https://discord.gg/yourserver"},
            {label = "Server Website", url = "https://yourserver.com"}
        }
    }
}
```

## Performance Optimization

Optimize NexusGuard's performance with these settings:

```lua
Config.Performance = {
    -- Client-side settings
    clientCheckInterval = 1000, -- ms between client-side checks
    clientPositionUpdateInterval = 2000, -- ms between position updates to server
    clientHealthUpdateInterval = 3000, -- ms between health updates to server
    
    -- Server-side settings
    serverCleanupInterval = 60000, -- ms between cleanup operations
    maxHistorySize = 50, -- Maximum detection history entries per player
    maxSessionsInMemory = 100, -- Maximum number of sessions to keep in memory
    
    -- Adaptive checking (reduces checks for trusted players)
    adaptiveChecking = true,
    adaptiveCheckingMinInterval = 500, -- Minimum ms between checks
    adaptiveCheckingMaxInterval = 5000 -- Maximum ms between checks
}
```

### Optimization Tips

1. **Increase Check Intervals**: For high-population servers, increase check intervals to reduce CPU usage.
2. **Enable Adaptive Checking**: This reduces check frequency for trusted players.
3. **Limit History Size**: Reduce `maxHistorySize` if memory usage is a concern.
4. **Disable Unused Features**: Turn off features you don't need (e.g., Discord integration, specific detectors).

## Troubleshooting

### Common Issues and Solutions

#### False Positives

If you're experiencing false positives:

1. **Increase Thresholds**: Raise the relevant thresholds in `Config.Thresholds`.
2. **Check Server Sync**: Poor server performance can cause false positives. Ensure your server is not overloaded.
3. **Review Logs**: Set `Config.LogLevel = 4` temporarily to get detailed logs for analysis.

#### Performance Issues

If NexusGuard is causing performance problems:

1. **Increase Check Intervals**: Raise the values in `Config.Performance`.
2. **Disable Resource-Intensive Detectors**: Some detectors (like noclip) are more CPU-intensive.
3. **Reduce Database Activity**: Set `Config.Database.enabled = false` if database operations are slow.

#### Database Errors

If you're seeing database errors:

1. **Check Connection**: Ensure `oxmysql` is properly configured.
2. **Verify Schema**: Make sure you've imported `sql/schema.sql`.
3. **Check Permissions**: Ensure the database user has appropriate permissions.

### Getting Help

If you need further assistance:

1. Check the [NexusGuard GitHub repository](https://github.com/yourusername/nexus-guard) for updates and issues.
2. Join our [Discord server](https://discord.gg/yourserver) for community support.
3. Open an issue on GitHub with detailed information about your problem.

## Conclusion

Proper configuration is essential for NexusGuard to effectively protect your server while minimizing false positives and performance impact. Start with conservative settings and gradually tune them based on your server's specific needs and player behavior patterns.

Remember that anti-cheat is an ongoing process. Regularly review logs, update configurations, and stay informed about new cheating methods to maintain effective protection for your server.
