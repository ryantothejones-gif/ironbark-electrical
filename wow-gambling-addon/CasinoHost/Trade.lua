-- CasinoHost - Trade
-- Detects a completed trade and announces how much gold the other player put up (their bet),
-- then awards points for it.

local ADDON, ns = ...

local T = {}
ns.Trade = T

-- Snapshot of the most recent trade state while the window is open.
local pending

local function partnerName()
  local name = UnitName("NPC")
  if (not name or name == "" or name == UNKNOWN) and TradeFrameRecipientNameText then
    name = TradeFrameRecipientNameText:GetText()
  end
  return name
end

-- Trade money can change right up until both sides lock in; re-snapshot on every update.
ns:On("TRADE_ACCEPT_UPDATE", function(self)
  pending = {
    partner = partnerName(),
    theyGive = GetTargetTradeMoney() or 0,  -- copper the OTHER player is offering (their bet)
    iGive = GetPlayerTradeMoney() or 0,      -- copper YOU are offering (a payout)
  }
end)

-- Trade completed successfully.
ns:On("UI_INFO_MESSAGE", function(self, _, message)
  if message == ERR_TRADE_COMPLETE and pending then
    T:Complete(pending)
    pending = nil
  end
end)

-- Window closed - if it wasn't completed, discard shortly after.
ns:On("TRADE_CLOSED", function()
  if C_Timer and C_Timer.After then
    C_Timer.After(0.5, function() pending = nil end)
  else
    pending = nil
  end
end)

function T:Complete(info)
  local betCopper = info.theyGive or 0
  local payCopper = info.iGive or 0
  local name = info.partner
  local known = name and name ~= "" and name ~= UNKNOWN
  if not known then name = "Someone" end

  -- Gold YOU handed over = a payout. Log it against the player's P&L.
  if payCopper > 0 and known then
    ns.Ledger:AddPayout(name, payCopper)
    ns:Print(string.format("Payout logged: %s to %s.", ns:GoldStr(payCopper), ns:Short(name)))
  end

  if betCopper <= 0 then
    -- No incoming gold: payout-only or item-only trade. Nothing to announce.
    if payCopper > 0 and ns.UI then ns.UI:Refresh() end
    return
  end

  local gold = math.floor(betCopper / 10000)
  ns:Announce(string.format("%s just bet %s!", ns:Short(name), ns:GoldStr(betCopper)))

  table.insert(ns.db.betLog, {
    player = ns:Norm(name),
    display = ns:Short(name),
    copper = betCopper,
    time = date("%Y-%m-%d %H:%M"),
  })
  if known then
    ns.Ledger:AddBet(name, betCopper)
  end

  local pts, total = ns.Points:AwardForBet(name, gold)
  if pts and pts > 0 then
    ns:Print(string.format("%s bet %s -> +%d points (total %d).", ns:Short(name), ns:GoldStr(betCopper), pts, total))
  end

  -- Let the player know their new balance right away.
  if known then
    SendChatMessage(string.format(
      "Bet received: %s (+%d points). Balance: %d points. Whisper !redeem <amount> to cash in.",
      ns:GoldStr(betCopper), pts or 0, total or ns.Points:Get(name)),
      "WHISPER", nil, ns:Norm(name))
  end

  if ns.UI then ns.UI:Refresh() end
end
