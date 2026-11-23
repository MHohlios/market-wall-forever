local addon = require("spec.helpers.addon")

local WEAPON, ARMOR, CONSUMABLE = 2, 4, 0
local UNCOMMON, RARE = 2, 3
local STRANGE_DUST, LESSER_MAGIC_ESSENCE, SMALL_RADIANT_SHARD = 10940, 10938, 11084
local LOW_CRAFT_ID = 250620     -- one of Forever's crafted items with an estimate
local CLASSIC = "Classic table"

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

  -- The item's outcomes by material ID, and where the odds come from
  local function OutcomesByID(id)
    local list, source = ns.DisenchantOutcomes(id)
    local byID = {}
    for _, o in ipairs(list) do byID[o.id] = o end
    return byID, source
  end

  it("prices green armor from the classic table", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    -- 80% for 1.5 dust at 100, 20% for 1.5 essence at 1000
    local value, source = ns.DisenchantValue(1001)
    assert.near(420, value, 1e-6)
    assert.equal(CLASSIC, source)
  end)

  it("uses Forever's estimate for its new crafts", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    assert.same({ 700, "Forever estimate" }, { ns.DisenchantValue(LOW_CRAFT_ID) })
  end)

  it("estimates Forever's new rares by item level", function()
    Item(200001, RARE, 30, ARMOR)
    assert.same({ 400, "Forever estimate" }, { ns.DisenchantValue(200001) })
  end)

  describe("blending your own results with the prior", function()
    -- Level 10 green armor's table: 80% for 1-2 dust, 20% for 1-2 essence, counted as 50 disenchants
    before_each(function() Item(1001, UNCOMMON, 10, ARMOR) end)

    it("is the prior alone with no results of your own", function()
      Observe(1001, 0, {})
      local value, source = ns.DisenchantValue(1001)
      assert.near(420, value, 1e-6)
      assert.equal(CLASSIC, source)
    end)

    it("stays mostly the prior after 20 disenchants that all gave dust", function()
      Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
      local byID, source = OutcomesByID(1001)
      assert.equal("Classic table + your 20 disenchants", source)
      assert.near((40 + 20) / 70, byID[STRANGE_DUST].chance, 1e-9)
      assert.near(10 / 70, byID[LESSER_MAGIC_ESSENCE].chance, 1e-9)   -- nearer the table's 20% than your 0%
      -- dust 6/7 × 100/60 × 100, essence 1/7 × 1.5 × 1000
      assert.near(1000 / 7 + 1500 / 7, (ns.DisenchantValue(1001)), 1e-6)
    end)

    it("is mostly your own after 500 disenchants", function()
      Observe(1001, 500, { [STRANGE_DUST] = { hits = 500, total = 1000 } })
      local byID = OutcomesByID(1001)
      assert.near(540 / 550, byID[STRANGE_DUST].chance, 1e-9)
      assert.near(10 / 550, byID[LESSER_MAGIC_ESSENCE].chance, 1e-9)
    end)

    it("averages the quantity over every drop, the prior's and yours", function()
      Observe(1001, 10, { [STRANGE_DUST] = { hits = 10, total = 40 } })
      -- (50 × 0.8 × 1.5 + 40) / (50 × 0.8 + 10)
      assert.near(2, OutcomesByID(1001)[STRANGE_DUST].quantity, 1e-9)
    end)

    it("adds a material only your results have", function()
      Observe(1001, 10, { [STRANGE_DUST] = { hits = 8, total = 12 }, [SMALL_RADIANT_SHARD] = { hits = 2, total = 2 } })
      local shard = OutcomesByID(1001)[SMALL_RADIANT_SHARD]
      assert.near(2 / 60, shard.chance, 1e-9)
      assert.equal(1, shard.quantity)
    end)

    it("widens the table's range with the fewest and most you recorded", function()
      Observe(1001, 5, { [STRANGE_DUST] = { hits = 5, total = 15, min = 2, max = 4 },
        [LESSER_MAGIC_ESSENCE] = { hits = 1, total = 1 } })   -- saved before ranges were recorded
      local byID = OutcomesByID(1001)
      assert.same({ 1, 4 }, { byID[STRANGE_DUST].min, byID[STRANGE_DUST].max })
      assert.same({ 1, 2 }, { byID[LESSER_MAGIC_ESSENCE].min, byID[LESSER_MAGIC_ESSENCE].max })
    end)
  end)

  it("gives an estimate an average without a range, even after your own results", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Observe(LOW_CRAFT_ID, 3, { [STRANGE_DUST] = { hits = 3, total = 6, min = 2, max = 2 } })
    local dust, source = OutcomesByID(LOW_CRAFT_ID)
    dust = dust[STRANGE_DUST]
    assert.equal("Forever estimate + your 3 disenchants", source)
    assert.is_nil(dust.min)
    assert.is_nil(dust.max)
  end)

  it("names a single disenchant in the singular", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Observe(1001, 1, { [STRANGE_DUST] = { hits = 1, total = 1 } })
    assert.equal("Classic table + your 1 disenchant", select(2, ns.DisenchantValue(1001)))
  end)

  describe("with no table or estimate", function()
    -- uncommon armor above the classic table's item levels
    before_each(function() Item(1001, UNCOMMON, 70, ARMOR) end)

    it("has no value below 20 disenchants of your own", function()
      Observe(1001, 19, { [STRANGE_DUST] = { hits = 19, total = 38 } })
      assert.is_nil(ns.DisenchantValue(1001))
    end)

    it("uses your own results alone from 20 disenchants", function()
      Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40, min = 1, max = 3 } })
      assert.same({ 200, "Your 20 disenchants" }, { ns.DisenchantValue(1001) })
      local dust = OutcomesByID(1001)[STRANGE_DUST]
      assert.same({ 1, 2, 1, 3 }, { dust.chance, dust.quantity, dust.min, dust.max })
    end)
  end)

  it("keeps a Forever item's results out of its classic kind", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Item(1001, UNCOMMON, 10, ARMOR)
    Observe(LOW_CRAFT_ID, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    local value, source = ns.DisenchantValue(1001)
    assert.near(420, value, 1e-6)
    assert.equal(CLASSIC, source)
  end)

  it("keeps a classic kind's results out of a Forever item's estimate", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 10, ARMOR)
    Item(200001, RARE, 30, ARMOR)
    Item(1001, UNCOMMON, 10, ARMOR)
    Item(1002, RARE, 30, ARMOR)
    Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    Observe(1002, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    assert.same({ 700, "Forever estimate" }, { ns.DisenchantValue(LOW_CRAFT_ID) })
    assert.same({ 400, "Forever estimate" }, { ns.DisenchantValue(200001) })
  end)

  it("pools results across classic items of the same kind", function()
    Item(1001, UNCOMMON, 26, ARMOR)
    Item(1002, UNCOMMON, 30, ARMOR)   -- same quality, item levels 26-30 and armor
    Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    assert.equal("Classic table + your 20 disenchants", select(2, ns.DisenchantOutcomes(1002)))
    assert.equal(20, select(3, ns.DisenchantOutcomes(1002)))
  end)

  it("keeps weapons, armor and item-level buckets apart", function()
    Item(1001, UNCOMMON, 26, ARMOR)
    Item(1002, UNCOMMON, 26, WEAPON)
    Item(1003, UNCOMMON, 31, ARMOR)
    Observe(1001, 20, { [STRANGE_DUST] = { hits = 20, total = 40 } })
    assert.equal(CLASSIC, select(2, ns.DisenchantOutcomes(1002)))
    assert.equal(CLASSIC, select(2, ns.DisenchantOutcomes(1003)))
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

  it("blends your Salvager results with the table at its Salvager quantities, scaling only the table", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("on", 50)
    Observe(1001, 25, { [STRANGE_DUST] = { hits = 25, total = 75 } }, true)
    Observe(1001, 25, { [STRANGE_DUST] = { hits = 25, total = 25 } }, false)
    -- dust: 65/75 at (40 × 2.25 + 75) / 65, so 220; essence: 10/75 at 2.25 × 1000, so 300
    local value, source = ns.DisenchantValue(1001)
    assert.near(520, value, 1e-6)
    assert.equal("Classic table + your 25 disenchants", source)
  end)

  it("lists the outcomes with the Salvager bonus in their quantities and ranges, as the value counts it", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("on", 50)
    -- 1 to 2 scaled by 1.5 is 1.5 to 3: the range stays whole, 1 to 3, the average scaled
    assert.same({
      { { id = STRANGE_DUST, chance = 0.8, quantity = 2.25, min = 1, max = 3 },
        { id = LESSER_MAGIC_ESSENCE, chance = 0.2, quantity = 2.25, min = 1, max = 3 } },
      CLASSIC,
      0,
    }, { ns.DisenchantOutcomes(1001) })
    assert.is_nil(ns.DisenchantOutcomes(11287))
  end)

  it("widens a scaled range out to whole counts", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Salvager("on", 10)
    local outcomes = ns.DisenchantOutcomes(1001)
    assert.same({ 1, 3 }, { outcomes[1].min, outcomes[1].max })   -- 1.1 to 2.2
  end)

  it("adds up the deposits to list the materials, at their expected quantities", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    local deposits = { [STRANGE_DUST] = 10, [LESSER_MAGIC_ESSENCE] = 50 }
    local depositOf = function(id) return deposits[id] end
    -- 80% for 1.5 dust at 10 each, 20% for 1.5 essence at 50 each
    local value, _, materialDeposits = ns.DisenchantValue(1001, depositOf)
    assert.near(420, value, 1e-6)
    assert.near(12 + 15, materialDeposits, 1e-6)
    Salvager("on", 50)
    assert.near(27 * 1.5, select(3, ns.DisenchantValue(1001, depositOf)), 1e-6)
  end)

  it("counts no deposit for a rare material with no price, as it counts no value", function()
    -- Forever's new level 60 rare: 99.5% Large Brilliant Shard, 0.5% Nexus Crystal with no price
    local BRILLIANT, NEXUS = 14344, 20725
    Item(200001, RARE, 60, ARMOR)
    ns.LatestWall = function(id) if id == BRILLIANT then return 1000 end end
    local deposits = { [BRILLIANT] = 100, [NEXUS] = 10000 }
    local value, _, materialDeposits = ns.DisenchantValue(200001, function(id) return deposits[id] end)
    assert.near(995, value, 1e-6)
    assert.near(99.5, materialDeposits, 1e-6)
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
