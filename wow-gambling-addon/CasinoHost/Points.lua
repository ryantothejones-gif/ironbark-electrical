-- CasinoHost - Points & redemptions
-- Players earn points from bets. They whisper the host:
--   !balance / !points   -> get their point total
--   !redeem <amount>      -> spend points (queued for the host to fulfil)
--   !help                 -> list commands

local ADDON, ns = ...

local P = {}
ns.Points = P

function P:Get(name)
  return ns.db.points[ns:Norm(name)] or 0
end

function P:Add(name, amount)
  local key = ns:Norm(name)
  ns.db.points[key] = (ns.db.points[key] or 0) + amount
  if ns.db.points[key] < 0 then ns.db.points[key] = 0 end
  return ns.db.points[key]
end

-- Returns pointsAwarded, newTotal
function P:AwardForBet(name, goldAmount)
  local rate = ns.db.pointsPerGold or 1
  local pts = math.floor(goldAmount * rate)
  if pts <= 0 then return 0, self:Get(name) end
  local total = self:Add(name, pts)
  return pts, total
end

function P:Redeem(sender, amt)
  local bal = self:Get(sender)
  if amt <= 0 then
    SendChatMessage("Redeem amount must be a positive number, e.g. !redeem 50", "WHISPER", nil, sender)
    return
  end
  if bal < amt then
    SendChatMessage(string.format("Not enough points - you have %d, tried to redeem %d.", bal, amt), "WHISPER", nil, sender)
    return
  end
  self:Add(sender, -amt)
  table.insert(ns.db.redemptions, {
    player = ns:Norm(sender),
    display = ns:Short(sender),
    amount = amt,
    time = date("%Y-%m-%d %H:%M"),
  })
  SendChatMessage(string.format("Redeemed %d points! Balance: %d. A host will sort you out shortly.", amt, self:Get(sender)), "WHISPER", nil, sender)
  ns:Print(string.format("|cffffcc00REDEEM|r %s wants to redeem %d points (balance now %d). See /casino redemptions.", ns:Short(sender), amt, self:Get(sender)))
  if RaidNotice_AddMessage and RaidWarningFrame then
    RaidNotice_AddMessage(RaidWarningFrame, string.format("%s redeemed %d points", ns:Short(sender), amt), ChatTypeInfo["RAID_WARNING"])
  end
  if PlaySound then PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960) end
  if ns.UI then ns.UI:Refresh() end
end

-- ---------------------------------------------------------------------------
-- Whisper command handling
-- ---------------------------------------------------------------------------
local function handleWhisper(self, text, sender)
  if not text then return end
  local t = text:gsub("^%s+", ""):gsub("%s+$", "")
  local low = t:lower()

  if low == "!balance" or low == "!points" or low == "!bal" then
    SendChatMessage(string.format("You have %d point(s).", P:Get(sender)), "WHISPER", nil, sender)
    return
  end

  if low == "!help" then
    SendChatMessage("Commands: !balance = check points | !redeem <amount> = spend points", "WHISPER", nil, sender)
    return
  end

  local amt = low:match("^!redeem%s+(%d+)")
  if amt then
    P:Redeem(sender, tonumber(amt))
    return
  end

  if low:match("^!redeem") then
    SendChatMessage("Usage: !redeem <amount>  e.g. !redeem 100", "WHISPER", nil, sender)
  end
end

ns:On("CHAT_MSG_WHISPER", handleWhisper)
