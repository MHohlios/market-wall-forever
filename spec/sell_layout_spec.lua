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

  local function Top(region) return -region.points[1][3] end
  local function Bottom(region) return Top(region) + region.height end

  it("starts the bags and listings just under the strip, with no band between", function()
    assert.is_true(Top(page.bags) - Bottom(page.strip) <= 6)
    assert.equal(Top(page.bags), Top(page.listings))
    assert.is_true(page.bags.points[1][2] + page.bags.width <= page.listings.points[1][2])
  end)

  it("gives the answer's breakdown a row of its own under the status line, wide enough for gold amounts", function()
    local LINE = 13
    -- "92 × 2s 5c = 1g 88s 60c · 5% cut -9s 43c · deposit -27s 60c" runs about 350 wide in the small font
    assert.is_true(page.breakdown.width >= 450)
    assert.is_true(Top(page.breakdown) >= Top(page.info) + LINE)
    assert.is_true(Top(page.breakdown) + LINE <= page.strip.height)
    assert.is_true(page.versus.width >= 240)   -- and wraps rather than cutting a long comparison off
  end)

  it("keeps the warnings over the bags' column, where the bags make room for them", function()
    assert.equal(Top(page.bags), Top(page.warnings))
    assert.equal(page.bags.width, page.warnings.width)
  end)

  it("fits the Price history view and the listings in the right panel, under its tabs", function()
    local tabs = Top(page.auctions)
    assert.is_true(tabs > 0)
    assert.equal(tabs, Top(page.view))
    assert.is_true(Bottom(page.view) <= page.listings.height)
    assert.is_true(Bottom(page.auctions) <= page.listings.height)
  end)
end)
