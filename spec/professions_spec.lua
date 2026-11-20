local addon = require("spec.helpers.addon")

local GUID = "Player-5250-0ABC1234"
local BOLT, SILK, THREAD, MOONCLOTH_PATTERN, FOREVER_MANTLE = 4305, 4306, 2320, 14526, 200123

local function Link(id) return "|cffffffff|Hitem:" .. id .. "::::::::::0|h[Item]|h|r" end

describe("Professions", function()
  local ns, fire, globals, rows

  local function Stub(name, value)
    globals[#globals + 1] = name
    _G[name] = value
  end

  -- A profession window over rows: { name, kind, product, made, reagents = { { id, count } } }.
  -- A row's product or reagent ID of false reads as a nil link, as for an uncached item.
  local function OpenWindow(name, rank)
    Stub("GetTradeSkillLine", function() return name, rank, 300 end)
    Stub("GetNumTradeSkills", function() return #rows end)
    Stub("GetTradeSkillInfo", function(i) return rows[i].name, rows[i].kind end)
    Stub("GetTradeSkillItemLink", function(i) return rows[i].product and Link(rows[i].product) or nil end)
    Stub("GetTradeSkillNumMade", function(i) return rows[i].made or 1, rows[i].made or 1 end)
    Stub("GetTradeSkillNumReagents", function(i) return #(rows[i].reagents or {}) end)
    Stub("GetTradeSkillReagentInfo", function(i, r) return "Reagent", "icon", rows[i].reagents[r][2], 0 end)
    Stub("GetTradeSkillReagentItemLink", function(i, r)
      local id = rows[i].reagents[r][1]
      return id and Link(id) or nil
    end)
  end

  before_each(function()
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    globals = {}
    Stub("UnitGUID", function(unit) return unit == "player" and GUID or nil end)
    rows = {
      { name = "Cloth", kind = "header" },
      { name = "Bolt of Silk Cloth", kind = "easy", product = BOLT, reagents = { { SILK, 3 } } },
      { name = "Gleamweave Mantle", kind = "optimal", product = FOREVER_MANTLE, made = 2,
        reagents = { { BOLT, 4 }, { THREAD, 1 } } },
    }
    OpenWindow("Tailoring", 236)
  end)

  after_each(function()
    for _, name in ipairs(globals) do _G[name] = nil end
  end)

  local function Saved()
    return MarketWallDB.crafting[GUID].Tailoring
  end

  describe("reading the profession window", function()
    it("saves the profession's rank and each recipe, per character, on TRADE_SKILL_SHOW", function()
      fire("TRADE_SKILL_SHOW")
      local saved = Saved()
      assert.same({ 236, 300 }, { saved.rank, saved.maxRank })
      assert.same({ name = "Bolt of Silk Cloth", made = 1, reagents = { { SILK, 3 } }, colour = "green" }, saved.recipes[BOLT])
    end)

    it("reads Forever-only products and multi-output recipes", function()
      fire("TRADE_SKILL_SHOW")
      local mantle = Saved().recipes[FOREVER_MANTLE]
      assert.same({ 2, "orange", { { BOLT, 4 }, { THREAD, 1 } } }, { mantle.made, mantle.colour, mantle.reagents })
    end)

    it("skips a recipe while its product or a reagent link is nil, and adds it on a later update", function()
      rows[2].product = false
      rows[3].reagents[2][1] = false
      fire("TRADE_SKILL_SHOW")
      assert.same({}, Saved().recipes)

      rows[2].product = BOLT
      fire("TRADE_SKILL_UPDATE")
      assert.is_table(Saved().recipes[BOLT])
      assert.is_nil(Saved().recipes[FOREVER_MANTLE])
    end)

    it("saves the average of a made range", function()
      Stub("GetTradeSkillNumMade", function(i) if i == 2 then return 2, 4 end return 1, 1 end)
      fire("TRADE_SKILL_SHOW")
      assert.equal(3, Saved().recipes[BOLT].made)
    end)

    it("keeps the saved recipe while a reagent count or the number of reagents reads nil", function()
      fire("TRADE_SKILL_SHOW")
      local saved = Saved().recipes[BOLT]
      Stub("GetTradeSkillReagentInfo", function() return "Reagent", "icon", nil, 0 end)
      fire("TRADE_SKILL_UPDATE")
      assert.equal(saved, Saved().recipes[BOLT])
      Stub("GetTradeSkillNumReagents", function() return nil end)
      fire("TRADE_SKILL_UPDATE")
      assert.equal(saved, Saved().recipes[BOLT])
      assert.same({ { SILK, 3 } }, Saved().recipes[BOLT].reagents)
    end)

    it("reads nothing, without an error, when the client lacks a profession window call", function()
      Stub("GetTradeSkillNumReagents", nil)
      fire("TRADE_SKILL_SHOW")
      assert.same({}, MarketWallDB.crafting)
    end)

    it("keeps recipes a later read no longer shows, as a collapsed header hides them", function()
      fire("TRADE_SKILL_SHOW")
      rows = { rows[1], rows[3] }
      fire("TRADE_SKILL_UPDATE")
      assert.is_table(Saved().recipes[BOLT])
    end)

    it("saves nothing without a profession open or a character GUID", function()
      Stub("GetTradeSkillLine", function() return "UNKNOWN", 0, 0 end)
      fire("TRADE_SKILL_SHOW")
      assert.same({}, MarketWallDB.crafting)
      OpenWindow("Tailoring", 236)
      Stub("UnitGUID", function() return nil end)
      fire("TRADE_SKILL_SHOW")
      assert.same({}, MarketWallDB.crafting)
    end)
  end)

  describe("lookups", function()
    local function Find(list, product)
      for _, recipe in ipairs(list) do
        if recipe.product == product then return recipe end
      end
    end

    it("merges known recipes over the tailoring table", function()
      fire("TRADE_SKILL_SHOW")
      local recipes = ns.Professions.Recipes("Tailoring")
      local bolt = Find(recipes, BOLT)
      assert.same({ true, { { SILK, 3 } }, 125 }, { bolt.known, bolt.reagents, bolt.skill })   -- the table says 4 silk
      assert.is_true(Find(recipes, FOREVER_MANTLE).forever)
      assert.is_false(Find(recipes, 14048).known)   -- Bolt of Runecloth, from the table only
    end)

    it("finds the recipe a pattern teaches", function()
      local recipe, profession = ns.Professions.ByPattern(MOONCLOTH_PATTERN)
      assert.same({ 14342, "Tailoring", false }, { recipe.product, profession, recipe.known })
      assert.is_nil(ns.Professions.ByPattern(1))
    end)

    it("finds a recipe by name, ignoring case", function()
      assert.equal(14048, ns.Professions.ByName("Tailoring", "bolt of runecloth").product)
      assert.is_nil(ns.Professions.ByName("Tailoring", "No Such Recipe"))
    end)

    it("lists professions with a table or saved recipes", function()
      OpenWindow("Cooking", 50)
      fire("TRADE_SKILL_SHOW")
      assert.same({ "Cooking", "Tailoring" }, ns.Professions.Names())
    end)
  end)

  describe("the guide at game prices", function()
    it("evaluates and ranks every recipe, with the rank from the profession window", function()
      Stub("C_Item", {})
      fire("TRADE_SKILL_SHOW")
      local r = ns.R()
      r.days[SILK] = { [ns.Today()] = { 150, 150, 150, 100, 140 } }
      r.days[BOLT] = { [ns.Today()] = { 1000, 1000, 1000, 50, 900 } }
      r.supplied[BOLT] = true
      local guide = ns.Professions.Guide("Tailoring")
      local top = guide[1]
      assert.equal(BOLT, top.recipe.product)
      assert.same({ 450, 950, 500 }, { top.cost, top.net, top.profit })
      assert.equal("green", top.colour)
      assert.equal(236, ns.Professions.Rank("Tailoring"))
    end)
  end)
end)
