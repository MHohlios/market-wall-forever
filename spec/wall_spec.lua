local ns = {}
assert(loadfile("Wall.lua"))("MarketWall", ns)
local W = ns.Wall

local SHARE, MIN_UNITS, CUT = 0.05, 5, 0.05

local function Ladder(map)
  return W.SortLadder(map)
end

describe("Wall.Compute", function()
  it("has no wall for an empty ladder", function()
    assert.is_nil(W.Compute({}, 0, SHARE, MIN_UNITS))
    assert.is_nil(W.Compute(nil, 10, SHARE, MIN_UNITS))
  end)

  it("ignores a few stray cheap units below the real supply", function()
    local ladder, total = Ladder({ [10] = 2, [100] = 50, [120] = 48 })
    local wall, low = W.Compute(ladder, total, SHARE, MIN_UNITS)
    assert.equal(100, wall)
    assert.equal(10, low)
  end)

  it("needs only half the units on thin supply", function()
    -- 3 units: minUnits (5) is out of reach, so the wall is where half the supply sits
    local ladder, total = Ladder({ [10] = 1, [20] = 2 })
    assert.equal(20, (W.Compute(ladder, total, SHARE, MIN_UNITS)))
  end)

  it("treats a single listing as the wall", function()
    local ladder, total = Ladder({ [50] = 1 })
    assert.same({ 50, 50 }, { W.Compute(ladder, total, SHARE, MIN_UNITS) })
  end)

  it("falls back to the top price when the ladder never reaches the share", function()
    local ladder = Ladder({ [10] = 1, [20] = 1 })
    assert.equal(20, (W.Compute(ladder, 1000, SHARE, MIN_UNITS)))
  end)
end)

describe("Wall.UnitsUnder", function()
  local ladder = Ladder({ [10] = 2, [20] = 3, [30] = 4 })

  it("counts only units strictly below the limit", function()
    assert.same({ 5, 80 }, { W.UnitsUnder(ladder, 30) })
  end)

  it("is zero without a limit or ladder", function()
    assert.same({ 0, 0 }, { W.UnitsUnder(ladder, nil) })
    assert.same({ 0, 0 }, { W.UnitsUnder(nil, 30) })
  end)
end)

describe("Wall.Snipe", function()
  it("is nothing without a wall", function()
    assert.same({ 0, 0, 0, 0 }, { W.Snipe({}, nil, CUT) })
  end)

  it("stops at units that would not profit after the cut", function()
    -- wall 100 resells at 95: units at 96 sit under the wall but lose money
    local ladder = Ladder({ [50] = 2, [96] = 10, [100] = 20 })
    local units, cost, profit, discount = W.Snipe(ladder, 100, CUT)
    assert.equal(2, units)
    assert.equal(100, cost)
    assert.equal(90, profit)
    assert.equal(0.5, discount)
  end)

  it("prices resale at a lower reference when the wall is inflated", function()
    local ladder = Ladder({ [50] = 2, [70] = 3, [100] = 20 })
    -- ref 60 resells at 57, so the 70s no longer count
    local units = W.Snipe(ladder, 100, CUT, 60)
    assert.equal(2, units)
  end)
end)

describe("Wall.Percentile", function()
  it("handles empty, single and interpolated cases", function()
    assert.is_nil(W.Percentile({}, 0.5))
    assert.equal(7, W.Percentile({ 7 }, 0.9))
    assert.equal(15, W.Percentile({ 10, 20 }, 0.5))
    assert.equal(20, W.Percentile({ 10, 20 }, 1))
  end)
end)

describe("Wall.Stats", function()
  it("reports n = 0 for no history", function()
    assert.same({ n = 0 }, W.Stats({}))
  end)

  it("stands today's wall in for an item's first scan", function()
    local stats = W.Stats({}, 120)
    assert.same({ 1, 120, 120, 120, true }, { stats.n, stats.median, stats.p25, stats.p75, stats.firstScan })
    assert.is_nil(W.Stats({ 100 }, 120).firstScan)
    assert.equal(100, W.Stats({ 100 }, 120).median)
  end)

  it("uses the last three days for recent, without reordering the input", function()
    local walls = { 100, 100, 100, 100, 40, 50, 60 }
    local stats = W.Stats(walls)
    assert.equal(50, stats.recent)
    assert.equal(100, stats.median)
    assert.equal(40, stats.low)
    assert.equal(100, stats.high)
    assert.same({ 100, 100, 100, 100, 40, 50, 60 }, walls)
  end)
end)

describe("Wall.IsDip", function()
  local DIP = 0.10
  local steady = W.Stats({ 100, 100, 100, 110, 90, 100, 100 })

  local function Reason(wall, stats)
    return select(2, W.IsDip(wall, stats, DIP, CUT))
  end

  it("needs at least one past day: a first scan has nothing to dip from", function()
    assert.equal("history", Reason(50, W.Stats({}, 50)))
    assert.equal("history", Reason(50, W.Stats({})))
    assert.equal("history", Reason(nil, steady))
  end)

  it("can dip from a single past day", function()
    assert.is_true((W.IsDip(50, W.Stats({ 100 }), DIP, CUT)))
  end)

  it("is normal within the dip band", function()
    assert.equal("normal", Reason(95, steady))
  end)

  it("is a dip well under a steady baseline", function()
    assert.is_true((W.IsDip(80, steady, DIP, CUT)))
  end)

  it("is not a dip while the price is already falling", function()
    assert.equal("falling", Reason(50, W.Stats({ 100, 100, 100, 100, 80, 80, 80 })))
  end)

  it("is not a dip when the cut eats the profit", function()
    -- a 25% cut leaves 75 from a 100 median, under today's 80
    assert.equal("noprofit", select(2, W.IsDip(80, steady, DIP, 0.25)))
  end)
end)

describe("Wall.Suggest", function()
  it("uses the quartiles once there is a past day", function()
    assert.same({ 90, 110 }, { W.Suggest(500, W.Stats({ 90, 100, 110, 90, 110 }), CUT) })
  end)

  it("falls back to the wall without history, first scan included", function()
    for _, stats in ipairs({ { n = 0 }, W.Stats({}, 100) }) do
      local buy, sell = W.Suggest(100, stats, CUT)
      assert.equal(95, buy)
      -- 100 * 1.10 is a hair over 110 in floating point, so ceil gives 111
      assert.is_true(sell >= 110 and sell <= 111)
    end
  end)

  it("suggests nothing without a wall or history", function()
    assert.is_nil(W.Suggest(nil, nil, CUT))
  end)

  it("never suggests a sell price that loses money after the cut", function()
    local buy, sell = W.Suggest(nil, W.Stats({ 100, 100, 100 }), CUT)
    assert.equal(100, buy)
    assert.is_true(sell * (1 - CUT) > buy)
  end)
end)
