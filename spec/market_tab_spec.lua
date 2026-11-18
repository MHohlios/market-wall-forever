local addon = require("spec.helpers.addon")

-- The auction house's tab template adds each new tab to its parent's Tabs array, like the game
local function NewTab(parent)
  local tab = { scripts = {}, points = {} }
  function tab:SetPoint(point, relativeTo, relativePoint, x, y)
    if relativeTo == self then error("Cannot anchor to itself") end
    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
  end
  function tab:SetScript(name, fn) self.scripts[name] = fn end
  parent.Tabs[#parent.Tabs + 1] = tab
  return setmetatable(tab, { __index = function() return function() end end })
end

describe("the Market tab", function()
  local ns, blizzardTab, setDisplayMode

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    ns.MaybeAutoScan = function() end   -- not under test
    blizzardTab = {}
    _G.AuctionHouseFrame = { Tabs = { {}, blizzardTab } }
    setDisplayMode = function() end
    function AuctionHouseFrame.SetDisplayMode(_, mode) setDisplayMode(mode) end

    -- Building the page needs frames whose Create* methods return more frames
    local plainFrame = CreateFrame
    local function NewPageFrame(...)
      local frame = plainFrame(...)
      for _, method in ipairs({ "CreateTexture", "CreateFontString" }) do
        frame[method] = function() return NewPageFrame() end
      end
      return frame
    end
    _G.CreateFrame = function(kind, name, parent, template)
      if template == "AuctionHouseFrameDisplayModeTabTemplate" then return NewTab(parent) end
      return NewPageFrame(kind, name, parent, template)
    end
    _G.PanelTemplates_TabResize = function() end
    _G.PanelTemplates_DeselectTab = function() end
    _G.PanelTemplates_SelectTab = function() end
    _G.hooksecurefunc = function(object, name, hook)
      local original = object[name]
      object[name] = function(...) original(...) hook(...) end
    end
  end)

  after_each(function()
    _G.AuctionHouseFrame = nil
  end)

  it("anchors to the last Blizzard tab, never to itself", function()
    ns.OnAuctionHouseShow()
    local tab = AuctionHouseFrame.Tabs[3]
    assert.is_truthy(tab)
    assert.same({ "TOPLEFT", blizzardTab, "TOPRIGHT", 3, 0 }, tab.points[1])
  end)

  it("gets its click handler and hooks the display mode switch", function()
    ns.OnAuctionHouseShow()
    local tab = AuctionHouseFrame.Tabs[3]
    assert.is_function(tab.scripts.OnClick)

    local deselected
    _G.PanelTemplates_DeselectTab = function(t) deselected = t end
    AuctionHouseFrame:SetDisplayMode({ 1 })
    assert.equals(tab, deselected)
  end)
end)
