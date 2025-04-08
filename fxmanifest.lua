fx_version 'cerulean'
game 'gta5'

author 'NexusGuard Team'
description 'Modular FiveM Anti-Cheat Framework'
version '0.7.0'

shared_scripts {
    'config.lua',
    'shared/event_registry.lua',
}

client_scripts {
    'client/client_main.lua',
    'client/detectors/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'globals.lua', -- Load globals first to define API table
    'server/sv_utils.lua',
    'server/sv_permissions.lua',
    'server/sv_security.lua',
    'server/sv_bans.lua',
    'server/sv_database.lua', -- Load new database module
    'server/sv_event_handlers.lua', -- Load new event handlers module
    'server/modules/*.lua',  -- Load other modules (like detections)
    'server/server_main.lua' -- Load main server logic last
    -- 'sql/setup.lua' -- Removed, DB init handled in sv_database.lua
}

dependencies {
    'oxmysql',
    'screenshot-basic',
    'ox_lib'
}

exports {
    'GetNexusGuardServerAPI' -- Export the correct function name from globals.lua
    -- 'GetCore' -- Removed potentially unused/old export
}
