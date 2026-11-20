-- MarketWall: the one record of creature names and families that kills, mobs and sessions read.
-- Saved in MarketWallDB.creatures, shared by every character: [npcID] = { name =, family = }.
-- Filled from every unit the game lets an add-on read: your target, the mouseover, nameplates and
-- soft targets. Secret values are never stored. A mob never seen that way is asked of the game's
-- creature cache through a hidden tooltip; a name found there is kept like any other.
local _, ns = ...

local Creatures = {}
ns.Creatures = Creatures

local ASK_AGAIN = 60   -- seconds before a mob the game could not name is asked again

-- Records a sighting into creatures. guid, name and family are readable values or nil.
function Creatures.Saw(creatures, guid, name, family)
  local kind, npc = ns.Kills.ParseGUID(guid)
  if kind ~= "npc" then return end
  if name == _G.UNKNOWNOBJECT or name == "" then name = nil end   -- a unit whose name has not loaded yet
  if type(name) ~= "string" and type(family) ~= "string" then return end
  local creature = creatures[npc] or {}
  if type(name) == "string" then creature.name = name end
  if type(family) == "string" then creature.family = family end
  creatures[npc] = creature
end

-- A mob's name: the one last seen, else the one its kills were recorded under, else the game's
-- creature cache, which is kept when it answers. nil when nothing knows it.
function Creatures.Name(npc, recorded)
  local creature = MarketWallDB.creatures[npc]
  if creature and creature.name then return creature.name end
  if recorded then return recorded end
  local asked = Creatures.Ask(npc)
  if asked then
    creature = creature or {}
    creature.name = asked
    MarketWallDB.creatures[npc] = creature
  end
  return asked
end

-- In game -----------------------------------------------------------------------------------

local Readable = ns.Readable
local scanner, askedAt = nil, {}

-- The name the game's creature cache gives a creature link, or nil. Guarded: a client that has
-- no creature links leaves the tooltip empty or refuses the link.
local function TooltipName(npc)
  scanner = scanner or CreateFrame("GameTooltip", "MarketWallCreatureScan", UIParent, "GameTooltipTemplate")
  scanner:SetOwner(UIParent, "ANCHOR_NONE")
  local ok = pcall(scanner.SetHyperlink, scanner, "unit:Creature-0-0-0-0-" .. npc .. "-0000000000")
  local line = ok and _G.MarketWallCreatureScanTextLeft1
  local text = line and Readable(line:GetText())
  scanner:Hide()
  if type(text) == "string" and text ~= "" and text ~= _G.UNKNOWNOBJECT then return text end
end

-- Asks the game for a creature's name, at most once a minute each: a first ask may only start
-- the game's query, so a later one can succeed
function Creatures.Ask(npc)
  local now = time()
  if askedAt[npc] and now - askedAt[npc] < ASK_AGAIN then return nil end
  askedAt[npc] = now
  local ok, name = pcall(TooltipName, npc)
  return ok and name or nil
end

function Creatures.SawUnit(unit)
  local guid = Readable(UnitGUID(unit))
  if not guid then return end
  Creatures.Saw(MarketWallDB.creatures, guid, Readable(UnitName(unit)), Readable(UnitCreatureFamily(unit)))
end

local HANDLERS = {
  PLAYER_TARGET_CHANGED = function() Creatures.SawUnit("target") end,
  UPDATE_MOUSEOVER_UNIT = function() Creatures.SawUnit("mouseover") end,
  NAME_PLATE_UNIT_ADDED = function(unit) Creatures.SawUnit(unit) end,
  PLAYER_SOFT_ENEMY_CHANGED = function() Creatures.SawUnit("softenemy") end,
  PLAYER_SOFT_INTERACT_CHANGED = function() Creatures.SawUnit("softinteract") end,
}

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do
  pcall(frame.RegisterEvent, frame, event)   -- a client without the event refuses it
end
frame:SetScript("OnEvent", function(_, event, ...) HANDLERS[event](...) end)
