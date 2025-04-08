-- Script to verify and setup luasocket for debugging
print("Checking luasocket installation...")

local success, socket = pcall(require, "socket")
if not success then
    print("LuaSocket is not installed! Installing...")
    
    -- For Windows users, download and setup instructions
    print("\nPlease follow these steps to install luasocket:")
    print("1. Download LuaSocket from https://github.com/lunarmodules/luasocket/releases")
    local path = package.cpath:match("[^;]+")
    print("2. Extract the files to: " .. (path or "your Lua modules directory"))
    print("3. Ensure socket.dll and mime.dll are in the correct location")
    print("\nAlternatively, if using LuaRocks, run: luarocks install luasocket")
    print("\nError details: " .. tostring(socket))
else
    print("LuaSocket is installed!")
    print("Version: " .. (socket._VERSION or "unknown"))
    
    -- Fixed ambiguity with parentheses and added better error handling
    local success, socketPath = pcall(package.searchpath, "socket.core", package.cpath)
    if success and socketPath then
        print("Location: " .. socketPath)
    else
        print("Location: Not found in package.cpath")
        if not success then
            print("Error: " .. tostring(socketPath))
        end
    end
end

-- Check if LuaPanda can be loaded
local success, panda = pcall(require, "LuaPanda")
if not success then
    print("\nLuaPanda is not correctly installed!")
    print("Make sure the LuaHelper extension is properly installed in VS Code.")
    print("Error details: " .. tostring(panda))
else
    print("\nLuaPanda is installed!")
end

print("\nDebugging environment details:")
print("Lua version: " .. _VERSION)
print("package.path: " .. package.path)
print("package.cpath: " .. package.cpath)
