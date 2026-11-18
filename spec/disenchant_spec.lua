local addon = require("spec.helpers.addon")

local WEAPON, ARMOR, CONSUMABLE = 2, 4, 0
local UNCOMMON, RARE = 2, 3
local STRANGE_DUST, LESSER_MAGIC_ESSENCE, SMALL_RADIANT_SHARD = 10940, 10938, 11084
local LOW_CRAFT_ID = 250620     -- one of Forever's crafted items with an estimate

describe("DisenchantValue", function()
  local ns, items

  before_each(function()
    ns = addon.Load()
    local prices = { [STRANGE_DUST] = 100, [LESSER_MAGIC_ESSENCE] = 1000, [SMALL_RADIANT_SHARD] = 400 }
    ns.LatestWall = function(id) return prices[id] end
    items = {}
    _G.C_Item = {
      GetItemInfo = function(id)
        local item = items[id]
        if not item then return nil end
        return "item", "link", item.quality, item.level, 1, "", "", 1, "", 0, 0, item.classID
      end,
    }
    _G.MarketWallDB = { cfg = {}, disenchants = { samples = {} } }
  end)

  after_each(function()
    _G.C_Item, _G.MarketWallDB, _G.C_UnitAuras = nil, nil, nil
  end)

  local function Item(id, quality, level, classID)
    items[id] = { quality = quality, level = level, classID = classID }
  end

  -- MarketWall's log holding an item's results, under Salvager or not
  local function Observe(id, count, materials, salvager)
    local item = items[id]
    local key = ns.DisenchantLog.SampleKey(id, item.quality, item.level, item.classID, salvager)
    MarketWallDB.disenchants.samples[key] = { count = count, materials = materials }
  end

  local function Salvager(mode, bonus)
    MarketWallDB.cfg.salvagerMode, MarketWallDB.cfg.salvagerBonus = mode, bonus
  end

  it("prices green armor from the classic table", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    -- 80% for 1.5 dust at 100, 20% for 1.5 essence at 1000
    local value, note = ns.DisenchantValue(1001)
    assert.near(420, value, 1e-6)
    assert.is_nil(note)
  end)

  it("uses Forever's estimate for its new crafts", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    assert.same({ 700, "estimate" }, { ns.DisenchantValue(LOW_CRAFT_ID) })
  end)

  it("estimates Forever's new rares by item level", function()
    Item(200001, RARE, 30, ARMOR)
    assert.same({ 400, "estimate" }, { ns.DisenchantValue(200001) })
  end)

  it("prefers your own results once there are 20 of them", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Observe(LOW_CRAFT_ID, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    assert.same({ 200, "your 20 disenchants" }, { ns.DisenchantValue(LOW_CRAFT_ID) })
  end)

  it("ignores your own results below 20 samples", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Observe(LOW_CRAFT_ID, 19, { [STRANGE_DUST] = { hits = 19, total = 38 } })
    assert.same({ 700, "estimate" }, { ns.DisenchantValue(LOW_CRAFT_ID) })
  end)

  it("keeps a Forever item's results out of its classic kind", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Item(1001, UNCOMMON, 10, ARMOR)
    Observe(LOW_CRAFT_ID, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    local value, note = ns.DisenchantValue(1001)
    assert.near(420, value, 1e-6)   -- the classic table
    assert.is_nil(note)
  end)

  it("keeps a Forever item's estimate until it has 20 results of its own", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Item(200001, RARE, 30, ARMOR)
    Item(1001, UNCOMMON, 10, ARMOR)
    Item(1002, RARE, 30, ARMOR)
    Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    Observe(1002, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    assert.same({ 700, "estimate" }, { ns.DisenchantValue(LOW_CRAFT_ID) })
    assert.same({ 400, "estimate" }, { ns.DisenchantValue(200001) })
  end)

  it("pools results across classic items of the same kind", function()
    Item(1001, UNCOMMON, 26, ARMOR)
    Item(1002, UNCOMMON, 30, ARMOR)   -- same quality, item levels 26-30 and armor
    Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    assert.same({ 200, "your 20 disenchants" }, { ns.DisenchantValue(1002) })
  end)

  it("keeps weapons, armor and item-level buckets apart", function()
    Item(1001, UNCOMMON, 26, ARMOR)
    Item(1002, UNCOMMON, 26, WEAPON)
    Item(1003, UNCOMMON, 31, ARMOR)
    Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    local _, weaponNote = ns.DisenchantValue(1002)
    local _, higherNote = ns.DisenchantValue(1003)
    assert.not_equal("your 20 disenchants", weaponNote)
    assert.not_equal("your 20 disenchants", higherNote)
  end)

  it("adds the Salvager bonus to table values when set on", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("on", 50)
    assert.near(630, (ns.DisenchantValue(1001)), 1e-6)
  end)

  it("adds the Salvager bonus on auto only while the buff is up", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("auto", 50)
    local buff = false
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() return buff and {} or nil end }
    assert.near(420, (ns.DisenchantValue(1001)), 1e-6)
    buff = true
    assert.near(630, (ns.DisenchantValue(1001)), 1e-6)
  end)

  it("never adds the Salvager bonus when set off", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("off", 50)
    _G.C_UnitAuras = { GetPlayerAuraBySpellID = function() return {} end }
    assert.near(420, (ns.DisenchantValue(1001)), 1e-6)
  end)

  it("does not add the Salvager bonus again to your own Salvager results", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("on", 50)
    Observe(1001, 25, { [STRANGE_DUST] = { hits = 25, total = 75 } }, true)
    Observe(1001, 25, { [STRANGE_DUST] = { hits = 25, total = 25 } }, false)
    assert.same({ 300, "your 25 disenchants" }, { ns.DisenchantValue(1001) })
  end)

  it("is false while a likely material has no price", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    ns.LatestWall = function(id) if id == STRANGE_DUST then return 100 end end
    assert.is_false(ns.DisenchantValue(1001))
  end)

  it("is nil for items that cannot be disenchanted", function()
    Item(11287, UNCOMMON, 10, ARMOR)   -- an enchanter-made wand
    Item(1002, UNCOMMON, 10, CONSUMABLE)
    assert.is_nil(ns.DisenchantValue(11287))
    assert.is_nil(ns.DisenchantValue(1002))
    assert.is_nil(ns.DisenchantValue(9999))   -- not cached yet
  end)
end)
