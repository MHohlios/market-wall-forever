local addon = require("spec.helpers.addon")

local Plain = addon.Plain

describe("price view", function()
  local ns, PV
  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    PV = ns.PriceView
  end)

  describe("summary and trend", function()
    local function Points(...)
      local out = {}
      for i, w in ipairs({ ... }) do out[i] = { t = i, w = w } end
      return out
    end

    it("has no summary without points and no trend from one point", function()
      assert.is_nil(PV.Summary({}))
      assert.is_nil(PV.Summary(Points(100)).trend)
    end)

    it("measures the trend from the first to the last point only", function()
      local week = PV.Summary(Points(100, 500, 10, 110))
      assert.is_true(math.abs(week.trend - 0.10) < 1e-9)
      assert.equal(10, week.low)
      assert.equal(500, week.high)
      assert.equal(180, week.average)
      assert.equal(105, week.median)
      assert.equal(4, week.n)
      assert.equal(1, week.from)
    end)

    it("calls moves within 3% flat, including the edge", function()
      assert.equal("flat", PV.TrendText(0))
      assert.equal("flat", PV.TrendText(0.03))
      assert.equal("flat", PV.TrendText(-0.03))
    end)

    it("calls a computed 3% change flat despite float error", function()
      assert.equal("flat", PV.TrendText(1030 / 1000 - 1))
      assert.equal("flat", PV.TrendText(970 / 1000 - 1))
    end)

    it("names moves past 3% up or down with the rounded percent", function()
      assert.truthy(PV.TrendText(0.031):find("up 3%%"))
      assert.truthy(PV.TrendText(-0.126):find("down 13%%"))
    end)
  end)

  describe("chart range", function()
    local now, DAY = 1000000, 86400
    local series = { { t = now - 31 * DAY, w = 1 }, { t = now - 8 * DAY, w = 2 }, { t = now - 7 * DAY, w = 3 }, { t = now - DAY, w = 4 } }

    local function Walls(points)
      local out = {}
      for i, p in ipairs(points) do out[i] = p.w end
      return out
    end

    it("keeps the points from the last 7 or 30 days, the edge included", function()
      assert.same({ 3, 4 }, Walls(PV.InRange(series, 7, now)))
      assert.same({ 2, 3, 4 }, Walls(PV.InRange(series, 30, now)))
    end)

    it("keeps every point for All", function()
      assert.same({ 1, 2, 3, 4 }, Walls(PV.InRange(series, nil, now)))
    end)
  end)

  describe("chart series", function()
    local ID = 4321

    local function Walls(points)
      local out = {}
      for i, p in ipairs(points) do out[i] = p.w end
      return out
    end

    before_each(function()
      local today, now = ns.Today(), time()
      ns.R().days[ID] = { [today - 40] = { 50, 50, 50, 10, 50 }, [today - 20] = { 80, 80, 80, 10, 80 }, [today] = { 110, 110, 110, 10, 110 } }
      ns.R().snaps[ID] = { { now - 3600, 100, 100, 10 }, { now - 60, 110, 110, 10 } }
      local monday = today - 60 - (today - 60 + 3) % 7
      ns.R().weeks[ID] = ns.PackWeeks({ { start = monday - 63, wall = 20, low = 15, high = 25 }, { start = monday, wall = 30, low = 25, high = 35 } })
    end)

    it("draws only the snapshots by default, as the Sell page always has", function()
      assert.same({ 100, 110 }, Walls(ns.Series(ID)))
    end)

    it("keeps the weekly and daily history from before the first snapshot for the range switch", function()
      local series = ns.Series(ID, true)
      assert.same({ 20, 30, 50, 80, 100, 110 }, Walls(series))
      for i = 2, #series do assert.is_true(series[i - 1].t < series[i].t) end
      assert.same({ 80, 100, 110 }, Walls(PV.InRange(series, 30, time())))
    end)

    it("leaves the weekly points out of the daily series for an item without snapshots", function()
      ns.R().snaps[ID] = nil
      assert.same({ 50, 80, 110 }, Walls(ns.Series(ID)))
      assert.same({ 20, 30, 50, 80, 110 }, Walls(ns.Series(ID, true)))
    end)
  end)

  describe("stats grid", function()
    local ID = 12359
    local today

    -- One recorded day: wall, lowest and highest wall that day, units, lowest listing
    local function Day(ago, wall, low, high)
      ns.R().days[ID][today - ago] = { wall, low or wall, high or wall, 100, wall }
    end

    local function Grid(keys, range)
      local out = {}
      for _, cell in ipairs(PV.Cells(PV.Facts(ID, time(), range), keys)) do
        out[#out + 1] = Plain(cell.label) .. ": " .. Plain(cell.value)
      end
      return out
    end

    before_each(function()
      -- a vendor price of 2c; common quality, so it cannot be disenchanted
      _G.C_Item = { GetItemInfo = function() return "Thorium Bar", nil, 1, 40, nil, nil, nil, 20, nil, nil, 2 end }
      today = ns.Today()
      ns.R().days[ID] = {}
      Day(20, 200, 200, 210)   -- outside the 14-day baseline and the last 7 days
      Day(5, 100)
      Day(4, 110)
      Day(3, 90, 80)
      Day(2, 120)
      Day(1, 100)
      ns.R().watch[ID] = { buy = 90, sell = 120 }
    end)
    after_each(function() _G.C_Item = nil end)

    describe("for the search window's chart range", function()
      local RANGE_CELLS = { "rangeMin", "rangeMax", "rangeAverage", "rangeMedian", "rangeTrend", "rangePoints" }
      local SEVEN_DAYS, THIRTY_DAYS, ALL = PV.RANGES[1], PV.RANGES[2], PV.RANGES[3]

      it("summarizes the last 7 days", function()
        assert.same({ "Min: 90c", "Max: 1s 20c", "Average: 1s 4c", "Median: 1s 0c", "Trend: flat", "Points: 5 over 6 days" },
          Grid(RANGE_CELLS, SEVEN_DAYS))
      end)

      it("summarizes the last 30 days", function()
        assert.same({ "Min: 90c", "Max: 2s 0c", "Average: 1s 20c", "Median: 1s 5c", "Trend: down 50%", "Points: 6 over 21 days" },
          Grid(RANGE_CELLS, THIRTY_DAYS))
      end)

      it("reaches back into the weekly history for All", function()
        local start = today - 62 - (today - 62 + 3) % 7   -- a Monday about two months back
        ns.R().weeks[ID] = ns.PackWeeks({ { start = start, wall = 260, low = 240, high = 280 } })
        local days = today - (start + 3) + 1   -- the weekly point sits mid-week
        assert.same({ "Min: 90c", "Max: 2s 60c", "Average: 1s 40c", "Median: 1s 10c", "Trend: down 62%", "Points: 7 over " .. days .. " days" },
          Grid(RANGE_CELLS, ALL))
        assert.same({ "Points: 6 over 21 days" }, Grid({ "rangePoints" }, THIRTY_DAYS))
      end)

      it("draws the same points it summarizes", function()
        local facts = PV.Facts(ID, time(), SEVEN_DAYS)
        assert.same(PV.InRange(ns.Series(ID, true), 7, facts.now), facts.chart)
        assert.equal(#facts.chart, facts.range.n)
      end)

      it("shows the current wall with its age", function()
        assert.same({ "Current (yesterday): 1s 0c" }, Grid({ "current" }, SEVEN_DAYS))
        ns.ladders[ID] = { ladder = { { p = 95, q = 2 }, { p = 99, q = 200 } }, total = 202, t = time() }
        assert.same({ "Current (just now): 99c" }, Grid({ "current" }, SEVEN_DAYS))
      end)

      it("shows dashes for a range with no points, keeping the current wall", function()
        ns.R().days[ID] = {}
        Day(20, 200)
        assert.same({ "Current (20 days ago): 2s 0c", "Min: -", "Max: -", "Average: -", "Median: -", "Trend: -", "Points: -" },
          Grid({ "current", "rangeMin", "rangeMax", "rangeAverage", "rangeMedian", "rangeTrend", "rangePoints" }, SEVEN_DAYS))
      end)
    end)

    it("fills the search window's other cells from the item's history", function()
      assert.same({
        "Normal range: 1s 0c - 1s 10c",
        "Vendor: 2c",
        "Disenchant: -",
        "Your buy / sell: 90c / 1s 20c",
      }, Grid({ "normalRange", "vendor", "disenchant", "limits" }, PV.RANGES[1]))
    end)

    it("fills the Sell page's cells from the same facts, with no live listings loaded", function()
      assert.same({
        "Wall (last scan): 1s 0c",
        "Lowest listing: -",
        "Supply: -",
        "7-day trend: flat",
        "7-day average: 1s 4c",
        "Median (5 days): 1s 0c",
        "Normal range: 1s 0c - 1s 10c",
        "Vs median: +0% (normal)",
      }, Grid({ "wallNow", "lowestListing", "supply", "trend", "average", "median", "normalRange", "versusMedian" }))
    end)

    it("prefers live listings for the wall, with their age", function()
      ns.ladders[ID] = { ladder = { { p = 95, q = 2 }, { p = 99, q = 200 } }, total = 202, t = time() }
      assert.same({ "Wall now (just now): 99c", "Lowest listing: 95c", "Supply: 202 units" },
        Grid({ "wallNow", "lowestListing", "supply" }))
    end)

    it("shows a dash for everything an unseen item lacks", function()
      _G.C_Item = {}
      ns.R().days[ID], ns.R().watch[ID] = nil, nil
      assert.same({ "Current: -", "Median (0 days): -", "7-day trend: -", "Min: -", "Points: -", "Vendor: -", "Your buy / sell: -" },
        Grid({ "current", "median", "trend", "rangeMin", "rangePoints", "vendor", "limits" }, PV.RANGES[3]))
    end)
  end)

  describe("weekly history", function()
    local ID, DAY = 777, 86400
    local today, monday

    -- One recorded day: wall, lowest and highest wall that day
    local function Day(day, wall, low, high)
      ns.R().days[ID][day] = { wall, low or wall, high or wall, 10, wall }
    end

    local function Week(start, wall, low, high)
      return { start = start, wall = wall, low = low or wall, high = high or wall }
    end

    local function Record()
      ns.Record(ID, { { p = 500, q = 50 } }, 50, time())
    end

    local function SavedWeeks()
      return ns.UnpackWeeks(ns.R().weeks[ID])
    end

    before_each(function()
      today = ns.Today()
      monday = today - 60 - (today - 60 + 3) % 7
      ns.R().days[ID] = {}
    end)

    it("packs weeks into one string and back, gold prices included", function()
      local weeks = { Week(monday - 7, 12345678, 12000000, 13000000), Week(monday, 95, 90, 99) }
      local packed = ns.PackWeeks(weeks)
      assert.equal("string", type(packed))
      assert.same(weeks, ns.UnpackWeeks(packed))
      assert.is_nil(ns.PackWeeks({}))
      assert.same({}, ns.UnpackWeeks(nil))
    end)

    it("keeps a week with no data as an empty segment", function()
      local weeks = { Week(monday - 14, 100), Week(monday, 300) }
      local packed = ns.PackWeeks(weeks)
      assert.truthy(packed:find(";;", 1, true))
      assert.same(weeks, ns.UnpackWeeks(packed))
    end)

    it("folds expired days into their Monday-start week with the median, low and high", function()
      assert.equal("1", date("%w", ns.DayStart(monday) + DAY / 2))   -- Monday in local time
      Day(monday, 100, 90, 105)
      Day(monday + 3, 300, 280, 320)
      Day(monday + 6, 120, 110, 130)   -- Sunday ends the week
      Day(monday + 7, 400)             -- the next Monday starts another
      Record()
      assert.same({ Week(monday, 120, 90, 320), Week(monday + 7, 400) }, SavedWeeks())
      for day in pairs(ns.R().days[ID]) do assert.is_true(day > today - 30) end
    end)

    it("appends a folded week to the saved ones, after a gap", function()
      ns.R().weeks[ID] = ns.PackWeeks({ Week(monday - 21, 50) })
      Day(monday, 200)
      Record()
      assert.same({ Week(monday - 21, 50), Week(monday, 200) }, SavedWeeks())
    end)

    it("merges a folded week older than the saved ones into an ordered string", function()
      ns.R().weeks[ID] = ns.PackWeeks({ Week(monday - 7, 50), Week(monday, 60) })
      Day(monday - 21, 200)   -- older than the first saved week
      Day(monday, 300)        -- the same week as a saved one: the folded data wins
      ns.FoldWeeks(ID, today)
      assert.same({ Week(monday - 21, 200), Week(monday - 7, 50), Week(monday, 300) }, SavedWeeks())
    end)

    it("unpacks a malformed string to no weeks without raising", function()
      local first = ns.PackWeeks({ Week(monday, 100) }):match("^[^;]+")   -- a valid Monday
      assert.equal(1, #ns.UnpackWeeks(first .. ";2s,0,0"))
      for _, text in ipairs({ "", "garbage", "zz;1,2", first .. ";2n9,1c", first .. ";!!,0,0", first .. ";2s,0,0,9", ";;", 42 }) do
        assert.same({}, ns.UnpackWeeks(text))
      end
    end)

    it("keeps the days of a week straddling the cutoff until the whole week has expired", function()
      Day(monday - 1, 100)   -- the Sunday before
      Day(monday, 200)
      Day(monday + 1, 300)
      ns.FoldWeeks(ID, monday + 3)
      assert.same({ Week(monday - 7, 100) }, SavedWeeks())
      assert.is_not_nil(ns.R().days[ID][monday])
      assert.is_not_nil(ns.R().days[ID][monday + 1])
    end)

    it("does not fold a watched item's days", function()
      ns.R().watch[ID] = {}
      Day(monday, 100)
      Day(today - 400, 100)
      Record()
      assert.is_nil(ns.R().weeks[ID])
      assert.is_not_nil(ns.R().days[ID][monday])
      assert.is_nil(ns.R().days[ID][today - 400])
    end)

    it("keeps the newest 52 weeks, trimming the oldest", function()
      local weeks = {}
      for i = 1, 52 do weeks[i] = Week(monday - (53 - i) * 7, i) end
      ns.R().weeks[ID] = ns.PackWeeks(weeks)
      Day(monday, 100)
      Record()
      local saved = SavedWeeks()
      assert.equal(52, #saved)
      assert.same(Week(monday - 51 * 7, 2), saved[1])
      assert.same(Week(monday, 100), saved[52])
    end)

    it("stays under 1 KB for a full year of gold-priced weeks", function()
      local weeks = {}
      for i = 1, 52 do weeks[i] = Week(monday - (52 - i) * 7, 1500000 + i, 1400000, 1600000) end
      assert.is_true(#ns.PackWeeks(weeks) < 1024)
    end)
  end)
end)
