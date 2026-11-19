local addon = require("spec.helpers.addon")

-- The Sell page's bag groups, priced with the game's own deposit at the auction house
describe("Sell page deposits", function()
  local ITEM, WALL = 7001, 2000
  local ns, grouped, vendor

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    ns.BuildSellPage(CreateFrame("Frame"))
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
      GetContainerItemInfo = function() return { itemID = ITEM, stackCount = 1 } end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.Enum = { ItemCommodityStatus = { Commodity = 1, Item = 2 } }
    _G.C_AuctionHouse = {
      IsSellItemValid = function() return true end,
      GetItemCommodityStatus = function() return 2 end,
      CalculateItemDeposit = function() return 50 end,
    }
    vendor = 1000
    _G.C_Item = { GetItemInfo = function() return "Vest", "link", 2, 18, 1, "", "", 1, "", 0, vendor, 4 end }
    ns.LatestWall = function() return WALL end
    ns.R().supplied = { [ITEM] = true }
    MarketWallDB.cfg.mobDisenchant = "never"
    local Groups = ns.SellPricing.Groups
    ns.SellPricing.Groups = function(items)
      grouped = items
      return Groups(items)
    end
  end)

  after_each(function()
    _G.C_Container, _G.ItemLocation, _G.Enum, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil, nil, nil
  end)

  it("takes the game's deposit off the auction house rather than the estimate", function()
    ns.EstimateDeposit = function() return 999 end
    ns.RefreshSell()
    assert.equal(WALL * 0.95 - 50, grouped[1].values.auction)
  end)

  it("learns the rate from it for estimates away from the auction house", function()
    ns.RefreshSell()   -- 50c on a 1,000c vendor price, under the 30% default
    assert.equal(0.05, MarketWallDB.depositRate[2])
    assert.equal(50, ns.EstimateDeposit(ITEM, 2))
  end)
end)
