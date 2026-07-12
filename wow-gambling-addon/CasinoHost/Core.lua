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

-- ---------------------------------------------------------------------------
-- Announce to the configured channel (or print locally in dry-run mode)
-- ---------------------------------------------------------------------------
-- SAY/YELL are protected in the open world on retail: an addon can only send
-- them from a hardware event (a real click). So outside instances we queue the
-- message on a big button the host clicks to fire it.
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

local function queueSay(msg, ch)
  if not sayButton then
    local b = CreateFrame("Button", "CasinoHostAnnounceButton", UIParent, "UIPanelButtonTemplate")
    b:SetSize(300, 30)
    b:SetPoint("TOP", UIParent, "TOP", 0, -160)
    b:SetFrameStrata("DIALOG")
    b:SetClampedToScreen(true)
    b:SetMovable(true)
    b:RegisterForDrag("RightButton")
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", b.StopMovingOrSizing)
    b:SetScript("OnClick", function()
      -- This click IS the hardware event, so say/yell is allowed here.
      local item = table.remove(sayQueue, 1)
      if item then SendChatMessage(item.msg, item.ch) end
      updateSayButton()
    end)
    sayButton = b
  end
  table.insert(sayQueue, { msg = msg, ch = ch })
  updateSayButton()
end

function ns:Announce(msg)
  local db = self.db
  if not db or db.dryRun then
    self:Print("|cffffcc00[dry-run]|r " .. msg)
    return
  end
  local ch = db.channel or "PARTY"
  if ch == "CHANNEL" and db.channelName then
    local id = GetChannelName(db.channelName)
    if id and id > 0 then
      SendChatMessage(msg, "CHANNEL", nil, id)
      return
    end
    self:Print("Channel '" .. db.channelName .. "' not joined - showing locally: " .. msg)
    return
  end
  if (ch == "SAY" or ch == "YELL") and not IsInInstance() then
    queueSay(msg, ch)
    return
  end
  SendChatMessage(msg, ch)
end

-- ---------------------------------------------------------------------------
-- Saved-variable defaults
-- ---------------------------------------------------------------------------
local defaults = {
  channel = "PARTY",       -- SAY / YELL / PARTY / RAID / GUILD / INSTANCE_CHAT / CHANNEL
  channelName = nil,        -- custom channel name when channel == "CHANNEL"
  dryRun = false,           -- print announcements locally instead of sending
  pointsPerGold = 1,        -- points awarded per 1 gold bet
  target = 100,             -- blackjack target number
  points = {},              -- [Name-Realm] = points
  redemptions = {},         -- queue of { player, display, amount, time }
  betLog = {},              -- history of { player, display, copper, time }
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
ns:AddCommand("channel", "<party|say|raid|guild|yell|channel NAME> - where to announce", function(self, rest)
  local a, b = rest:match("^(%S+)%s*(.-)$")
  a = a and a:upper() or ""
  local valid = { SAY = true, YELL = true, PARTY = true, RAID = true, GUILD = true, INSTANCE_CHAT = true }
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
    self:Print("Valid: party, say, raid, guild, yell, channel <name>")
  end
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
  self:Announce(string.format("%s just bet %s!", self:Short(name), self:GoldStr(gold * 10000)))
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
  self:Print("All data wiped.")
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("ui", "open/close the window", function(self)
  if ns.UI then ns.UI:Toggle() else self:Print("UI not loaded.") end
end)
