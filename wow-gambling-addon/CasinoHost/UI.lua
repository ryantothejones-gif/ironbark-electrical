-- CasinoHost - UI
-- A movable window (tabs: Blackjack / Points / Redeem / Bets) plus a minimap button.

local ADDON, ns = ...

local UI = {}
ns.UI = UI
UI.tab = "bj"

local TABS = {
  { key = "bj",     label = "Blackjack" },
  { key = "points", label = "Points" },
  { key = "redeem", label = "Redeem" },
  { key = "bets",   label = "Bets" },
  { key = "pl",     label = "P&L" },
}

-- ---------------------------------------------------------------------------
-- Content builders (return a single string blob)
-- ---------------------------------------------------------------------------
local function header()
  local db = ns.db
  local ch = db.channel == "CHANNEL" and ("channel:" .. (db.channelName or "?")) or db.channel
  return string.format(
    "|cff33ff99Channel:|r %s   |cff33ff99Rate:|r %d/g   |cff33ff99Dry-run:|r %s\n\n",
    ch, db.pointsPerGold, db.dryRun and "|cff00ff00ON|r" or "OFF")
end

local function bjContent()
  local BJ = ns.BJ
  local out = header()
  out = out .. (BJ.active and "|cff00ff00Round is OPEN|r" or "|cffff8800Round closed|r")
  out = out .. "  (target " .. (ns.db.target or 100) .. ")\n\n"
  if BJ.tiebreak then
    out = out .. string.format("|cffffcc00ROLL-OFF|r (tied at %s) - Result forces it if someone bails\n", tostring(BJ.tiebreak.total or "?"))
    for _, key in ipairs(BJ.tiebreak.order) do
      local p = BJ.tiebreak.players[key]
      out = out .. string.format("  %s - %s\n", p.display, p.roll and tostring(p.roll) or "|cffff8800waiting...|r")
    end
    out = out .. "\n"
  end
  if #BJ.order == 0 and not BJ.tiebreak then
    return out .. "No rolls yet. Start with /casino bj start, then players /roll."
  end
  for _, key in ipairs(BJ.order) do
    local p = BJ.players[key]
    local status = p.status
    local colour = "|cffffffff"
    if status == "bust" then colour = "|cffff4040"
    elseif status == "stand" then colour = "|cff40ff40" end
    out = out .. string.format("%s%s|r - %d  (%d rolls, %s)\n", colour, p.display, p.total, p.rolls, status)
  end
  return out
end

local function pointsContent()
  local out = header()
  local list = {}
  for k, v in pairs(ns.db.points) do table.insert(list, { k, v }) end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  if #list == 0 then return out .. "No points awarded yet." end
  out = out .. "|cff33ff99Leaderboard|r\n"
  for i = 1, #list do
    out = out .. string.format("%2d. %s - %d\n", i, ns:Short(list[i][1]), list[i][2])
  end
  return out
end

local function redeemContent()
  local out = header()
  local r = ns.db.redemptions
  if #r == 0 then return out .. "No pending redemptions." end
  out = out .. "|cff33ff99Pending redemptions|r (/casino fulfill <n>)\n"
  for i, e in ipairs(r) do
    out = out .. string.format("%2d. %s - %d pts  (%s)\n", i, e.display or e.player, e.amount, e.time or "")
  end
  return out
end

local function betsContent()
  local out = header()
  local b = ns.db.betLog
  if #b == 0 then return out .. "No bets logged yet." end
  out = out .. "|cff33ff99Recent bets|r\n"
  for i = #b, math.max(1, #b - 30), -1 do
    local e = b[i]
    out = out .. string.format("%s - %s  (%s)\n", e.display or e.player, ns:GoldStr(e.copper), e.time or "")
  end
  return out
end

local function plContent()
  local out = header()
  local s = ns.db.session
  out = out .. string.format("|cff33ff99Session|r (since %s)\nIn: %s   Out: %s   Net: %s\n\n",
    s.started ~= "" and s.started or "?",
    ns:GoldStr(s.bets), ns:GoldStr(s.payouts), ns:SignedGold(s.bets - s.payouts))

  local bets, payouts = ns.Ledger:Summary()
  out = out .. string.format("|cff33ff99All-time|r\nIn: %s   Out: %s   Net: %s\n\n",
    ns:GoldStr(bets), ns:GoldStr(payouts), ns:SignedGold(bets - payouts))

  local list = {}
  for _, e in pairs(ns.db.ledger) do table.insert(list, e) end
  if #list == 0 then return out .. "No trades logged yet." end
  table.sort(list, function(a, b) return (a.bets - a.payouts) > (b.bets - b.payouts) end)
  out = out .. "|cff33ff99Per player|r (house net vs them)\n"
  for _, e in ipairs(list) do
    out = out .. string.format("%s - bet %s, paid %s, net %s  (%d bets)\n",
      e.display, ns:GoldStr(e.bets), ns:GoldStr(e.payouts), ns:SignedGold(e.bets - e.payouts), e.count or 0)
  end
  return out
end

local builders = {
  bj = bjContent,
  points = pointsContent,
  redeem = redeemContent,
  bets = betsContent,
  pl = plContent,
}

-- ---------------------------------------------------------------------------
-- Frame construction
-- ---------------------------------------------------------------------------
local function build()
  if UI.frame then return end

  local f = CreateFrame("Frame", "CasinoHostFrame", UIParent, "BackdropTemplate")
  f:SetSize(530, 500)
  f:SetPoint("CENTER")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  UI.frame = f

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("CasinoHost")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Tab buttons
  UI.tabButtons = {}
  local prev
  for _, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(96, 22)
    b:SetText(t.label)
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
    else
      b:SetPoint("TOPLEFT", 16, -44)
    end
    b:SetScript("OnClick", function() UI.tab = t.key; UI:Refresh() end)
    UI.tabButtons[t.key] = b
    prev = b
  end

  -- Scrolling content
  local scroll = CreateFrame("ScrollFrame", "CasinoHostScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -76)
  scroll:SetPoint("BOTTOMRIGHT", -34, 52)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(470, 1)
  scroll:SetScrollChild(child)

  local content = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  content:SetPoint("TOPLEFT", 0, 0)
  content:SetWidth(470)
  content:SetJustifyH("LEFT")
  content:SetJustifyV("TOP")
  UI.content = content
  UI.child = child

  -- Action buttons along the bottom
  local function actionButton(text, width, anchor, onClick)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(width, 24)
    b:SetText(text)
    b:SetPoint("BOTTOMLEFT", anchor and anchor or f, anchor and "BOTTOMRIGHT" or "BOTTOMLEFT", anchor and 4 or 16, anchor and 0 or 16)
    b:SetScript("OnClick", onClick)
    return b
  end

  local bStart = actionButton("Start", 70, nil, function() ns.BJ:Start() end)
  local bStop = actionButton("Stop", 60, bStart, function() ns.BJ:Stop() end)
  local bResult = actionButton("Result", 70, bStop, function() ns.BJ:Result() end)
  local bClear = actionButton("Clear", 60, bResult, function() ns.BJ.active = false; ns.BJ:Clear() end)
  local bDry = actionButton("Dry-run", 80, bClear, function()
    ns.db.dryRun = not ns.db.dryRun
    ns:Print("Dry-run " .. (ns.db.dryRun and "ON" or "OFF"))
    UI:Refresh()
  end)
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  -- highlight active tab
  for key, b in pairs(self.tabButtons) do
    if key == self.tab then b:LockHighlight() else b:UnlockHighlight() end
  end
  local builder = builders[self.tab] or builders.bj
  local text = builder()
  self.content:SetText(text)
  self.child:SetHeight(self.content:GetStringHeight() + 10)
end

function UI:Toggle()
  build()
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
    self:Refresh()
  end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------
local function buildMinimap()
  if UI.minimap or not Minimap then return end
  local mb = CreateFrame("Button", "CasinoHostMinimapButton", Minimap)
  mb:SetSize(31, 31)
  mb:SetFrameStrata("MEDIUM")
  mb:SetFrameLevel(8)
  mb:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local icon = mb:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  local border = mb:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  local function updatePos()
    local angle = math.rad(ns.db.minimap.angle or 220)
    mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
  end

  mb:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then ns:ShowHelp() else UI:Toggle() end
  end)

  mb:SetMovable(true)
  mb:RegisterForDrag("LeftButton")
  mb:SetScript("OnDragStart", function()
    mb:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx))
      updatePos()
    end)
  end)
  mb:SetScript("OnDragStop", function() mb:SetScript("OnUpdate", nil) end)

  mb:SetScript("OnEnter", function()
    GameTooltip:SetOwner(mb, "ANCHOR_LEFT")
    GameTooltip:AddLine("CasinoHost")
    GameTooltip:AddLine("Left-click: open window", 1, 1, 1)
    GameTooltip:AddLine("Right-click: command help", 1, 1, 1)
    GameTooltip:Show()
  end)
  mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

  updatePos()
  UI.minimap = mb
  if ns.db.minimap.hide then mb:Hide() end
end

ns:OnReady(function()
  buildMinimap()
end)
