local addon = require("spec.helpers.addon")

local TODAY = 20000
local THREAD, CLOTH, SHIRT, BAG, VEST, PATTERN = 1, 2, 3, 4, 5, 6
local MONTH = 30 * 86400

describe("Crafting view", function()
  local ns, V, Crafting

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, mobs = {}, depositRate = {}, crafting = {} }
    _G.C_Item = {}
    V, Crafting = ns.CraftingView, ns.Crafting
  end)

  local function Plain(text) return addon.Plain(text) end

  -- Walls are { price, supplied }; days[id] holds units listed on each day
  local function Evaluate(recipe, p)
    local prices = {
      buy = function(id) return (p.buy or {})[id] end,
      vendor = function(id) return (p.vendor or {})[id] end,
      wall = function(id)
        local wall = (p.walls or {})[id]
        if wall then return wall[1], wall[2] end
      end,
      deposit = function() return 0 end,
      disenchant = function(id) return (p.disenchant or {})[id], 0 end,
    }
    local function Days(id)
      local units = (p.days or {})[id]
      if not units then return nil end
      local days = {}
      for i, n in ipairs(units) do days[TODAY - i + 1] = { 100, 100, 100, n, 90 } end
      return days
    end
    return Crafting.Evaluate(recipe, { prices = prices, opts = { cut = 0, disenchant = p.disenchant ~= nil },
      days = Days, today = TODAY, rank = p.rank })
  end

  local function Recipe(fields)
    local recipe = { product = SHIRT, name = "Linen Shirt", made = 1, reagents = { { THREAD, 1 }, { CLOTH, 2 } }, known = true }
    for k, v in pairs(fields) do recipe[k] = v end
    return recipe
  end

  local PRICED = { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true }, [SHIRT] = { 500, true } }, days = { [SHIRT] = { 12, 12 } } }

  local function Names(evaluations)
    local names = {}
    for i, evaluation in ipairs(evaluations) do names[i] = evaluation.recipe.name end
    return names
  end

  describe("filtering", function()
    local function Guide()
      return {
        Evaluate(Recipe({}), PRICED),
        Evaluate(Recipe({ product = BAG, name = "Red Woolen Bag" }), { walls = { [CLOTH] = { 100, true }, [BAG] = { 50, true } }, buy = { [THREAD] = 10 } }),
        Evaluate(Recipe({ product = VEST, name = "Robe of the Void", known = false }), { buy = { [THREAD] = 10 }, vendor = { [VEST] = 300 }, walls = { [CLOTH] = { 100, true }, [VEST] = { 900, false } }, days = { [VEST] = { 1 } } }),
        Evaluate(Recipe({ product = 7, name = "Mystery Cloak", known = false }), {}),
      }
    end

    it("lists known, learnable or all recipes", function()
      assert.same({ "Linen Shirt", "Red Woolen Bag" }, Names(V.Filter(Guide(), { mode = "known" })))
      assert.same({ "Robe of the Void", "Mystery Cloak" }, Names(V.Filter(Guide(), { mode = "learnable" })))
      assert.equal(4, #V.Filter(Guide(), { mode = "all" }))
    end)

    it("hides thin markets and losses, but never a recipe whose profit is unknown", function()
      assert.same({ "Linen Shirt", "Red Woolen Bag", "Mystery Cloak" }, Names(V.Filter(Guide(), { mode = "all", hideThin = true })))
      assert.same({ "Linen Shirt", "Robe of the Void", "Mystery Cloak" }, Names(V.Filter(Guide(), { mode = "all", hideLosses = true })))
    end)

    it("matches part of the name, ignoring case and spaces around it", function()
      assert.same({ "Red Woolen Bag" }, Names(V.Filter(Guide(), { mode = "all", filter = " woolen " })))
    end)
  end)

  describe("unknown values", function()
    it("show as no data, never as 0", function()
      for _, text in ipairs({ V.Money(nil), V.Profit(nil), V.Margin(nil), V.Skill(nil, nil), V.Payback(nil) }) do
        assert.equal("no data", Plain(text))
      end
      assert.equal("No data", Plain(V.Market({ level = Crafting.NO_DATA, units = 0, recent = 0 })))
    end)

    it("leave every cell of an unpriced recipe as no data", function()
      local cells = V.Cells(Evaluate(Recipe({ known = false, source = { kind = "drop" }, pattern = PATTERN }), {}), "learnable")
      assert.same({ "Linen Shirt", "no data", "no data", "no data", "no data", "No data", "Pattern drop · not listed", "no data", "no data" },
        { Plain(cells[1]), Plain(cells[2]), Plain(cells[3]), Plain(cells[4]), Plain(cells[5]), Plain(cells[6]), Plain(cells[7]), Plain(cells[8]), Plain(cells[9]) })
    end)
  end)

  describe("cells", function()
    it("sign profit and margin, red for a loss", function()
      assert.equal("+1s 20c", Plain(V.Profit(120)))
      assert.equal(ns.COLOR.LOSS, V.Profit(-7):sub(1, 10))
      assert.equal("-7c", Plain(V.Profit(-7)))
      assert.equal("-23%", Plain(V.Margin(-0.23)))
    end)

    it("give the profit cell its exact amount on hover only when the cell rounds it", function()
      assert.equal("+1g 2s 34c", Plain(V.CellTips({ profit = 10234 })[5]))
      assert.is_nil(V.CellTips({ profit = 120 }))
    end)

    it("colour the skill, red above your rank", function()
      local evaluation = Evaluate(Recipe({ skill = 250 }), { rank = 236 })
      assert.equal("|cffff2020250|r", V.Skill(evaluation.recipe.skill, evaluation.colour))
    end)

    it("show the market depth and the units listed", function()
      local evaluation = Evaluate(Recipe({}), PRICED)
      assert.equal("Steady · 12 listed", Plain(V.Market(evaluation.market)))
    end)

    it("tag a product that pays most disenchanted", function()
      local p = { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true }, [SHIRT] = { 500, true } }, disenchant = { [SHIRT] = 900 } }
      local evaluation = Evaluate(Recipe({}), p)
      assert.equal(900, V.Cells(evaluation, "known")[4])
      assert.equal(" DE", Plain(V.Suffixes(evaluation)[4]))
    end)

    it("fit the search window's 736-pixel list in every mode", function()
      for _, mode in ipairs(V.MODES) do
        local width = 0
        for _, column in ipairs(V.Columns(mode.key)) do width = width + column[2] end
        assert.is_true(width <= 736, mode.key .. " columns are " .. width .. " wide")
      end
    end)

    it("mark disenchanting best for a product never listed when it pays more than a vendor", function()
      local p = { buy = { [THREAD] = 10 }, vendor = { [SHIRT] = 100 }, walls = { [CLOTH] = { 100, true } }, disenchant = { [SHIRT] = 900 } }
      local evaluation = Evaluate(Recipe({}), p)
      assert.equal(900, V.Cells(evaluation, "known")[4])
      assert.equal(" DE", Plain(V.Suffixes(evaluation)[4]))
      local product = V.Breakdown(evaluation, { name = tostring, bags = function() return 0 end })[2]
      assert.same({ "1s", "9s" }, { Plain(product.rows[1][2]), Plain(product.rows[3][2]):match("[%d].*") })
      assert.matches("^best", Plain(product.rows[3][2]))
    end)

    it("say where a recipe is learned and whether its pattern is listed", function()
      local function LearnFrom(fields, p) return Plain(V.LearnFrom(Evaluate(Recipe(fields), p or {}))) end
      assert.equal("Known", LearnFrom({}))
      assert.equal("Trainer", LearnFrom({ known = false, source = { kind = "trainer", cost = 500 } }))
      assert.equal("Vendor (limited supply)", LearnFrom({ known = false, pattern = PATTERN, source = { kind = "vendor", cost = 800, limited = true } }))
      assert.equal("Pattern drop · on the AH", LearnFrom({ known = false, pattern = PATTERN, source = { kind = "drop" } }, { walls = { [PATTERN] = { 650, true } } }))
    end)

    it("count crafts to pay back, or never", function()
      assert.same({ "1 craft", "3 crafts", "never" }, { Plain(V.Payback(1)), Plain(V.Payback(3)), Plain(V.Payback(Crafting.NEVER)) })
    end)
  end)

  describe("sorting by a column", function()
    local function Entries(evaluations, mode)
      local entries = {}
      for i, evaluation in ipairs(evaluations) do
        entries[i] = { evaluation = evaluation, sort = V.SortValues(evaluation, mode) }
      end
      return entries
    end
    local function Sorted(entries)
      local names = {}
      for i, entry in ipairs(entries) do names[i] = entry.evaluation.recipe.name end
      return names
    end

    it("puts unknown values last either way", function()
      local entries = Entries({ Evaluate(Recipe({ name = "Unpriced" }), {}), Evaluate(Recipe({ name = "Priced" }), PRICED) }, "known")
      for _, desc in ipairs({ true, false }) do
        ns.MobsView.Sort(entries, { col = 5, desc = desc })   -- profit
        assert.same({ "Priced", "Unpriced" }, Sorted(entries))
      end
    end)

    it("orders markets deep, steady, thin, and a recipe that never pays back after any that does", function()
      local deep = Evaluate(Recipe({ name = "Deep", known = false, source = { kind = "trainer", cost = 100 } }),
        { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true }, [SHIRT] = { 500, true } }, days = { [SHIRT] = { 50, 50, 50, 50, 50 } } })
      local steady = Evaluate(Recipe({ name = "Steady", known = false, source = { kind = "trainer", cost = 100 } }), PRICED)
      local thin = Evaluate(Recipe({ name = "Thin", known = false, source = { kind = "trainer", cost = 100 } }),
        { buy = { [THREAD] = 10 }, walls = { [CLOTH] = { 100, true }, [SHIRT] = { 150, false } }, days = { [SHIRT] = { 2 } } })
      local entries = Entries({ thin, steady, deep }, "learnable")
      ns.MobsView.Sort(entries, { col = 6, desc = true })   -- market
      assert.same({ "Deep", "Steady", "Thin" }, Sorted(entries))
      ns.MobsView.Sort(entries, { col = 9, desc = false })   -- pays back
      assert.equal("Thin", Sorted(entries)[3])
    end)
  end)

  describe("status line", function()
    it("asks for the profession window until the recipes are read", function()
      assert.equal("Tailoring · Open your profession window once to read your recipes. · no full scan yet",
        Plain(V.StatusText("Tailoring", nil, nil, nil)))
    end)

    it("leaves the rank out when the window was never read", function()
      assert.equal("Tailoring · Open your profession window once to read your recipes. · no full scan yet",
        Plain(V.StatusText("Tailoring", 0, nil, nil)))
    end)

    it("gives the rank, the recipes known and the age of the read and the prices", function()
      local known = { rank = 236, maxRank = 300, t = os.time() - 7200, recipes = { [SHIRT] = {}, [BAG] = {} } }
      assert.equal("Tailoring 236/300 · 2 recipes known (read from your profession window 2h ago) · prices from the full scan 2h ago",
        Plain(V.StatusText("Tailoring", 236, known, os.time() - 7200)))
      assert.matches("prices from the full scan 30d ago", Plain(V.StatusText("Tailoring", 236, known, os.time() - MONTH)))
    end)
  end)

  describe("breakdown", function()
    local INFO = { name = function(id) return ({ [THREAD] = "Coarse Thread", [CLOTH] = "Linen Cloth" })[id] end,
      bags = function(id) return id == CLOTH and 5 or 0 end }

    local function Rows(section)
      local rows = {}
      for i, row in ipairs(section.rows) do rows[i] = Plain(row[1]) .. " = " .. Plain(row[2]) end
      return rows
    end

    it("lists each reagent with its source and bag count, and the total", function()
      local mats = V.Breakdown(Evaluate(Recipe({}), PRICED), INFO)[1]
      assert.same({ "1 x Coarse Thread  vendor, 0 in bags = 10c", "2 x Linen Cloth  wall, 5 in bags = 2s", "Cost = 2s 10c" }, Rows(mats))
    end)

    it("leaves the cost unknown when a reagent has no price", function()
      local mats = V.Breakdown(Evaluate(Recipe({}), { buy = { [THREAD] = 10 } }), INFO)[1]
      assert.same({ "1 x Coarse Thread  vendor, 0 in bags = 10c", "2 x Linen Cloth  no price, 5 in bags = no data", "Cost = no data" }, Rows(mats))
    end)

    it("prices each outlet per craft and marks the best", function()
      local p = { buy = { [THREAD] = 10 }, vendor = { [SHIRT] = 100 }, walls = { [CLOTH] = { 100, true }, [SHIRT] = { 500, true } } }
      local product = V.Breakdown(Evaluate(Recipe({ made = 2 }), p), INFO)[2]
      assert.equal("Product, 2 per craft, after the cut and deposit", product.title)
      assert.same({ "Vendor = 2s", "Market (net) = best  10s", "Disenchant (net) = no data", "Profit per craft = +7s 90c" }, Rows(product))
    end)

    it("shows the market's listings, days seen and trend", function()
      local market = V.Breakdown(Evaluate(Recipe({}), PRICED), { name = INFO.name, bags = INFO.bags, trend = -0.04 })[3]
      assert.same({ "Listed, latest scan = 12", "Seen in scans, last 7 days = 2 of 7 days", "Wall, 7-day trend = ▼ 4%" }, Rows(market))
      market = V.Breakdown(Evaluate(Recipe({}), {}), INFO)[3]
      assert.same({ "Listed, latest scan = no data", "Seen in scans, last 7 days = 0 of 7 days", "Wall, 7-day trend = no data" }, Rows(market))
    end)
  end)

  describe("panel", function()
    before_each(function()
      _G.C_Item = { GetItemCount = function() return 0 end }
    end)

    local function Learnable(panel)
      panel.mode = "learnable"
      panel:Refresh()
      return panel.list.data
    end
    local function WithPattern(data)
      for _, entry in ipairs(data) do
        if entry.evaluation.recipe.pattern then return entry end
      end
    end

    it("lists the bundled table before any recipe is read, with the first row selected", function()
      local panel = V.Build(CreateFrame("Frame"))
      panel:Refresh()
      assert.equal("Tailoring", panel.profession)
      assert.same({}, panel.list.data)
      local data = Learnable(panel)
      assert.is_true(#data > 100)
      assert.is_true(data[1].highlight)
    end)

    it("evaluates the guide again after each profession window event, even within a second", function()
      local loaded, fire = addon.Load()   -- a load of its own, to fire events at its frames
      _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, mobs = {}, depositRate = {}, crafting = {} }
      local evaluated = 0
      local guide = loaded.Professions.Guide
      loaded.Professions.Guide = function(profession)
        evaluated = evaluated + 1
        return guide(profession)
      end
      local panel = loaded.CraftingView.Build(CreateFrame("Frame"))
      panel:Refresh()
      panel:Refresh()
      assert.equal(1, evaluated)
      fire("TRADE_SKILL_UPDATE")
      fire("TRADE_SKILL_LIST_UPDATE")
      panel:Refresh()
      assert.equal(2, evaluated)
    end)

    it("opens a learnable recipe's pattern only where a pattern opener is given", function()
      local opened = {}
      local market = V.Build(CreateFrame("Frame"), { top = -50, onPattern = function(id) opened[#opened + 1] = id end })
      local entry = WithPattern(Learnable(market))
      market.list.onClick(entry)
      assert.same({ entry.evaluation.recipe.pattern }, opened)
      assert.equal(entry.id, market.selected)

      local window = V.Build(CreateFrame("Frame"))
      entry = WithPattern(Learnable(window))
      window.list.onClick(entry)
      assert.equal(entry.id, window.selected)
      assert.equal(1, #opened)
    end)
  end)
end)
