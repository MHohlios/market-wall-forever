local addon = require("spec.helpers.addon")

local function Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

describe("price view", function()
  local ns, PV
  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    PV = ns.PriceView
  end)

  describe("7-day trend", function()
    local function Points(...)
      local out = {}
      for i, w in ipairs({ ... }) do out[i] = { t = i, w = w } end
      return out
    end

    it("has no summary without points and no trend from one point", function()
      assert.is_nil(PV.WeekSummary({}))
      assert.is_nil(PV.WeekSummary(Points(100)).trend)
    end)

    it("measures the trend from the first to the last point only", function()
      local week = PV.WeekSummary(Points(100, 500, 10, 110))
      assert.is_true(math.abs(week.trend - 0.10) < 1e-9)
      assert.equal(10, week.low)
      assert.equal(500, week.high)
      assert.equal(180, week.average)
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

  describe("stats grid", function()
    local ID = 12359
    local today

    -- One recorded day: wall, lowest and highest wall that day, units, lowest listing
    local function Day(ago, wall, low, high)
      ns.R().days[ID][today - ago] = { wall, low or wall, high or wall, 100, wall }
    end

    local function Grid(keys)
      local out = {}
      for _, cell in ipairs(PV.Cells(PV.Facts(ID, time()), keys)) do
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

    it("fills the search window's cells from the item's history", function()
      assert.same({
        "Last wall (yesterday): 1s 0c",
        "Median (5 days): 1s 0c",
        "Normal range: 1s 0c - 1s 10c",
        "7-day average: 1s 4c",
        "7-day trend: flat",
        "Lowest / highest: 80c / 2s 10c",
        "Days of data: 6",
        "Vendor: 2c",
        "Disenchant: -",
        "Your buy / sell: 90c / 1s 20c",
      }, Grid({ "lastWall", "median", "normalRange", "average", "trend", "lowHigh", "days", "vendor", "disenchant", "limits" }))
    end)

    it("fills the Sell page's cells from the same facts, with no live listings loaded", function()
      assert.same({
        "Wall (last scan): 1s 0c",
        "Lowest listing: -",
        "Supply: -",
        "Vs median: +0% (normal)",
      }, Grid({ "wallNow", "lowestListing", "supply", "versusMedian" }))
    end)

    it("prefers live listings for the wall, with their age", function()
      ns.ladders[ID] = { ladder = { { p = 95, q = 2 }, { p = 99, q = 200 } }, total = 202, t = time() }
      assert.same({ "Wall now (just now): 99c", "Lowest listing: 95c", "Supply: 202 units", "Last wall (just now): 99c" },
        Grid({ "wallNow", "lowestListing", "supply", "lastWall" }))
    end)

    it("shows a dash for everything an unseen item lacks", function()
      _G.C_Item = {}
      ns.R().days[ID], ns.R().watch[ID] = nil, nil
      assert.same({ "Last wall: -", "Median (0 days): -", "7-day trend: -", "Lowest / highest: -", "Days of data: -", "Vendor: -", "Your buy / sell: -" },
        Grid({ "lastWall", "median", "trend", "lowHigh", "days", "vendor", "limits" }))
    end)
  end)
end)
