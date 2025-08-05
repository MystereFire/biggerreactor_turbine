local monitor = peripheral.find("monitor")
if not monitor then
    error("No monitor found")
end

local turbines = {}

-- Fonction pour recharger dynamiquement les turbines
local function refreshTurbines()
    local newList = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "BiggerReactors_Turbine" then
            local success, p = pcall(function()
                return peripheral.wrap(name)
            end)
            if success and p then
                local alreadyExists = false
                for _, existing in ipairs(turbines) do
                    if existing.name == name then
                        table.insert(newList, existing)
                        alreadyExists = true
                        break
                    end
                end
                if not alreadyExists then
                    table.insert(newList, {
                        name = name,
                        p = p,
                        x = 0,
                        y = 0,
                        auto = false,
                        autopilot = false,
                        flowStep = 500,
                        flowMin = 0,
                        flowMax = 120000,
                        currentFlow = 40000,
                        targetRPM = 1850,
                        kP = 0.2,
                        kD = 0.05,
                        lastRPM = 0
                    })
                end
            end
        end
    end
    turbines = newList
end

monitor.setTextScale(0.5)
local w, h = monitor.getSize()
local cardHeight = 8
local minCardWidth = 18
local perRow = math.max(1, math.floor(w / (minCardWidth + 2)))
local cardWidth = math.floor((w - (perRow + 1) * 2) / perRow)

-- Placement des cartes
local function repositionCards()
    for i, t in ipairs(turbines) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        t.x = col * (cardWidth + 2) + 1
        t.y = row * (cardHeight + 1) + 3
    end
end

local allState = false
local allAutopilot = false

-- Dessine uniquement les bordures d'une carte
local function drawBox(x, y, width, height, color)
    monitor.setTextColor(color)
    monitor.setCursorPos(x, y)
    monitor.write("+" .. string.rep("-", width - 2) .. "+")
    for i = 1, height - 2 do
        monitor.setCursorPos(x, y + i)
        monitor.write("|" .. string.rep(" ", width - 2) .. "|")
    end
    monitor.setCursorPos(x, y + height - 1)
    monitor.write("+" .. string.rep("-", width - 2) .. "+")
end

-- Affiche le bouton ON/OFF global
local function drawButton()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(1, 1)
    monitor.clearLine()
    monitor.write(allState and "All OFF" or "All ON")

    local label = allAutopilot and "Auto OFF" or "Auto ON"
    monitor.setCursorPos(w - #label + 1, 1)
    monitor.write(label)
end

-- Affiche toutes les cartes turbine
local function drawCards()
    if #turbines == 0 then
        monitor.setTextColor(colors.red)
        monitor.setCursorPos(1, 3)
        monitor.write("Aucune turbine detectee. En attente...")
        return
    end

    for i, t in ipairs(turbines) do
        local ok, p = pcall(function()
            return t.p
        end)
        if not ok then
            goto continue
        end

        local success, active = pcall(function()
            return p.active and p.active() or false
        end)
        if not success then
            goto continue
        end

        local successRotor, rotor = pcall(function()
            return p.rotor()
        end)
        if not successRotor or type(rotor) ~= "table" then
            goto continue
        end

        local rpm = rotor.RPM and rotor.RPM() or 0

        local successBattery, battery = pcall(function()
            return p.battery()
        end)
        if not successBattery or type(battery) ~= "table" then
            goto continue
        end

        local rf = battery.producedLastTick and battery.producedLastTick() or 0

        local x, y = t.x, t.y

        drawBox(x, y, cardWidth, cardHeight, colors.gray)

        monitor.setCursorPos(x + 1, y)
        monitor.setTextColor(colors.lime)
        monitor.write("Turbine " .. i)

        monitor.setCursorPos(x + 1, y + 1)
        monitor.setTextColor(colors.lightGray)
        monitor.write("id: " .. string.match(t.name, "_(%d+)$"))

        monitor.setCursorPos(x + 1, y + 2)
        monitor.setTextColor(active and colors.green or colors.red)
        monitor.write("Status: " .. (active and "ON" or "OFF"))

        monitor.setCursorPos(x + 1, y + 3)
        monitor.setTextColor(colors.yellow)
        monitor.write(string.format("Speed: %d RPM", rpm))

        monitor.setCursorPos(x + 1, y + 4)
        monitor.setTextColor(colors.white)
        monitor.write(string.format("RF/t: %d", rf))

        monitor.setCursorPos(x + 1, y + 5)
        monitor.setTextColor(t.autopilot and colors.cyan or colors.lightGray)
        monitor.write("Autopilot: " .. (t.autopilot and "ON" or "OFF"))

        ::continue::
    end
end

-- Bascule ON/OFF turbine
local function toggleTurbine(t)
    t.auto = not t.auto
    pcall(function()
        t.p.setActive(t.auto)
        t.p.setCoilEngaged(t.auto)
    end)
end

-- Bascule toutes les turbines
local function toggleAll()
    allState = not allState
    for _, t in ipairs(turbines) do
        t.auto = allState
        pcall(function()
            t.p.setActive(allState)
            t.p.setCoilEngaged(allState)
        end)
    end
end

local function toggleAllAutopilot()
    allAutopilot = not allAutopilot
    for _, t in ipairs(turbines) do
        t.autopilot = allAutopilot
    end
end

-- Bascule l'autopilot pour une turbine
local function toggleAutopilot(t)
    t.autopilot = not t.autopilot
end

-- Ajuste FlowRate pour atteindre 1850 RPM
local function updateFlowRates()
    for _, t in ipairs(turbines) do
        if t.autopilot then
            local ok, p = pcall(function()
                return t.p
            end)
            if not ok or not p.active or not p.active() then
                goto continue
            end

            local success, input = pcall(function()
                return p.fluidTank().input()
            end)
            if not success or not input or input.amount() <= 0 then
                goto continue
            end

            local successRotor, rotor = pcall(function()
                return p.rotor()
            end)
            if not successRotor or type(rotor) ~= "table" then
                goto continue
            end

            local rpm = rotor.RPM and rotor.RPM() or 0
            local delta = rpm - t.lastRPM
            local error = t.targetRPM - rpm
            local adjustment = t.kP * error - t.kD * delta

            local newFlow = t.currentFlow + adjustment
            newFlow = math.max(t.flowMin, math.min(t.flowMax, newFlow))

            if newFlow > t.currentFlow + 1000 then
                newFlow = t.currentFlow + 1000
            end

            pcall(function()
                p.fluidTank().setNominalFlowRate(math.floor(newFlow))
            end)

            t.currentFlow = newFlow
            t.lastRPM = rpm

            pcall(function()
                p.setCoilEngaged(true)
            end)
        end
        ::continue::
    end
end

-- Initialisation
local function initFlowRates()
    while #turbines == 0 do
        print("Aucune turbine detectee. En attente de connexion...")
        sleep(2)
        refreshTurbines()
    end
    for _, t in ipairs(turbines) do
        pcall(function()
            t.p.fluidTank().setNominalFlowRate(40000)
            t.currentFlow = 40000
        end)
    end
end

initFlowRates()
refreshTurbines()
repositionCards()

-- Boucle principale
local timer = os.startTimer(1)
while true do
    local event, p1, p2, p3 = os.pullEvent()
    if event == "timer" and p1 == timer then
        refreshTurbines()
        repositionCards()
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
        drawButton()
        drawCards()
        updateFlowRates()
        timer = os.startTimer(2)
    elseif event == "monitor_touch" then
        local x, y = p2, p3
        if y == 1 then
            if x <= 7 then
                toggleAll()
            elseif x >= w - 8 then
                toggleAllAutopilot()
            end
        else
            for _, t in ipairs(turbines) do
                if x >= t.x and x < t.x + cardWidth and y >= t.y and y < t.y + cardHeight then
                    if y == t.y + 5 then
                        toggleAutopilot(t)
                    else
                        toggleTurbine(t)
                    end
                    break
                end
            end
        end
    end
end
