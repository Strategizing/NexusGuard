--[[
    NexusGuard Server Utilities Module
    Contains common helper functions used across server-side scripts.
]]

local Utils = {}

-- Simple logging utility
-- Needs access to Config for LogLevel
function Utils.Log(message, level)
    level = level or 2
    -- Access Config directly as it's loaded globally early
    local configLogLevel = (_G.Config and _G.Config.LogLevel) or 2 -- Default to Info if not set
    if level <= configLogLevel then -- Log if message level is less than or equal to config level
        print("[NexusGuard] " .. message)
    end
end

-- Helper function to format duration
function Utils.FormatDuration(totalSeconds)
    if not totalSeconds or totalSeconds <= 0 then return "Permanent" end
    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)
    local parts = {}
    if days > 0 then table.insert(parts, days .. "d") end
    if hours > 0 then table.insert(parts, hours .. "h") end
    if minutes > 0 then table.insert(parts, minutes .. "m") end
    if seconds > 0 or #parts == 0 then table.insert(parts, seconds .. "s") end
    return table.concat(parts, " ")
end

-- Helper to safely get players list
function Utils.SafeGetPlayers()
    local success, players = pcall(GetPlayers)
    if success and type(players) == "table" then
        return players
    end
    Utils.Log("^1Warning: Failed to get player list via GetPlayers().^7", 1)
    return {}
end

return Utils
