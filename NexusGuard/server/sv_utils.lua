--[[
    NexusGuard Server Utilities Module (server/sv_utils.lua)

    Purpose:
    - Provides common helper functions used across various NexusGuard server-side modules.
    - Encapsulates simple, reusable logic like logging, duration formatting, etc.

    Usage:
    - Required by other server scripts (e.g., globals.lua, server_main.lua).
    - Functions are accessed via the table returned by this module (e.g., Utils.Log(...)).
]]

local Utils = {}

--[[
    Logging Function (Utils.Log)
    Prints messages to the server console, respecting the LogLevel set in config.lua.
    Levels: 1=Error, 2=Info, 3=Debug, 4=Trace
    @param message (string): The message to log.
    @param level (number, optional): The severity level of the message (default: 2 - Info).
]]
function Utils.Log(message, level)
    level = level or 2 -- Default to Info level if not specified.
    -- Access the global Config table directly, as it's loaded early via shared_scripts.
    -- Default to LogLevel 2 (Info) if Config or Config.LogLevel is not yet available or set.
    local configLogLevel = (_G.Config and _G.Config.LogLevel) or 2
    -- Only print the message if its level is less than or equal to the configured LogLevel.
    if level <= configLogLevel then
        print("[NexusGuard] " .. message)
    end
end

--[[
    Format Duration Function (Utils.FormatDuration)
    Converts a duration in seconds into a human-readable string (e.g., "1d 2h 30m 15s").
    @param totalSeconds (number): The duration in seconds.
    @return (string): A formatted string representing the duration, or "Permanent" if input is invalid or zero.
]]
function Utils.FormatDuration(totalSeconds)
    if not totalSeconds or totalSeconds <= 0 then return "Permanent" end

    local days = math.floor(totalSeconds / 86400)
    local hours = math.floor((totalSeconds % 86400) / 3600)
    local minutes = math.floor((totalSeconds % 3600) / 60)
    local seconds = math.floor(totalSeconds % 60)

    local parts = {} -- Table to hold the components of the formatted string.
    if days > 0 then table.insert(parts, days .. "d") end
    if hours > 0 then table.insert(parts, hours .. "h") end
    if minutes > 0 then table.insert(parts, minutes .. "m") end
    -- Include seconds if it's the only unit or if it's non-zero.
    if seconds > 0 or #parts == 0 then table.insert(parts, seconds .. "s") end

    return table.concat(parts, " ") -- Join the parts with spaces.
end

--[[
    Safe Get Players Function (Utils.SafeGetPlayers)
    Safely calls the FiveM native `GetPlayers()` function using pcall to prevent errors
    if the native fails for some reason (though unlikely).
    @return (table): A table containing the list of connected player server IDs, or an empty table on failure.
]]
function Utils.SafeGetPlayers()
    -- pcall executes GetPlayers() and returns status + result/error.
    local success, players = pcall(GetPlayers)
    if success and type(players) == "table" then
        return players -- Return the list if successful.
    end
    -- Log a warning if GetPlayers() failed.
    Utils.Log("^1Warning: pcall to GetPlayers() failed. Returning empty player list.^7", 1)
    return {} -- Return an empty table to avoid errors in calling scripts.
end

-- Export the Utils table for use in other modules.
return Utils
