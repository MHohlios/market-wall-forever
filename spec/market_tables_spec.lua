local addon = require("spec.helpers.addon")

local Plain = addon.Plain

describe("the Market tab's tables", function()
  local ns, ui

  local function Titles(columns)
    local titles = {}
    for i, col in ipairs(columns) do titles[i] = col[1] end
    return titles
  end

  local function AnswerTitle(columns)
    for _, col in ipairs(columns) do
      if col.answer then return col[1] end
    end
  end

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, depositRate = {}, containers = {} }
    _G.C_Item = {}
    ui = ns.ui
  end)

  after_each(function()
    _G.MarketWallDB, _G.C_Item = nil, nil
  end)

  describe("Snipes", function()
    local SNIPE = { id = 7, wall = 396, min = 250, units = 4, cost = 1000, profit = 505, discount = 0.37, total = 40, days = 9 }

    it("reads in buying order, with no Data column", function()
      assert.same({ "Item", "Cheapest", "Units", "Cost", "Sells at (wall)", "Profit", "Under normal" }, Titles(ui.COLUMNS.snipes))
    end)

    it("puts each snipe's numbers under those titles", function()
      ns.snipes = { SNIPE }
      local cells = ui.SnipeData()[1].cells
      assert.same({ 250, "4", 1000, 396, 505, "37%" }, { cells[2], cells[3], cells[4], cells[5], cells[6], cells[7] })
    end)

    it("answers with Profit and sorts by it, biggest first", function()
      assert.equal("Profit", AnswerTitle(ui.COLUMNS.snipes))
      assert.equal("Profit", ui.COLUMNS.snipes[ui.sort.snipes.col][1])
      assert.is_true(ui.sort.snipes.desc)
    end)
  end)

  describe("Dips", function()
    it("has no Data column and answers with Profit each", function()
      assert.same({ "Item", "Wall now", "Normal", "Under by", "Supply", "Profit each" }, Titles(ui.COLUMNS.dips))
      assert.equal("Profit each", AnswerTitle(ui.COLUMNS.dips))
    end)
  end)

  describe("Disenchant", function()
    before_each(function() ns.lastFullScan = time() end)

    it("answers with Profit", function()
      assert.equal("Profit", AnswerTitle(ui.COLUMNS.disenchant))
    end)

    it("explains an empty list at Enchanting 0", function()
      assert.equal("No disenchant deals in the last full scan.\nYour Enchanting is 0, so only items you can't disenchant yet would show.",
        Plain(ui.DisenchantEmptyText(0, 0, 0)))
    end)

    it("points to the box when deals need more skill", function()
      assert.equal("No deals at your Enchanting skill.\n2 deals in the last scan need more skill; tick the box to see them.",
        Plain(ui.DisenchantEmptyText(150, 2, 5)))
      assert.equal("No deals at your Enchanting skill.\n1 deal in the last scan needs more skill; tick the box to see them.",
        Plain(ui.DisenchantEmptyText(150, 1, 5)))
    end)

    it("shortens a blended odds source to fit its column, leaving the rest whole", function()
      assert.equal("Table + 34 yours", ui.ShortOdds("Classic table + your 34 disenchants"))
      assert.equal("Estimate + 1 yours", ui.ShortOdds("Forever estimate + your 1 disenchant"))
      assert.equal("Forever estimate", ui.ShortOdds("Forever estimate"))
      assert.equal("Your 12 disenchants", ui.ShortOdds("Your 12 disenchants"))
    end)

    it("says when the last scan's deals all fall under the thresholds", function()
      assert.equal("No deals pass these thresholds.\n5 deals in the last full scan; lower the values above to see them.",
        Plain(ui.DisenchantEmptyText(150, 0, 5)))
    end)
  end)

  describe("Watchlist", function()
    local ID = 7

    local function Status(cur, entry)
      entry = entry or {}
      entry.cur = cur
      ns.R().watch[ID] = entry
      return Plain(ui.WatchData()[1].cells[8])
    end

    it("titles units under your buy price Under buy, and answers with Status", function()
      assert.equal("Under buy", ui.COLUMNS.watch[7][1])
      assert.equal("Status", AnswerTitle(ui.COLUMNS.watch))
    end)

    it("says Buy with units under your buy price", function()
      assert.equal("Buy", Status({ t = time(), w = 100, under = 3 }))
    end)

    it("says Sell when the wall reaches your sell price", function()
      assert.equal("Sell", Status({ t = time(), w = 100, under = 0 }, { sell = 90 }))
    end)

    it("shows a dash when there is nothing to do", function()
      assert.equal("-", Status({ t = time(), w = 100, under = 0 }))
    end)

    it("says Old with its age once the price is stale", function()
      assert.equal("Old · 2 h", Status({ t = time() - 2 * 3600, w = 100, under = 3 }))
    end)
  end)

  describe("Bait Detect", function()
    local RECORD = { p = 4073, u = 2, q = 2, w = 12000, first = 1, last = 2, seen = 2 }

    it("spells out its narrow titles and answers with Copies", function()
      assert.same({ "Item", "Bait", "Wall", "Under", "Copies", "Seen" }, Titles(ns.BaitColumns))
      assert.equal("Copies", AnswerTitle(ns.BaitColumns))
    end)

    it("shows the bait price as money, with its units on hover", function()
      ns.R().bait[7] = RECORD
      local row = ns.BaitListData()[1]
      assert.equal(4073, row.cells[2])
      assert.equal("2 units first seen at this price.", row.cellTips[2])
    end)
  end)

  describe("status line", function()
    it("gives the scan times, then the view's count", function()
      ns.R().lastFull = time()
      ui.view, ui.statusNote = "snipes", "105 snipes"
      assert.equal("Full scan just now · Watchlist scan never · 105 snipes", Plain(ui.StatusLine()))
    end)

    it("warns when there has been no full scan today", function()
      ui.view, ui.statusNote = "watch", nil
      assert.equal("Full scan never · Watchlist scan never · No full scan yet today", Plain(ui.StatusLine()))
    end)

    it("leaves out the watchlist scan and the prompt at the neutral Auction House", function()
      ns.R().lastFull = time() - 2 * 3600 - 60
      ns.neutralAH = true
      ui.view, ui.statusNote = "snipes", "41 of 103 snipes"
      assert.equal("Full scan 2h ago · 41 of 103 snipes", Plain(ui.StatusLine()))
      ns.R().lastFull = nil
      assert.equal("Full scan never · 41 of 103 snipes", Plain(ui.StatusLine()))
    end)
  end)
end)
