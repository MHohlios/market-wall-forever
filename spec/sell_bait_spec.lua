local addon = require("spec.helpers.addon")

local function Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

describe("Sell page bait handling", function()
  local ns, B, W, pricing
  local FLAT = 0.03
  -- the mockup's Thorium Bar: bait (1) + 14 copies at 30c under a 1s 02c wall
  local record = { p = 30, u = 1, q = 15, w = 102, first = 1, last = 1, seen = 2 }

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    B, W, pricing = ns.Bait, ns.Wall, ns.SellPricing
  end)

  describe("Note column", function()
    it("marks the bait level with its units and the copies since", function()
      assert.equal("bait? (1) + 14 copies", Plain(pricing.AuctionNote({ p = 30, q = 15 }, 102, record)))
    end)

    it("marks the wall, and nothing else, as before", function()
      assert.equal("wall", Plain(pricing.AuctionNote({ p = 102, q = 220 }, 102, record)))
      assert.equal("", pricing.AuctionNote({ p = 105, q = 140 }, 102, record))
      assert.equal("", pricing.AuctionNote({ p = 30, q = 15 }, 102, nil))
    end)
  end)

  describe("posting warning", function()
    it("warns at the bait price", function()
      assert.equal("1 unit at 30c sits 71% under the 1s 2c wall. Likely bait; don't match it.",
        Plain(B.PostWarning(record, 30, FLAT)))
    end)

    it("warns within 3% of the bait price, either side, including the edge", function()
      local wide = { p = 1000, u = 3, q = 3, w = 4000 }
      assert.truthy(B.PostWarning(wide, 1030, FLAT))
      assert.truthy(B.PostWarning(wide, 970, FLAT))
      assert.truthy(Plain(B.PostWarning(wide, 1010, FLAT)):find("^3 units at 10s 0c sits 75%% under the 40s 0c wall"))
    end)

    it("does not warn away from the bait price", function()
      local wide = { p = 1000, u = 3, q = 3, w = 4000 }
      assert.is_nil(B.PostWarning(wide, 1031, FLAT))
      assert.is_nil(B.PostWarning(wide, 969, FLAT))
      assert.is_nil(B.PostWarning(record, 102, FLAT))
    end)

    it("does not warn without a bait record", function()
      assert.is_nil(B.PostWarning(nil, 30, FLAT))
    end)
  end)

  describe("suggested price", function()
    it("starts at the wall, never at the bait level under it", function()
      local ladder, total = W.SortLadder({ [30] = 15, [102] = 220, [105] = 140 })
      ns.ladders[7] = { ladder = ladder, total = total, t = os.time(), kind = "commodity" }
      ns.R().bait[7] = record
      assert.equal(102, pricing.SuggestedPrice(7))
    end)
  end)
end)
