local monitor = peripheral.find('monitor')
if not monitor then
    error('No monitor found')
end

local modem = peripheral.find('modem')
if not modem then
    error('No modem found')
end

local CHANNEL = 1
modem.open(CHANNEL)

monitor.setTextScale(0.5)
local w, h = monitor.getSize()
local cardHeight = 8
local minCardWidth = 18
local perRow = math.max(1, math.floor(w / (minCardWidth + 2)))
local cardWidth = math.floor((w - (perRow + 1) * 2) / perRow)

local turbines = {}
local allState = false
local allAutopilot = false

local function repositionCards()
    for i, t in ipairs(turbines) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        t.x = col * (cardWidth + 2) + 1
        t.y = row * (cardHeight + 1) + 3
    end
end

local function drawBox(x, y, width, height, color)
    monitor.setTextColor(color)
    monitor.setCursorPos(x, y)
    monitor.write('+' .. string.rep('-', width - 2) .. '+')
    for i = 1, height - 2 do
        monitor.setCursorPos(x, y + i)
        monitor.write('|' .. string.rep(' ', width - 2) .. '|')
    end
    monitor.setCursorPos(x, y + height - 1)
    monitor.write('+' .. string.rep('-', width - 2) .. '+')
end

local function drawButton()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(1, 1)
    monitor.clearLine()
    monitor.write(allState and 'All OFF' or 'All ON')

    local label = allAutopilot and 'Auto OFF' or 'Auto ON'
    monitor.setCursorPos(w - #label + 1, 1)
    monitor.write(label)
end

local function drawCards()
    if #turbines == 0 then
        monitor.setTextColor(colors.red)
        monitor.setCursorPos(1, 3)
        monitor.write('Aucune turbine detectee. En attente...')
        return
    end

    for i, t in ipairs(turbines) do
        local x, y = t.x, t.y
        drawBox(x, y, cardWidth, cardHeight, colors.gray)

        monitor.setCursorPos(x + 1, y)
        monitor.setTextColor(colors.lime)
        monitor.write('Turbine ' .. i)

        monitor.setCursorPos(x + 1, y + 1)
        monitor.setTextColor(colors.lightGray)
        monitor.write('id: ' .. t.id)

        monitor.setCursorPos(x + 1, y + 2)
        monitor.setTextColor(t.active and colors.green or colors.red)
        monitor.write('Status: ' .. (t.active and 'ON' or 'OFF'))

        monitor.setCursorPos(x + 1, y + 3)
        monitor.setTextColor(colors.yellow)
        monitor.write(string.format('Speed: %d RPM', t.rpm))

        monitor.setCursorPos(x + 1, y + 4)
        monitor.setTextColor(colors.white)
        monitor.write(string.format('RF/t: %d', t.rf))

        monitor.setCursorPos(x + 1, y + 5)
        monitor.setTextColor(t.autopilot and colors.cyan or colors.lightGray)
        monitor.write('Autopilot: ' .. (t.autopilot and 'ON' or 'OFF'))
    end
end

local function draw()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    drawButton()
    drawCards()
end

while true do
    local event, p1, p2, p3, p4, p5 = os.pullEvent()
    if event == 'modem_message' and p2 == CHANNEL then
        local msg = p4
        if msg.type == 'status' then
            allState = msg.data.allState
            allAutopilot = msg.data.allAutopilot
            turbines = msg.data.turbines or {}
            repositionCards()
            draw()
        end
    elseif event == 'monitor_touch' then
        local x, y = p2, p3
        if y == 1 then
            if x <= 7 then
                modem.transmit(CHANNEL, CHANNEL, { type = 'toggle_all' })
            elseif x >= w - 8 then
                modem.transmit(CHANNEL, CHANNEL, { type = 'toggle_all_autopilot' })
            end
        else
            for i, t in ipairs(turbines) do
                if x >= t.x and x < t.x + cardWidth and y >= t.y and y < t.y + cardHeight then
                    if y == t.y + 5 then
                        modem.transmit(CHANNEL, CHANNEL, { type = 'toggle_autopilot', index = i })
                    else
                        modem.transmit(CHANNEL, CHANNEL, { type = 'toggle_turbine', index = i })
                    end
                    break
                end
            end
        end
    end
end
