-- CasinoHost - Blackjack (roll to 100)
-- Players /roll (1-100). Each roll adds to their running total. Get as close to the
-- target as possible; over the target = BUST. Type "stand" in chat to hold.

local ADDON, ns = ...

local BJ = {}
ns.BJ = BJ

BJ.active = false
BJ.players = {}   -- [Name-Realm] = { display, total, rolls, status }
BJ.order = {}     -- ordered list of keys for stable display

function BJ:Clear()
  self.players = {}
  self.order = {}
  if ns.UI then ns.UI:Refresh() end
end

local function ensure(name)
  local key = ns:Norm(name)
  local p = BJ.players[key]
  if not p then
    p = { display = ns:Short(name), total = 0, rolls = 0, status = "playing" }
    BJ.players[key] = p
    table.insert(BJ.order, key)
  end
  return p
end

function BJ:Start()
  self.active = true
  self:Clear()
  self.active = true
  local target = ns.db.target or 100
  ns:Announce(string.format(
    "Blackjack is OPEN! /roll (1-%d) to hit, keep rolling to get close to %d. Type 'stand' to hold - over %d and you BUST!",
    target, target, target))
  if ns.UI then ns.UI:Refresh() end
end

function BJ:Stop()
  self.active = false
  ns:Announce("Blackjack round closed - no more rolls.")
  if ns.UI then ns.UI:Refresh() end
end

function BJ:AddRoll(name, value)
  if not self.active then return end
  local p = ensure(name)
  if p.status ~= "playing" then return end  -- already stood or busted this round

  p.total = p.total + value
  p.rolls = p.rolls + 1
  local target = ns.db.target or 100

  if p.total > target then
    p.status = "bust"
    ns:Announce(string.format("%s just rolled %d - total %d. BUST!", p.display, value, p.total))
  elseif p.total == target then
    p.status = "stand"
    ns:Announce(string.format("%s just rolled %d - total %d. PERFECT %d!", p.display, value, p.total, target))
  else
    ns:Announce(string.format("%s just rolled %d - total %d.", p.display, value, p.total))
  end

  if ns.UI then ns.UI:Refresh() end
end

function BJ:Stand(name)
  if not self.active then return end
  local key = ns:Norm(name)
  local p = self.players[key]
  if not p or p.status ~= "playing" then return end
  p.status = "stand"
  ns:Announce(string.format("%s stands on %d.", p.display, p.total))
  if ns.UI then ns.UI:Refresh() end
end

function BJ:Result()
  local target = ns.db.target or 100
  local best, winners = -1, {}
  for _, key in ipairs(self.order) do
    local p = self.players[key]
    if p.status ~= "bust" and p.total <= target and p.rolls > 0 then
      if p.total > best then
        best = p.total
        winners = { p }
      elseif p.total == best then
        table.insert(winners, p)
      end
    end
  end

  if #winners == 0 then
    ns:Announce("Everyone busted - house wins!")
  elseif #winners == 1 then
    ns:Announce(string.format("%s wins with %d!", winners[1].display, best))
  else
    local names = {}
    for _, p in ipairs(winners) do table.insert(names, p.display) end
    ns:Announce(string.format("Tie at %d between %s.", best, table.concat(names, ", ")))
  end
end

-- ---------------------------------------------------------------------------
-- Wire up rolls and "stand" detection
-- ---------------------------------------------------------------------------
ns:OnRoll(function(self, who, roll, low, high)
  if not BJ.active then return end
  local target = self.db.target or 100
  -- Only count standard 1..target rolls so accidental /roll ranges don't corrupt totals.
  if low == 1 and high == target then
    BJ:AddRoll(who, roll)
  end
end)

local function checkStand(self, text, sender)
  if not BJ.active or not text then return end
  local t = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if t == "stand" or t == "!stand" then
    BJ:Stand(sender)
  end
end

ns:On("CHAT_MSG_PARTY", checkStand)
ns:On("CHAT_MSG_PARTY_LEADER", checkStand)
ns:On("CHAT_MSG_RAID", checkStand)
ns:On("CHAT_MSG_RAID_LEADER", checkStand)
ns:On("CHAT_MSG_SAY", checkStand)

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------
ns:AddCommand("bj", "start | stop | result | clear - run a blackjack round", function(self, rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "" or sub == "start" then
    BJ:Start()
  elseif sub == "stop" then
    BJ:Stop()
  elseif sub == "result" then
    BJ:Result()
  elseif sub == "clear" then
    BJ.active = false
    BJ:Clear()
    self:Print("Blackjack table cleared.")
  else
    self:Print("Usage: /casino bj start|stop|result|clear")
  end
end)
