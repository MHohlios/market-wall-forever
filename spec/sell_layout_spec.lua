local addon = require("spec.helpers.addon")

describe("Sell page layout", function()
  local page

  before_each(function()
    local ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    page = ns.BuildSellPage(CreateFrame("Frame"))
  end)

  -- The blocks hang from the page's top edge down to the top of the lists. A negative height
  -- pushes their TOPLEFT-anchored children above the window.
  it("gives the sale block a positive height reaching the lists", function()
    assert.equal(200, page.sale.height)
  end)

  it("gives the info block a positive height reaching the lists", function()
    assert.equal(200, page.info.height)
  end)
end)
