-- CONFIGURATION
local MAX_PER_BARREL  = 512000   -- capacité d'un barrel en mB
local UPDATE_INTERVAL = 1        -- en secondes

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

-- Fonction de dessin d'une barre de progression
local function drawProgressBar(y, percent)
  local margin = 2
  local barW   = w - margin * 2
  local filled = math.floor(barW * percent)
  -- fond gris
  paintutils.drawFilledBox(margin, y, margin + barW - 1, y, colors.gray)
  -- couleur selon le pourcentage
  local col = percent < 0.7 and colors.lime
            or percent < 0.95 and colors.yellow
            or colors.red
  if filled > 0 then
    paintutils.drawFilledBox(margin, y, margin + filled - 1, y, col)
  end
end

-- Variables pour calcul du débit
local lastAmt = nil
local lastTs  = nil

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

  -- Débit (mB/s) et temps restant (si ça se vide)
  local now = (os.epoch and os.epoch("utc") or (os.clock() * 1000))
  local rate_mb_s, time_left_s, status_txt = nil, nil, "—"

  if lastAmt and lastTs and now > lastTs then
    local dt_s = (now - lastTs) / 1000
    rate_mb_s = (totalAmt - lastAmt) / dt_s  -- positif = remplissage, négatif = vidange
    -- Seulement si on se vide à une vitesse significative
    if rate_mb_s and rate_mb_s < -0.001 then
      time_left_s = totalAmt / (-rate_mb_s)
      status_txt = formatDuration(time_left_s)
    elseif rate_mb_s and rate_mb_s > 0.001 then
      status_txt = "Remplissage"
    else
      status_txt = "Débit nul"
    end
  else
    status_txt = "Calcul…"
  end

  -- Mémorise pour la prochaine itération
  lastAmt = totalAmt
  lastTs  = now

  -- Rendu
  paintutils.drawFilledBox(1, 1, w, h, colors.black)           -- clear

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

  -- >>> Nouvelle ligne : Temps restant avant vidage <<<
  term.setCursorPos(2, 7)
  term.write(string.format("Temps restant (avant vide) : %s", status_txt))

  -- Barre de progression
  drawProgressBar(h - 3, pct)

  -- Alerte redstone si >=95%
  redstone.setOutput("back", pct >= 0.95)

  sleep(UPDATE_INTERVAL)
end
