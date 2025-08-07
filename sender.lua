local modem = peripheral.find('modem')
if not modem then
    error('No modem found')
end

local CHANNEL = 1
modem.open(CHANNEL)

local turbines = {}

local function refreshTurbines()
    local newList = {}
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == 'BiggerReactors_Turbine' then
            local ok, p = pcall(function()
                return peripheral.wrap(name)
            end)
            if ok and p then
                local exists = false
                for _, existing in ipairs(turbines) do
                    if existing.name == name then
                        table.insert(newList, existing)
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(newList, {
                        name = name,
                        p = p,
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

local allState = false
local allAutopilot = false

local function toggleTurbine(t)
    t.auto = not t.auto
    pcall(function()
        t.p.setActive(t.auto)
        t.p.setCoilEngaged(t.auto)
        if t.auto and t.p.setVentMode then
            t.p.setVentMode('vent_all')
        end
    end)
end

local function toggleAll()
    allState = not allState
    for _, t in ipairs(turbines) do
        t.auto = allState
        pcall(function()
            t.p.setActive(allState)
            t.p.setCoilEngaged(allState)
            if allState and t.p.setVentMode then
                t.p.setVentMode('vent_all')
            end
        end)
    end
end

local function toggleAllAutopilot()
    allAutopilot = not allAutopilot
    for _, t in ipairs(turbines) do
        t.autopilot = allAutopilot
    end
end

local function toggleAutopilot(t)
    t.autopilot = not t.autopilot
end

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
            if not successRotor or type(rotor) ~= 'table' then
                goto continue
            end

            local rpm = rotor.RPM and rotor.RPM() or 0
            local delta = rpm - t.lastRPM
            local err = t.targetRPM - rpm
            local adjust = t.kP * err - t.kD * delta

            local newFlow = t.currentFlow + adjust
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

local function initFlowRates()
    while #turbines == 0 do
        print('Aucune turbine detectee. En attente de connexion...')
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

local function sendStatus()
    local data = {
        allState = allState,
        allAutopilot = allAutopilot,
        turbines = {}
    }
    for i, t in ipairs(turbines) do
        local ok, p = pcall(function()
            return t.p
        end)
        if not ok then goto continue end

        local successActive, active = pcall(function()
            return p.active and p.active() or false
        end)
        if not successActive then goto continue end

        local successRotor, rotor = pcall(function()
            return p.rotor()
        end)
        if not successRotor or type(rotor) ~= 'table' then goto continue end
        local rpm = rotor.RPM and rotor.RPM() or 0

        local successBattery, battery = pcall(function()
            return p.battery()
        end)
        if not successBattery or type(battery) ~= 'table' then goto continue end
        local rf = battery.producedLastTick and battery.producedLastTick() or 0

        table.insert(data.turbines, {
            id = tonumber(string.match(t.name, '_(%d+)$')) or i,
            active = active,
            rpm = rpm,
            rf = rf,
            autopilot = t.autopilot
        })
        ::continue::
    end
    modem.transmit(CHANNEL, CHANNEL, { type = 'status', data = data })
end

refreshTurbines()
initFlowRates()

local timer = os.startTimer(1)
while true do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == 'timer' and p1 == timer then
        refreshTurbines()
        updateFlowRates()
        sendStatus()
        timer = os.startTimer(2)
    elseif event == 'modem_message' and p2 == CHANNEL then
        local msg = p4
        if msg.type == 'toggle_all' then
            toggleAll()
        elseif msg.type == 'toggle_all_autopilot' then
            toggleAllAutopilot()
        elseif msg.type == 'toggle_turbine' and msg.index then
            local t = turbines[msg.index]
            if t then toggleTurbine(t) end
        elseif msg.type == 'toggle_autopilot' and msg.index then
            local t = turbines[msg.index]
            if t then toggleAutopilot(t) end
        end
    end
end
