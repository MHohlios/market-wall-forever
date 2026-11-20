local addon = require("spec.helpers.addon")

local CUT = 0.05
local TODAY = 20000
local THREAD, CLOTH, PRODUCT, PATTERN = 1, 2, 3, 4

describe("Crafting", function()
  local C

  before_each(function()
    local ns = addon.Load()
    C = ns.Crafting
  end)

  -- Prices with no deposits or disenchanting: buy is the vendor's price for vendor-sold reagents,
  -- walls are { price, supplied }
  local function Prices(p)
    return {
      buy = function(id) return (p.buy or {})[id] end,
      vendor = function(id) return (p.vendor or {})[id] end,
      wall = function(id)
        local wall = (p.walls or {})[id]
        if wall then return wall[1], wall[2] end
      end,
      deposit = function() return 0 end,
      disenchant = function() return nil end,
    }
  end

  local function Recipe(fields)
    local recipe = { product = PRODUCT, made = 1, reagents = { { THREAD, 2 }, { CLOTH, 3 } } }
    for k, v in pairs(fields or {}) do recipe[k] = v end
    return recipe
  end

  local function Day(units) return { 100, 100, 100, units, 90 } end

  local function Evaluate(recipe, p, extra)
    local at = { prices = Prices(p), opts = { cut = CUT }, today = TODAY,
      days = function(id) return (p.days or {})[id] end }
    for k, v in pairs(extra or {}) do at[k] = v end
    return C.Evaluate(recipe, at)
  end

  describe("mats cost", function()
    it("prices a vendor-sold reagent at the vendor and any other at its wall", function()
      local cost, lines = C.Cost(Recipe(), Prices({ buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true } } }))
      assert.equal(2 * 10 + 3 * 100, cost)
      assert.same({ "vendor", 10, 20 }, { lines[1].source, lines[1].unit, lines[1].cost })
      assert.same({ "wall", 100, 300 }, { lines[2].source, lines[2].unit, lines[2].cost })
    end)

    it("uses the vendor's price even when the reagent also has a wall", function()
      local cost = C.Cost(Recipe(), Prices({ buy = { [THREAD] = 10, [CLOTH] = 50 }, walls = { [CLOTH] = { 100, true } } }))
      assert.equal(2 * 10 + 3 * 50, cost)
    end)

    it("is unknown, never 0, when any reagent has no price", function()
      local cost, lines = C.Cost(Recipe(), Prices({ walls = { [CLOTH] = { 100, true } } }))
      assert.is_nil(cost)
      assert.same({ THREAD, 2 }, { lines[1].id, lines[1].count })
      assert.is_nil(lines[1].unit)
      assert.is_nil(lines[1].source)
    end)
  end)

  describe("profit", function()
    local p = { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true }, [PRODUCT] = { 1000, true } } }

    it("nets the product after the cut, less the mats cost, with the margin on cost", function()
      local e = Evaluate(Recipe(), p)
      assert.same({ 320, 950, 630 }, { e.cost, e.net, e.profit })
      assert.near(630 / 320, e.margin, 1e-9)
      assert.equal("auction", e.outlet.outlet)
    end)

    it("counts every unit a multi-output recipe makes", function()
      local e = Evaluate(Recipe({ made = 3 }), p)
      assert.same({ 2850, 2530 }, { e.net, e.profit })
    end)

    it("has no net or profit, rather than a loss, when nothing prices the product", function()
      local e = Evaluate(Recipe({ source = { kind = "trainer", cost = 500 } }), { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true } } })
      assert.equal(320, e.cost)
      assert.is_nil(e.net)
      assert.is_nil(e.profit)
      assert.is_nil(e.margin)
      assert.is_nil(e.payback)
      -- a vendor price alone still values it
      e = Evaluate(Recipe(), { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true } }, vendor = { [PRODUCT] = 400 } })
      assert.same({ 400, 80 }, { e.net, e.profit })
    end)

    it("has no profit or margin when the cost is unknown", function()
      local e = Evaluate(Recipe(), { walls = { [PRODUCT] = { 1000, true } } })
      assert.same({ 950 }, { e.net })
      assert.is_nil(e.profit)
      assert.is_nil(e.margin)
    end)
  end)

  describe("payback", function()
    it("rounds learn cost over profit up", function()
      assert.equal(4, C.Payback(1000, 300))
      assert.equal(2, C.Payback(1000, 500))
    end)

    it("is never when a craft makes no profit", function()
      assert.equal(C.NEVER, C.Payback(1000, 0))
      assert.equal(C.NEVER, C.Payback(1000, -50))
    end)

    it("is unknown without a learn cost or a profit", function()
      assert.is_nil(C.Payback(nil, 300))
      assert.is_nil(C.Payback(1000, nil))
    end)

    it("prices learning at the pattern's wall when listed, else its vendor or trainer cost", function()
      local vendor = Recipe({ pattern = PATTERN, source = { kind = "vendor", cost = 5000 } })
      assert.same({ 2000, "wall" }, { C.LearnCost(vendor, Prices({ walls = { [PATTERN] = { 2000, false } } })) })
      assert.same({ 5000, "vendor" }, { C.LearnCost(vendor, Prices({})) })
      assert.same({ 300, "trainer" }, { C.LearnCost(Recipe({ source = { kind = "trainer", cost = 300 } }), Prices({})) })
      assert.same({}, { C.LearnCost(Recipe({ pattern = PATTERN, source = { kind = "drop" } }), Prices({})) })
    end)

    it("comes out of an evaluation", function()
      local recipe = Recipe({ source = { kind = "trainer", cost = 2000 } })
      local e = Evaluate(recipe, { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true }, [PRODUCT] = { 1000, true } } })
      assert.same({ 2000, "trainer", 4 }, { e.learnCost, e.learnSource, e.payback })
    end)
  end)

  describe("market", function()
    local function Days(spec)
      local days = {}
      for day, units in pairs(spec) do days[day] = Day(units) end
      return days
    end

    it("has no data without daily records", function()
      assert.same({ level = C.NO_DATA, units = 0, recent = 0 }, C.Market(nil, TODAY, false))
      assert.same({ level = C.NO_DATA, units = 0, recent = 0 }, C.Market({}, TODAY, false))
    end)

    it("is thin when the latest listings had no real supply", function()
      local days = Days({ [TODAY] = 60, [TODAY - 1] = 60, [TODAY - 2] = 60, [TODAY - 3] = 60, [TODAY - 4] = 60 })
      assert.equal(C.THIN, C.Market(days, TODAY, false).level)
    end)

    it("is deep with 40 listed on the latest day and records on 5 of the last 7 days", function()
      local days = Days({ [TODAY] = 40, [TODAY - 2] = 5, [TODAY - 3] = 5, [TODAY - 5] = 5, [TODAY - 6] = 5 })
      assert.same({ level = C.DEEP, units = 40, recent = 5 }, C.Market(days, TODAY, true))
    end)

    it("is steady with fewer units or fewer recent days", function()
      local few = Days({ [TODAY] = 39, [TODAY - 1] = 50, [TODAY - 2] = 50, [TODAY - 3] = 50, [TODAY - 4] = 50 })
      assert.equal(C.STEADY, C.Market(few, TODAY, true).level)
      -- a record 7 days ago is outside the last 7 days
      local patchy = Days({ [TODAY] = 80, [TODAY - 1] = 80, [TODAY - 2] = 80, [TODAY - 3] = 80, [TODAY - 7] = 80 })
      assert.same({ level = C.STEADY, units = 80, recent = 4 }, C.Market(patchy, TODAY, true))
    end)

    it("reads the latest recorded day's units, even when it is not today", function()
      assert.same({ level = C.STEADY, units = 12, recent = 1 }, C.Market(Days({ [TODAY - 3] = 12, [TODAY - 9] = 99 }), TODAY, true))
    end)

    it("comes out of an evaluation with the product's supplied flag", function()
      local p = { walls = { [PRODUCT] = { 1000, false } }, days = { [PRODUCT] = Days({ [TODAY] = 3 }) } }
      assert.equal(C.THIN, Evaluate(Recipe(), p).market.level)
    end)
  end)

  describe("skill colour", function()
    local recipe = Recipe({ skill = 200, skillUp = { 220, 235, 250 } })

    it("is red below the required skill", function()
      assert.equal(C.RED, C.SkillColour(recipe, 199))
      assert.equal(C.RED, C.SkillColour(Recipe({ skill = 200, colour = C.ORANGE }), 150))
    end)

    it("follows the thresholds from the required skill up", function()
      assert.same({ C.ORANGE, C.YELLOW, C.GREEN, C.GREY },
        { C.SkillColour(recipe, 200), C.SkillColour(recipe, 220), C.SkillColour(recipe, 235), C.SkillColour(recipe, 250) })
    end)

    it("takes the profession window's colour for a known recipe", function()
      assert.equal(C.GREEN, C.SkillColour(Recipe({ skill = 200, skillUp = { 220, 235, 250 }, colour = C.GREEN }), 205))
    end)

    it("is unknown without thresholds, a window colour or a rank", function()
      assert.is_nil(C.SkillColour(Recipe({ skill = 200 }), 210))
      assert.is_nil(C.SkillColour(recipe, nil))
    end)
  end)

  describe("ranking", function()
    local function E(product, profit, level)
      return { recipe = { product = product }, profit = profit, market = { level = level or C.STEADY } }
    end

    local function Order(evaluations)
      local products = {}
      for i, e in ipairs(C.Rank(evaluations)) do products[i] = e.recipe.product end
      return products
    end

    it("sorts by profit, unknown profit last", function()
      assert.same({ 2, 3, 1, 4 }, Order({ E(1, -5), E(2, 300), E(3, 10), E(4, nil) }))
    end)

    it("puts thin markets and those with no data after the rest at equal profit", function()
      assert.same({ 3, 4, 1, 2 }, Order({ E(1, 100, C.THIN), E(2, 100, C.NO_DATA), E(3, 100, C.DEEP), E(4, 100, C.STEADY) }))
      -- more profit still wins over a better market
      assert.same({ 1, 2 }, Order({ E(1, 101, C.THIN), E(2, 100, C.DEEP) }))
    end)
  end)

  describe("merging", function()
    local bundled = {
      { product = 10, name = "Bolt", made = 1, reagents = { { 1, 5 } }, skill = 250, pattern = 99,
        source = { kind = "vendor", cost = 500 } },
      { product = 11, name = "Robe", made = 1, reagents = { { 10, 3 } }, skill = 260, source = { kind = "trainer" } },
    }

    local function ByProduct(list)
      local out = {}
      for _, entry in ipairs(list) do out[entry.product] = entry end
      return out
    end

    it("lets a known recipe's data win and keeps the table's for the rest", function()
      local known = { [10] = { name = "Bolt", made = 2, reagents = { { 1, 4 } }, colour = C.YELLOW } }
      local merged = ByProduct(C.Merge(known, bundled))
      local bolt = merged[10]
      assert.same({ 2, { { 1, 4 } }, C.YELLOW, true }, { bolt.made, bolt.reagents, bolt.colour, bolt.known })
      assert.same({ 250, 99, "vendor" }, { bolt.skill, bolt.pattern, bolt.source.kind })
      assert.is_false(merged[11].known)
      assert.equal(1, bundled[1].made, "the table itself is left alone")
    end)

    it("keeps known recipes the table lacks, flagging Forever-only products", function()
      local known = { [200123] = { name = "Gleamweave Mantle", made = 1, reagents = { { 14048, 4 } } } }
      local merged = ByProduct(C.Merge(known, bundled))
      assert.same({ true, true }, { merged[200123].known, merged[200123].forever })
      assert.is_false(merged[10].forever)
      assert.equal(3, #C.Merge(known, bundled))
    end)

    it("makes a recipe with a saved trainer cost learned from that trainer, at that cost", function()
      local merged = ByProduct(C.Merge(nil, bundled, { [11] = 5000 }))
      assert.same({ kind = "trainer", cost = 5000 }, merged[11].source)
      assert.equal("vendor", merged[10].source.kind)
    end)
  end)
end)
