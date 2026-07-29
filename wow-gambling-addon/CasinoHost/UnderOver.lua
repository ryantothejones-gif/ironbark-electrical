-- CasinoHost - Under/Over 7 (Worn Troll Dice)
-- The host tosses a Worn Troll Dice toy, which fires TWO standard /roll 6 system
-- messages (the toy has no combined "total" line - it's literally two d6 rolls).
-- We collect the host's two 1-6 rolls, sum them, and announce UNDER 7 (2-6),
-- SEVEN (7), or OVER 7 (8-12) so nearby players know the result.
--
-- Gotcha (from the WoW API): a hand-typed "/roll 6" is byte-identical to a die,
-- so we only listen while the host has armed the game, only count the HOST's own
-- rolls, and pair them two-at-a-time. The "casually tosses [Worn Troll Dice]"
-- emote (when present - English clients) resyncs the pair so a stray single roll
-- can't mis-pair with the next toss.

local ADDON, ns = ...

local UO = {}
ns.UO = UO

UO.active = false
UO.pending = {}   -- collected die values for the current toss
UO.token = 0      -- invalidates stale stray-roll timers
UO.last = nil     -- { a, b, total, verdict } of the most recent settled toss

local function isHost(name)
  if not name then return false end
  local me = UnitName and UnitName("player")
  if not me then return false end
  -- Match on FULL Name-Realm (like every other module): a same-named player on
  -- a connected/other realm must NOT be mistaken for the host, or their /roll 6
  -- would be counted as one of the host's dice.
  return ns:Norm(name) == ns:Norm(me)
end

function UO:Start()
  self.active = true
  self.pending = {}
  self.token = self.token + 1
  -- Both games read 1-6 rolls; if a target-6 blackjack table is live the host's
  -- dice would feed it too. Warn rather than silently cross-contaminate.
  if ns.BJ and ns.BJ.active and (ns.db.target or 100) == 6 then
    ns:Print("|cffff8800Heads up:|r a blackjack round with target 6 is live - your dice tosses will also land on that table. Close it with /casino bj stop first.")
  end
  ns:Announce("Under/Over 7 is OPEN! Bet UNDER (2-6), SEVEN (7), or OVER (8-12). I'll toss the dice!", "table")
  if ns.UI then ns.UI:Refresh() end
end

function UO:Stop()
  self.active = false
  self.pending = {}
  self.token = self.token + 1
  self:RefundBets("closed")
  ns:Announce("Under/Over 7 is closed - no more bets.", "table")
  if ns.UI then ns.UI:Refresh() end
end

-- A fresh toss began: drop any half-collected pair so we stay in sync.
function UO:Resync()
  self.pending = {}
  self.token = self.token + 1
end

function UO:AddDie(value)
  if not self.active then return end
  local now = (GetTime and GetTime()) or 0

  -- A real toss lands its two dice in the same instant. If a lone die has been
  -- pending for a while, it was a stray /roll 6 - drop it so it can't bridge
  -- into a wrong pair with the next toss. Locale-independent (doesn't rely on
  -- the English toss emote), so it protects non-enUS clients too.
  if #self.pending == 1 and now > 0 and self.firstTime and (now - self.firstTime) > 2 then
    self.pending = {}
  end

  table.insert(self.pending, value)

  if #self.pending >= 2 then
    local a = self.pending[1]
    local b = self.pending[2]
    self.pending = {}
    self.token = self.token + 1 -- cancel any pending stray-clear timer
    self:Settle(a, b)
    return
  end

  -- Only one die so far. Remember when it arrived, and if a second never comes
  -- (a lone stray /roll 6), clear it after a few seconds.
  self.firstTime = now
  self.token = self.token + 1
  local myToken = self.token
  if C_Timer and C_Timer.After then
    C_Timer.After(6, function()
      if UO.token == myToken and #UO.pending < 2 then
        UO.pending = {}
        if ns.UI then ns.UI:Refresh() end
      end
    end)
  end
  if ns.UI then ns.UI:Refresh() end
end

function UO:Settle(a, b)
  local total = a + b
  local verdict
  if total == 7 then
    verdict = "SEVEN! Straight-up 7 pays!"
  elseif total < 7 then
    verdict = "UNDER 7!"
  else
    verdict = "OVER 7!"
  end
  self.last = { a = a, b = b, total = total, verdict = verdict }

  -- Rolling history (persisted) so players can whisper !dice for recent results.
  ns.db.uoHistory = ns.db.uoHistory or {}
  table.insert(ns.db.uoHistory, total)
  while #ns.db.uoHistory > 20 do table.remove(ns.db.uoHistory, 1) end

  ns:Announce(string.format("Dice: %d + %d = %d - %s", a, b, total, verdict), "hype")
  self:SettleBets(total)
  if ns.UI then ns.UI:Refresh() end
end

-- ---------------------------------------------------------------------------
-- Point betting: players whisper !bet <amount> <over/under/7>. Their points are
-- staked at once; the next real toss settles it. Over/under pay even money; a
-- straight 7 pays db.uoSevenPays:1 (default 4). The house edge lives in the fact
-- that a 7 loses BOTH over and under. !cancelbet refunds before the toss, and
-- stopping the game refunds every pending bet.
-- ---------------------------------------------------------------------------
local CHOICE_WORDS = {
  over = "over", o = "over", high = "over",
  under = "under", u = "under", low = "under",
  seven = "seven", ["7"] = "seven",
}

local function choiceLabel(c)
  if c == "seven" then return "SEVEN (7)" end
  return c:upper()
end

function UO:PlaceBet(sender, amount, choiceWord)
  if not self.active then
    ns:SendChat("Under/Over 7 isn't open right now - wait for the host to open it.", "WHISPER", nil, sender)
    return
  end
  if #self.pending >= 1 then
    -- A toss is mid-flight (a die is already showing publicly); freeze betting
    -- so nobody can bet with partial knowledge of the result.
    ns:SendChat("Too late - the dice are rolling! Bet on the next toss.", "WHISPER", nil, sender)
    return
  end
  local choice = CHOICE_WORDS[(choiceWord or ""):lower()]
  if not amount or amount <= 0 or not choice then
    ns:SendChat("Usage: !bet <amount> <over/under/7>  e.g. !bet 100 over", "WHISPER", nil, sender)
    return
  end
  local key = ns:Norm(sender)
  ns.db.uoBets = ns.db.uoBets or {}
  local existing = ns.db.uoBets[key]
  if existing then
    ns:SendChat(string.format("You already have %d on %s this toss. Whisper !cancelbet to change it.",
      existing.amount, choiceLabel(existing.choice)), "WHISPER", nil, sender)
    return
  end
  local bal = ns.Points:Get(sender)
  if bal < amount then
    ns:SendChat(string.format("Not enough points - you have %d, tried to bet %d. (Bet gold with me to earn points.)", bal, amount), "WHISPER", nil, sender)
    return
  end
  -- Build the bet, THEN deduct, THEN store, so a failure can't leave a player's
  -- stake gone with no recorded bet.
  local bet = { display = ns:Short(sender), amount = amount, choice = choice }
  ns.Points:Add(sender, -amount)
  ns.db.uoBets[key] = bet
  pcall(ns.SendChat, ns, string.format("Bet placed: %d on %s. Balance: %d. Good luck!", amount, choiceLabel(choice), ns.Points:Get(sender)), "WHISPER", nil, sender)
  ns:Print(string.format("|cffffcc00BET|r %s put %d points on %s.", ns:Short(sender), amount, choiceLabel(choice)))
  if ns.UI then ns.UI:Refresh() end
end

function UO:CancelBet(sender)
  local key = ns:Norm(sender)
  local b = ns.db.uoBets and ns.db.uoBets[key]
  if not b then
    ns:SendChat("You have no pending Under/Over 7 bet.", "WHISPER", nil, sender)
    return
  end
  ns.Points:Add(key, b.amount)
  ns.db.uoBets[key] = nil
  ns:SendChat(string.format("Bet cancelled - %d points refunded. Balance: %d.", b.amount, ns.Points:Get(key)), "WHISPER", nil, sender)
  ns:Print(string.format("%s cancelled their %d point bet.", b.display, b.amount))
  if ns.UI then ns.UI:Refresh() end
end

function UO:RefundBets(reason)
  local bets = ns.db.uoBets
  if not bets or not next(bets) then return end
  ns.db.uoBets = {} -- clear before refunding so a failed whisper can't double-refund
  for key, b in pairs(bets) do
    ns.Points:Add(key, b.amount)
    pcall(ns.SendChat, ns, string.format("Under/Over 7 %s - your %d point bet was refunded.", reason or "closed", b.amount), "WHISPER", nil, key)
  end
  if ns.UI then ns.UI:Refresh() end
end

function UO:SettleBets(total)
  local bets = ns.db.uoBets
  if not bets or not next(bets) then return end
  ns.db.uoBets = {} -- clear BEFORE paying so a failed whisper can't re-pay next toss
  local winning = (total == 7 and "seven") or (total < 7 and "under") or "over"
  local sevenPays = ns.db.uoSevenPays or 4
  local names, winners, paid = {}, 0, 0
  for key, b in pairs(bets) do
    if b.choice == winning then
      local ratio = (b.choice == "seven") and sevenPays or 1
      local profit = b.amount * ratio
      local newbal = ns.Points:Add(key, b.amount + profit) -- stake back + winnings
      winners = winners + 1
      paid = paid + profit
      table.insert(names, b.display)
      pcall(ns.SendChat, ns, string.format("YOU WON! %s hit - +%d points (bet %d). Balance: %d.",
        choiceLabel(winning), profit, b.amount, newbal), "WHISPER", nil, key)
    else
      pcall(ns.SendChat, ns, string.format("No luck - it was %s, you had %s. Lost %d. Balance: %d.",
        choiceLabel(winning), choiceLabel(b.choice), b.amount, ns.Points:Get(key)), "WHISPER", nil, key)
    end
  end
  if winners > 0 then
    ns:Announce(string.format("Point bets: %d winner(s) - %s - paid %d points!", winners, table.concat(names, ", "), paid), "hype")
  else
    ns:Announce("Point bets: no winners - the house keeps the lot!", "hype")
  end
end

-- Compact pending-bet summary for the UI (nil if none).
function UO:BetsSummary()
  local bets = ns.db.uoBets
  if not bets or not next(bets) then return nil end
  local lines, pool = {}, 0
  for _, b in pairs(bets) do
    table.insert(lines, string.format("%s: %d on %s", b.display, b.amount, choiceLabel(b.choice)))
    pool = pool + b.amount
  end
  return lines, pool
end

-- Compact "newest first" summary of the last `count` results (nil if none).
-- e.g. "11 over, 7 SEVEN, 5 under"
function UO:RecentString(count)
  local h = ns.db.uoHistory
  if not h or #h == 0 then return nil end
  count = count or 10
  local parts = {}
  for i = #h, math.max(1, #h - count + 1), -1 do
    local total = h[i]
    local mark = (total == 7 and "SEVEN") or (total < 7 and "under") or "over"
    table.insert(parts, total .. " " .. mark)
  end
  return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- Wire up: read the two dice from the host's 1-6 rolls (via RollParser),
-- and use the toss emote (if any) to resync the pair.
-- ---------------------------------------------------------------------------
ns:OnRoll(function(self, who, roll, low, high)
  if not UO.active then return end
  if low ~= 1 or high ~= 6 then return end   -- only six-sided dice count
  if not isHost(who) then return end          -- only the host's tosses
  UO:AddDie(roll)
end)

ns:On("CHAT_MSG_TEXT_EMOTE", function(self, text, author)
  if not UO.active or not text then return end
  -- Resync on the host's toss emote. "Worn Troll Dice" is the enUS name; the
  -- item hyperlink ("Hitem:") is present in every locale, so matching either
  -- makes the resync work regardless of client language.
  if (text:find("Worn Troll Dice") or text:find("Hitem:")) and (author == nil or isHost(author)) then
    UO:Resync()
  end
end)

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------
ns:AddCommand("uo", "on | off | history | pays <n> - Under/Over 7 dice (players whisper !bet <amount> <over/under/7>)", function(self, rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "on" or sub == "start" or sub == "" then
    UO:Start()
  elseif sub == "off" or sub == "stop" then
    UO:Stop()
  elseif sub == "history" or sub == "last" or sub == "rolls" then
    local s = UO:RecentString(10)
    self:Print(s and ("Last 10 Under/Over 7 (newest first): " .. s) or "No dice results yet.")
  elseif sub == "pays" then
    local n = tonumber((rest or ""):match("^%S+%s+(%d+)"))
    if n and n >= 1 then
      self.db.uoSevenPays = n
      self:Print("Under/Over 7: a straight '7' bet now pays " .. n .. ":1 (over/under pay even money).")
    else
      self:Print("A '7' bet pays " .. (self.db.uoSevenPays or 4) .. ":1. Set with /casino uo pays <n>")
    end
  else
    self:Print("Usage: /casino uo on|off|history|pays <n>  (then toss your Worn Troll Dice)")
  end
end)

-- Refund any bets left in the DB from a previous session (a logout or reload
-- instead of /casino uo off). The game always comes up inactive, so these would
-- otherwise settle against an unrelated future toss.
ns:OnReady(function()
  local bets = ns.db.uoBets
  if bets and next(bets) then
    local n = 0
    for key, b in pairs(bets) do ns.Points:Add(key, b.amount); n = n + 1 end
    ns.db.uoBets = {}
    ns:Print(string.format("Refunded %d leftover Under/Over 7 point bet(s) from a previous session.", n))
  end
end)
