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

    it("takes the deposit for one unit off the auction house", function()
      MarketWallDB.cfg.mobDisenchant = "never"
      assert.equal(940, O.Game()(ITEM, 10).auction)
    end)
  end)
end)
