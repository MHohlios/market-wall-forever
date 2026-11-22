local addon = require("spec.helpers.addon")

-- Live item searches once saved walls divided by each row's quantity: the one-time repair
describe("repairing divided walls", function()
  local FIRST_SEEN = 20779   -- 2026-11-22
  local ns, r, stacks

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    r = ns.R()
    stacks = {}
    _G.C_Item = { GetItemMaxStackSizeByID = function(id) return stacks[id] end, RequestLoadItemDataByID = function() end }
  end)
  after_each(function() _G.C_Item = nil end)

  -- A day with one observation: wall, low and high all one value
  local function Day(wall) return { wall, wall, wall, 10, wall } end

  -- Green Silk Pack's day on 2026-11-22: the 11:58 full scan saw 59s25c, then a live search
  -- saved 1s57c over it
  local function DividedDay()
    return { 157, 157, 5925, 126, 157, { [3] = 5925, [4] = 157 } }
  end

  -- Green Silk Pack's days before the divided wall, plus `extra`
  local function GreenSilkPack(extra)
    local days = {
      [FIRST_SEEN - 4] = Day(5797), [FIRST_SEEN - 3] = Day(6000),
      [FIRST_SEEN - 2] = Day(6300), [FIRST_SEEN - 1] = Day(6150),
    }
    for day, d in pairs(extra) do days[day] = d end
    return days
  end

  local function Snap(day, wall) return { ns.DayStart(day) + 60, wall, wall, 10 } end

  it("restores a divided wall from the day's high, and drops its day part and snapshot", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = DividedDay(), [FIRST_SEEN + 3] = DividedDay() })   -- installed days later
    r.snaps[5764] = { Snap(FIRST_SEEN, 5925), Snap(FIRST_SEEN, 157) }
    assert.same({ 2, 1 }, { ns.RepairDividedWalls() })
    for _, day in ipairs({ FIRST_SEEN, FIRST_SEEN + 3 }) do
      assert.same({ 5925, 5925, 5925, 126, 5925, { [3] = 5925 } }, r.days[5764][day])
    end
    assert.same({ Snap(FIRST_SEEN, 5925) }, r.snaps[5764])
    assert.is_true(r.dividedWallsRepaired)
  end)

  it("keeps a wall a full scan corrected, dropping the divided low, day part and snapshot", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = { 6100, 157, 6200, 126, 6000, { [2] = 157, [3] = 6200, [4] = 6100 } } })
    r.snaps[5764] = { Snap(FIRST_SEEN, 157), Snap(FIRST_SEEN, 6100) }
    assert.same({ 1, 1 }, { ns.RepairDividedWalls() })
    assert.same({ 6100, 6100, 6200, 126, 6000, { [3] = 6200, [4] = 6100 } }, r.days[5764][FIRST_SEEN])
    assert.same({ Snap(FIRST_SEEN, 6100) }, r.snaps[5764])
  end)

  -- Squire's Boots fell from 65s to 10s in one full scan: nothing beside it says divided
  it("leaves a real decline, a single low observation far under the other days", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = Day(1000) })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.same(Day(1000), r.days[5764][FIRST_SEEN])
  end)

  it("leaves days before the divided wall was first seen", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN - 5] = DividedDay() })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.same(DividedDay(), r.days[5764][FIRST_SEEN - 5])
  end)

  it("never touches commodities, or items with fewer than 3 other days", function()
    stacks[13545], stacks[2139] = 20, 1
    r.days[13545] = GreenSilkPack({ [FIRST_SEEN] = DividedDay() })
    r.days[2139] = { [FIRST_SEEN] = DividedDay(), [FIRST_SEEN - 1] = Day(6150), [FIRST_SEEN - 2] = Day(6300) }
    ns.RepairDividedWalls()
    assert.same(DividedDay(), r.days[13545][FIRST_SEEN])
    assert.same(DividedDay(), r.days[2139][FIRST_SEEN])
  end)

  it("runs once", function()
    stacks[5764] = 1
    ns.RepairDividedWalls()
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = DividedDay() })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.same(DividedDay(), r.days[5764][FIRST_SEEN])
  end)

  it("waits for an item whose stack size is still loading, then repairs it", function()
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = DividedDay() })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.same(DividedDay(), r.days[5764][FIRST_SEEN])
    stacks[5764] = 1
    assert.same({ 1, 1 }, { ns.RepairDividedWalls() })
    assert.equal(5925, r.days[5764][FIRST_SEEN][1])
    assert.is_true(r.dividedWallsRepaired)
  end)
end)
