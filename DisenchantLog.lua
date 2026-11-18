-- MarketWall: the disenchant log. Each of your disenchants becomes a "disenchant" event in the
-- recording core, and its materials are added to the results for its item kind, which
-- Disenchant.lua prefers over estimates once a kind has 20 of them.
--
-- Pairing a disenchant with its loot: when a Disenchant cast (spell 13262) starts, the item under
-- it is the one locked in your bags; the cast locks its target however it was aimed (a click, a
-- macro or another add-on's button). Two locked items at once are ambiguous and record nothing.
-- On success, the next loot window, within a few seconds, whose every slot comes from an Item
-- source holds the materials. Any window consumes the cast, as with Kills.lua's gathering casts.
--
-- Saved in MarketWallDB.disenchants, shared by every character:
--   samples  [kind] = { count = disenchants, materials = { [itemID] = { hits =, total = } } }
--            where kind is "quality:levels:classID:mode", e.g. "2:26-30:4:normal" (see KindKey)
--   imported [Disenchantry key] = { count =, materials = { [itemID] = { hits =, total = } } }
--            the watermark of each Disenchantry sample already merged
--   importedAt  when Disenchantry was first imported
local _, ns = ...

local Log = {}
ns.DisenchantLog = Log

local DISENCHANT = 13262
local CAST_WINDOW = 3   -- seconds after the cast in which a loot window is its result
local WEAPON, ARMOR = 2, 4

-- Item kinds group item levels in fives (1-5, 6-10, ...), which line up with the classic tables
function Log.KindKey(quality, level, classID, salvager)
  local low = math.floor((level - 1) / 5) * 5 + 1
  return table.concat({ quality, low .. "-" .. (low + 4), classID, salvager and "salvager" or "normal" }, ":")
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

-- Your results for an item kind, nil before the first one
function Log.Sample(quality, level, classID, salvager)
  local store = Store()
  return store and store.samples and store.samples[Log.KindKey(quality, level, classID, salvager)]
end

-- Adds one disenchant event to the samples
function Log.Add(store, event)
  store.samples = store.samples or {}
  local sample = SampleIn(store.samples, Log.KindKey(event.quality, event.level, event.classID, event.salvager))
  sample.count = sample.count + 1
  for id, qty in pairs(event.materials) do AddMaterial(sample, id, 1, qty) end
end

-- What a disenchant needs to know about its item: nil unless it is weapon or armor with known info
function Log.Describe(id)
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
    local id = type(slot.link) == "string" and tonumber(string.match(slot.link, "item:(%d+)"))
    if id then out[id] = (out[id] or 0) + (slot.quantity or 1) end
  end
  return out
end

-- emit: Recording.Emit
function Log.NewTracker(emit)
  local tracker = {}

  -- A Disenchant cast started on item (from Describe, nil when unknown) with Salvager's buff up or not
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
  local item, quality, level, classID, mode = string.match(key, ":(%d+):(%d+):(%d+):(%d+):(%a+)$")
  if not (mode == "salvager" or mode == "normal") then return nil end
  return tonumber(quality), tonumber(level), tonumber(classID), mode == "salvager", item
end

-- The item part of a Disenchantry key, "itemID:quality:itemLevel:classID", to match your own events
local function ItemKey(item, quality, level, classID)
  return table.concat({ item, quality, level, classID }, ":")
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

local function Watermark(sample)
  local mark = { count = sample.count, materials = {} }
  for id, m in pairs(sample.materials) do mark.materials[id] = { hits = m.hits, total = m.total } end
  return mark
end

local NONE = { count = 0, materials = {} }

-- Each valid Disenchantry sample with its key's parts and its watermark of what was already
-- imported. A sample whose count fell below its watermark was reset, so all of it is new.
local function EachSample(store, disenchantry, fn)
  store.samples, store.imported = store.samples or {}, store.imported or {}
  local samples = type(disenchantry) == "table" and disenchantry.disenchantSamples
  if type(samples) ~= "table" then return end
  for key, sample in pairs(samples) do
    local quality, level, classID, salvager, item = ParseDisenchantryKey(key)
    if quality and level > 0 and ValidSample(sample) then
      local mark = store.imported[key] or NONE
      if sample.count < mark.count then mark = NONE end
      fn(key, sample, mark, quality, level, classID, salvager, item)
    end
  end
end

-- Adds each Disenchantry sample's results past its watermark to MarketWall's samples and moves
-- the watermark up to its current counts. Returns the number of results merged.
function Log.Sync(store, disenchantry)
  local merged = 0
  EachSample(store, disenchantry, function(key, sample, mark, quality, level, classID, salvager)
    local added = sample.count - mark.count
    if added > 0 then
      local target = SampleIn(store.samples, Log.KindKey(quality, level, classID, salvager))
      target.count = target.count + added
      for id, m in pairs(sample.materials) do
        local seen = mark.materials[id] or NONE
        local hits, total = m.hits - (seen.hits or 0), m.total - (seen.total or 0)
        if hits > 0 and total > 0 then AddMaterial(target, id, hits, total) end
      end
      merged = merged + added
    end
    store.imported[key] = Watermark(sample)
  end)
  return merged
end

-- Disenchantry's Salvager setting becomes MarketWall's, once
function Log.ImportSettings(cfg, disenchantry)
  local mode = disenchantry.salvagerMode
  if mode == "auto" or mode == "on" or mode == "off" then cfg.salvagerMode = mode end
  local bonus = tonumber(disenchantry.salvagerBonusPercent)
  if bonus and bonus >= 0 and bonus <= 1000 then cfg.salvagerBonus = bonus end
end

-- At login, while Disenchantry is enabled: the first time copies its log and Salvager setting;
-- later logins merge only results it logged since, such as while MarketWall was off.
function Log.Import(store, cfg, disenchantry)
  if type(disenchantry) ~= "table" then return end
  local merged = Log.Sync(store, disenchantry)
  if not store.importedAt then
    store.importedAt = time()
    Log.ImportSettings(cfg, disenchantry)
    ns.Print("Imported " .. merged .. " disenchant results from Disenchantry.")
  end
end

-- At logout: the results Disenchantry logged this session that MarketWall recorded itself are
-- marked as imported, so next login merges only the ones MarketWall missed. recorded is this
-- session's disenchant events by ItemKey; each one accounts for at most one Disenchantry result.
function Log.MarkSeen(store, disenchantry, recorded)
  if not store.importedAt then return end
  EachSample(store, disenchantry, function(key, sample, mark, quality, level, classID, _, item)
    local own = recorded[ItemKey(item, quality, level, classID)]
    local added = sample.count - mark.count
    if not own or added <= 0 then return end
    local seen = Watermark(mark)
    for _ = 1, math.min(added, #own) do
      local event = table.remove(own, 1)
      seen.count = seen.count + 1
      for id, qty in pairs(event.materials) do
        local m = seen.materials[id] or { hits = 0, total = 0 }
        m.hits, m.total = m.hits + 1, m.total + qty
        seen.materials[id] = m
      end
    end
    store.imported[key] = seen
  end)
end

-- In game -----------------------------------------------------------------------------------

local tracker = Log.NewTracker(function(event) ns.Recording.Emit(event) end)
Log.tracker = tracker

local recorded = {}   -- this session's disenchant events by ItemKey, for MarkSeen at logout

ns.Recording.On("disenchant", function(event)
  local store = Store()
  if store then Log.Add(store, event) end
  local key = ItemKey(event.item, event.quality, event.level, event.classID)
  recorded[key] = recorded[key] or {}
  table.insert(recorded[key], event)
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
  return Log.Describe(LockedBagItem()), ns.SalvagerActive()
end

local HANDLERS = {
  UNIT_SPELLCAST_START = function() tracker:Started(CastItem()) end,
  UNIT_SPELLCAST_SUCCEEDED = function() tracker:Succeeded(time(), CastItem()) end,
  UNIT_SPELLCAST_FAILED = function() tracker:Stopped() end,
  UNIT_SPELLCAST_INTERRUPTED = function() tracker:Stopped() end,
}

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do frame:RegisterUnitEvent(event, "player") end
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, _, _, spellID)
  if event == "PLAYER_LOGOUT" then
    local store = Store()
    if store then Log.MarkSeen(store, DisenchantryDB, recorded) end
  elseif spellID == DISENCHANT then
    HANDLERS[event]()
  end
end)

function Log.Start()
  local store = Store()
  if store then Log.Import(store, MarketWallDB.cfg, DisenchantryDB) end
end
