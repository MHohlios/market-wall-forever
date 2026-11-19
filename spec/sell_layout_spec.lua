local addon = require("spec.helpers.addon")

-- The Market tab's frame: the auction house window (800 x 538) inset 4 at the sides, 24 at the
-- top and 27 at the bottom (UI.lua's Build)
local PAGE_WIDTH, PAGE_HEIGHT = 792, 487

describe("Sell page layout", function()
  local page, regions

  before_each(function()
    local ns, fire, frames = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    page = ns.BuildSellPage(CreateFrame("Frame"))
    regions = {}
    for _, frame in ipairs(frames) do
      if frame.parent == page then regions[#regions + 1] = frame end
    end
  end)

  -- A negative size pushes TOPLEFT-anchored children out of the window, as the old top blocks did
  it("gives no top-level region a negative size", function()
    assert.is_true(#regions >= 4)
    for _, region in ipairs(regions) do
      if region.width then assert.is_true(region.width >= 0) end
      if region.height then assert.is_true(region.height >= 0) end
    end
  end)

  it("keeps every sized block inside the Market tab frame", function()
    for _, region in ipairs(regions) do
      local anchor = region.points[1]
      if region.width and region.height and anchor and anchor[1] == "TOPLEFT" then
        local x, y = anchor[2], anchor[3]
        assert.is_true(x >= 0 and x + region.width <= PAGE_WIDTH)
        assert.is_true(y <= 0 and -y + region.height <= PAGE_HEIGHT)
      end
    end
  end)

  it("lays the strip, warnings, bags and listings out top to bottom without overlap", function()
    local function Top(region) return -region.points[1][3] end
    local function Bottom(region) return Top(region) + region.height end
    assert.is_true(Bottom(page.strip) <= Top(page.warnings))
    assert.is_true(Bottom(page.warnings) <= Top(page.bags))
    assert.equal(Top(page.bags), Top(page.listings))
    assert.is_true(page.bags.points[1][2] + page.bags.width <= page.listings.points[1][2])
  end)

  it("ends the Price history view, low-data flag included, above the bottom tabs", function()
    local TABS_HEIGHT = 2 + 22   -- the tab buttons sit 2 above the panel's bottom edge
    assert.is_true(-page.view.points[1][3] + page.view.height <= page.listings.height - TABS_HEIGHT)
  end)
end)
