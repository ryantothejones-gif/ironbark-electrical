-- CasinoHost - Blackjack (roll to 100)
-- Players /roll (1-100). Each roll adds to their running total. Get as close to the
-- target as possible; over the target = BUST. Type "stand" in chat to hold.

local ADDON, ns = ...

local BJ = {}
ns.BJ = BJ

BJ.active = false
BJ.players = {}   -- [Name-Realm] = { display, total, rolls, status }
BJ.order = {}     -- ordered list of keys for stable display
BJ.tiebreak = nil -- { total, order = {keys}, players = { [key] = { display, roll } } }

function BJ:Clear()
  self.players = {}
  self.order = {}
  self.tiebreak = nil
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
  self.tiebreak = nil
  ns:Announce("Blackjack round closed - no more rolls.")
  if ns.UI then ns.UI:Refresh() end
end

-- Reset the table for the next round (used after a result resolves).
function BJ:NextRound()
  if not self.active then return end
  self.players = {}
  self.order = {}
  local target = ns.db.target or 100
  ns:Announce(string.format("New round is OPEN - /roll (1-%d) to play!", target))
end

function BJ:AddRoll(name, value)
  if not self.active then return end
  local p = ensure(name)
  if p.status ~= "playing" then
    -- Host-only note so a silently ignored roll never looks like a broken addon.
    ns:Print(string.format("Ignored roll from %s - already %s this round (next round opens after /casino bj result).",
      p.display, p.status == "bust" and "busted" or "standing"))
    return
  end

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
  -- During a roll-off, /casino bj result force-resolves it (no-shows forfeit).
  if self.tiebreak then
    self:ResolveTiebreak(true)
    return
  end

  local target = ns.db.target or 100
  local best, winners = -1, {}
  local anyRolls = false
  for _, key in ipairs(self.order) do
    local p = self.players[key]
    if p.rolls > 0 then anyRolls = true end
    if p.status ~= "bust" and p.total <= target and p.rolls > 0 then
      if p.total > best then
        best = p.total
        winners = { { key = key, p = p } }
      elseif p.total == best then
        table.insert(winners, { key = key, p = p })
      end
    end
  end

  if not anyRolls then
    ns:Print("No rolls this round - nothing to announce.")
    return
  end

  if #winners == 0 then
    ns:Announce("Everyone busted - house wins!", "hype")
  elseif #winners == 1 then
    ns:Announce(string.format("%s wins with %d!", winners[1].p.display, best), "hype")
  else
    -- Tie: winner decided by a roll-off, not a shrug.
    self:StartTiebreak(winners, best)
    return
  end

  -- Auto-open the next round so the host never has to /casino bj start again mid-session.
  self:NextRound()
  if ns.UI then ns.UI:Refresh() end
end

-- ---------------------------------------------------------------------------
-- Roll-off: tied players each /roll once, highest wins; ties repeat until broken.
-- ---------------------------------------------------------------------------
function BJ:StartTiebreak(winners, total)
  local order, players, names = {}, {}, {}
  for _, w in ipairs(winners) do
    table.insert(order, w.key)
    players[w.key] = { display = w.p.display, roll = nil }
    table.insert(names, w.p.display)
  end
  self.tiebreak = { total = total, order = order, players = players }
  local target = ns.db.target or 100
  ns:Announce(string.format("Tie at %d between %s - ROLL-OFF! /roll (1-%d), highest wins!",
    total, table.concat(names, ", "), target))
  if ns.UI then ns.UI:Refresh() end
end

function BJ:TiebreakRoll(who, roll)
  local tb = self.tiebreak
  local key = ns:Norm(who)
  local p = tb.players[key]
  if not p then
    ns:Print(string.format("%s rolled but isn't in the roll-off - ignored.", ns:Short(who)))
    return
  end
  if p.roll then
    ns:Print(string.format("Ignored extra roll-off roll from %s (already rolled %d).", p.display, p.roll))
    return
  end
  p.roll = roll
  tb.voidArmed = nil
  ns:Announce(string.format("Roll-off: %s rolls %d!", p.display, roll))

  for _, k in ipairs(tb.order) do
    if not tb.players[k].roll then
      if ns.UI then ns.UI:Refresh() end
      return -- still waiting on someone
    end
  end
  self:ResolveTiebreak(false)
end

function BJ:ResolveTiebreak(force)
  local tb = self.tiebreak
  if not tb then return end

  local best, top, waiting = -1, {}, {}
  for _, k in ipairs(tb.order) do
    local p = tb.players[k]
    if p.roll then
      if p.roll > best then
        best = p.roll
        top = { { key = k, p = p } }
      elseif p.roll == best then
        table.insert(top, { key = k, p = p })
      end
    else
      table.insert(waiting, p.display)
    end
  end

  if best < 0 then
    -- Everyone is a no-show. First forced result warns; the second voids the
    -- roll-off, so a hasty double-tap can't kill a roll-off nobody's had time
    -- to roll in yet.
    if force and tb.voidArmed then
      ns:Announce("Nobody rolled - roll-off void, house keeps it!")
      self.tiebreak = nil
      self:NextRound()
      if ns.UI then ns.UI:Refresh() end
    elseif force then
      tb.voidArmed = true
      ns:Print("Roll-off: nobody has rolled yet (waiting on " .. table.concat(waiting, ", ") .. "). Result again to VOID the roll-off.")
    else
      ns:Print("Roll-off: no one has rolled yet - still waiting on " .. table.concat(waiting, ", ") .. ".")
    end
    return
  end
  if #waiting > 0 then
    if not force then return end
    ns:Announce(string.format("%s didn't roll - forfeit!", table.concat(waiting, ", ")))
  end

  if #top == 1 then
    ns:Announce(string.format("%s wins the roll-off with %d!", top[1].p.display, best), "hype")
    self.tiebreak = nil
    self:NextRound()
  else
    -- Tied again: only the players still tied at the top roll once more.
    local order, players, names = {}, {}, {}
    for _, w in ipairs(top) do
      table.insert(order, w.key)
      players[w.key] = { display = w.p.display, roll = nil }
      table.insert(names, w.p.display)
    end
    self.tiebreak = { total = tb.total, order = order, players = players }
    ns:Announce(string.format("Still tied at %d - %s roll again!", best, table.concat(names, ", ")))
  end
  if ns.UI then ns.UI:Refresh() end
end

-- ---------------------------------------------------------------------------
-- Wire up rolls and "stand" detection
-- ---------------------------------------------------------------------------
ns:OnRoll(function(self, who, roll, low, high)
  -- A roll-off stays rollable even if the table was stopped first (stop -> result).
  if not BJ.active and not BJ.tiebreak then return end
  local target = self.db.target or 100
  -- Only count standard 1..target rolls so accidental /roll ranges don't corrupt totals.
  if low ~= 1 or high ~= target then return end
  if BJ.tiebreak then
    BJ:TiebreakRoll(who, roll)
  else
    BJ:AddRoll(who, roll)
  end
end)

local function checkStand(self, text, sender)
  if not BJ.active or BJ.tiebreak or not text then return end
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
ns:AddCommand("bj", "start | stop | result | clear - result announces the winner and opens the next round", function(self, rest)
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
