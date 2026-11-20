local addon = require("spec.helpers.addon")

local ID = 7
local FLAG = "Only 1 day of data · treat these numbers as rough"

local Plain = addon.Plain

describe("data from an item's first scan", function()
  local ns

  -- One wall per entry, oldest first, ending today
  local function SeedWalls(...)
    local walls = { ... }
    local days = {}
    for i, wall in ipairs(walls) do days[ns.Today() - (#walls - i)] = { wall } end
    ns.R().days[ID] = days
  end

  local function TooltipLines()
    local lines = {}
    ns.TooltipLines.Add({
      AddLine = function(_, text) lines[#lines + 1] = Plain(text) end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = Plain(left) .. "|" .. Plain(right) end,
    }, ID)
    return lines
  end

  local function Has(lines, text)
    for _, line in ipairs(lines) do
      if line:find(text, 1, true) then return true end
    end
    return false
  end

  local function Stats()
    local out = {}
    for _, stat in ipairs(ns.PriceView.Stats(ns.PriceView.Facts(ID, time()))) do
      out[#out + 1] = stat.label .. ": " .. Plain(stat.value)
    end
    return out
  end

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, depositRate = {}, containers = {} }
    _G.C_Item = {}
    _G.IsShiftKeyDown = function() return true end
  end)

  after_each(function()
    _G.MarketWallDB, _G.C_Item, _G.IsShiftKeyDown = nil, nil, nil
  end)

  describe("one scan", function()
    before_each(function() SeedWalls(1000) end)

    it("shows a normal range and median in the stats, with no trend from one day", function()
      assert.same({ "Today: 10s", "Normal range: 10s – 10s", "Median: 10s" }, Stats())
    end)

    it("flags the tooltip just under the heading, and the trend reads n/a", function()
      local lines = TooltipLines()
      assert.equal("MarketWall|", lines[2])
      assert.equal("  " .. FLAG .. "|", lines[3])
      assert.is_true(Has(lines, "  Against median|+0% (normal)"))
      assert.is_true(Has(lines, "7-day trend|n/a (first scan)"))
    end)

    it("counts one day of data", function()
      assert.equal(1, ns.DaysOfData(ID))
      assert.equal(FLAG, ns.LowDataText(1))
    end)
  end)

  it("drops the flag at exactly the threshold", function()
    SeedWalls(1000, 1000, 1000, 1000, 1000)
    assert.equal(5, ns.DaysOfData(ID))
    assert.is_false(Has(TooltipLines(), "of data"))
    assert.is_nil(ns.LowDataText(5))
    assert.equal("|cffa3acac5 d|r", ns.DataBadge(5))
  end)

  describe("the badge after a low-data item's name", function()
    local YOUNG, SEASONED = 7, 8
    local SUFFIX = "|cffffb057 · 1 d|r"
    local TIP = "Only 1 day of data; the normal price may be off."

    before_each(function()
      SeedWalls(1000)
      local days = {}
      for ago = 0, 4 do days[ns.Today() - ago] = { 1000 } end
      ns.R().days[SEASONED] = days
    end)

    local function ByID(rows)
      local out = {}
      for _, row in ipairs(rows) do out[row.id] = row end
      return out
    end

    it("ends a low-data Watchlist row's Item cell with an orange badge, and adds its hover", function()
      ns.R().watch[YOUNG], ns.R().watch[SEASONED] = {}, {}
      local rows = ByID(ns.ui.WatchData())
      assert.same({ SUFFIX }, rows[YOUNG].suffixes)
      assert.equal(TIP, rows[YOUNG].itemTip)
      assert.equal("10s to 10s\nData: 1 d\n" .. TIP, Plain(rows[YOUNG].cellTips[4]))
      assert.same({}, rows[SEASONED].suffixes)
      assert.is_nil(rows[SEASONED].itemTip)
    end)

    it("does the same for Bait Detect rows", function()
      local flagged = { p = 30, u = 1, q = 1, w = 1000, first = 1, last = 2, seen = 2 }
      ns.R().bait[YOUNG], ns.R().bait[SEASONED] = flagged, flagged
      local rows = ByID(ns.BaitListData())
      assert.same({ SUFFIX }, rows[YOUNG].suffixes)
      assert.equal(TIP, rows[YOUNG].itemTip)
      assert.equal("Data: 1 d\n" .. TIP, Plain(rows[YOUNG].cellTips[3]))
      assert.same({}, rows[SEASONED].suffixes)
      assert.is_nil(rows[SEASONED].itemTip)
    end)

    it("does the same for Snipes and Dips, which have no Data column", function()
      local deal = { wall = 100, min = 50, median = 120, units = 1, cost = 50, profit = 40, discount = 0.5, under = 0.2, total = 9 }
      local function Deal(id, days)
        local copy = { id = id, days = days }
        for k, v in pairs(deal) do copy[k] = v end
        return copy
      end
      ns.snipes = { Deal(YOUNG, 1), Deal(SEASONED, 5) }
      ns.dips = { Deal(YOUNG, 1), Deal(SEASONED, 5) }
      for _, rows in ipairs({ ByID(ns.ui.SnipeData()), ByID(ns.ui.DipData()) }) do
        assert.same({ SUFFIX }, rows[YOUNG].suffixes)
        assert.equal(TIP, rows[YOUNG].itemTip)
        assert.same({}, rows[SEASONED].suffixes)
        assert.is_nil(rows[SEASONED].itemTip)
      end
    end)

    -- A cell 90 wide, with every character 6 wide and colour codes taking no room
    local function Cell()
      local cell = {}
      function cell.SetText(_, text) cell.text = text end
      function cell.GetWidth() return 90 end
      function cell.GetStringWidth() return 6 * #Plain(cell.text):gsub("…", ".") end
      return cell
    end

    it("shortens the name, never the badge, to fit the cell", function()
      local cell = Cell()
      ns.widgets.FitText(cell, "|cff1eff00Mageweave Cloth|r", SUFFIX)
      assert.equal("|cff1eff00Magewea…|r" .. SUFFIX, cell.text)
    end)

    it("leaves a name that fits whole", function()
      local cell = Cell()
      ns.widgets.FitText(cell, "Silk", SUFFIX)
      assert.equal("Silk" .. SUFFIX, cell.text)
    end)
  end)

  it("counts past days without a scan today", function()
    ns.R().days[ID] = { [ns.Today() - 2] = { 1000 }, [ns.Today() - 1] = { 1000 } }
    assert.equal(2, ns.DaysOfData(ID))
  end)

  it("moves the flag with the setting", function()
    SeedWalls(1000, 1000, 1000)
    MarketWallDB.cfg.minHistoryDays = 3
    assert.is_nil(ns.LowDataText(3))
    MarketWallDB.cfg.minHistoryDays = 10
    assert.equal("Only 3 days of data · treat these numbers as rough", ns.LowDataText(3))
    assert.equal("|cffffb0573 d|r", ns.DataBadge(3))
  end)

  it("holds the setting to 1 through one day past the baseline window", function()
    MarketWallDB.cfg.minHistoryDays = 0
    assert.equal(1, ns.ReliableDays())
    assert.is_nil(ns.LowDataText(1))
    MarketWallDB.cfg.minHistoryDays = 99
    assert.equal(15, ns.ReliableDays())   -- the most days an item can have: 14 past and today
    assert.is_nil(ns.LowDataText(15))
  end)

  describe("full scan deals", function()
    local CUT = 0.05
    -- 10 units at 50 under a 100 wall
    local LADDER = { { p = 50, q = 10 }, { p = 100, q = 200 } }

    local function Deals()
      return ns.FullScanDeals(ID, LADDER, 210, 100, 50, ns.StatsFor(ID), CUT)
    end

    it("includes a snipe on an item's first day, resold at today's wall", function()
      SeedWalls(100)
      local snipe = Deals()
      assert.same({ 10, 500, 1 }, { snipe.units, snipe.cost, snipe.days })
    end)

    it("excludes a day-1 dip only because the item has no past day", function()
      -- a 200 normal price that today's 100 wall falls well under, once as a past day...
      local pastDay = ns.Wall.Stats({ 200 })
      assert.is_true((ns.Wall.IsDip(100, pastDay, ns.Cfg("dipPct"), CUT)))
      -- ...and once with the same numbers marked as a first scan
      local firstDay = ns.Wall.Stats({ 200 })
      firstDay.firstScan = true
      assert.same({ false, "history" }, { ns.Wall.IsDip(100, firstDay, ns.Cfg("dipPct"), CUT) })

      SeedWalls(100)
      local _, dip = ns.FullScanDeals(ID, LADDER, 210, 100, 50, ns.StatsFor(ID), CUT)
      assert.is_nil(dip)
      assert.equal("history", select(2, ns.Wall.IsDip(100, ns.StatsFor(ID), ns.Cfg("dipPct"), CUT)))
    end)

    it("includes a dip from the second day", function()
      SeedWalls(200, 100)
      local _, dip = Deals()
      assert.same({ 200, 0.5, 2 }, { dip.median, dip.under, dip.days })
    end)

    it("excludes nothing however high the setting", function()
      MarketWallDB.cfg.minHistoryDays = 30
      SeedWalls(200, 100)
      local snipe, dip = Deals()
      assert.is_table(snipe)
      assert.is_table(dip)
    end)
  end)
end)
