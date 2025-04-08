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
    'server/modules/*.lua',  -- Load all modular components
    'server/server_main.lua',
    'sql/setup.lua'
}

dependencies {
    'oxmysql',
    'screenshot-basic',
    'ox_lib'
}

exports {
    'GetNexusGuardAPI',
    'GetCore'
}
