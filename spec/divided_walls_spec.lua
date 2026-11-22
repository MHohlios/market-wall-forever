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

  -- { [day] = wall } as day records whose wall, low and high are that wall
  local function Days(walls)
    local days = {}
    for day, wall in pairs(walls) do days[day] = { wall, wall, wall, 10, wall } end
    return days
  end

  -- Green Silk Pack's days before the divided wall, then one at 1s57c
  local function GreenSilkPack(extra)
    local walls = { [FIRST_SEEN - 4] = 5797, [FIRST_SEEN - 3] = 6000, [FIRST_SEEN - 2] = 6300, [FIRST_SEEN - 1] = 6150 }
    for day, wall in pairs(extra) do walls[day] = wall end
    return Days(walls)
  end

  local function Snap(day, wall) return { ns.DayStart(day) + 60, wall, wall, 10 } end

  it("drops a non-stacking item's day whose wall is divided, and its snapshots", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = 157, [FIRST_SEEN + 3] = 160 })   -- installed days later
    r.snaps[5764] = { Snap(FIRST_SEEN - 1, 6150), Snap(FIRST_SEEN, 6100), Snap(FIRST_SEEN, 157) }
    assert.same({ 2, 1 }, { ns.RepairDividedWalls() })
    assert.is_nil(r.days[5764][FIRST_SEEN])
    assert.is_nil(r.days[5764][FIRST_SEEN + 3])
    assert.same({ Snap(FIRST_SEEN - 1, 6150) }, r.snaps[5764])
    assert.is_true(r.dividedWallsRepaired)
  end)

  it("keeps a day whose wall a full scan corrected, dropping its divided low, day part and snapshot", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({})
    r.days[5764][FIRST_SEEN] = { 6100, 157, 6200, 126, 6000, { [2] = 157, [3] = 6200, [4] = 6100 } }
    r.snaps[5764] = { Snap(FIRST_SEEN, 157), Snap(FIRST_SEEN, 6100) }
    assert.same({ 1, 1 }, { ns.RepairDividedWalls() })
    assert.same({ 6100, 6100, 6200, 126, 6000, { [3] = 6200, [4] = 6100 } }, r.days[5764][FIRST_SEEN])
    assert.same({ Snap(FIRST_SEEN, 6100) }, r.snaps[5764])
  end)

  it("leaves days before the divided wall was first seen", function()
    stacks[5764] = 1
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN - 5] = 157 })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.equal(157, r.days[5764][FIRST_SEEN - 5][1])
  end)

  it("never touches commodities, or items with fewer than 3 other days", function()
    stacks[13545], stacks[2139] = 20, 1
    r.days[13545] = GreenSilkPack({ [FIRST_SEEN] = 157 })
    r.days[2139] = Days({ [FIRST_SEEN] = 157, [FIRST_SEEN - 1] = 6150, [FIRST_SEEN - 2] = 6300 })
    ns.RepairDividedWalls()
    assert.equal(157, r.days[13545][FIRST_SEEN][1])
    assert.equal(157, r.days[2139][FIRST_SEEN][1])
  end)

  it("runs once", function()
    stacks[5764] = 1
    ns.RepairDividedWalls()
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = 157 })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.equal(157, r.days[5764][FIRST_SEEN][1])
  end)

  it("waits for an item whose stack size is still loading, then repairs it", function()
    r.days[5764] = GreenSilkPack({ [FIRST_SEEN] = 157 })
    assert.same({ 0, 0 }, { ns.RepairDividedWalls() })
    assert.equal(157, r.days[5764][FIRST_SEEN][1])
    stacks[5764] = 1
    assert.same({ 1, 1 }, { ns.RepairDividedWalls() })
    assert.is_nil(r.days[5764][FIRST_SEEN])
    assert.is_true(r.dividedWallsRepaired)
  end)
end)
