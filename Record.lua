-- MarketWall: the shared recording core. One synchronous stream of events that the kill tracker,
-- disenchant log, money ledger and farm sessions write to and read from.
-- An event is { t, kind, source, ... }:
--   kill    a settled kill: guid, npc, name, outcome, coin, drops, gather, via (see Kills.lua)
--   loot    a corpse, chest or container you looted: window, guid, npc, name, coin, drops
--   gather  skinning, herbalism or mining: guid, npc (nil for a node), skill, drops
--   fish    a fishing catch: window, coin, drops
--   window  a loot window opened, or closed when closed is true: window
--   quest   a quest reward: coin, drops (items arrive as their own events)
--   money   a gold change in the ledger: delta, with source its ledger source (see Ledger.lua)
--   disenchant  one of your disenchants: item, quality, level, classID, salvager, materials
--               (see DisenchantLog.lua)
-- source is "npc:<id>", "object:<id>", "item" (a bag container), "item:<id>" (a disenchanted
-- item) or "fishing"; for a quest it is "quest:<id>" for its gold and "quest" for its items.
-- window numbers the loot window an event came from. drops are raw { [itemID] = quantity }.
local _, ns = ...

local Recording = {}
ns.Recording = Recording

local listeners = {}   -- [kind] = { fn, ... }

function Recording.On(kind, fn)
  local list = listeners[kind]
  if not list then list = {} listeners[kind] = list end
  list[#list + 1] = fn
end

function Recording.Emit(event)
  event.t = event.t or time()
  local list = listeners[event.kind]
  if not list then return end
  for i = 1, #list do list[i](event) end
end

-- The logged-in character's GUID, the key of its ledger book and sessions; nil before the game
-- knows it. Not "Name-Realm": WoW Forever reports one realm name for every realm, so characters
-- of the same name on different realms would share a key.
function Recording.CharacterKey()
  local guid = UnitGUID and UnitGUID("player")
  if type(guid) ~= "string" then return nil end
  return guid
end

-- The logged-in character's name, as shown to you; nil before the game knows it
function Recording.CharacterName()
  local name = UnitName and UnitName("player")
  if type(name) ~= "string" then return nil end
  return name
end

-- The "Name-Realm" key characters had before CharacterKey, kept only to adopt data saved under it
function Recording.LegacyKey()
  local name = Recording.CharacterName()
  return name and (name .. "-" .. ns.Realm())
end
