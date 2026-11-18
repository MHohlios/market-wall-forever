local addon = require("spec.helpers.addon")

local ID = 7

describe("item tooltip lines", function()
  local ns, tooltip

  -- A tooltip that records its lines as "left|right" strings
  local function NewTooltip(owner)
    local lines = {}
    return {
      lines = lines,
      GetOwner = function() return owner end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. "|" .. right end,
    }
  end

  -- Gives the item one wall per entry, oldest first, ending today
  local function SeedWalls(...)
    local walls = { ... }
    local days = {}
    for i, wall in ipairs(walls) do days[ns.Today() - (#walls - i)] = { wall } end
    ns.R().days[ID] = days
  end

  local function Has(text)
    for _, line in ipairs(tooltip.lines) do
      if line:find(text, 1, true) then return true end
    end
    return false
  end

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {} }
    _G.C_Item = {}
    tooltip = NewTooltip()
  end)

  after_each(function()
    _G.MarketWallDB, _G.C_Item, _G.C_Container = nil, nil, nil
  end)

  describe("7-day trend", function()
    it("shows nothing for a never-scanned item", function()
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({}, tooltip.lines)
    end)

    it("is absent with a single price", function()
      SeedWalls(1000)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Market wall"))
      assert.is_false(Has("7-day trend"))
    end)

    it("is absent when the only other price is older than 7 days", function()
      ns.R().days[ID] = { [ns.Today() - 10] = { 900 }, [ns.Today()] = { 1000 } }
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("7-day trend"))
    end)

    it("names a rise past 3% up and a fall past 3% down", function()
      SeedWalls(1000, 1060)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("7-day trend|r|"))
      assert.is_true(Has("up 6%"))

      tooltip = NewTooltip()
      SeedWalls(1000, 940)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("down 6%"))
    end)

    it("calls moves just inside 3% flat and just past it a trend", function()
      SeedWalls(1000, 1029)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("flat"))

      tooltip = NewTooltip()
      SeedWalls(1000, 971)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("flat"))

      tooltip = NewTooltip()
      SeedWalls(1000, 1031)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("up 3%"))

      tooltip = NewTooltip()
      SeedWalls(1000, 969)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("down 3%"))
    end)
  end)

  describe("stack total", function()
    local function BagSlot(info)
      _G.C_Container = { GetContainerItemInfo = function() return info end }
      return { GetSlotAndBagID = function() return 4, 0 end }
    end

    before_each(function() SeedWalls(1000) end)

    it("multiplies the wall by the stack size", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Stack of 20|r|" .. ns.Money(20000)))
    end)

    it("shows nothing for a stack of 1", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 1 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
    end)

    it("shows nothing when the count cannot be found", function()
      ns.TooltipLines.Add(tooltip, ID)   -- no owner
      assert.is_false(Has("Stack of"))

      tooltip = NewTooltip(BagSlot(nil))   -- empty slot
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))

      tooltip = NewTooltip(BagSlot({ itemID = ID }))   -- no stackCount
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
    end)

    it("ignores a slot that holds a different item", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID + 1, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
    end)

    it("reads the slot from the owner's id and its parent's id when it has no slot method", function()
      _G.C_Container = {
        GetContainerItemInfo = function(bag, slot)
          return bag == 2 and slot == 5 and { itemID = ID, stackCount = 3 } or nil
        end,
      }
      local owner = { GetID = function() return 5 end, GetParent = function() return { GetID = function() return 2 end } end }
      assert.equal(3, ns.TooltipLines.StackCount(NewTooltip(owner), ID))
    end)

    it("adds no stack line to a never-scanned item", function()
      ns.R().days[ID] = nil
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({}, tooltip.lines)
    end)
  end)
end)
