-- CasinoHost - Ledger
-- Trade logger / P&L: tracks gold IN (bets) vs gold OUT (payouts) per player,
-- plus a running session total, so you always know how the house is doing.

local ADDON, ns = ...

local L = {}
ns.Ledger = L

local function entry(name)
  local key = ns:Norm(name)
  local e = ns.db.ledger[key]
  if not e then
    e = { display = ns:Short(name), bets = 0, payouts = 0, count = 0 }
    ns.db.ledger[key] = e
  end
  e.display = ns:Short(name)
  return e
end

function L:AddBet(name, copper)
  local e = entry(name)
  e.bets = e.bets + copper
  e.count = e.count + 1
  ns.db.session.bets = ns.db.session.bets + copper
end

function L:AddPayout(name, copper)
  local e = entry(name)
  e.payouts = e.payouts + copper
  ns.db.session.payouts = ns.db.session.payouts + copper
end

-- All-time totals across every player.
function L:Summary()
  local bets, payouts = 0, 0
  for _, e in pairs(ns.db.ledger) do
    bets = bets + (e.bets or 0)
    payouts = payouts + (e.payouts or 0)
  end
  return bets, payouts
end

ns:OnReady(function()
  if ns.db.session.started == "" then
    ns.db.session.started = date("%Y-%m-%d %H:%M")
  end
end)

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
ns:AddCommand("pl", "print session and all-time profit/loss", function(self)
  local s = self.db.session
  self:Print(string.format("Session (since %s): in %s | out %s | net %s",
    s.started, self:GoldStr(s.bets), self:GoldStr(s.payouts), self:SignedGold(s.bets - s.payouts)))
  local bets, payouts = L:Summary()
  self:Print(string.format("All-time: in %s | out %s | net %s",
    self:GoldStr(bets), self:GoldStr(payouts), self:SignedGold(bets - payouts)))
end)

ns:AddCommand("payout", "<name> <gold> - manually log a payout (mail, COD, etc.)", function(self, rest)
  local name, gold = rest:match("^(%S+)%s+(%d+)$")
  if not name then self:Print("Usage: /casino payout <name> <gold>") return end
  L:AddPayout(name, tonumber(gold) * 10000)
  self:Print(string.format("Logged payout of %sg to %s.", gold, self:Short(name)))
  if ns.UI then ns.UI:Refresh() end
end)

ns:AddCommand("session", "show session P&L, or 'reset' to start a new session", function(self, rest)
  if rest:lower() == "reset" then
    self.db.session = { bets = 0, payouts = 0, started = date("%Y-%m-%d %H:%M") }
    self:Print("New session started - session P&L zeroed (all-time ledger kept).")
    if ns.UI then ns.UI:Refresh() end
    return
  end
  local s = self.db.session
  self:Print(string.format("Session since %s: in %s | out %s | net %s  (/casino session reset to start fresh)",
    s.started, self:GoldStr(s.bets), self:GoldStr(s.payouts), self:SignedGold(s.bets - s.payouts)))
end)
