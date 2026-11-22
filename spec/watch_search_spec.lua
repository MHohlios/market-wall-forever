local addon = require("spec.helpers.addon")

-- Live searches on the Sell page: each ladder belongs to the item searched, at its real unit price
describe("a live search", function()
  local ns, fire, rows, printed

  local realPrint = print
  before_each(function()
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    ns.ahOpen = true
    rows, printed = {}, {}
    _G.print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
    _G.GetTime = function() return 0 end
    _G.C_AuctionHouse = {
      MakeItemKey = function(id) return { itemID = id } end,
      GetItemKeyInfo = function() return {} end,
      IsThrottledMessageSystemReady = function() return true end,
      SendSearchQuery = function() end,
      HasSearchResults = function() return true end,
      HasFullItemSearchResults = function() return true end,
      HasFullCommoditySearchResults = function() return true end,
      GetItemSearchResultsQuantity = function(key) return #(rows[key.itemID] or {}) end,
      GetCommoditySearchResultsQuantity = function(id) return #(rows[id] or {}) end,
      GetNumItemSearchResults = function(key) return #(rows[key.itemID] or {}) end,
      GetNumCommoditySearchResults = function(id) return #(rows[id] or {}) end,
      GetItemSearchResultInfo = function(key, i) return rows[key.itemID][i] end,
      GetCommoditySearchResultInfo = function(id, i) return rows[id][i] end,
    }
  end)
  after_each(function() _G.C_AuctionHouse, _G.GetTime, _G.print = nil, nil, realPrint end)

  local function Search(id)
    ns.StartWatchScan({ id })
    ns.scanState.active.phase = "wait"   -- the query has gone out
  end

  -- Green Silk Pack's real rows: buyoutAmount is each bag's price, not the row's total
  it("reads an item row's buyout as the price of one unit", function()
    rows[5764] = {
      { auctionID = 1, buyoutAmount = 6123, quantity = 39 },
      { auctionID = 2, buyoutAmount = 5918, quantity = 22 },
    }
    Search(5764)
    fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 5764 })
    assert.same({ { p = 5918, q = 22 }, { p = 6123, q = 39 } }, ns.ladders[5764].ladder)
    assert.equal(5918, ns.ladders[5764].auctions[1].unit)
  end)

  it("ignores another item's results arriving while an item is searched", function()
    rows[1] = { { auctionID = 1, buyoutAmount = 157, quantity = 39 } }
    rows[2] = { { unitPrice = 30, quantity = 3 } }
    rows[5764] = { { auctionID = 2, buyoutAmount = 6123, quantity = 1 } }
    Search(5764)
    fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
    fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2)
    assert.is_nil(ns.ladders[5764])
    assert.same({}, ns.R().days)
    fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 5764 })
    assert.same({ { p = 6123, q = 1 } }, ns.ladders[5764].ladder)
    assert.is_nil(ns.ladders[1])
    assert.is_nil(ns.ladders[2])
  end)

  describe("/mw debug search", function()
    it("prints the next raw result for that item only, then stops", function()
      rows[1] = { { buyoutAmount = 157, quantity = 39 } }
      rows[5764] = {
        { buyoutAmount = 6123, quantity = 39 },
        { buyoutAmount = 6216, quantity = 28 },
        { buyoutAmount = 6210, quantity = 27 },
        { buyoutAmount = 5918, quantity = 22 },
      }
      SlashCmdList.MARKETWALL("debug search 5764")
      Search(5764)
      local before = #printed
      fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
      assert.equal(before, #printed)
      fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 5764 })
      local out = addon.Plain(table.concat(printed, "\n", before + 1))
      assert.matches("Debug search 5764: ITEM_SEARCH_RESULTS_UPDATED, kind item, active search 5764 %(wait%)", out)
      assert.matches("row 1: buyoutAmount=6123 quantity=39", out, 1, true)
      assert.matches("row 3: buyoutAmount=6210 quantity=27", out, 1, true)
      assert.is_nil(out:find("row 4", 1, true))
      local after = #printed
      fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 5764 })
      assert.equal(after, #printed)
    end)

    it("prints commodity rows by unit price", function()
      rows[2589] = { { unitPrice = 30, quantity = 3 } }
      SlashCmdList.MARKETWALL("debug search 2589")
      fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
      local out = addon.Plain(table.concat(printed, "\n"))
      assert.matches("kind commodity, active search none (-)", out, 1, true)
      assert.matches("row 1: unitPrice=30 quantity=3", out, 1, true)
    end)
  end)
end)
