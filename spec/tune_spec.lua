local addon = require("spec.helpers.addon")

-- The deal lists keep a full scan's candidates and apply the thresholds when shown, so a
-- change on the tune row or in Settings re-filters them at once, without a scan
describe("tuning the deal lists", function()
  local ns, ui

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, depositRate = {}, containers = {} }
    _G.C_Item = {}
    ui = ns.ui
  end)

  after_each(function()
    _G.MarketWallDB, _G.C_Item = nil, nil
  end)

  local function Ids(data)
    local ids = {}
    for i, row in ipairs(data) do ids[i] = row.id end
    return ids
  end

  describe("Snipes", function()
    before_each(function()
      ns.snipes = {
        { id = 1, wall = 100, min = 50, units = 10, cost = 500, profit = 400, discount = 0.47, total = 200, days = 5 },
        { id = 2, wall = 100, min = 80, units = 1, cost = 80, profit = 15, discount = 0.16, total = 200, days = 5 },
        { id = 3, wall = 100, min = 50, units = 2, cost = 100, profit = 90, discount = 0.47, total = 5, days = 5 },
      }
    end)

    it("shows only the candidates over Min profit, Min discount and Min supply", function()
      assert.same({ 1 }, Ids(ui.SnipeData()))
    end)

    it("re-filters the same candidates when a threshold changes", function()
      MarketWallDB.cfg.minSnipeProfit = 10
      assert.same({ 1, 2 }, Ids(ui.SnipeData()))
      MarketWallDB.cfg.minSnipeDiscount = 0.20
      assert.same({ 1 }, Ids(ui.SnipeData()))
      MarketWallDB.cfg.minSnipeProfit, MarketWallDB.cfg.minSupply = 500, 1
      assert.same({}, Ids(ui.SnipeData()))
      assert.equal(3, #ns.snipes)
    end)
  end)

  describe("Dips", function()
    before_each(function()
      ns.dips = {
        { id = 1, wall = 90, median = 100, under = 0.1, total = 50, profit = 5, days = 5 },   -- exactly the default 10%
        { id = 2, wall = 95, median = 100, under = 0.05, total = 50, profit = 0, days = 5 },
        { id = 3, wall = 50, median = 100, under = 0.5, total = 8, profit = 45, days = 5 },
      }
    end)

    it("shows only the candidates at least Dip size under, with Min supply", function()
      assert.same({ 1 }, Ids(ui.DipData()))
    end)

    it("re-filters the same candidates when Dip size or Min supply changes", function()
      MarketWallDB.cfg.dipPct = 0.05
      assert.same({ 1, 2 }, Ids(ui.DipData()))
      MarketWallDB.cfg.minSupply = 5
      assert.same({ 1, 2, 3 }, Ids(ui.DipData()))
      MarketWallDB.cfg.dipPct = 0.2
      assert.same({ 3 }, Ids(ui.DipData()))
    end)
  end)

  describe("Disenchant", function()
    before_each(function()
      ns.EnchantingSkill = function() return 300 end
      ns.disenchants = {
        { id = 1, price = 10000, value = 20000, profit = 10000, pct = 1.0, odds = "classic table", skill = 1 },
        { id = 2, price = 10000, value = 13000, profit = 3000, pct = 0.3, odds = "classic table", skill = 1 },
      }
    end)

    it("re-filters the same deals when Min profit or Min profit % changes", function()
      assert.same({ 1 }, Ids((ui.DisenchantData())))
      MarketWallDB.cfg.minDisenchantProfit = 2000
      assert.same({ 1, 2 }, Ids((ui.DisenchantData())))
      MarketWallDB.cfg.minDisenchantPct = 0.5
      assert.same({ 1 }, Ids((ui.DisenchantData())))
    end)

    it("counts only passing deals as hidden by skill", function()
      ns.EnchantingSkill = function() return 0 end
      local data, _, hidden = ui.DisenchantData()
      assert.same({ 0, 1 }, { #data, hidden })
    end)
  end)

  describe("full scan candidates", function()
    local CUT = 0.05

    it("keeps a snipe under the thresholds and on a thin market", function()
      MarketWallDB.cfg.minSnipeProfit = 1000000
      -- 1 unit at 80 under a 100 wall, 3 units listed in all
      local snipe = ns.FullScanDeals(7, { { p = 80, q = 1 }, { p = 100, q = 2 } }, 3, 100, 80, { n = 0 }, CUT)
      assert.same({ 1, 3 }, { snipe.units, snipe.total })
      assert.is_false(ns.PassesSnipe(snipe))
    end)

    it("keeps a dip smaller than Dip size", function()
      local stats = ns.Wall.Stats({ 100, 100, 100, 100 })
      local _, dip = ns.FullScanDeals(7, { { p = 93, q = 50 } }, 50, 93, 93, stats, CUT)
      assert.near(0.07, dip.under, 1e-9)
      assert.is_false(ns.PassesDip(dip))
    end)
  end)

  describe("the tune row", function()
    local row

    local function Edit(index)
      local edit = row.edits[index].edit
      function edit.SetText(_, text) edit.text = text end
      return edit
    end

    local function Type(edit, text)
      function edit.GetText() return text end
      edit.scripts.OnEnterPressed(edit)
    end

    local function SettingsDef(key)
      for _, group in ipairs(ui.settingGroups) do
        for _, def in ipairs(group.settings) do
          if def.key == key then return def end
        end
      end
    end

    before_each(function()
      ui.list = { offset = 4 }
      row = ui.BuildTuneRow(CreateFrame("Frame"), "snipes")
    end)

    it("edits the same settings as the Settings page, read the same way", function()
      assert.equal(SettingsDef("minSnipeProfit"), row.edits[1].def)
      assert.equal(SettingsDef("minSnipeDiscount"), row.edits[2].def)
    end)

    it("saves money and percents on Enter and shows them as Settings does", function()
      local profit, discount = Edit(1), Edit(2)
      Type(profit, "50s")
      Type(discount, "25%")
      assert.equal(5000, MarketWallDB.cfg.minSnipeProfit)
      assert.equal(0.25, MarketWallDB.cfg.minSnipeDiscount)
      assert.equal("50s", profit.text)
      assert.equal("25%", discount.text)
      assert.equal(0, ui.list.offset)   -- the list re-filters from its top
    end)

    it("keeps the typed value, not its rounded display, when Enter also leaves the box", function()
      local discount = Edit(2)
      function discount.GetText() return discount.text end
      function discount.ClearFocus(self) self.scripts.OnEditFocusLost(self) end   -- as the game does
      discount.text = "25.55%"
      discount.scripts.OnEnterPressed(discount)
      assert.near(0.2555, MarketWallDB.cfg.minSnipeDiscount, 1e-12)
      assert.equal("25.6%", discount.text)
    end)

    it("keeps the setting when the text does not read", function()
      MarketWallDB.cfg.minSnipeProfit = 30
      local profit = Edit(1)
      Type(profit, "lots")
      assert.equal(30, MarketWallDB.cfg.minSnipeProfit)
      assert.equal("30c", profit.text)
    end)

    it("shows a value changed in Settings", function()
      local profit = Edit(1)
      MarketWallDB.cfg.minSnipeProfit = 10000
      ui.RefreshTune(row)
      assert.equal("1g", profit.text)
    end)

    it("resets only its own screen's values", function()
      MarketWallDB.cfg.minSnipeProfit, MarketWallDB.cfg.minSnipeDiscount, MarketWallDB.cfg.dipPct = 1, 0.5, 0.3
      ui.ResetTune("snipes")
      assert.same({ dipPct = 0.3 }, MarketWallDB.cfg)
    end)
  end)

  describe("the status line count", function()
    it("counts what passes out of the scan's candidates", function()
      assert.equal("41 of 103 snipes", ui.CountOf(41, 103, "snipe"))
      assert.equal("0 of 1 dip", ui.CountOf(0, 1, "dip"))
    end)

    it("gives a plain count when everything passes", function()
      assert.equal("103 snipes", ui.CountOf(103, 103, "snipe"))
      assert.equal("0 deals", ui.CountOf(0, 0, "deal"))
    end)
  end)
end)
