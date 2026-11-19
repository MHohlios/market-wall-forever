local addon = require("spec.helpers.addon")

-- Which bags the Sell page reads: the backpack and equipped bags, plus the reagent bag when the client has one
describe("Sell page bag range", function()
  local BACKPACK_ITEM, BAG_4_ITEM, REAGENT_ITEM = 7001, 7004, 7005
  local ns, grouped

  local function ItemIDs()
    local ids = {}
    for _, item in ipairs(grouped) do ids[item.id] = true end
    return ids
  end

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    ns.BuildSellPage(CreateFrame("Frame"))
    local itemInBag = { [0] = BACKPACK_ITEM, [4] = BAG_4_ITEM, [5] = REAGENT_ITEM }
    _G.C_Container = {
      GetContainerNumSlots = function(bag) return itemInBag[bag] and 1 or 0 end,
      GetContainerItemInfo = function(bag) return { itemID = itemInBag[bag], stackCount = 1 } end,
    }
    _G.ItemLocation = { CreateFromBagAndSlot = function() return {} end }
    _G.Enum = { ItemCommodityStatus = { Commodity = 1, Item = 2 } }
    _G.C_AuctionHouse = {
      IsSellItemValid = function() return true end,
      GetItemCommodityStatus = function() return 2 end,
      CalculateItemDeposit = function() return 50 end,
    }
    _G.C_Item = { GetItemInfo = function() return "Item", "link", 2, 18, 1, "", "", 1, "", 0, 1000, 4 end }
    local Groups = ns.SellPricing.Groups
    ns.SellPricing.Groups = function(items)
      grouped = items
      return Groups(items)
    end
  end)

  after_each(function()
    _G.C_Container, _G.ItemLocation, _G.Enum, _G.C_AuctionHouse, _G.C_Item = nil, nil, nil, nil, nil
    _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = nil
  end)

  it("includes the reagent bag when the client reports it", function()
    _G.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
    ns.RefreshSell()
    assert.same({ [BACKPACK_ITEM] = true, [BAG_4_ITEM] = true, [REAGENT_ITEM] = true }, ItemIDs())
  end)

  it("reads only bags 0 to 4 without those globals", function()
    ns.RefreshSell()
    assert.same({ [BACKPACK_ITEM] = true, [BAG_4_ITEM] = true }, ItemIDs())
  end)
end)
