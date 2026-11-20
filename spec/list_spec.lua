local addon = require("spec.helpers.addon")

local Plain = addon.Plain

-- A frame that remembers its text, scripts and whether it is shown, and makes more of itself
local function NewFrame()
  local frame = { scripts = {}, shown = true }
  function frame:SetText(text) self.text = text end
  function frame:GetText() return self.text end
  function frame:SetScript(name, fn) self.scripts[name] = fn end
  function frame:GetScript(name) return self.scripts[name] end
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:SetShown(shown) self.shown = shown and true or false end
  function frame:IsShown() return self.shown end
  function frame.GetWidth() return 1000 end
  function frame.GetStringWidth() return 10 end
  frame.CreateTexture = NewFrame
  frame.CreateFontString = NewFrame
  return setmetatable(frame, { __index = function() return function() end end })
end

describe("a list", function()
  local ns, list, tip

  local MONEY = { { "Item", 200 }, { "Profit", 100, "RIGHT", "Profit after the cut.", money = true } }

  local function Row(i) return list.rows[i] end
  local function CellText(i, c) return Plain(Row(i).cells[c].text) end
  local function HoverCell(i, c)
    tip = nil
    Row(i).hits[c].scripts.OnEnter(Row(i).hits[c])
    return tip
  end

  before_each(function()
    ns = addon.Load()
    _G.CreateFrame = NewFrame
    _G.GameTooltip = {
      SetOwner = function() tip = {} end,
      SetText = function(_, text) tip.title = text end,
      AddLine = function(_, text) tip[#tip + 1] = text end,
      SetItemByID = function(_, id) tip.item = id end,
      Show = function() end,
    }
    list = ns.widgets.CreateList(NewFrame(), 3)
    list:SetColumns(MONEY)
  end)

  after_each(function() _G.GameTooltip = nil end)

  describe("money cells", function()
    it("show at most two coins", function()
      list:SetData({ { id = 1, cells = { "Linen", 50473 } } })
      assert.equal("5g 5s", CellText(1, 2))
    end)

    it("put the exact amount first on hover when the cell rounds it", function()
      list:SetData({ { id = 1, cells = { "Linen", 50473 }, cellTips = { [2] = "From 3 units." } } })
      local shown = HoverCell(1, 2)
      assert.equal("Profit", shown.title)
      assert.equal("5g 4s 73c\nFrom 3 units.", Plain(shown[1]))
    end)

    it("show the exact amount alone on hover when the row has nothing to add", function()
      list:SetData({ { id = 1, cells = { "Linen", 50473 } } })
      assert.equal("5g 4s 73c", Plain(HoverCell(1, 2)[1]))
    end)

    it("fall back to the row's hover when the cell shows the amount exactly", function()
      list:SetData({ { id = 7, cells = { "Linen", 5040 } } })
      local shown = HoverCell(1, 2)
      assert.equal(7, shown.item)
      assert.is_nil(shown.title)
    end)
  end)

  describe("when empty", function()
    before_each(function() list:SetData({}, "Nothing here.") end)

    it("hides its column titles and shows its message instead", function()
      assert.is_false(list.headers[1]:IsShown())
      assert.is_false(list.headers[2]:IsShown())
      assert.is_true(list.empty:IsShown())
      assert.equal("Nothing here.", list.empty.text)
    end)

    it("brings the titles back with rows", function()
      list:SetData({ { id = 1, cells = { "Linen", 1 } } })
      assert.is_true(list.headers[1]:IsShown())
      assert.is_false(list.empty:IsShown())
    end)
  end)

  describe("longer than it shows", function()
    local function Rows(n)
      local data = {}
      for i = 1, n do data[i] = { id = i, cells = { "Item " .. i, i } } end
      return data
    end

    it("counts the rows on screen and shows a scrollbar", function()
      list:SetData(Rows(10))
      assert.equal("1–3 of 10", list.count.text)
      assert.is_true(list.scrollBar:IsShown())
    end)

    it("scrolls to where the scrollbar is dragged", function()
      list:SetData(Rows(10))
      list.scrollBar.scripts.OnValueChanged(list.scrollBar, 7)
      assert.equal("Item 8", CellText(1, 1))
      assert.equal("8–10 of 10", list.count.text)
    end)

    it("opens at the top after a longer list was scrolled to its end", function()
      -- like the game's slider: a shrinking range clamps the value and reports the change
      local bar = list.scrollBar
      function bar:SetValue(value)
        self.value = value
        self.scripts.OnValueChanged(self, value)
      end
      function bar:SetMinMaxValues(_, max)
        if (rawget(self, "value") or 0) > max then self:SetValue(max) end
      end
      list:SetData(Rows(20))
      bar.scripts.OnValueChanged(bar, 17)
      bar.value = 17
      list.offset = 0   -- as switching views does
      list:SetData(Rows(6))
      assert.equal("1–3 of 6", list.count.text)
      assert.equal("Item 1", CellText(1, 1))
    end)

    it("needs neither the count nor the scrollbar when every row fits", function()
      list:SetData(Rows(3))
      assert.equal("", list.count.text)
      assert.is_false(list.scrollBar:IsShown())
    end)
  end)
end)
