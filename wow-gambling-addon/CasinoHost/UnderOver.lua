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
  ns:Announce(string.format("Dice: %d + %d = %d - %s", a, b, total, verdict), "hype")
  if ns.UI then ns.UI:Refresh() end
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
ns:AddCommand("uo", "on | off - Under/Over 7 dice game (toss your Worn Troll Dice)", function(self, rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "on" or sub == "start" or sub == "" then
    UO:Start()
  elseif sub == "off" or sub == "stop" then
    UO:Stop()
  else
    self:Print("Usage: /casino uo on|off  (then toss your Worn Troll Dice)")
  end
end)
