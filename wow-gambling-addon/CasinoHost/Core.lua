-- CasinoHost - Core
-- Shared namespace, saved variables, event dispatch, slash commands, utilities.

local ADDON, ns = ...

ns.name = ADDON
local function meta(field)
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    return C_AddOns.GetAddOnMetadata(ADDON, field)
  end
  return GetAddOnMetadata and GetAddOnMetadata(ADDON, field)
end
ns.version = meta("Version") or "0.1.0"

local floor = math.floor

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
function ns:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CasinoHost|r: " .. tostring(msg))
end

local myRealm = ""

-- Normalise a name to "Name-Realm" so trade / whisper / roll all key the same.
function ns:Norm(name)
  if not name or name == "" then return name end
  name = name:gsub("%s", "")
  if not name:find("%-") then
    name = name .. "-" .. myRealm
  end
  return name
end

-- Short display name (drops own realm).
function ns:Short(name)
  if not name then return "" end
  if Ambiguate then return Ambiguate(name, "short") end
  return (name:gsub("%-.*$", ""))
end

-- Copper -> readable gold string.
function ns:GoldStr(copper)
  copper = copper or 0
  local g = floor(copper / 10000)
  local s = floor((copper % 10000) / 100)
  local c = copper % 100
  if g > 0 and s > 0 then return string.format("%dg %ds", g, s) end
  if g > 0 then return string.format("%dg", g) end
  if s > 0 then return string.format("%ds", s) end
  return string.format("%dc", c)
end

-- Signed, coloured gold string for profit/loss display.
function ns:SignedGold(copper)
  if copper >= 0 then return "|cff40ff40+" .. self:GoldStr(copper) .. "|r" end
  return "|cffff4040-" .. self:GoldStr(-copper) .. "|r"
end

-- The global SendChatMessage was deprecated in 11.2.0; prefer C_ChatInfo.
function ns:SendChat(msg, chatType, language, target)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  send(msg, chatType, language, target)
end

-- ---------------------------------------------------------------------------
-- Announce to the configured channel (or print locally in dry-run mode)
-- ---------------------------------------------------------------------------
-- SAY/YELL are protected in the open world on retail: an addon can only send
-- them from a hardware event. A real mouse click on the button qualifies, and so
-- does a CLICK keybind (SetOverrideBindingClick). A "/click Name" macro does NOT:
-- it runs the handler on a non-hardware path, so the say/yell is silently eaten.
-- That's why there is a /casino bindkey command instead of a macro.
local sayQueue = {}
local sayButton

local function updateSayButton()
  if not sayButton then return end
  local nextMsg = sayQueue[1]
  if not nextMsg then
    sayButton:Hide()
    return
  end
  local extra = #sayQueue > 1 and string.format("  (+%d more)", #sayQueue - 1) or ""
  sayButton:SetText("Announce: " .. nextMsg.msg .. extra)
  sayButton:SetWidth(math.min(600, sayButton:GetFontString():GetStringWidth() + 40))
  sayButton:Show()
end

local function applyAnnounceBinding()
  if not sayButton then return end
  if InCombatLockdown and InCombatLockdown() then
    ns.bindPending = true -- bindings are protected in combat; re-applied on PLAYER_REGEN_ENABLED
    return
  end
  ClearOverrideBindings(sayButton)
  local key = ns.db and ns.db.announceKey
  if key and key ~= "" then
    SetOverrideBindingClick(sayButton, false, key, "CasinoHostAnnounceButton", "LeftButton")
  end
end

local function ensureSayButton()
  if sayButton then return end
  local b = CreateFrame("Button", "CasinoHostAnnounceButton", UIParent, "UIPanelButtonTemplate")
  b:SetSize(300, 30)
  b:SetPoint("TOP", UIParent, "TOP", 0, -160)
  b:SetFrameStrata("DIALOG")
  b:SetClampedToScreen(true)
  b:SetMovable(true)
  b:RegisterForDrag("RightButton")
  b:SetScript("OnDragStart", b.StartMoving)
  b:SetScript("OnDragStop", b.StopMovingOrSizing)
  -- Key bindings deliver a click on the phase picked by the ActionButtonUseKeyDown
  -- CVar (retail default: key DOWN), while the default click registration is
  -- LeftButtonUp only - which would make the bindkey silently dead. Register both
  -- phases and act on exactly the configured one.
  b:RegisterForClicks("AnyDown", "AnyUp")
  b:SetScript("OnClick", function(_, button, down)
    if button ~= "LeftButton" then return end -- right button is the drag handle
    local useDown = true
    if C_CVar and C_CVar.GetCVarBool then
      useDown = C_CVar.GetCVarBool("ActionButtonUseKeyDown")
    elseif GetCVarBool then
      useDown = GetCVarBool("ActionButtonUseKeyDown")
    end
    if (down == true) ~= (useDown == true) then return end
    -- This click IS the hardware event (mouse, or the bindkey CLICK binding).
    local item = table.remove(sayQueue, 1)
    if item then ns:SendChat(item.msg, item.ch) end
    updateSayButton()
  end)
  b:Hide()
  sayButton = b
  applyAnnounceBinding()
end

local function queueSay(msg, ch)
  ensureSayButton()
  table.insert(sayQueue, { msg = msg, ch = ch })
  updateSayButton()
end

-- class "hype" = the big moments (bets, payouts, winners) -> db.channel.
-- anything else = table play-by-play (rolls, round opens, roll-offs) -> db.tableChannel.
function ns:Announce(msg, class)
  local db = self.db
  if not db or db.dryRun then
    self:Print("|cffffcc00[dry-run]|r " .. msg)
    return
  end
  local ch
  if class == "hype" then
    ch = db.channel or "PARTY"
  else
    ch = db.tableChannel or "PARTY"
  end
  if ch == "OFF" then
    self:Print("|cff888888[quiet]|r " .. msg)
    return
  end
  if ch == "CHANNEL" and db.channelName then
    local id = GetChannelName(db.channelName)
    if id and id > 0 then
      self:SendChat(msg, "CHANNEL", nil, id)
      return
    end
    self:Print("Channel '" .. db.channelName .. "' not joined - showing locally: " .. msg)
    return
  end
  -- SAY/YELL always need a click; in Midnight (12.0+) instances block addon
  -- chat sends entirely, so never try to auto-send these.
  if ch == "SAY" or ch == "YELL" then
    queueSay(msg, ch)
    return
  end
  self:SendChat(msg, ch)
end

-- ---------------------------------------------------------------------------
-- Saved-variable defaults
-- ---------------------------------------------------------------------------
local defaults = {
  channel = "PARTY",       -- big announcements: SAY / YELL / PARTY / RAID / GUILD / INSTANCE_CHAT / CHANNEL
  channelName = nil,        -- custom channel name when channel == "CHANNEL"
  tableChannel = "PARTY",   -- play-by-play: PARTY / SAY / YELL / RAID / GUILD / OFF
  dryRun = false,           -- print announcements locally instead of sending
  pointsPerGold = 1,        -- points awarded per 1 gold bet
  target = 100,             -- blackjack target number
  bjAuto = true,            -- auto-call the blackjack result once every player is done
  bjAutoDelay = 3,          -- grace seconds before the auto-result fires (any roll cancels it)
  points = {},              -- [Name-Realm] = points
  redemptions = {},         -- queue of { player, display, amount, time }
  betLog = {},              -- history of { player, display, copper, time }
  uoHistory = {},           -- rolling list of recent Under/Over 7 totals
  uoBets = {},              -- [Name-Realm] = { display, amount, choice } pending point bets
  uoSevenPays = 4,          -- a straight '7' point bet pays this:1 (over/under = even money)
  ledger = {},              -- [Name-Realm] = { display, bets, payouts, count } (copper)
  session = { bets = 0, payouts = 0, started = "" },
  minimap = { hide = false, angle = 220 },
}

local function applyDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      applyDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

-- ---------------------------------------------------------------------------
-- Event dispatch: modules register with ns:On(event, fn)
-- ---------------------------------------------------------------------------
ns.handlers = {}
ns.onReady = {}

local frame = CreateFrame("Frame")
ns.frame = frame

function ns:On(event, fn)
  if not self.handlers[event] then
    self.handlers[event] = {}
    self.frame:RegisterEvent(event)
  end
  table.insert(self.handlers[event], fn)
end

-- Register a callback fired once the player is logged in and the DB is ready.
function ns:OnReady(fn)
  table.insert(self.onReady, fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = ns.handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    fn(ns, ...)
  end
end)

ns:On("ADDON_LOADED", function(self, name)
  if name ~= ADDON then return end
  CasinoHostDB = CasinoHostDB or {}
  applyDefaults(CasinoHostDB, defaults)
  self.db = CasinoHostDB
end)

ns:On("PLAYER_LOGIN", function(self)
  if GetNormalizedRealmName then
    myRealm = GetNormalizedRealmName() or ""
  elseif GetRealmName then
    myRealm = (GetRealmName() or ""):gsub("%s", "")
  end
  for _, fn in ipairs(self.onReady) do
    local ok, err = pcall(fn, self)
    if not ok then self:Print("init error: " .. tostring(err)) end
  end
  self:Print("loaded v" .. self.version .. ". Type |cffffff00/casino|r for options.")
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
ns.commands = {}
ns.cmdOrder = {}

function ns:AddCommand(name, help, fn)
  self.commands[name] = { help = help, fn = fn }
  table.insert(self.cmdOrder, name)
end

function ns:ShowHelp()
  self:Print("commands:")
  for _, name in ipairs(self.cmdOrder) do
    self:Print("  |cffffff00/casino " .. name .. "|r - " .. (self.commands[name].help or ""))
  end
end

SLASH_CASINOHOST1 = "/casino"
SLASH_CASINOHOST2 = "/ch"
SlashCmdList["CASINOHOST"] = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower() or ""
  if cmd == "" then
    if ns.UI then ns.UI:Toggle() else ns:ShowHelp() end
    return
  end
  if cmd == "help" then ns:ShowHelp() return end
  local c = ns.commands[cmd]
  if c then
    c.fn(ns, rest or "")
  else
    ns:Print("unknown command '" .. cmd .. "'.")
    ns:ShowHelp()
  end
end

-- ---------------------------------------------------------------------------
-- Configuration / management commands
-- ---------------------------------------------------------------------------
ns:AddCommand("channel", "<party|say|raid|guild|yell|channel NAME> - where BIG announcements go (bets, payouts, winners)", function(self, rest)
  local a, b = rest:match("^(%S+)%s*(.-)$")
  a = a and a:upper() or ""
  local valid = { SAY = true, YELL = true, EMOTE = true, PARTY = true, RAID = true, GUILD = true, INSTANCE_CHAT = true }
  if a == "CHANNEL" then
    if b == "" then self:Print("Usage: /casino channel channel <ChannelName>") return end
    self.db.channel = "CHANNEL"
    self.db.channelName = b
    self:Print("Announcing to custom channel: " .. b)
  elseif valid[a] then
    self.db.channel = a
    self.db.channelName = nil
    self:Print("Announcing to " .. a)
  else
    self:Print("Current: " .. (self.db.channel == "CHANNEL" and ("channel " .. (self.db.channelName or "?")) or self.db.channel))
    self:Print("Valid: party, say, yell (red), emote (orange), raid, guild, channel <name>")
  end
end)

ns:AddCommand("gamechat", "<party|say|raid|guild|yell|off> - where play-by-play goes (rolls, round opens, roll-offs)", function(self, rest)
  local a = rest:match("^(%S*)")
  a = a and a:upper() or ""
  local valid = { SAY = true, YELL = true, PARTY = true, RAID = true, GUILD = true, INSTANCE_CHAT = true, OFF = true }
  if valid[a] then
    self.db.tableChannel = a
    self:Print("Play-by-play going to " .. (a == "OFF" and "nowhere (host-only prints)" or a))
  else
    self:Print("Current play-by-play channel: " .. (self.db.tableChannel or "PARTY"))
    self:Print("Valid: party, say, raid, guild, yell, off")
  end
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("rate", "<n> - points awarded per 1 gold bet", function(self, rest)
  local n = tonumber(rest)
  if not n or n < 0 then
    self:Print("Points rate: " .. self.db.pointsPerGold .. " per gold. Set with /casino rate <n>")
    return
  end
  self.db.pointsPerGold = n
  self:Print("Points rate set to " .. n .. " per gold.")
end)

ns:AddCommand("target", "<n> - blackjack target number (default 100; low targets make ties easy)", function(self, rest)
  local n = tonumber(rest)
  if not n or n < 2 or n ~= math.floor(n) then
    self:Print("Blackjack target: " .. (self.db.target or 100) .. ". Set with /casino target <n> (min 2).")
    return
  end
  self.db.target = n
  self:Print("Blackjack target set to " .. n .. ". Players /roll (1-" .. n .. ").")
  if ns.BJ and ns.BJ.active then
    self:Print("Heads up: you changed the target mid-round - /casino bj clear then start for a clean table.")
  end
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("dryrun", "on|off - test announcements locally without spamming chat", function(self, rest)
  local v = rest:lower()
  if v == "on" then
    self.db.dryRun = true
    self:Print("Dry-run |cff00ff00ON|r - announcements print locally only.")
  elseif v == "off" then
    self.db.dryRun = false
    self:Print("Dry-run |cffff0000OFF|r - announcements go to chat.")
  else
    self:Print("Dry-run is " .. (self.db.dryRun and "ON" or "OFF") .. ". Use: /casino dryrun on|off")
  end
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("points", "[name] - show a balance, or the top balances", function(self, rest)
  if rest and rest ~= "" then
    self:Print(self:Short(rest) .. ": " .. ns.Points:Get(rest) .. " points")
    return
  end
  local list = {}
  for k, v in pairs(self.db.points) do table.insert(list, { k, v }) end
  table.sort(list, function(x, y) return x[2] > y[2] end)
  if #list == 0 then self:Print("No points awarded yet.") return end
  self:Print("Top balances:")
  for i = 1, math.min(10, #list) do
    self:Print(string.format("  %d. %s - %d", i, self:Short(list[i][1]), list[i][2]))
  end
end)

ns:AddCommand("give", "<name> <points> - manually adjust points", function(self, rest)
  local name, amt = rest:match("^(%S+)%s+(%-?%d+)$")
  if not name then self:Print("Usage: /casino give <name> <points>") return end
  local total = ns.Points:Add(name, tonumber(amt))
  self:Print(string.format("%s now has %d points.", self:Short(name), total))
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("bet", "<name> <gold> - manually log a bet (if you didn't trade)", function(self, rest)
  local name, gold = rest:match("^(%S+)%s+(%d+)$")
  if not name then self:Print("Usage: /casino bet <name> <gold>") return end
  gold = tonumber(gold)
  self:Announce(string.format("%s just bet %s!", self:Short(name), self:GoldStr(gold * 10000)), "hype")
  ns.Ledger:AddBet(name, gold * 10000)
  local pts, total = ns.Points:AwardForBet(name, gold)
  table.insert(self.db.betLog, { player = self:Norm(name), display = self:Short(name), copper = gold * 10000, time = date("%Y-%m-%d %H:%M") })
  self:Print(string.format("Logged %s bet of %dg -> +%d pts (total %d).", self:Short(name), gold, pts or 0, total or ns.Points:Get(name)))
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("redemptions", "list pending redemptions", function(self)
  local r = self.db.redemptions
  if #r == 0 then self:Print("No pending redemptions.") return end
  self:Print("Pending redemptions:")
  for i, e in ipairs(r) do
    self:Print(string.format("  %d. %s - %d pts (%s)", i, e.display or e.player, e.amount, e.time or ""))
  end
  self:Print("Clear one with /casino fulfill <n>")
end)

ns:AddCommand("fulfill", "<n> - remove a redemption from the queue", function(self, rest)
  local n = tonumber(rest)
  local r = self.db.redemptions
  if not n or not r[n] then self:Print("Usage: /casino fulfill <number> (see /casino redemptions)") return end
  local e = table.remove(r, n)
  self:Print(string.format("Fulfilled: %s - %d pts.", e.display or e.player, e.amount))
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("reset", "wipe all points, redemptions & logs (add 'confirm')", function(self, rest)
  if rest ~= "confirm" then
    self:Print("This wipes ALL points, redemptions and logs. Type: /casino reset confirm")
    return
  end
  self.db.points = {}
  self.db.redemptions = {}
  self.db.betLog = {}
  self.db.ledger = {}
  self.db.uoHistory = {}
  self.db.uoBets = {}
  self.db.session = { bets = 0, payouts = 0, started = date("%Y-%m-%d %H:%M") }
  self:Print("All data wiped.")
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("bindkey", "<key|off> - keybind that fires the Announce button, e.g. F8", function(self, rest)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if rest == "" then
    self:Print("Announce keybind: " .. (self.db.announceKey or "none") .. ". Set with /casino bindkey F8 (or: off)")
    return
  end
  if rest:lower() == "off" then
    self.db.announceKey = nil
  else
    if rest:find("%s") then
      self:Print("Keys with modifiers use dashes: SHIFT-F8, CTRL-ALT-F8. Try again.")
      return
    end
    self.db.announceKey = rest:upper()
  end
  ensureSayButton()
  applyAnnounceBinding()
  if self.bindPending then
    self:Print("Keybind change queued - it applies when you leave combat.")
  elseif self.db.announceKey and GetBindingAction then
    -- SetOverrideBindingClick fails silently on bad key names; catch that here.
    local action = GetBindingAction(self.db.announceKey, true)
    if action ~= "CLICK CasinoHostAnnounceButton:LeftButton" then
      self:Print("'" .. self.db.announceKey .. "' doesn't look like a valid key name - binding NOT applied. Use names like F8, NUMPAD1, SHIFT-F8.")
      self.db.announceKey = nil
      applyAnnounceBinding()
      return
    end
  end
  self:Print("Announce keybind: " .. (self.db.announceKey or "none"))
end)

ns:AddCommand("ui", "open/close the window", function(self)
  if ns.UI then ns.UI:Toggle() else self:Print("UI not loaded.") end
end)

-- ---------------------------------------------------------------------------
-- Post-login wiring (ns:On / ns:OnReady exist by this point in the file)
-- ---------------------------------------------------------------------------
-- Create the announce button at login so the bindkey works before the first queue.
ns:OnReady(function()
  ensureSayButton()
end)

ns:On("PLAYER_REGEN_ENABLED", function(self)
  if self.bindPending then
    self.bindPending = nil
    applyAnnounceBinding()
  end
end)
