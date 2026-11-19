local addon = require("spec.helpers.addon")

-- The Sell page always lists the auction house and Vendor groups, so "nothing to sell" is judged by items
describe("Sell page empty state", function()
  local ns, grid, emptyShown

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    grid = ns.BuildSellPage(CreateFrame("Frame")).grid
    grid.empty.SetShown = function(_, shown) emptyShown = shown end
    _G.C_Item = {}
  end)

  after_each(function() _G.C_Item = nil end)

  local function Group(outlet, ...)
    return { outlet = outlet, items = { ... }, value = 0 }
  end

  it("shows when every group is empty", function()
    grid:SetGroups({ Group(ns.Outlet.AUCTION), Group(ns.Outlet.VENDOR) })
    assert.is_true(emptyShown)
  end)

  it("hides once any group holds an item", function()
    grid:SetGroups({ Group(ns.Outlet.AUCTION), Group(ns.Outlet.VENDOR, { id = 1, count = 1 }) })
    assert.is_false(emptyShown)
  end)
end)
