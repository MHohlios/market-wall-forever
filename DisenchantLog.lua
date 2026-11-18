-- MarketWall: the disenchant log. Each of your disenchants becomes a "disenchant" event in the
-- recording core, and its materials are added to its sample, which Disenchant.lua prefers over
-- estimates once it has 20 results.
--
-- Pairing a disenchant with its loot: when a Disenchant cast (spell 13262) starts, the item under
-- it is the one locked in your bags; the cast locks its target however it was aimed (a click, a
-- macro or another add-on's button). Two locked items at once are ambiguous and record nothing.
-- On success, the next loot window, within a few seconds, whose every slot comes from an Item
-- source holds the materials. Any window consumes the cast, as with Kills.lua's gathering casts.
--
-- Importing Disenchantry is one-time: the first login that finds DisenchantryDB copies its samples
-- and Salvager setting, and later logins import nothing. From then on MarketWall records every
-- disenchant itself, Disenchantry's button included, so merging Disenchantry's later results would
-- count them twice. (The live Disenchantry file had no samples to import when this was written.)
--
-- Saved in MarketWallDB.disenchants, shared by every character:
--   samples  [key] = { count = disenchants, materials = { [itemID] = { hits =, total = } } }
--            keyed by SampleKey
--   imported true once Disenchantry has been imported
local _, ns = ...

local Log = {}
ns.DisenchantLog = Log

local DISENCHANT = 13262
local CAST_WINDOW = 3   -- seconds after the cast in which a loot window is its result
local WEAPON, ARMOR = 2, 4

-- Items with their own Forever estimate are kept to themselves: "item:<id>:mode". Classic items
-- pool by kind, "quality:levels:classID:mode" with item levels in fives (1-5, 6-10, ...), which
-- line up with the classic tables, e.g. "2:26-30:4:normal".
function Log.SampleKey(id, quality, level, classID, salvager)
  local mode = salvager and "salvager" or "normal"
  if ns.HasForeverEstimate(id, quality) then return "item:" .. id .. ":" .. mode end
  local low = math.floor((level - 1) / 5) * 5 + 1
  return table.concat({ quality, low .. "-" .. (low + 4), classID, mode }, ":")
end

local function Store()
  return MarketWallDB and MarketWallDB.disenchants
end

local function SampleIn(samples, key)
  local sample = samples[key]
  if not sample then
    sample = { count = 0, materials = {} }
    samples[key] = sample
  end
  return sample
end

local function AddMaterial(sample, id, hits, total)
  local m = sample.materials[id] or { hits = 0, total = 0 }
  m.hits, m.total = m.hits + hits, m.total + total
  sample.materials[id] = m
end

-- Your results for an item, nil before the first one
function Log.Sample(id, quality, level, classID, salvager)
  local store = Store()
  return store and store.samples and store.samples[Log.SampleKey(id, quality, level, classID, salvager)]
end

local function Add(store, event)
  store.samples = store.samples or {}
  local key = Log.SampleKey(event.item, event.quality, event.level, event.classID, event.salvager)
  local sample = SampleIn(store.samples, key)
  sample.count = sample.count + 1
  for id, qty in pairs(event.materials) do AddMaterial(sample, id, 1, qty) end
end

-- What a disenchant needs to know about its item: nil unless it is weapon or armor with known info
local function Describe(id)
  if not (id and C_Item and C_Item.GetItemInfo) then return nil end
  local _, _, quality, level, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(id)
  if not (quality and level and (classID == WEAPON or classID == ARMOR)) then return nil end
  return { id = id, quality = quality, level = level, classID = classID }
end

local function FromItems(slots)
  if #slots == 0 then return false end
  for _, slot in ipairs(slots) do
    local sources = slot.sources or {}   -- guid, quantity, guid, quantity, ...
    if not ns.Kills.IsItemSource(sources[1]) then return false end
    for i = 1, sources.n or #sources, 2 do
      if not ns.Kills.IsItemSource(sources[i]) then return false end
    end
  end
  return true
end

-- Materials in a window, { [itemID] = quantity }, summed across slots
local function Materials(slots)
  local out = {}
  for _, slot in ipairs(slots) do
    local id = ns.ItemID(slot.link)
    if id then out[id] = (out[id] or 0) + (slot.quantity or 1) end
  end
  return out
end

-- emit: Recording.Emit
function Log.NewTracker(emit)
  local tracker = {}

  -- A Disenchant cast started on item (from Describe, nil when unknown), with Salvager active or not
  function tracker:Started(item, salvager)
    self.casting = item and { item = item, salvager = salvager }
  end

  function tracker:Stopped()
    self.casting = nil
  end

  -- The cast finished; item and salvager stand in when the start named no item
  function tracker:Succeeded(t, item, salvager)
    local cast = self.casting or (item and { item = item, salvager = salvager })
    self.casting = nil
    self.pending = cast and { item = cast.item, salvager = cast.salvager, t = t }
  end

  -- A loot window opened; slots as in Kills.SplitLoot
  function tracker:Loot(slots, t)
    local cast = self.pending
    self.pending = nil
    if not cast or t - cast.t > CAST_WINDOW or not FromItems(slots) then return end
    local materials = Materials(slots)
    if not next(materials) then return end
    local item = cast.item
    emit({ t = t, kind = "disenchant", source = "item:" .. item.id, item = item.id, quality = item.quality,
      level = item.level, classID = item.classID, salvager = cast.salvager == true, materials = materials })
  end

  return tracker
end

-- Disenchantry keys samples "version:build:itemID:quality:itemLevel:classID:mode"
local function ParseDisenchantryKey(key)
  if type(key) ~= "string" then return nil end
  local id, quality, level, classID, mode = string.match(key, ":(%d+):(%d+):(%d+):(%d+):(%a+)$")
  if not (mode == "salvager" or mode == "normal") then return nil end
  return tonumber(id), tonumber(quality), tonumber(level), tonumber(classID), mode == "salvager"
end

local function ValidSample(sample)
  if type(sample) ~= "table" or type(sample.count) ~= "number" or type(sample.materials) ~= "table" then
    return false
  end
  for id, m in pairs(sample.materials) do
    if type(id) ~= "number" or type(m) ~= "table" or type(m.hits) ~= "number" or type(m.total) ~= "number" then
      return false
    end
  end
  return true
end

-- Adds every valid Disenchantry sample to MarketWall's; returns the number of results copied
local function CopySamples(store, samples)
  store.samples = store.samples or {}
  local copied = 0
  for key, sample in pairs(type(samples) == "table" and samples or {}) do
    local id, quality, level, classID, salvager = ParseDisenchantryKey(key)
    if id and level > 0 and ValidSample(sample) and sample.count > 0 then
      local target = SampleIn(store.samples, Log.SampleKey(id, quality, level, classID, salvager))
      target.count = target.count + sample.count
      for materialID, m in pairs(sample.materials) do
        if m.hits > 0 and m.total > 0 then AddMaterial(target, materialID, m.hits, m.total) end
      end
      copied = copied + sample.count
    end
  end
  return copied
end

local function CopySettings(cfg, disenchantry)
  local mode = disenchantry.salvagerMode
  if mode == "auto" or mode == "on" or mode == "off" then cfg.salvagerMode = mode end
  local bonus = tonumber(disenchantry.salvagerBonusPercent)
  if bonus and bonus >= 0 and bonus <= 1000 then cfg.salvagerBonus = bonus end
end

local function Import(store, cfg, disenchantry)
  if store.imported or type(disenchantry) ~= "table" then return end
  local copied = CopySamples(store, disenchantry.disenchantSamples)
  CopySettings(cfg, disenchantry)
  store.imported = true
  ns.Print("Imported " .. copied .. " disenchant results from Disenchantry.")
end

-- In game -----------------------------------------------------------------------------------

local tracker = Log.NewTracker(function(event) ns.Recording.Emit(event) end)
Log.tracker = tracker

ns.Recording.On("disenchant", function(event)
  local store = Store()
  if store then Add(store, event) end
end)

-- The item ID locked in your bags, nil when none or several are
local function LockedBagItem()
  if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
  local found
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.isLocked and info.itemID then
        if found then return nil end
        found = info.itemID
      end
    end
  end
  return found
end

local function CastItem()
  return Describe(LockedBagItem()), ns.SalvagerActive()
end

local HANDLERS = {
  UNIT_SPELLCAST_START = function() tracker:Started(CastItem()) end,
  UNIT_SPELLCAST_SUCCEEDED = function() tracker:Succeeded(time(), CastItem()) end,
  UNIT_SPELLCAST_FAILED = function() tracker:Stopped() end,
  UNIT_SPELLCAST_INTERRUPTED = function() tracker:Stopped() end,
}

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do frame:RegisterUnitEvent(event, "player") end
frame:SetScript("OnEvent", function(_, event, _, _, spellID)
  if spellID == DISENCHANT then HANDLERS[event]() end
end)

function Log.Start()
  local store = Store()
  if store then Import(store, MarketWallDB.cfg, DisenchantryDB) end
end
