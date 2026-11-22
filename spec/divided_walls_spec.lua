local addon = require("spec.helpers.addon")

-- Live item searches once saved walls divided by each row's quantity: the one-time repair
describe("repairing divided walls", function()
  local ns, r, today, stacks

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    r = ns.R()
    today = ns.Today()
    stacks = {}
    _G.C_Item = { GetItemMaxStackSizeByID = function(id) return stacks[id] end, RequestLoadItemDataByID = function() end }
  end)
  after_each(function() _G.C_Item = nil end)

  -- walls by days ago
  local function Days(walls)
    local days = {}
    for ago, wall in pairs(walls) do days[today - ago] = { wall, wall, wall, 10, wall } end
    return days
  end

  local GREEN_SILK_PACK = { [0] = 157, [1] = 6150, [2] = 6300, [3] = 6000, [4] = 5797 }

  it("drops a non-stacking item's day under a fifth of its other days, and its snapshots", function()
    stacks[5764] = 1
    r.days[5764] = Days(GREEN_SILK_PACK)
    r.snaps[5764] = { { ns.DayStart(today - 1) + 60, 6150, 6150, 10 }, { ns.DayStart(today) + 60, 157, 157, 39 } }
    assert.same({ 1, 1 }, { ns.RepairDividedWalls() })
    assert.is_nil(r.days[5764][today])
    assert.equal(6150, r.days[5764][today - 1][1])
    assert.equal(1, #r.snaps[5764])
    assert.is_true(r.dividedWallsRepaired)
  end)

  it("runs once", function()
    stacks[5764] = 1
    ns.RepairDividedWalls()
    r.days[5764] = Days(GREEN_SILK_PACK)
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.equal(157, r.days[5764][today][1])
  end)

  it("never touches commodities, or items with fewer than 3 other days", function()
    stacks[13545], stacks[2139] = 20, 1
    r.days[13545] = Days(GREEN_SILK_PACK)
    r.days[2139] = Days({ [0] = 157, [1] = 6150, [2] = 6300 })
    ns.RepairDividedWalls()
    assert.equal(157, r.days[13545][today][1])
    assert.equal(157, r.days[2139][today][1])
  end)

  it("looks only at the last 30 days", function()
    stacks[5764] = 1
    r.days[5764] = Days({ [31] = 157, [40] = 6150, [41] = 6300, [42] = 6000, [0] = 6000 })
    ns.RepairDividedWalls()
    assert.equal(157, r.days[5764][today - 31][1])
  end)

  it("waits for an item whose stack size is still loading, then repairs it", function()
    r.days[5764] = Days(GREEN_SILK_PACK)
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.equal(157, r.days[5764][today][1])
    stacks[5764] = 1
    assert.same({ 1, 1 }, { ns.RepairDividedWalls() })
    assert.is_nil(r.days[5764][today])
    assert.is_true(r.dividedWallsRepaired)
  end)
end)
