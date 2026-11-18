local addon = require("spec.helpers.addon")

local WEAPON, ARMOR, CONSUMABLE = 2, 4, 0
local COMMON, UNCOMMON = 1, 2
local STRANGE_DUST, LESSER_MAGIC_ESSENCE = 10940, 10938
local LOW_CRAFT_ID = 250620     -- one of Forever's crafted items with an estimate
local CUT = 0.05

describe("FindDisenchantDeals", function()
  local ns, items, prices

  before_each(function()
    ns = addon.Load()
    prices = { [STRANGE_DUST] = 100, [LESSER_MAGIC_ESSENCE] = 1000 }
    ns.LatestWall = function(id) return prices[id] end
    items = {}
    _G.C_Item = {
      GetItemInfo = function(id)
        local item = items[id]
        if not item then return nil end
        return "item", "link", item.quality, item.level, 1, "", "", 1, "", 0, 0, item.classID
      end,
    }
    _G.GetBuildInfo = function() return "1.15.0", "12345" end
  end)

  after_each(function()
    _G.C_Item, _G.GetBuildInfo = nil, nil
  end)

  local function Item(id, quality, level, classID)
    items[id] = { quality = quality, level = level, classID = classID }
  end

  -- Green level-10 armor disenchants for 420 (80% of 1.5 dust at 100, 20% of 1.5 essence at
  -- 1000), so 399 after the 5% cut
  it("keeps gear listed under its value after the cut", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    local deals = ns.FindDisenchantDeals({ [1001] = 300 }, CUT, 0, 0)
    assert.equal(1, #deals)
    local d = deals[1]
    assert.equal(1001, d.id)
    assert.equal(300, d.price)
    assert.near(399, d.value, 1e-6)
    assert.near(99, d.profit, 1e-6)
    assert.near(0.33, d.pct, 1e-6)
    assert.equal("classic table", d.odds)
    assert.equal(1, d.skill)
  end)

  it("leaves out gear priced over its value after the cut, though under its value before it", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 410 }, CUT, 0, 0))
  end)

  it("applies the minimum profit", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    assert.equal(1, #ns.FindDisenchantDeals({ [1001] = 300 }, CUT, 98, 0))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 300 }, CUT, 100, 0))
  end)

  it("applies the minimum profit %", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    assert.equal(1, #ns.FindDisenchantDeals({ [1001] = 300 }, CUT, 0, 0.32))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 300 }, CUT, 0, 0.34))
  end)

  it("leaves out items whose likely materials have no price", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    prices[LESSER_MAGIC_ESSENCE] = nil
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 1 }, CUT, 0, 0))
  end)

  it("leaves out items below uncommon, non-gear and uncached items", function()
    Item(1001, COMMON, 10, ARMOR)
    Item(LOW_CRAFT_ID, UNCOMMON, 10, CONSUMABLE)   -- has an estimate, but is not gear
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 1, [LOW_CRAFT_ID] = 1, [9999] = 1 }, CUT, 0, 0))
  end)

  it("names the source of the odds and the skill each item needs", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 30, WEAPON)
    local d = ns.FindDisenchantDeals({ [LOW_CRAFT_ID] = 1 }, CUT, 0, 0)[1]
    assert.equal("Forever estimate", d.odds)
    assert.equal(50, d.skill)
  end)

  it("puts the most profit first", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Item(1002, UNCOMMON, 10, WEAPON)   -- weapons lean to essence: 1230, so 1168.5 after the cut
    Item(1003, UNCOMMON, 12, ARMOR)
    local deals = ns.FindDisenchantDeals({ [1001] = 300, [1002] = 300, [1003] = 200 }, CUT, 0, 0)
    assert.same({ 1002, 1003, 1001 }, { deals[1].id, deals[2].id, deals[3].id })
  end)
end)

describe("DisenchantSkill", function()
  local ns = addon.Load()

  it("needs 1 skill up to item level 20", function()
    assert.equal(1, ns.DisenchantSkill(1))
    assert.equal(1, ns.DisenchantSkill(20))
  end)

  it("needs 25 more for every 5 levels after that", function()
    assert.equal(25, ns.DisenchantSkill(21))
    assert.equal(25, ns.DisenchantSkill(25))
    assert.equal(50, ns.DisenchantSkill(26))
    assert.equal(200, ns.DisenchantSkill(60))
  end)

  it("tops out at 225 from item level 61", function()
    assert.equal(225, ns.DisenchantSkill(61))
    assert.equal(225, ns.DisenchantSkill(88))
  end)
end)

describe("EnchantingSkill", function()
  local ns
  local lines

  before_each(function()
    ns = addon.Load()
    lines = {}
    _G.GetNumSkillLines = function() return #lines end
    _G.GetSkillLineInfo = function(i) return unpack(lines[i]) end
  end)

  after_each(function()
    _G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
  end)

  it("reads the rank from the skill list", function()
    lines = { { "Professions", true, true }, { "Tailoring", false, nil, 150 }, { "Enchanting", false, nil, 225 } }
    assert.equal(225, ns.EnchantingSkill())
  end)

  it("is 0 without Enchanting", function()
    lines = { { "Professions", true, true }, { "Tailoring", false, nil, 150 } }
    assert.equal(0, ns.EnchantingSkill())
  end)

  it("is unknown while a collapsed section could hide it", function()
    lines = { { "Professions", true, false } }
    assert.is_nil(ns.EnchantingSkill())
  end)

  it("is unknown when the game has no skill API", function()
    _G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
    assert.is_nil(ns.EnchantingSkill())
  end)
end)
