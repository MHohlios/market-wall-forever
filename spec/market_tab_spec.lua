local addon = require("spec.helpers.addon")

-- Tracks Show and Hide the way the game does, so a test can ask which page is on screen
local function Showable(frame)
  frame = frame or {}
  frame.shown = true
  function frame:Show() self.shown = true end
  function frame:Hide() self.shown = false end
  function frame:SetShown(shown) self.shown = shown and true or false end
  function frame:IsShown() return self.shown end
  return frame
end

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

-- Blizzard's SetDisplayMode: skip a repeat, hide every known subframe, show the mode's frames
local BLIZZARD_MODES = { Buy = { "BrowseResultsFrame" } }
local function SetDisplayMode(self, mode)
  if mode == self.displayMode then return end
  self.displayMode = mode
  for _, names in pairs(BLIZZARD_MODES) do
    for _, name in ipairs(names) do self[name]:Hide() end
  end
  for _, name in ipairs(mode) do self[name]:Show() end
end

-- An Auctionator tab as LibAHTab builds it: it selects with an empty mode and hides its page
-- only on a non-empty one
local function InstallAuctionatorTab()
  local page = Showable()
  page:Hide()
  local tab = {}
  hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
    if mode ~= nil and #mode > 0 then page:Hide() end
  end)
  local lib = { internalState = { Tabs = { tab } } }
  _G.LibStub = function(name) if name == "LibAHTab-1-0" then return lib end end
  local function select()
    AuctionHouseFrame:SetDisplayMode({})
    AuctionHouseFrame.displayMode = nil
    page:Show()
  end
  return { page = page, tab = tab, select = select }
end

describe("the Market tab", function()
  local ns, blizzardTab

  local function MarketPage() return ns.ui.frame end
  local function MarketTab() return AuctionHouseFrame.Tabs[3] end
  local function ClickMarket() MarketTab().scripts.OnClick() end
  local function ShowBuy() AuctionHouseFrame:SetDisplayMode(BLIZZARD_MODES.Buy) end

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    ns.MaybeAutoScan = function() end   -- not under test
    blizzardTab = {}
    _G.AuctionHouseFrame = { Tabs = { {}, blizzardTab }, BrowseResultsFrame = Showable() }
    AuctionHouseFrame.SetDisplayMode = SetDisplayMode
    AuctionHouseFrame.SetTitle = function() end
    _G.LibStub = nil

    -- Building the page needs frames whose Create* methods return more frames
    local plainFrame = CreateFrame
    local function NewPageFrame(...)
      local frame = Showable(plainFrame(...))
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
    _G.LibStub = nil
  end)

  describe("without Auctionator", function()
    before_each(function() ns.OnAuctionHouseShow() end)

    it("anchors to the last Blizzard tab, never to itself", function()
      assert.same({ "TOPLEFT", blizzardTab, "TOPRIGHT", 3, 0 }, MarketTab().points[1])
    end)

    it("shows Market in place of Blizzard's page", function()
      ClickMarket()
      assert.is_true(MarketPage():IsShown())
      assert.is_false(AuctionHouseFrame.BrowseResultsFrame:IsShown())
    end)

    it("still shows Market when clicked again", function()
      ClickMarket()
      MarketPage():Hide()
      ClickMarket()
      assert.is_true(MarketPage():IsShown())
    end)

    it("leads back from an item page through the list's tab, which stays clickable", function()
      -- like the game: selecting a tab disables it, and a disabled button ignores clicks
      _G.PanelTemplates_SelectTab = function(t) t.disabled = true end
      _G.PanelTemplates_DeselectTab = function(t) t.disabled = false end
      for _, tab in pairs(ns.ui.nav) do
        function tab:Enable() self.disabled = false end
      end
      local function Click(tab) if not tab.disabled then tab.scripts.OnClick() end end

      ClickMarket()
      Click(ns.ui.nav.snipes)
      ns.ui.lastList = "snipes"   -- as ui.ShowItem records it
      ns.ui.Show("item")
      Click(ns.ui.nav.snipes)
      assert.equal("snipes", ns.ui.view)
    end)

    it("hides Market and deselects its tab on a Blizzard mode", function()
      ClickMarket()
      local deselected
      _G.PanelTemplates_DeselectTab = function(t) deselected = t end
      ShowBuy()
      assert.is_false(MarketPage():IsShown())
      assert.equals(MarketTab(), deselected)
    end)

    describe("lists with nothing to show", function()
      local function EmptyOf(view)
        ns.ui.Show(view)
        return addon.Plain(ns.ui.list.emptyText)
      end

      before_each(ClickMarket)

      it("invite a first watchlist item", function()
        assert.equal("Your watchlist is empty.\nAdd items you buy or sell often, and MarketWall tells you when to buy and when to sell.",
          EmptyOf("watch"))
      end)

      it("ask for a full scan before there is one", function()
        assert.equal("Run a full scan to look for listings priced under the wall.", EmptyOf("snipes"))
        assert.equal("Run a full scan. Dips compare today's wall price with each item's own history.", EmptyOf("dips"))
        assert.equal("Run a full scan to look for gear listed under its disenchant value.", EmptyOf("disenchant"))
      end)

      it("say a full scan this session found none", function()
        ns.lastFullScan = time()
        assert.equal("No snipes in the last full scan.", EmptyOf("snipes"))
        assert.equal("No dips in the last full scan.", EmptyOf("dips"))
        assert.equal("No disenchant deals in the last full scan.", EmptyOf("disenchant"))
      end)

      it("say a full scan from an earlier session is not loaded", function()
        ns.R().lastFull = time() - 7200
        assert.equal("Results are from this session only.\nRun a full scan to refresh the list. Last full scan: 2h ago.",
          EmptyOf("snipes"))
      end)
    end)

    describe("the watchlist's Add row", function()
      local printed

      local function Type(text)
        local box = ns.ui.addBox
        box.text = text
        function box:GetText() return self.text end
        function box:SetText(value) self.text = value end
      end

      before_each(function()
        ClickMarket()
        ns.ui.Show("watch")
        printed = nil
        ns.Print = function(text) printed = text end
      end)

      it("shows only on the watchlist", function()
        assert.is_true(ns.ui.footer:IsShown())
        ns.ui.Show("snipes")
        assert.is_false(ns.ui.footer:IsShown())
      end)

      it("opens the typed item's page on Enter and clears the box", function()
        ns.R().names[2589] = "Linen Cloth"
        Type("linen cloth")
        ns.ui.addBox.scripts.OnEnterPressed(ns.ui.addBox)
        assert.same({ "item", 2589, "" }, { ns.ui.view, ns.ui.itemID, ns.ui.addBox.text })
      end)

      it("keeps the text and says so when no item matches", function()
        Type("no such item")
        ns.ui.addBox.scripts.OnEnterPressed(ns.ui.addBox)
        assert.same({ "watch", "no such item" }, { ns.ui.view, ns.ui.addBox.text })
        assert.truthy(printed)
      end)
    end)
  end)

  describe("beside Auctionator's tabs", function()
    local auctionator

    before_each(function()
      auctionator = InstallAuctionatorTab()
      ns.OnAuctionHouseShow()
    end)

    it("anchors after Auctionator's last tab", function()
      assert.same({ "TOPLEFT", auctionator.tab, "TOPRIGHT", 3, 0 }, MarketTab().points[1])
    end)

    it("hides Auctionator's page when Market is selected", function()
      auctionator.select()
      ClickMarket()
      assert.is_false(auctionator.page:IsShown())
      assert.is_true(MarketPage():IsShown())
    end)

    it("hides Market when an Auctionator tab is selected", function()
      ClickMarket()
      auctionator.select()
      assert.is_false(MarketPage():IsShown())
      assert.is_true(auctionator.page:IsShown())
    end)
  end)
end)
