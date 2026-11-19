local addon = require("spec.helpers.addon")

local CUT = 0.05

describe("Outlet", function()
  local ns, O

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    O = ns.Outlet
  end)

  local function Values(p)
    p.cut = p.cut or CUT
    return O.Values(p)
  end

  describe("classification", function()
    it("sends an item to the auction house when its wall after the cut and deposit beats both", function()
      local v = Values({ vendor = 100, wall = 1000, supplied = true, disenchant = 500, deposit = 50 })
      assert.same({ O.AUCTION, 900, 900 }, { v.outlet, v.auction, v.best })
    end)

    it("counts the deposit, so a vendor that pays as much wins", function()
      assert.equal(O.AUCTION, Values({ vendor = 90, wall = 100, supplied = true, deposit = 4 }).outlet)   -- 91 net
      assert.equal(O.VENDOR, Values({ vendor = 90, wall = 100, supplied = true, deposit = 5 }).outlet)    -- 90 net, a tie
    end)

    it("sends an item to disenchanting when its materials after the cut beat both", function()
      local v = Values({ vendor = 100, wall = 1000, supplied = true, disenchant = 2000 })
      assert.same({ O.DISENCHANT, 1900 }, { v.outlet, v.best })
      -- a tie with the auction house stays on the auction house
      assert.equal(O.AUCTION, Values({ vendor = 100, wall = 1000, supplied = true, disenchant = 1000 }).outlet)
    end)

    it("leaves disenchanting out when it is not counted", function()
      assert.equal(O.AUCTION, Values({ vendor = 100, wall = 1000, supplied = true, disenchant = nil }).outlet)
    end)

    it("sends an item to a vendor when the market is too thin to trust", function()
      local v = Values({ vendor = 10, wall = 1000, supplied = false })
      assert.same({ O.VENDOR, true, 950, 10, 10 }, { v.outlet, v.thin, v.auction, v.market, v.best })
    end)

    it("has no market data without any wall history, but still values the other outlets", function()
      local v = Values({ vendor = 10, disenchant = 200 })
      assert.same({ O.NO_DATA, nil, 190 }, { v.outlet, v.auction, v.best })
    end)
  end)

  -- The same inputs through the mob values' lenses: Optimal is the chosen outlet's worth
  describe("agreement with the Mobs Optimal lens", function()
    local CASES = {
      { vendor = 100, wall = 1000, supplied = true, disenchant = 500 },     -- auction house
      { vendor = 100, wall = 1000, supplied = true, disenchant = 2000 },    -- disenchant
      { vendor = 100, wall = 100, supplied = true },                        -- vendor
      { vendor = 10, wall = 1000, supplied = false, disenchant = 5 },       -- thin market
      { vendor = 10, disenchant = 200 },                                    -- no data
      { wall = 300, supplied = true },                                      -- no vendor price
    }

    it("picks the outlet whose value the Optimal lens gives", function()
      for i, case in ipairs(CASES) do
        local prices = {
          vendor = function() return case.vendor end,
          wall = function() return case.wall, case.supplied end,
          deposit = function() return 0 end,
          disenchant = function() return case.disenchant end,
        }
        local lens = ns.Mobs.Lenses(prices, { cut = CUT, disenchant = true }, {})
        local v = Values(case)
        local chosen = ({ [O.AUCTION] = v.market, [O.DISENCHANT] = v.disenchant, [O.VENDOR] = v.vendor })[v.outlet]
        assert.equal(lens.optimal(i), v.best)
        assert.equal(lens.market(i), v.market)
        if chosen then assert.equal(lens.optimal(i), chosen) end
      end
    end)
  end)

  describe("in game", function()
    local ITEM = 7001

    before_each(function()
      _G.C_Item = { GetItemInfo = function() return "Ring", "link", 2, 30, 1, "", "", 1, "", 0, 100, 4 end }
      ns.LatestWall = function() return 1000 end
      ns.R().supplied = { [ITEM] = true }
      ns.DisenchantValue = function() return 5000 end
      ns.EnchantingSkill = function() return 0 end
    end)

    after_each(function() _G.C_Item = nil end)

    it("follows the mob-value disenchanting setting", function()
      MarketWallDB.cfg.mobDisenchant = "never"
      assert.equal(O.AUCTION, O.Game()(ITEM, 0).outlet)
      MarketWallDB.cfg.mobDisenchant = "always"
      assert.equal(O.DISENCHANT, O.Game()(ITEM, 0).outlet)
      MarketWallDB.cfg.mobDisenchant = "auto"   -- without Enchanting
      assert.equal(O.AUCTION, O.Game()(ITEM, 0).outlet)
    end)

    it("takes the Sell page's real deposit for one unit off the auction house", function()
      MarketWallDB.cfg.mobDisenchant = "never"
      assert.equal(940, O.Game()(ITEM, 10).auction)
    end)

    it("estimates the deposit at the Sell page's duration when there is no real one", function()
      MarketWallDB.cfg.mobDisenchant = "never"
      assert.equal(950 - 30, O.Game()(ITEM).auction)   -- 30% of the 100c vendor price for 24h
      MarketWallDB.cfg.sellDuration = 3
      assert.equal(950 - 60, O.Game()(ITEM).auction)
    end)
  end)

  describe("disenchant net", function()
    it("takes the cut off the materials, then the deposits to list them", function()
      local v = Values({ vendor = 100, wall = 1000, supplied = true, disenchant = 2000, disenchantDeposit = 150 })
      assert.same({ O.DISENCHANT, 1750 }, { v.outlet, v.disenchant })
    end)

    it("can lose to the auction house once the material deposits count", function()
      local p = { vendor = 100, wall = 1000, supplied = true, disenchant = 1100 }   -- 1045 against 950
      assert.equal(O.DISENCHANT, Values(p).outlet)
      p.disenchantDeposit = 100
      assert.equal(O.AUCTION, Values(p).outlet)
    end)
  end)

  describe("deposit estimate", function()
    local vendor

    before_each(function()
      vendor = 1000
      _G.C_Item = { GetItemInfo = function() return "Vest", "link", 2, 18, 1, "", "", 1, "", 0, vendor, 4 end }
    end)

    after_each(function() _G.C_Item = nil end)

    it("starts at 15% of the vendor price per 12 hours", function()
      assert.same({ 150, 300, 600 }, { ns.EstimateDeposit(1, 1), ns.EstimateDeposit(1, 2), ns.EstimateDeposit(1, 3) })
    end)

    it("learns each duration's rate from a real deposit, the latest one winning", function()
      O.LearnDepositRate(2, 101, 2052)   -- the mockup's vest: 1s 1c to list a 20s 52c item for 24h
      assert.near(1000 * 101 / 2052, ns.EstimateDeposit(1, 2), 1e-9)
      O.LearnDepositRate(2, 50, 1000)
      assert.equal(50, ns.EstimateDeposit(1, 2))
      assert.equal(150, ns.EstimateDeposit(1, 1))   -- other durations keep theirs
    end)

    it("learns per unit from a post of several", function()
      O.LearnDepositRate(1, 400, 20 * 100)   -- 20 units at a 100c vendor price
      assert.equal(200, ns.EstimateDeposit(1, 1))
    end)

    it("learns nothing from posts too cheap for whole-copper deposits to show the rate", function()
      O.LearnDepositRate(2, 1, 99)
      assert.equal(300, ns.EstimateDeposit(1, 2))
    end)

    it("is nothing for an item without a vendor price", function()
      vendor = 0
      assert.equal(0, ns.EstimateDeposit(1, 2))
      _G.C_Item = { GetItemInfo = function() return nil end }   -- not cached yet
      assert.equal(0, ns.EstimateDeposit(1, 2))
    end)

    it("is worked out once per item for a set of game prices", function()
      local calls = 0
      ns.EstimateDeposit = function() calls = calls + 1 return 30 end
      local prices = ns.Mobs.GamePrices()
      prices.deposit(1)
      prices.deposit(1)
      assert.equal(1, calls)
    end)
  end)
end)
