-- MarketWall: the shared recording core. One synchronous stream of events that the kill tracker,
-- and later the money ledger, sessions and disenchant log, write to and read from.
-- An event is { t, kind, source, ... }:
--   kill    a settled kill: guid, npc, name, outcome, coin, drops, gather, via (see Kills.lua)
--   loot    a corpse or container you looted: guid, npc, coin, drops
--   gather  skinning or other gathering: guid, npc (nil for a node), drops
--   fish    a fishing catch: coin, drops
-- source is "npc:<id>", "object:<id>" or "fishing". drops are raw { [itemID] = quantity }.
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

-- "Name-Realm" for the logged-in character, nil before the game knows the name
function Recording.CharacterKey()
  local name = UnitName and UnitName("player")
  if type(name) ~= "string" then return nil end
  return name .. "-" .. ns.Realm()
end
