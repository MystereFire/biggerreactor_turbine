-- Installation script for Bigger Reactors turbine control programs
-- Intended to be uploaded to Pastebin for easier installation.

local BASE_URL = "https://raw.githubusercontent.com/MystereFire/biggerreactor_turbine/main/"

local function download(file)
    local url = BASE_URL .. file
    print("Downloading " .. file .. "...")
    if not shell.run("wget", url, file) then
        print("Failed to download: " .. url)
    else
        print("Installed: " .. file)
    end
end

print("Connection type? (wired/wireless)")
local mode = read():lower()

if mode == "wired" or mode == "w" then
    download("turbine_control.lua")
elseif mode == "wireless" or mode == "wl" then
    print("Emitter or receiver? (e/r)")
    local role = read():lower()
    if role == "e" or role == "emitter" then
        download("sender.lua")
    elseif role == "r" or role == "receiver" then
        download("receiver.lua")
    else
        print("Invalid choice: " .. role)
    end
else
    print("Unknown mode: " .. mode)
end

