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
  local copper = info.theyGive or 0
  local name = info.partner
  if not name or name == "" or name == UNKNOWN then name = "Someone" end

  if copper <= 0 then
    -- No incoming gold: this was a payout or item-only trade. Nothing to announce.
    return
  end

  local gold = math.floor(copper / 10000)
  ns:Announce(string.format("%s just bet %s!", ns:Short(name), ns:GoldStr(copper)))

  table.insert(ns.db.betLog, {
    player = ns:Norm(name),
    display = ns:Short(name),
    copper = copper,
    time = date("%Y-%m-%d %H:%M"),
  })

  local pts, total = ns.Points:AwardForBet(name, gold)
  if pts and pts > 0 then
    ns:Print(string.format("%s bet %s -> +%d points (total %d).", ns:Short(name), ns:GoldStr(copper), pts, total))
  end

  if ns.UI then ns.UI:Refresh() end
end
