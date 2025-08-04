-- Automatically manages Bigger Reactors turbines via ComputerCraft

local monitor = peripheral.find("monitor")
if not monitor then
  error("No monitor attached")
end

-- detect turbines
local turbines = {}
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "BiggerReactors_Turbine" then
    turbines[#turbines + 1] = {
      name = name,
      p = peripheral.wrap(name),
      auto = false,
    }
  end
end

if #turbines == 0 then
  error("No turbines found")
end

monitor.setTextScale(0.5)

local cardWidth, cardHeight = 20, 8
local w, h = monitor.getSize()
local perRow = math.max(1, math.floor(w / (cardWidth + 2)))

for i, t in ipairs(turbines) do
  local col = (i-1) % perRow
  local row = math.floor((i-1) / perRow)
  t.x = col * (cardWidth + 2) + 1
  t.y = row * (cardHeight + 1) + 3 -- leave space for global button
  t.auto = peripheral.call(t.name, "getActive") and peripheral.call(t.name, "getInductorEngaged")
end

local allState = false

local function drawButton()
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.setCursorPos(1,1)
  monitor.clearLine()
  monitor.setCursorPos(1,1)
  monitor.write(allState and "All OFF" or "All ON")
end

local function drawCards()
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  drawButton()
  for i, t in ipairs(turbines) do
    local p = t.p
    local x, y = t.x, t.y
    local active = p.getActive()
    local rpm = p.getRotorSpeed()
    local rf = p.getEnergyProducedLastTick()
    local inAmt = p.getInputAmount()
    local inType = p.getInputType() or "-"
    local outAmt = p.getOutputAmount()
    local outType = p.getOutputType() or "-"
    local induct = p.getInductorEngaged()

    monitor.setTextColor(active and colors.green or colors.red)
    monitor.setCursorPos(x, y)
    monitor.write("Turbine " .. i)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(x, y+1)
    monitor.write("Status: " .. (active and "ON" or "OFF"))
    monitor.setCursorPos(x, y+2)
    monitor.write(string.format("Speed: %d RPM", rpm))
    monitor.setCursorPos(x, y+3)
    monitor.write(string.format("RF/t: %d", rf))
    monitor.setCursorPos(x, y+4)
    monitor.write(string.format("In: %s %d", inType, inAmt))
    monitor.setCursorPos(x, y+5)
    monitor.write(string.format("Out: %s %d", outType, outAmt))
    monitor.setCursorPos(x, y+6)
    monitor.write("Inductor: " .. (induct and "ON" or "OFF"))
  end
end

local function toggleTurbine(t)
  t.auto = not t.auto
  t.p.setActive(t.auto)
  t.p.setInductorEngaged(t.auto)
end

local function toggleAll()
  allState = not allState
  for _, t in ipairs(turbines) do
    t.auto = allState
    t.p.setActive(allState)
    t.p.setInductorEngaged(allState)
  end
end

local timer = os.startTimer(1)
while true do
  local event, p1, p2, p3 = os.pullEvent()
  if event == "timer" and p1 == timer then
    drawCards()
    timer = os.startTimer(1)
  elseif event == "monitor_touch" then
    local x, y = p2, p3
    if y == 1 and x <= 7 then -- global button
      toggleAll()
      drawCards()
    else
      for _, t in ipairs(turbines) do
        if x >= t.x and x < t.x + cardWidth and y >= t.y and y < t.y + cardHeight then
          toggleTurbine(t)
          drawCards()
          break
        end
      end
    end
  end
end

