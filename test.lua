--[[
Responsive nuclear waste monitor.
Displays fill level and estimated time remaining on a monitor or terminal.
The UI adapts to the monitor size, clears the screen every tick and draws
using a double buffer to limit flicker.
]]

-- CONFIGURATION -----------------------------------------------------------
local MAX_PER_BARREL  = 512000   -- capacity of a barrel in mB
local UPDATE_INTERVAL = 1        -- seconds between refreshes
local AVERAGE_SAMPLES = 10       -- number of samples to average for rate

-- PERIPHERAL DETECTION ----------------------------------------------------
local function findDisplay()
  return peripheral.find("monitor") or term.current()
end

local native = term.current()
local target = findDisplay()
local oldTerm = term.redirect(target)

-- LAYOUT VARIABLES --------------------------------------------------------
local margin, w, h, contentW, contentH, buffer

-- TEXT SCALE --------------------------------------------------------------
local function chooseTextScale()
  if type(target.setTextScale) ~= "function" then
    w, h = target.getSize()
    return
  end
  local scales = {0.5, 0.75, 1.0}
  local chosen = scales[1]
  for _, s in ipairs(scales) do
    target.setTextScale(s)
    local tw, th = target.getSize()
    if (th - 2) >= 4 then -- minimal content height
      chosen = s
    else
      break
    end
  end
  target.setTextScale(chosen)
  w, h = target.getSize()
end

local function refreshLayout()
  margin = 1
  chooseTextScale()
  w, h = target.getSize()
  contentW = w - 2 * margin
  contentH = h - 2 * margin
  buffer = window.create(target, 1, 1, w, h, true)
end

-- HELPER FUNCTIONS --------------------------------------------------------
local function drawBox(x1, y1, x2, y2, bg)
  local old = term.getBackgroundColor()
  term.setBackgroundColor(bg)
  paintutils.drawFilledBox(x1, y1, x2, y2, bg)
  term.setBackgroundColor(old)
end

local function drawProgress(x, y, width, ratio, fg, bg)
  ratio = math.max(0, math.min(1, ratio))
  width = math.max(0, math.min(width, w - x + 1))
  drawBox(x, y, x + width - 1, y, bg)
  local filled = math.floor(width * ratio)
  if filled > 0 then
    drawBox(x, y, x + filled - 1, y, fg)
  end
end

local function printAt(x, y, text, fg, bg)
  local maxW = w - x + 1
  if #text > maxW then
    if maxW >= 3 then
      text = text:sub(1, maxW - 3) .. "..."
    else
      text = text:sub(1, maxW)
    end
  end
  term.setCursorPos(x, y)
  term.setTextColor(fg)
  term.setBackgroundColor(bg)
  term.write(text)
end

local function wrapText(text, maxWidth)
  local lines = {}
  for line in text:gmatch("[^\n]+") do
    local current = ""
    for word in line:gmatch("%S+") do
      if #current + (#current > 0 and 1 or 0) + #word > maxWidth then
        table.insert(lines, current)
        current = word
      else
        if #current > 0 then
          current = current .. " " .. word
        else
          current = word
        end
      end
    end
    table.insert(lines, current)
  end
  return lines
end

-- GENERAL HELPERS ---------------------------------------------------------
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

-- BLOCK READER DETECTION --------------------------------------------------
local readers = {}
local function detectReaders()
  readers = {}
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
end

detectReaders()
if #readers == 0 then error("Aucun BlockReader trouve") end

-- DRAWING -----------------------------------------------------------------
local function drawUI(totalAmt, totalCap, pct, statusTxt)
  buffer.setVisible(false)
  local old = term.redirect(buffer)

  term.setBackgroundColor(colors.black)
  term.clear()
  term.setCursorPos(1, 1)

  local title = "NUCLEAR WASTE STORAGE"
  printAt(math.floor((w - #title) / 2) + 1, margin, title, colors.white, colors.black)

  local y = margin + 1
  local lines = {
    string.format("Barrels : %d   Capacite : %d mB", #readers, totalCap),
    string.format("Stocke   : %d mB (%.2f%%)", totalAmt, pct * 100),
    string.format("Temps restant : %s", statusTxt)
  }
  for _, text in ipairs(lines) do
    for _, line in ipairs(wrapText(text, contentW)) do
      if y >= h - margin then break end
      printAt(margin, y, line, colors.white, colors.black)
      y = y + 1
    end
  end

  local barY = h - margin
  local fg = pct < 0.7 and colors.lime or (pct < 0.95 and colors.yellow or colors.red)
  drawProgress(margin, barY, contentW, pct, fg, colors.gray)

  term.redirect(old)
  buffer.setVisible(true)
end

-- MAIN LOOP ---------------------------------------------------------------
local lastAmt, lastTs
local rates = {}

local function updateDisplay()
  local newTarget = findDisplay()
  if newTarget ~= target then
    term.redirect(newTarget)
    target = newTarget
    refreshLayout()
  else
    local tw, th = target.getSize()
    if tw ~= w or th ~= h then
      refreshLayout()
    end
  end
end

local function main()
  refreshLayout()
  while true do
    updateDisplay()

    local totalAmt = 0
    for _, name in ipairs(readers) do
      local data = peripheral.call(name, "getBlockData")
      local tank = data and data.GasTanks and data.GasTanks[1]
      if tank and tank.stored and tank.stored.amount then
        totalAmt = totalAmt + tank.stored.amount
      end
    end

    local totalCap = #readers * MAX_PER_BARREL
    local pct = totalCap > 0 and (totalAmt / totalCap) or 0

    local now = (os.epoch and os.epoch("utc") or (os.clock() * 1000))
    local statusTxt = "Calcul"

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
        statusTxt = formatDuration(time_left_s)
      else
        statusTxt = "Debit nul"
      end
    end

    lastAmt = totalAmt
    lastTs = now

    drawUI(totalAmt, totalCap, pct, statusTxt)

    redstone.setOutput("back", pct >= 0.95)
    sleep(UPDATE_INTERVAL)
  end
end

local ok, err = pcall(main)
term.redirect(oldTerm)
if not ok then error(err) end

