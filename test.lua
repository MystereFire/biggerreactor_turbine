-- CONFIGURATION
local MAX_PER_BARREL  = 512000   -- capacité d'un barrel en mB
local UPDATE_INTERVAL = 5        -- en secondes
local AVERAGE_SAMPLES = 10       -- nombre de mesures à moyenner

-- Récupère le monitor et vérifie
local monitor = peripheral.find("monitor")
if not monitor then error("❌ Aucun monitor trouvé") end

-- Ajuste l'échelle de texte si possible
if type(monitor.setTextScale) == "function" then
  monitor.setTextScale(0.5)
end

-- Taille de l'écran
local w, h = monitor.getSize()
term.redirect(monitor)

-- Paramètres du graphe d'historique
local GRAPH_HEIGHT = math.max(1, math.min(6, h - 10))
local pct_history  = {}

-- Détecte tous les blockReaders (barrel)
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
if #readers == 0 then error("❌ Aucun BlockReader trouvé") end

-- Helpers
local function formatDuration(sec)
  if not sec or sec == math.huge or sec < 0 then return "—" end
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

-- Fonction de dessin d'une barre de progression
local function drawProgressBar(y, percent)
  local margin = 2
  local barW   = w - margin * 2
  local filled = math.floor(barW * percent)
  paintutils.drawFilledBox(margin, y, margin + barW - 1, y, colors.gray)
  local col = percent < 0.7 and colors.lime
            or percent < 0.95 and colors.yellow
            or colors.red
  if filled > 0 then
    paintutils.drawFilledBox(margin, y, margin + filled - 1, y, col)
  end
end

-- Dessine l'historique du pourcentage de remplissage
local function drawHistory(bottomY, height)
  local margin = 2
  local width  = w - margin * 2
  for i = 1, #pct_history do
    local v = pct_history[i]
    local barH = math.floor(v * height + 0.5)
    if barH > 0 then
      paintutils.drawLine(margin + i - 1, bottomY, margin + i - 1, bottomY - barH + 1, colors.blue)
    end
  end
end

-- Variables pour calcul du débit
local lastAmt = nil
local lastTs  = nil
local rates   = {} -- historique des débits

-- Boucle principale
while true do
  -- Calcule le total stocké
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

  -- Met à jour l'historique de pourcentage
  table.insert(pct_history, pct)
  local histW = w - 4
  if #pct_history > histW then
    table.remove(pct_history, 1)
  end

  -- Débit (mB/s) et temps restant (moyenne)
  local now = (os.epoch and os.epoch("utc") or (os.clock() * 1000))
  local status_txt = "—"

  if lastAmt and lastTs and now > lastTs then
    local dt_s = (now - lastTs) / 1000
    local rate_mb_s = (totalAmt - lastAmt) / dt_s -- positif = remplissage, négatif = vidange

    -- Ajoute à l'historique
    table.insert(rates, rate_mb_s)
    if #rates > AVERAGE_SAMPLES then
      table.remove(rates, 1)
    end

    local avg_rate = average(rates)

    if avg_rate and avg_rate < -0.001 then
      local time_left_s = totalAmt / (-avg_rate)
      status_txt = formatDuration(time_left_s)
    elseif avg_rate and avg_rate > 0.001 then
      status_txt = "Remplissage"
    else
      status_txt = "Débit nul"
    end
  else
    status_txt = "Calcul…"
  end

  lastAmt = totalAmt
  lastTs  = now

  -- Rendu
  paintutils.drawFilledBox(1, 1, w, h, colors.black)

  -- En-tête centré
  local title = "NUCLEAR WASTE STORAGE"
  local x = math.floor((w - #title) / 2) + 1
  term.setCursorPos(x, 2)
  term.setTextColor(colors.white)
  term.write(title)

  -- Statistiques
  term.setCursorPos(2, 5)
  term.write(string.format("Barrels : %d   Capacite : %d mB", #readers, totalCap))
  term.setCursorPos(2, 6)
  term.write(string.format("Stocke   : %d mB (%.2f%%)", totalAmt, pct * 100))
  term.setCursorPos(2, 7)
  term.write(string.format("Temps restant (moyenne) : %s", status_txt))

  -- Historique du remplissage
  if GRAPH_HEIGHT > 0 then
    drawHistory(h - 5, GRAPH_HEIGHT)
  end

  -- Barre de progression
  drawProgressBar(h - 3, pct)

  -- Alerte redstone si >=95%
  redstone.setOutput("back", pct >= 0.95)

  sleep(UPDATE_INTERVAL)
end
