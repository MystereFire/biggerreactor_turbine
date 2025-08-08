-- CONFIGURATION
local MAX_PER_BARREL  = 512000   -- capacity of a barrel in mB
local UPDATE_INTERVAL = 1        -- seconds
local AVERAGE_SAMPLES = 10       -- number of samples to average

-- Prefer advanced monitors so we can display colours
local monitor = peripheral.find("monitor", function(name, mon)
  return mon and mon.isColor and mon.isColor()
end)
if not monitor then error("Aucun moniteur avance trouve") end

-- adjust text scale
if type(monitor.setTextScale) == "function" then
  monitor.setTextScale(0.5)
end

local w, h = monitor.getSize()
term.redirect(monitor)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()

-- detect all block readers
local readers = {}
for _, name in ipairs(peripheral.getNames()) do
  local methods = peripheral.getMethods(name)
  if methods then
    for _, m in ipairs(methods) do
      if m == "getBlockData" then
        table.insert(readers, name)
        break
      end
    end
  end
end
if #readers == 0 then error("Aucun BlockReader trouve") end

-- helpers
local function formatDuration(sec)
  if not sec or sec == math.huge or sec < 0 then return "N/A" end
  sec = math.floor(sec + 0.5)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  if h > 0 then
    return string.format("%dh %02dm %02ds", h, m, s)
  elseif m > 0 then
    return string.format("%dm %02ds", m, s)
  else
    return string.format("%ds", s)
  end
end

local function average(t)
  if #t == 0 then return nil end
  local sum = 0
  for _, v in ipairs(t) do sum = sum + v end
  return sum / #t
end

-- draw progress bar
local function drawProgressBar(y, percent)
  local margin = 2
  local barW = w - margin * 2
  local filled = math.floor(barW * percent)
  paintutils.drawFilledBox(margin, y, margin + barW - 1, y, colors.gray)
  local col = percent < 0.7 and colors.lime
            or percent < 0.95 and colors.yellow
            or colors.red
  if filled > 0 then
    paintutils.drawFilledBox(margin, y, margin + filled - 1, y, col)
  end
end

-- rate calculation
local lastAmt = nil
local lastTs  = nil
local rates   = {}

-- main loop
while true do
  local totalAmt = 0
  for _, name in ipairs(readers) do
    local data = peripheral.call(name, "getBlockData")
    local tank = data and data.GasTanks and data.GasTanks[1]
    if tank and tank.stored and tank.stored.amount then
      totalAmt = totalAmt + tank.stored.amount
    end
  end

  local totalCap = #readers * MAX_PER_BARREL
  local pct      = totalAmt / totalCap

  local now = (os.epoch and os.epoch("utc") or (os.clock() * 1000))
  local status_txt = "Calcul"

  if lastAmt and lastTs and now > lastTs then
    local dt_s = (now - lastTs) / 1000
    local rate_mb_s = (totalAmt - lastAmt) / dt_s

    table.insert(rates, rate_mb_s)
    if #rates > AVERAGE_SAMPLES then
      table.remove(rates, 1)
    end

    local avg_rate = average(rates)

    if avg_rate and math.abs(avg_rate) > 0.001 then
      local time_left_s
      if avg_rate > 0 then
        time_left_s = (totalCap - totalAmt) / avg_rate
      else
        time_left_s = totalAmt / (-avg_rate)
      end
      status_txt = formatDuration(time_left_s)
    else
      status_txt = "Debit nul"
    end
  end

  lastAmt = totalAmt
  lastTs  = now

  paintutils.drawFilledBox(1, 1, w, h, colors.black)
  paintutils.drawBox(1, 1, w, h, colors.white)

  local title = "NUCLEAR WASTE STORAGE"
  local x = math.floor((w - #title) / 2) + 1
  term.setCursorPos(x, 2)
  term.setTextColor(colors.white)
  term.write(title)

  term.setCursorPos(3, 5)
  term.write(string.format("Barrels : %d   Capacite : %d mB", #readers, totalCap))
  term.setCursorPos(3, 6)
  term.write(string.format("Stocke   : %d mB (%.2f%%)", totalAmt, pct * 100))
  term.setCursorPos(3, 7)
  term.write(string.format("Temps restant : %s", status_txt))

  drawProgressBar(h - 3, pct)

  redstone.setOutput("back", pct >= 0.95)

  sleep(UPDATE_INTERVAL)
end

