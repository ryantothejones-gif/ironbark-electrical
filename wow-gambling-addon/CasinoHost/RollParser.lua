-- CasinoHost - RollParser
-- Turns "PlayerName rolls 42 (1-100)" system messages into structured roll events.

local ADDON, ns = ...

-- Build a Lua pattern from the localised RANDOM_ROLL_RESULT global ("%s rolls %d (%d-%d)").
local rollPattern
do
  local template = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  -- 1) protect the format specifiers before escaping magic characters
  template = template:gsub("%%s", "\1"):gsub("%%d", "\2")
  -- 2) escape Lua-pattern magic characters
  template = template:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
  -- 3) restore the specifiers as capture groups
  template = template:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
  rollPattern = template
end

ns.rollListeners = {}

-- Register a callback: fn(ns, who, roll, low, high)
function ns:OnRoll(fn)
  table.insert(self.rollListeners, fn)
end

function ns:FireRoll(who, roll, low, high)
  for _, fn in ipairs(self.rollListeners) do
    fn(self, who, roll, low, high)
  end
end

ns:On("CHAT_MSG_SYSTEM", function(self, text)
  if not text then return end
  local who, roll, low, high = text:match(rollPattern)
  if not who then return end
  self:FireRoll(who, tonumber(roll), tonumber(low), tonumber(high))
end)
