fx_version 'cerulean'
game 'gta5'

author 'NexusGuard Team'
description 'Modular FiveM Anti-Cheat Framework'
version '0.7.0'

shared_scripts {
    'shared/natives.lua',            -- Load natives wrapper first
    'shared/dependency_manager.lua', -- Load dependency manager
    'config.lua',
    'shared/event_registry.lua',
}

client_scripts {
    'client/event_proxy.lua',
    'client_main.lua', -- Main client entry point
    'client/detectors/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'shared/module_loader.lua',      -- Load module loader first
    'shared/natives.lua',            -- Load natives wrapper
    'shared/dependency_manager.lua', -- Load dependency manager
    'server/sv_utils.lua',           -- Load utils (needed for logging)
    'server/sv_core.lua',            -- Load core module (handles module loading)
    'server/sv_permissions.lua',
    'server/sv_security.lua',
    'server/sv_event_proxy.lua',
    'server/sv_session.lua',        -- Load session management module
    'server/sv_bans.lua',
    'server/sv_database.lua',       -- Load database module
    'server/sv_discord.lua',        -- Load Discord module
    'server/sv_event_handlers.lua', -- Load event handlers module
    'server/modules/*.lua',         -- Load other modules (like detections)
    'globals.lua',                  -- Load globals to define API table (after modules are available)
    'server/server_main.lua'        -- Load main server logic last
}

dependency {
    'oxmysql',
    'screenshot-basic',
    'ox_lib'
}

export {
    'GetNexusGuardServerAPI' -- Export the correct function name from globals.lua
}
