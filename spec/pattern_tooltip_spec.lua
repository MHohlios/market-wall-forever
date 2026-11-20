local addon = require("spec.helpers.addon")

local GUID = "Player-5250-0ABC1234"
-- The Mooncloth pattern teaches Mooncloth from 2 Felcloth; a vendor sells it for 2g
local PATTERN, MOONCLOTH, FELCLOTH = 14526, 14342, 14256
local GREEN, RED = "|cff4fc36b", "|cffe0524a"

describe("pattern tooltip", function()
  local ns, fire, right

  local function Show(id)
    right = {}
    local tooltip = {
      AddLine = function() end,
      -- keyed by the label without its row indent
      AddDoubleLine = function(_, left, text) right[addon.Plain(left):match("^%s*(.-)$")] = text end,
    }
    ns.TooltipLines.Add(tooltip, id)
  end

  -- A wall seen today with units listed, supplied unless told otherwise
  local function Wall(id, wall, units, thin)
    ns.R().days[id] = { [ns.Today()] = { wall, wall, wall, units or 50, wall } }
    ns.R().supplied[id] = not thin
  end

  before_each(function()
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    _G.C_Item = {}
    _G.UnitGUID = function(unit) return unit == "player" and GUID or nil end
    _G.IsShiftKeyDown = function() return false end
    Wall(FELCLOTH, 1000)
  end)

  after_each(function()
    _G.C_Item, _G.UnitGUID, _G.IsShiftKeyDown = nil, nil, nil
  end)

  it("shows what a pattern teaches, its profit, market and payback at its wall, not known", function()
    Wall(MOONCLOTH, 10000, 12)
    Wall(PATTERN, 30000)
    Show(PATTERN)
    assert.equal("", right["Crafting"])
    assert.equal("Mooncloth (250)", right["Teaches"])
    local profit = right["Profit per craft"]
    assert.equal(GREEN .. "+", profit:sub(1, #GREEN + 1))
    assert.equal("Steady · 12 listed", right["Market"])
    assert.equal("4 crafts", right["Pays back at 3g 0s 0c"])   -- 3g at 7g 50s profit a craft
    assert.equal("Not known", right["You"])
  end)

  it("prices payback at the vendor's cost when the pattern isn't listed", function()
    Wall(MOONCLOTH, 10000)
    Show(PATTERN)
    assert.equal("3 crafts", right["Pays back at 2g 0s 0c"])
  end)

  it("says never when a craft loses money", function()
    Wall(MOONCLOTH, 1500, 3, true)
    Show(PATTERN)
    assert.equal(RED, right["Profit per craft"]:sub(1, #RED))
    assert.equal("Thin · 3 listed", right["Market"])
    assert.equal(RED .. "never|r", right["Pays back at 2g 0s 0c"])
  end)

  it("says no data when nothing prices the product", function()
    Show(PATTERN)
    assert.equal("no data", addon.Plain(right["Profit per craft"]))
    assert.equal("No data", addon.Plain(right["Market"]))
    assert.equal("no data", addon.Plain(right["Pays back at 2g 0s 0c"]))
  end)

  it("says Known, without payback, once the profession window has shown the recipe", function()
    Wall(MOONCLOTH, 10000)
    MarketWallDB.crafting[GUID] = { Tailoring = { rank = 260, recipes = {
      [MOONCLOTH] = { name = "Mooncloth", made = 1, reagents = { { FELCLOTH, 2 } } },
    } } }
    Show(PATTERN)
    assert.equal("Known", addon.Plain(right["You"]))
    assert.is_nil(right["Pays back at 2g 0s 0c"])
  end)

  it("adds nothing to an item that is not a pattern", function()
    Show(FELCLOTH)
    assert.is_nil(right["Crafting"])
  end)
end)
