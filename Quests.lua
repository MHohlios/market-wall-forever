-- MarketWall: records quest rewards into the recording core (Record.lua) as "quest" events.
-- The gold comes with QUEST_TURNED_IN; reward items arrive as "You receive item" loot messages
-- while the reward window is open or just after the turn-in.
local _, ns = ...

local Quests = {}
ns.Quests = Quests

local RECENT = 2   -- seconds after a turn-in in which received items are its rewards

-- A Lua pattern matching a game format string such as "You receive item: %sx%d."
local function Pattern(format)
  local escaped = format:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
  return "^" .. escaped:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)") .. "$"
end

-- itemID and quantity from a received-item message, nil for any other message.
-- single and multiple are the game's LOOT_ITEM_PUSHED_SELF and LOOT_ITEM_PUSHED_SELF_MULTIPLE.
function Quests.ParseReceived(message, single, multiple)
  if type(message) ~= "string" then return nil end
  local link, quantity = nil, 1
  if multiple then link, quantity = message:match(Pattern(multiple)) end
  if not link and single then link, quantity = message:match(Pattern(single)), 1 end
  local id = link and tonumber(link:match("item:(%d+)"))
  if id then return id, tonumber(quantity) end
end

-- Whether an item received now is a quest reward: the reward window is open, or a quest was
-- turned in within RECENT seconds, and no merchant, mail, trade or auction window is open.
-- state: { reward = open, turnedIn = time, shops = { [window] = true while open } }
function Quests.IsReward(state, now)
  if next(state.shops) then return false end
  return state.reward or (state.turnedIn ~= nil and now - state.turnedIn <= RECENT)
end

-- In game -----------------------------------------------------------------------------------

local state = { reward = false, shops = {} }

-- The windows an item could be bought or received through, which are never quest rewards
local SHOPS = {
  MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
  MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
  TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false },
  AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
}

local HANDLERS = {
  QUEST_COMPLETE = function() state.reward = true end,
  QUEST_FINISHED = function() state.reward = false end,
  QUEST_TURNED_IN = function(questID, _, money)
    state.turnedIn = time()
    if type(money) == "number" and money > 0 then
      ns.Recording.Emit({ kind = "quest", source = "quest:" .. tostring(questID), coin = money, drops = {} })
    end
  end,
  CHAT_MSG_LOOT = function(message)
    if not Quests.IsReward(state, time()) then return end
    local id, quantity = Quests.ParseReceived(message, _G.LOOT_ITEM_PUSHED_SELF, _G.LOOT_ITEM_PUSHED_SELF_MULTIPLE)
    if id then ns.Recording.Emit({ kind = "quest", source = "quest", coin = 0, drops = { [id] = quantity } }) end
  end,
}

for event, shop in pairs(SHOPS) do
  HANDLERS[event] = function() state.shops[shop[1]] = shop[2] or nil end
end

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...) HANDLERS[event](...) end)
