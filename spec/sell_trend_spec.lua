local addon = require("spec.helpers.addon")

describe("Sell 7-day trend", function()
  local trend
  before_each(function() trend = addon.Load().SellTrend end)

  local function Points(...)
    local out = {}
    for i, w in ipairs({ ... }) do out[i] = { t = i, w = w } end
    return out
  end

  it("has no summary without points and no trend from one point", function()
    assert.is_nil(trend.WeekSummary({}))
    assert.is_nil(trend.WeekSummary(Points(100)).trend)
  end)

  it("measures the trend from the first to the last point only", function()
    local week = trend.WeekSummary(Points(100, 500, 10, 110))
    assert.is_true(math.abs(week.trend - 0.10) < 1e-9)
    assert.equal(10, week.low)
    assert.equal(500, week.high)
    assert.equal(180, week.average)
  end)

  it("calls moves within 3% flat, including the edge", function()
    assert.equal("flat", trend.TrendText(0))
    assert.equal("flat", trend.TrendText(0.03))
    assert.equal("flat", trend.TrendText(-0.03))
  end)

  it("calls a computed 3% change flat despite float error", function()
    assert.equal("flat", trend.TrendText(1030 / 1000 - 1))
    assert.equal("flat", trend.TrendText(970 / 1000 - 1))
  end)

  it("names moves past 3% up or down with the rounded percent", function()
    assert.truthy(trend.TrendText(0.031):find("up 3%%"))
    assert.truthy(trend.TrendText(-0.126):find("down 13%%"))
  end)
end)
