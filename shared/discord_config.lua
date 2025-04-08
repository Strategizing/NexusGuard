Config.Discord = {
    -- Bot configuration
    BotToken = '',  -- Your Discord bot token
    GuildId = '',   -- Your Discord server ID
    
    -- Channels
    Channels = {
        Reports = '',       -- Channel ID for player reports
        DetectionLogs = '', -- Channel ID for cheat detections
        AdminCommands = '', -- Channel ID for admin commands
        BanLogs = '',       -- Channel ID for ban logs
        GeneralLogs = ''    -- Channel ID for general logs
    },
    
    -- Role IDs for permissions
    Roles = {
        Admin = '',         -- Full access to all commands
        Moderator = '',     -- Access to moderate commands
        Staff = ''          -- Basic access to view reports
    },
    
    -- Rich Presence settings
    RichPresence = {
        Enabled = true,
        AppId = '',         -- Your Discord application ID
        LargeImage = 'logo',
        LargeImageText = 'Protected by NexusGuard',
        SmallImage = 'shield',
        SmallImageText = 'Anti-Cheat Active',
        UpdateInterval = 60  -- Seconds between rich presence updates
    },
    
    -- Webhook URLs
    Webhooks = {
        Reports = '',
        Detections = '',
        Bans = '',
        Appeals = ''
    },
    
    -- Command prefix for Discord bot commands
    CommandPrefix = '!',
    
    -- Discord bot commands
    Commands = {
        report = true,
        status = true,
        players = true,
        ban = true,
        unban = true,
        check = true,
        history = true,
        stats = true
    }
}
