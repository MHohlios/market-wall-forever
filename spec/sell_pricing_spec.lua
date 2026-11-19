local addon = require("spec.helpers.addon")

local function Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local ID = 7

describe("Sell page pricing", function()
  local ns, P, O, W
  local walls

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    P, O, W = ns.SellPricing, ns.Outlet, ns.Wall
    walls = {}
    ns.LatestWall = function(id) return walls[id] end
  end)

  local function List(levels)
    local ladder, total = W.SortLadder(levels)
    ns.ladders[ID] = { ladder = ladder, total = total, t = os.time(), kind = "commodity" }
  end

  describe("starting price", function()
    -- the mockup's Silk Cloth: 2 bait units at 20c under a 2s 5c wall
    local bait = { p = 20, u = 2, q = 2, w = 205, first = 1, last = 1, seen = 2 }

    it("starts at the lowest level listed right now", function()
      List({ [198] = 160, [200] = 22, [205] = 1229 })
      walls[ID] = 300
      assert.same({ price = 198, source = "lowest", skipped = false }, P.StartingPrice(ID))
    end)

    it("skips a level Bait Detect has flagged", function()
      List({ [20] = 2, [198] = 160, [205] = 1229 })
      ns.R().bait[ID] = bait
      assert.same({ price = 198, source = "lowest", skipped = true }, P.StartingPrice(ID))
    end)

    it("keeps a level whose bait record is not flagged yet", function()
      List({ [20] = 2, [198] = 160, [205] = 1229 })
      ns.R().bait[ID] = { p = 20, u = 2, q = 2, w = 205, first = 1, last = 1, seen = 1 }
      assert.equal(20, P.StartingPrice(ID).price)
    end)

    it("falls back to the last recorded wall without live listings", function()
      walls[ID] = 205
      assert.same({ price = 205, source = "wall" }, P.StartingPrice(ID))
      List({ [20] = 2 })
      ns.R().bait[ID] = bait   -- only the bait is listed
      assert.same({ price = 205, source = "wall" }, P.StartingPrice(ID))
    end)

    it("has no price without listings or history", function()
      assert.is_nil(P.StartingPrice(ID))
    end)
  end)

  describe("info line", function()
    local start = { price = 198, source = "lowest", skipped = true }

    it("says where the price came from and how far under the wall it is", function()
      assert.equal("Price set to the lowest listing, 1s 98c (bait level skipped). That's 3% under the 2s 5c wall.",
        Plain(P.InfoLine(198, start, 205)))
    end)

    it("says nothing about the wall at or over it", function()
      assert.equal("Price set to the lowest listing, 2s 5c.",
        Plain(P.InfoLine(205, { price = 205, source = "lowest" }, 205)))
      assert.equal("", P.InfoLine(210, start, 205))
    end)

    it("describes a price the player typed against the wall", function()
      assert.equal("This price is 50% under the 2s 0c wall.", Plain(P.InfoLine(100, start, 200)))
      assert.equal("This price is just under the 20g 0s 0c wall.", Plain(P.InfoLine(199999, start, 200000)))
    end)

    it("names the wall fallback", function()
      assert.equal("No listings loaded, so the price starts at the last recorded wall, 2s 5c.",
        Plain(P.InfoLine(205, { price = 205, source = "wall" }, 205)))
    end)
  end)

  describe("warnings", function()
    local stats = { n = 9, p25 = 199, p75 = 200, median = 200 }
    local onAuction = { outlet = "auction" }

    local function Warnings(f)
      f.netEach = f.netEach or 1000
      f.outlet = f.outlet or onAuction
      local out = {}
      for i, line in ipairs(P.Warnings(f)) do out[i] = Plain(line) end
      return out
    end

    it("has none for a sound price", function()
      assert.same({}, Warnings({ price = 199, stats = stats, vendor = 40, netEach = 189 }))
    end)

    it("warns below the low end of the normal range, not at it", function()
      assert.same({ "Below expected: 1s 98c is under this item's normal range (1s 99c - 2s 0c)." },
        Warnings({ price = 198, stats = stats }))
      assert.same({}, Warnings({ price = 199, stats = stats }))
    end)

    it("needs 3 days of history for the normal range", function()
      assert.same({}, Warnings({ price = 1, stats = { n = 2, p25 = 199, p75 = 200 } }))
    end)

    it("warns when a vendor pays more after the cut and deposit, not when it pays the same", function()
      assert.same({ "A vendor pays more: 40c each, against 35c after the cut and deposit." },
        Warnings({ price = 60, vendor = 40, netEach = 35 }))
      assert.same({}, Warnings({ price = 60, vendor = 40, netEach = 40 }))
      assert.same({}, Warnings({ price = 60, vendor = 0, netEach = -5 }))
    end)

    it("warns at a bait price", function()
      local bait = { p = 20, u = 2, q = 2, w = 205, seen = 2 }
      assert.same({ "Matches a bait price: 2 units at 20c sits 90% under the 2s 5c wall. Likely bait; don't match it." },
        Warnings({ price = 20, bait = bait }))
      assert.same({}, Warnings({ price = 198, bait = bait }))
    end)

    it("names a better outlet than the auction house", function()
      local de = O.Values({ vendor = 100, wall = 1000, supplied = true, disenchant = 2000, cut = 0.05 })
      assert.same({ "Best outlet is disenchanting: 19s 0c each after the cut, more than the auction house or a vendor." },
        Warnings({ price = 1000, outlet = de }))
      local vendor = O.Values({ vendor = 100, wall = 100, supplied = true, cut = 0.05 })
      assert.same({ "Best outlet is a vendor: 1s 0c each, at least what the auction house pays after fees." },
        Warnings({ price = 1000, outlet = vendor }))
      local thin = O.Values({ vendor = 10, wall = 1000, supplied = false, cut = 0.05 })
      assert.same({ "Best outlet is a vendor: the market is too thin to trust." }, Warnings({ price = 1000, outlet = thin }))
      assert.same({}, Warnings({ price = 1000, outlet = O.Values({ vendor = 10, cut = 0.05 }) }))
    end)
  end)

  describe("outlet line", function()
    it("compares the three outlets, with a dash where one does not apply", function()
      local v = O.Values({ vendor = 40, wall = 205, supplied = true, deposit = 15.75, cut = 0.05 })
      assert.equal("AH 1s 79c after cut and deposit · Vendor 40c · Disenchant —", Plain(P.OutletLine(v)))
      assert.equal("AH — · Vendor — · Disenchant 1s 90c", Plain(P.OutletLine(O.Values({ disenchant = 200, cut = 0.05 }))))
    end)
  end)

  describe("bag groups", function()
    local function Item(id, count, values) return { id = id, count = count, values = values } end

    it("groups by outlet, most valuable group and item first", function()
      local ah = function(best) return { outlet = O.AUCTION, best = best } end
      local groups = P.Groups({
        Item(1, 1, ah(100)), Item(2, 10, { outlet = O.VENDOR, best = 50 }), Item(3, 5, ah(100)),
        Item(4, 3, { outlet = O.NO_DATA, best = 0 }),
      })
      local summary = {}
      for i, group in ipairs(groups) do
        local ids = {}
        for j, item in ipairs(group.items) do ids[j] = item.id end
        summary[i] = { group.outlet, group.value, ids }
      end
      assert.same({ { O.AUCTION, 600, { 3, 1 } }, { O.VENDOR, 500, { 2 } }, { O.NO_DATA, 0, { 4 } } }, summary)
    end)
  end)
end)
