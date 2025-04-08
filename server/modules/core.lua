local NexusGuardAPI = {}

-- Core functionality extracted from globals.lua
NexusGuardAPI.Version = "0.7.0"

-- Initialize server-side tracking
NexusGuardAPI.PlayerMetrics = {}
NexusGuardAPI.OnlineAdmins = {}

-- Export the API
return NexusGuardAPI
