-- Installation script for Bigger Reactors turbine control programs
-- Intended to be uploaded to Pastebin for easier installation.

local BASE_URL = "https://raw.githubusercontent.com/MystereFire/biggerreactor_turbine/main/"

local function download(remote, target)
    target = target or remote
    local url = BASE_URL .. remote
    print("Downloading " .. remote .. " as " .. target .. "...")
    if not shell.run("wget", url, target) then
        print("Failed to download: " .. url)
    else
        print("Installed: " .. target)
    end
end

term.clear()
term.setCursorPos(1, 1)
print("Connection type? (wired/wireless)")
local mode = read():lower()
term.clear()
term.setCursorPos(1, 1)

if mode == "wired" or mode == "w" then
    download("turbine_control.lua", "startup")
elseif mode == "wireless" or mode == "wl" then
    print("Emitter or receiver? (e/r)")
    local role = read():lower()
    term.clear()
    term.setCursorPos(1, 1)
    if role == "e" or role == "emitter" then
        download("sender.lua", "startup")
    elseif role == "r" or role == "receiver" then
        download("receiver.lua", "startup")
    else
        print("Invalid choice: " .. role)
    end
else
    print("Unknown mode: " .. mode)
end

print("Rebooting...")
sleep(1)
os.reboot()

