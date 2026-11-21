local addon = require("spec.helpers.addon")

local ID = 7001
local CUT = 0.05
local Plain = addon.Plain

describe("thin items", function()
  local ns

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    _G.C_Item = { GetItemInfo = function() return "Ring", "link", 4, 30, 1, "", "", 1, "", 0, 0, 4 end }
    MarketWallDB.cfg.mobDisenchant = "never"
    MarketWallDB.cfg.mobSkinning = "never"
  end)

  after_each(function() _G.C_Item, _G.IsShiftKeyDown = nil, nil end)

  -- Walls by how many days ago they were recorded
  local function SeedDays(wallsByAgo)
    local days = {}
    for ago, wall in pairs(wallsByAgo) do days[ns.Today() - ago] = { wall } end
    ns.R().days[ID] = days
  end

  describe("recording", function()
    it("records a day for an unwatched item with one unit listed", function()
      ns.Record(ID, { { p = 5000, q = 1 } }, 1, time())
      assert.equal(5000, ns.R().days[ID][ns.Today()][1])
    end)
  end)

  describe("ValuationWall", function()
    it("prices a thin item at the median of its last 30 days, so one outlier day does not move it", function()
      SeedDays({ [0] = 90000, [1] = 1000, [2] = 1200, [5] = 1100 })
      assert.same({ 1150, false }, { ns.ValuationWall(ID) })
    end)

    it("ignores days older than 30", function()
      SeedDays({ [0] = 1000, [30] = 50000, [31] = 50000, [40] = 50000 })
      assert.same({ 1000, false }, { ns.ValuationWall(ID) })
    end)

    it("falls back to the latest wall when a thin item has no day in the last 30", function()
      SeedDays({ [35] = 2000, [40] = 3000 })
      assert.same({ 2000, false }, { ns.ValuationWall(ID) })
    end)

    it("prices a supplied item at its latest wall", function()
      SeedDays({ [0] = 90000, [1] = 1000, [2] = 1200 })
      ns.R().supplied = { [ID] = true }
      assert.same({ 90000, true }, { ns.ValuationWall(ID) })
    end)

    it("is nil without history", function()
      assert.is_nil(ns.ValuationWall(ID))
    end)
  end)

  it("values the outlet, Market and Optimal at the thin median", function()
    SeedDays({ [0] = 90000, [1] = 1000, [2] = 1000 })
    local v = ns.Outlet.Game()(ID, 0)
    assert.same({ 950, true }, { v.auction, v.thin })
    local lens = ns.Mobs.Lenses(ns.Mobs.GamePrices(), ns.Mobs.GameOptions(), {})
    assert.same({ 950, 950 }, { lens.market(ID), lens.optimal(ID) })
  end)

  it("leaves Snipes and Dips on the live scan's wall", function()
    SeedDays({ [0] = 100, [1] = 5000, [2] = 5000 })
    local ladder = { { p = 50, q = 10 }, { p = 100, q = 200 } }
    local snipe = ns.FullScanDeals(ID, ladder, 210, 100, 50, ns.StatsFor(ID), CUT)
    assert.equal(100, snipe.wall)
  end)

  describe("tooltip, with Shift held", function()
    local function Lines()
      local lines = {}
      ns.TooltipLines.Add({
        AddLine = function(_, text) lines[#lines + 1] = Plain(text) end,
        AddDoubleLine = function(_, left, right) lines[#lines + 1] = Plain(left) .. "|" .. Plain(right) end,
      }, ID)
      return table.concat(lines, "\n")
    end

    before_each(function() _G.IsShiftKeyDown = function() return true end end)

    it("says when an item was last seen more than 3 days ago", function()
      SeedDays({ [4] = 1000 })
      assert.truthy(Lines():find("Last seen|4 days ago", 1, true))
    end)

    it("says nothing at 3 days or fewer", function()
      SeedDays({ [3] = 1000 })
      assert.falsy(Lines():find("Last seen", 1, true))
    end)
  end)
end)
