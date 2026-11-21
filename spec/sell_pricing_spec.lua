local addon = require("spec.helpers.addon")

local Plain = addon.Plain

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
      assert.same({ price = 205, source = "wall", skipped = false }, P.StartingPrice(ID))
      List({ [20] = 2 })
      ns.R().bait[ID] = bait   -- only the bait is listed
      assert.same({ price = 205, source = "wall", skipped = true }, P.StartingPrice(ID))
    end)

    it("has no price without listings or history", function()
      assert.is_nil(P.StartingPrice(ID))
    end)
  end)

  describe("info line", function()
    local start = { price = 198, source = "lowest", skipped = true }

    it("says where the price came from and how far under the wall it is", function()
      assert.equal("Set to the lowest listing, 1s 98c (bait level skipped). That's 3% under the 2s 5c wall.",
        Plain(P.InfoLine(198, start, 205)))
    end)

    it("says nothing about the wall at or over it", function()
      assert.equal("Set to the lowest listing, 2s 5c.",
        Plain(P.InfoLine(205, { price = 205, source = "lowest" }, 205)))
      assert.equal("", P.InfoLine(210, start, 205))
    end)

    it("describes a price the player typed against the wall", function()
      assert.equal("This price is 50% under the 2s wall.", Plain(P.InfoLine(100, start, 200)))
      assert.equal("This price is just under the 20g wall.", Plain(P.InfoLine(199999, start, 200000)))
    end)

    it("names the wall fallback", function()
      assert.equal("No listings loaded, so the price starts at the last recorded wall, 2s 5c.",
        Plain(P.InfoLine(205, { price = 205, source = "wall" }, 205)))
    end)

    it("says when listings are loaded but every level is flagged bait", function()
      assert.equal("Every level listed is flagged bait, so the price starts at the last recorded wall, 2s 5c.",
        Plain(P.InfoLine(205, { price = 205, source = "wall", skipped = true }, 205)))
    end)
  end)

  describe("warnings", function()
    local stats = { n = 9, p25 = 199, p75 = 200, median = 200 }
    local onAuction = { outlet = "auction" }

    local function Warnings(f)
      f.outlet = f.outlet or onAuction
      local out = {}
      for i, line in ipairs(P.Warnings(f)) do out[i] = Plain(line) end
      return out
    end

    it("has none for a sound price", function()
      assert.same({}, Warnings({ price = 199, stats = stats, totals = P.Totals(199, 10, 100, 40, 0.05) }))
    end)

    it("warns below the low end of the normal range, not at it", function()
      assert.same({ "Below expected: 1s 98c is under this item's normal range (1s 99c - 2s)." },
        Warnings({ price = 198, stats = stats }))
      assert.same({}, Warnings({ price = 199, stats = stats }))
    end)

    it("warns from an item's first scan, against today's wall", function()
      local firstScan = W.Stats({}, 200)
      assert.same({ "Below expected: 1s 99c is under this item's normal range (2s - 2s)." },
        Warnings({ price = 199, stats = firstScan }))
    end)

    it("does not warn with no normal range at all", function()
      assert.same({}, Warnings({ price = 1, stats = { n = 0 } }))
    end)

    -- the same totals that colour "AH beats vendor by", so the two always agree
    it("warns when a vendor pays as much or more after the cut and deposit", function()
      -- 92 at 40c: 3,496c after the cut, minus a 276c deposit is 3,220c, 35c each
      assert.same({ "A vendor pays more: 40c each, against 35c after the cut and deposit." },
        Warnings({ price = 40, totals = P.Totals(40, 92, 276, 40, 0.05) }))
      assert.same({ "A vendor pays as much: 40c each, against 40c after the cut and deposit." },
        Warnings({ price = 50, totals = P.Totals(50, 10, 75, 40, 0.05) }))   -- 475 - 75 = 400, a tie
      assert.same({}, Warnings({ price = 50, totals = P.Totals(50, 10, 74, 40, 0.05) }))
    end)

    it("does not compare with a vendor for an item with no vendor price", function()
      assert.same({}, Warnings({ price = 1, totals = P.Totals(1, 1, 50, nil, 0.05) }))
      assert.same({}, Warnings({ price = 1, totals = P.Totals(1, 1, 50, 0, 0.05) }))
    end)

    it("warns at a bait price", function()
      local bait = { p = 20, u = 2, q = 2, w = 205, seen = 2 }
      assert.same({ "Matches a bait price: 2 units at 20c sits 90% under the 2s 5c wall. Likely bait; don't match it." },
        Warnings({ price = 20, bait = bait }))
      assert.same({}, Warnings({ price = 198, bait = bait }))
    end)

    it("names a better outlet than the auction house", function()
      local de = O.Values({ vendor = 100, wall = 1000, supplied = true, disenchant = 2000, cut = 0.05 })
      assert.same({ "Best outlet is disenchanting: 19s each after fees, more than the auction house or a vendor." },
        Warnings({ price = 1000, outlet = de }))
      local vendor = O.Values({ vendor = 100, wall = 100, supplied = true, cut = 0.05 })
      assert.same({ "Best outlet is a vendor: 1s each, at least what the auction house pays after fees." },
        Warnings({ price = 1000, outlet = vendor }))
      local thinUnderVendor = O.Values({ vendor = 1000, wall = 1000, supplied = false, cut = 0.05 })
      assert.same({ "Best outlet is a vendor: 10s each, at least what the auction house pays after fees." },
        Warnings({ price = 1000, outlet = thinUnderVendor }))
      assert.same({}, Warnings({ price = 1000, outlet = O.Values({ vendor = 10, cut = 0.05 }) }))
    end)

    it("notes a thin market under the Minimum supply setting when it is the best outlet", function()
      local thin = O.Values({ vendor = 9500, wall = 20000, supplied = false, disenchant = 8900, cut = 0.05 })
      assert.same({ "Thin market: fewer than 20 listed." }, Warnings({ price = 20000, outlet = thin }))
      MarketWallDB.cfg.minSupply = 8
      assert.same({ "Thin market: fewer than 8 listed." }, Warnings({ price = 20000, outlet = thin }))
      local supplied = O.Values({ vendor = 9500, wall = 20000, supplied = true, cut = 0.05 })
      assert.same({}, Warnings({ price = 20000, outlet = supplied }))
    end)

    it("never sends an item with no vendor price to a vendor", function()
      local reliable = { "No reliable price: the auction house nets nothing after the cut and deposit." }
      for _, vendor in ipairs({ 0, false }) do
        local nothingNet = O.Values({ vendor = vendor or nil, wall = 10, supplied = true, deposit = 9.5, cut = 0.05 })
        assert.same(reliable, Warnings({ price = 10, outlet = nothingNet }))   -- 9.5 after the cut, minus 9.5
      end
    end)
  end)

  describe("asking before a post", function()
    local range = { n = 9, p25 = 229, p75 = 279, median = 250 }   -- 2s 29c to 2s 79c
    local bait = { p = 20, u = 2, q = 2, w = 205, seen = 2 }

    local function Ask(f)
      local out = {}
      for i, line in ipairs(P.AskFirst(f)) do out[i] = Plain(line) end
      return out
    end

    it("does not ask a little under the range, though the page warns", function()
      assert.same({}, Ask({ price = 219, stats = range }))   -- 4% under
      assert.equal(1, #P.Warnings({ price = 219, stats = range, outlet = { outlet = "auction" } }))
    end)

    it("asks well under the range, saying how far", function()
      assert.same({ "1s 37c is 40% under this item's normal range (2s 29c - 2s 79c)." },
        Ask({ price = 137, stats = range }))
    end)

    it("asks only past 30% under for an item up to 1g", function()
      assert.same({}, Ask({ price = 161, stats = range }))   -- the cutoff is 160.3c
      assert.equal(1, #Ask({ price = 160, stats = range }))
      local gold = { n = 9, p25 = 10000, p75 = 12000, median = 11000 }
      assert.same({}, Ask({ price = 7010, stats = gold }))   -- the cutoff is 7,000c
      assert.equal(1, #Ask({ price = 6990, stats = gold }))
    end)

    it("slides toward 70% under as the item gets dearer", function()
      local tenGold = { n = 9, p25 = 100000, p75 = 120000, median = 110000 }   -- the cutoff is 34% of it
      assert.same({}, Ask({ price = 34010, stats = tenGold }))
      assert.same({ "3g 39s 90c is 66% under this item's normal range (10g - 12g)." }, Ask({ price = 33990, stats = tenGold }))
      local twentyGold = { n = 9, p25 = 200000, p75 = 220000, median = 210000 }   -- 32%
      assert.same({}, Ask({ price = 64010, stats = twentyGold }))
      assert.equal(1, #Ask({ price = 63990, stats = twentyGold }))
    end)

    it("does not ask when a vendor pays more, or the market is thin", function()
      local totals = P.Totals(229, 92, 276, 400, 0.05)
      assert.is_true(totals.beats < 0)
      assert.same({}, Ask({ price = 229, stats = range, totals = totals }))
      assert.same({}, Ask({ price = 229, stats = range, outlet = O.Values({ vendor = 10, wall = 1000, supplied = false, cut = 0.05 }) }))
    end)

    it("has no percentage to ask without a normal range", function()
      assert.same({}, Ask({ price = 1 }))
      assert.same({}, Ask({ price = 1, stats = { n = 0 } }))
    end)

    it("asks at a bait price, even with no range or one seen once", function()
      local line = "Matches a bait price: 2 units at 20c sits 90% under the 2s 5c wall. Likely bait; don't match it."
      assert.same({ line }, Ask({ price = 20, bait = bait }))
      assert.equal(1, #Ask({ price = 20, bait = { p = 20, u = 2, q = 2, w = 205, seen = 1 } }))
      assert.same({}, Ask({ price = 198, bait = bait }))
    end)

    it("lists both reasons when both apply", function()
      assert.equal(2, #Ask({ price = 20, stats = range, bait = bait }))
    end)
  end)

  describe("totals", function()
    it("takes the cut, then the deposit as a cost, and compares with the vendor", function()
      -- the mockup's 92 Silk Cloth at 2s 5c, a 27s 60c deposit and 40c at a vendor
      local t = P.Totals(205, 92, 2760, 40, 0.05)
      assert.same({ 18860, 17917, 2760, 15157, 3680, 11477, 40 },
        { t.total, t.afterCut, t.deposit, t.net, t.vendor, t.beats, t.vendorEach })
      assert.near(15157 / 92, t.netEach, 1e-9)
    end)

    it("leaves the vendor out for an item with no vendor price", function()
      local t = P.Totals(205, 92, 2760, nil, 0.05)
      assert.same({ nil, nil, nil }, { t.vendor, t.beats, t.vendorEach })
      assert.is_nil(P.Totals(205, 92, 2760, 0, 0.05).beats)
    end)
  end)

  describe("answer", function()
    local function Answer(price, quantity, deposit, vendorEach)
      local a = P.Answer(P.Totals(price, quantity, deposit, vendorEach, 0.05), quantity, price, 0.05)
      return { Plain(a.net), Plain(a.versus), Plain(a.breakdown) }, a
    end

    it("says what the auction house pays and how much more than a vendor, in green", function()
      -- the mockup's 17 Roasted Boar Meat at 10c, a 20c deposit and 6c at a vendor
      local text, a = Answer(10, 17, 20, 6)
      assert.same({ "1s 42c", "+40c more than vendor (1s 2c)", "17 × 10c = 1s 70c · 5% cut -8c · deposit -20c" }, text)
      assert.truthy(a.versus:find("^|cff4fc36b"))
    end)

    it("shows exact amounts, and a breakdown that adds up to the rounded net", function()
      -- 92 at 2s 5c: a cut of 943c, a net of 15157c
      local text = Answer(205, 92, 2760, 40)
      assert.same({ "1g 51s 57c", "+1g 14s 77c more than vendor (36s 80c)",
        "92 × 2s 5c = 1g 88s 60c · 5% cut -9s 43c · deposit -27s 60c" }, text)
    end)

    it("says in red how much less the auction house pays when a vendor wins", function()
      local text, a = Answer(40, 92, 276, 40)
      assert.equal("4s 60c less than vendor (36s 80c)", text[2])
      assert.truthy(a.versus:find("^|cffe06060"))
      assert.equal("The same as vendor (4s)", Answer(50, 10, 75, 40)[2])
    end)

    it("says when a vendor won't buy the item", function()
      assert.equal("A vendor won't buy this.", Answer(205, 92, 2760, nil)[2])
    end)

    it("shows a net the deposit eats in red", function()
      local text, a = Answer(1, 5, 20, nil)
      assert.equal("-15c", text[1])
      assert.truthy(a.net:find("^|cffe06060"))
    end)
  end)

  describe("outlet line", function()
    it("compares the three outlets, with a dash where one does not apply", function()
      local v = O.Values({ vendor = 40, wall = 205, supplied = true, deposit = 15.75, cut = 0.05 })
      assert.equal("AH 1s 79c after cut and deposit · Vendor 40c · Disenchant —", Plain(P.OutletLine(v)))
      assert.equal("AH — · Vendor — · Disenchant 1s 90c", Plain(P.OutletLine(O.Values({ disenchant = 200, cut = 0.05 }))))
    end)

    it("says when the auction house price is a thin market", function()
      local v = O.Values({ vendor = 40, wall = 205, supplied = false, deposit = 15.75, cut = 0.05 })
      assert.equal("AH 1s 79c after cut and deposit (thin market) · Vendor 40c · Disenchant —", Plain(P.OutletLine(v)))
    end)
  end)

  describe("bag groups", function()
    local function Item(id, count, values) return { id = id, count = count, values = values } end

    local function Summary(groups)
      local summary = {}
      for i, group in ipairs(groups) do
        local ids = {}
        for j, item in ipairs(group.items) do ids[j] = item.id end
        summary[i] = { group.outlet, group.value, ids }
      end
      return summary
    end

    it("groups by outlet in a fixed order, most valuable item first", function()
      local ah = function(best) return { outlet = O.AUCTION, best = best } end
      local groups = P.Groups({
        Item(1, 1, ah(100)), Item(2, 10, { outlet = O.VENDOR, vendor = 50, best = 50 }), Item(3, 5, ah(100)),
        Item(4, 3, { outlet = O.NO_DATA, vendor = 0, best = 0 }),
      })
      assert.same({ { O.AUCTION, 600, { 3, 1 } }, { O.VENDOR, 500, { 2 } }, { O.NO_DATA, 0, { 4 } } }, Summary(groups))
    end)

    it("lists the auction house first even when Vendor is worth more", function()
      local groups = P.Groups({
        Item(1, 1, { outlet = O.AUCTION, best = 996 }), Item(2, 1, { outlet = O.VENDOR, vendor = 1038, best = 1038 }),
      })
      assert.same({ { O.AUCTION, 996, { 1 } }, { O.VENDOR, 1038, { 2 } } }, Summary(groups))
    end)

    it("lists Vendor before Disenchant before No reliable price whatever each is worth", function()
      local groups = P.Groups({
        Item(1, 1, { outlet = O.NO_DATA, vendor = 0, best = 900 }),
        Item(2, 1, { outlet = O.DISENCHANT, best = 500 }),
        Item(3, 1, { outlet = O.VENDOR, vendor = 10, best = 10 }),
      })
      assert.same({ O.AUCTION, O.VENDOR, O.DISENCHANT, O.NO_DATA }, { groups[1].outlet, groups[2].outlet, groups[3].outlet, groups[4].outlet })
    end)

    it("keeps empty auction house and Vendor groups, and leaves out the other empty groups", function()
      assert.same({ { O.AUCTION, 0, {} }, { O.VENDOR, 0, {} } }, Summary(P.Groups({})))
      local groups = P.Groups({ Item(1, 1, { outlet = O.VENDOR, vendor = 5, best = 5 }) })
      assert.same({ { O.AUCTION, 0, {} }, { O.VENDOR, 5, { 1 } } }, Summary(groups))
    end)

    it("puts an item with no vendor price whose auction house nets nothing under No reliable price", function()
      local nothingNet = O.Values({ vendor = 0, wall = 10, supplied = true, deposit = 20, cut = 0.05 })
      assert.equal(O.VENDOR, nothingNet.outlet)   -- Outlet's own values are unchanged
      local groups = P.Groups({ Item(1, 1, nothingNet) })
      assert.same({ O.NO_DATA, 1 }, { groups[3].outlet, #groups[3].items })
      assert.same({ 0, 0 }, { #groups[1].items, #groups[2].items })
    end)

    it("puts a thin market that pays most in the auction house group, with or without a vendor price", function()
      local thin = O.Values({ vendor = 9500, wall = 20000, supplied = false, disenchant = 8900, cut = 0.05 })
      local thinNoVendor = O.Values({ wall = 1000, supplied = false, cut = 0.05 })
      assert.same({ { O.AUCTION, 19000 + 950, { 1, 2 } }, { O.VENDOR, 0, {} } },
        Summary(P.Groups({ Item(1, 1, thin), Item(2, 1, thinNoVendor) })))
    end)
  end)
end)
