-- MarketWall: the Sell page.
-- Top: the item and what you are about to post, with an info line and warnings under it.
-- Left: your bags as an icon grid, grouped by the best outlet for each item (SellBags.lua).
-- Right: the auctions listed right now, or the item's price history, under two bottom tabs.
-- Prices and words come from SellPricing.lua.
local _, ns = ...
local P, PV, Outlet = ns.SellPricing, ns.PriceView, ns.Outlet
local ui = ns.ui

local BLUE, ORANGE, GREY = "|cff7cc0ff", "|cffffb057", "|cffa3acac"
local DURATIONS = { { 1, "12h" }, { 2, "24h" }, { 3, "48h" } }

-- The Market tab's page is about 782 x 480 below the navigation row
local WIDTH = 782
local STRIP_TOP, STRIP_HEIGHT = -50, 96
local INFO_Y, WARNINGS_Y, WARNINGS_HEIGHT = -150, -166, 56
local BODY_TOP, BODY_HEIGHT = -226, 254
local LEFT_WIDTH, RIGHT_X = 300, 312
local POST_X, TOTALS_X, TOTALS_WIDTH = 384, 556, 192   -- the strip's Duration and Post column, and its totals
local TOTAL_ROW = 13
local TOTAL_VALUES = { "total", "afterCut", "deposit", "net", "vendor", "beats", "perUnit" }
local RIGHT_WIDTH = WIDTH - RIGHT_X
local LIST_ROWS = 8

local AUCTION_COLUMNS = {
  { "Price each", 120, nil, "Each price level listed right now, cheapest first. Click a row to set Price each to it." },
  { "Units", 70, "RIGHT", "Units listed at this price." },
  { "Running total", 100, "RIGHT", "Units listed at this price or cheaper." },
  { "Note", 170, "RIGHT", "Wall: the price level with real supply behind it. Bait?: a few units far under the wall, posted so others copy the price, with the copies posted since. The highlighted row is where your price would sit." },
}
-- the item search window's grid, under its 7 days / 30 days / All switch
local HISTORY_CELLS = {
  "current", "rangeMin", "rangeMax", "rangeAverage", "rangeMedian", "rangeTrend", "rangePoints", "normalRange",
  "vendor", "disenchant", "limits",
}

local page
local selectedID

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

-- Sellable bag items, one entry per item ID: { id, location, count }
local function BagItems()
  local byID, items = {}, {}
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if C_AuctionHouse.IsSellItemValid(location, false) then
          local item = byID[info.itemID]
          if not item then
            item = { id = info.itemID, location = location, count = 0 }
            byID[info.itemID] = item
            items[#items + 1] = item
          end
          item.count = item.count + (info.stackCount or 1)
        end
      end
    end
  end
  return items
end

local function IsCommodity(location)
  return C_AuctionHouse.GetItemCommodityStatus(location) == Enum.ItemCommodityStatus.Commodity
end

local function Deposit(item, quantity)
  local duration = ns.Cfg("sellDuration")
  if IsCommodity(item.location) then
    return C_AuctionHouse.CalculateCommodityDeposit(item.id, duration, quantity) or 0
  end
  return C_AuctionHouse.CalculateItemDeposit(item.location, duration, quantity) or 0
end

local function Vendor(id)
  return C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
end

-------------------------------------------------------------------------------
-- Price each: gold, silver and copper boxes
-------------------------------------------------------------------------------

local function ReadPrice()
  local function Part(box) return tonumber(box:GetText()) or 0 end
  local price = Part(page.gold) * 10000 + Part(page.silver) * 100 + Part(page.copper)
  return price > 0 and price or nil
end

local function SetPrice(copper)
  copper = copper and ns.Round(copper)
  page.gold:SetText(copper and tostring(math.floor(copper / 10000)) or "")
  page.silver:SetText(copper and tostring(math.floor(copper % 10000 / 100)) or "")
  page.copper:SetText(copper and tostring(copper % 100) or "")
end

-- A price set from a button or a listing row stays until the next item is picked
local function ChoosePrice(copper)
  page.priceEdited = true
  for _, box in ipairs({ page.gold, page.silver, page.copper }) do box:ClearFocus() end
  SetPrice(copper)
end

-------------------------------------------------------------------------------
-- Posting
-------------------------------------------------------------------------------

local function ReadInputs()
  local price = ReadPrice()
  local quantity = tonumber(page.quantity:GetText())
  if not (page.item and price and quantity and quantity >= 1 and quantity <= page.maxQuantity) then
    return nil
  end
  return price, quantity
end

local function Totals(item, price, quantity)
  return P.Totals(price, quantity, Deposit(item, quantity), Vendor(item.id), ns.Cfg("ahCut"))
end

local function Warnings(item, price, quantity, totals)
  return P.Warnings({
    price = price,
    totals = totals or Totals(item, price, quantity),
    stats = ns.StatsFor(item.id),
    bait = ns.R().bait[item.id],
    outlet = item.values,
  })
end

local function ShowTotals(t, quantity)
  local rows = page.totals
  rows.total:SetText(ns.Money(t.total))
  rows.afterCutLabel:SetText("After " .. ns.Round(ns.Cfg("ahCut") * 100) .. "% cut")
  rows.afterCut:SetText(ns.Money(t.afterCut))
  rows.deposit:SetText(ORANGE .. "- |r" .. ns.Money(t.deposit))
  rows.net:SetText(ns.Money(t.net))
  if t.vendor then
    rows.vendorLabel:SetText("Vendor (" .. quantity .. " x " .. ns.Money(t.vendorEach) .. ")")
    rows.vendor:SetText(ns.Money(t.vendor))
  else
    rows.vendorLabel:SetText("Vendor")
    rows.vendor:SetText("—")
  end
  rows.beats:SetText(P.BeatsText(t))
  rows.perUnit:SetText(GREY .. "per unit: AH " .. ns.Money(t.netEach) .. GREY .. " · vendor " .. (t.vendorEach and ns.Money(t.vendorEach) or "—") .. "|r")
end

local function UpdateTotals()
  local price, quantity = ReadInputs()
  page.post:SetEnabled(price ~= nil and ns.ahOpen)
  page.post:SetText(quantity and ("Post " .. quantity) or "Post")
  if not price then
    for _, key in ipairs(TOTAL_VALUES) do page.totals[key]:SetText("") end
    page.info:SetText(GREY .. "Enter a price and a quantity from 1 to " .. (page.maxQuantity or 0) .. ".|r")
    page.warning:SetText("")
    page.warnings:Hide()
    return
  end
  local totals = Totals(page.item, price, quantity)
  ShowTotals(totals, quantity)

  local info = P.InfoLine(price, page.start, P.Wall(page.item.id))
  if page.notes ~= "" then info = (info ~= "" and info .. "  " or "") .. GREY .. page.notes .. "|r" end
  page.info:SetText(BLUE .. info .. "|r")
  local warnings = Warnings(page.item, price, quantity, totals)
  page.warning:SetText(ORANGE .. "· " .. table.concat(warnings, "\n· ") .. "|r")
  page.warnings:SetShown(#warnings > 0)
end

local function Post(confirmed)
  local price, quantity = ReadInputs()
  local item = page.item
  if not price then return end
  if not confirmed then
    local warnings = Warnings(item, price, quantity)
    if #warnings > 0 then
      StaticPopup_Show("MARKETWALL_CONFIRM_POST", table.concat(warnings, "\n"))
      return
    end
  end
  if not item.location:IsValid() or C_Item.GetItemID(item.location) ~= item.id then
    ns.Print("Your bags changed. Pick the item again.")
    ns.RefreshUI()
    return
  end
  local duration = ns.Cfg("sellDuration")
  -- Both calls return true when the game wants a confirmation first; Blizzard's own sell
  -- frames hold the pending post and show that dialog.
  if IsCommodity(item.location) then
    if C_AuctionHouse.PostCommodity(item.location, duration, quantity, price) then
      local frame = AuctionHouseFrame.CommoditiesSellFrame
      if frame and frame.CachePendingPost then frame:CachePendingPost(item.location, duration, quantity, price) end
    end
  else
    if C_AuctionHouse.PostItem(item.location, duration, quantity, nil, price) then
      local frame = AuctionHouseFrame.ItemSellFrame
      if frame and frame.CachePendingPost then frame:CachePendingPost(item.location, duration, quantity, nil, price) end
    end
  end
  ns.Print(string.format("Posting %d x %s at %s each.", quantity, ns.Name(item.id) or "item", ns.Money(price)))
  page.priceEdited, page.quantityEdited = false, false
end

StaticPopupDialogs["MARKETWALL_CONFIRM_POST"] = {
  text = "%s\n\nPost anyway?",
  button1 = YES,
  button2 = NO,
  OnAccept = function() Post(true) end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------

local function LoadListings(id, force)
  local held = ns.ladders[id]
  local stale = not held or held.kind == "scan" or time() - held.t > 30
  if ns.ahOpen and not ns.scanState.running and not ns.fullScanRunning and (force or stale) then
    ns.StartWatchScan({ id })
  end
end

local function Select(id)
  selectedID = id
  page.priceEdited, page.quantityEdited = false, false
  LoadListings(id)
  ns.RefreshUI()
end

local function RefreshAuctions(id)
  local held = ns.ladders[id]
  local rows = {}
  local price = ReadPrice()
  local wall = PV.LiveWall(id)
  local bait = ns.R().bait[id]
  local running, marked = 0, false
  for _, tier in ipairs(held and held.ladder or {}) do
    running = running + tier.q
    local here = not marked and price and tier.p >= price
    if here then marked = true end
    rows[#rows + 1] = {
      price = tier.p,
      highlight = here,
      cells = { ns.Money(tier.p), tostring(tier.q), tostring(running), P.AuctionNote(tier, wall, bait) },
    }
  end
  local empty
  if ns.scanState.running then
    empty = "Loading current auctions..."
  elseif held then
    empty = "Nothing listed right now."
  else
    empty = "No auctions loaded. Press the refresh button."
  end
  page.auctions:SetData(rows, empty)
  page.listingsTitle:SetText("Current listings · " .. ns.ColorName(id))
  page.listingsAge:SetText(held and (GREY .. (held.kind == "scan" and "full scan, " or "live, ") .. ns.Ago(held.t) .. "|r") or "")
end

-- What the strip's notes add after the info line: your sell price and break-even
local function Notes(id)
  local notes = {}
  local entry = ns.R().watch[id]
  if entry and entry.sell then notes[#notes + 1] = "your sell price " .. ns.Money(entry.sell) end
  local pos = ns.R().pos[id]
  if pos and pos.qty > 0 then
    notes[#notes + 1] = "break-even " .. ns.Money(math.ceil((pos.cost / pos.qty) / (1 - ns.Cfg("ahCut"))))
  end
  return table.concat(notes, "  ·  ")
end

local function RefreshSelected(item)
  page.item = item
  page.strip:SetShown(item ~= nil)
  page.info:SetShown(item ~= nil)
  page.pick:SetShown(item == nil)
  page.listingsTitle:SetShown(item ~= nil and page.tab == "listings")
  page.view:SetShown(item ~= nil and page.tab == "history")
  if not item then
    page.view.id = nil   -- the item left the bags: drop its chart and stats with the listings
    page.warnings:Hide()
    page.auctions:SetData({}, "Pick an item from your bags.")
    page.listingsAge:SetText("")
    return
  end
  local id = item.id
  local entry = ns.R().watch[id]

  page.slot:SetItem(item)
  page.title:SetText(ns.ColorName(id) .. GREY .. "  ·  " .. item.count .. " in bags|r")
  page.notes = Notes(id)
  page.view:SetItem(id, nil, entry and entry.sell)

  page.maxQuantity = C_AuctionHouse.GetAvailablePostCount(item.location) or item.count
  page.start = P.StartingPrice(id)
  local focused = page.gold:HasFocus() or page.silver:HasFocus() or page.copper:HasFocus()
  if not page.priceEdited and not focused then SetPrice(page.start and page.start.price) end
  if not page.quantityEdited and not page.quantity:HasFocus() then
    page.quantity:SetText(tostring(page.maxQuantity))
  end
  for duration, radio in pairs(page.durations) do radio:SetChecked(duration == ns.Cfg("sellDuration")) end
  UpdateTotals()
  RefreshAuctions(id)
end

function ns.RefreshSell()
  if not page then return end
  local valuesOf, current = Outlet.Game(), nil
  local items = BagItems()
  for _, item in ipairs(items) do
    if item.id == selectedID then current = item end
    item.values = valuesOf(item.id, Deposit(item, 1))
  end
  page.grid:SetGroups(P.Groups(items), selectedID)
  if not current then selectedID = nil end
  RefreshSelected(current)
end

-- Open the Sell page with an item from the bags selected
function ns.ShowSell(id)
  ui.Show("sell")
  for _, item in ipairs(BagItems()) do
    if item.id == id then
      Select(id)
      return
    end
  end
  ns.Print("You have no " .. (ns.Name(id) or "such item") .. " in your bags to sell.")
end

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------

local function Panel(parent, x, y, width, height)
  local f = CreateFrame("Frame", nil, parent)
  f:SetPoint("TOPLEFT", x, y)
  f:SetSize(width, height)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(1, 1, 1, 0.04)
  return f
end

local function Label(parent, text, x, y)
  local label = ns.widgets.MakeText(parent, "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(text)
  return label
end

-------------------------------------------------------------------------------
-- Layout
-------------------------------------------------------------------------------

local function MoneyBox(parent, width, coin)
  local box = ns.widgets.MakeEdit(parent, width)
  box:SetNumeric(true)
  box:SetJustifyH("RIGHT")
  box:SetScript("OnTextChanged", function(_, userInput)
    if userInput then page.priceEdited = true end
    if page.item then
      UpdateTotals()
      RefreshAuctions(page.item.id)
    end
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box.coin = parent:CreateTexture(nil, "ARTWORK")
  box.coin:SetSize(12, 12)
  box.coin:SetTexture("Interface\\MoneyFrame\\UI-" .. coin .. "Icon")
  box.coin:SetPoint("LEFT", box, "RIGHT", 2, 0)
  return box
end

-- Left of the strip: the item, Quantity and Price each
local function BuildItemControls(w, s)
  page.slot = ns.SellBags.ItemSlot(s, 44)
  page.slot:SetPoint("TOPLEFT", 6, -4)
  page.title = w.MakeText(s, "GameFontNormal")
  page.title:SetPoint("TOPLEFT", 58, -4)
  page.title:SetWidth(300)
  page.title:SetWordWrap(false)

  Label(s, "Quantity", 58, -27)
  page.quantity = w.MakeEdit(s, 50)
  page.quantity:SetNumeric(true)
  page.quantity:SetPoint("TOPLEFT", 130, -22)
  page.quantity:SetScript("OnTextChanged", function(_, userInput)
    if userInput then page.quantityEdited = true end
    if page.item then UpdateTotals() end
  end)
  page.quantity:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local max = w.MakeButton(s, "Max", 44)
  max:SetPoint("LEFT", page.quantity, "RIGHT", 4, 0)
  max:SetScript("OnClick", function()
    page.quantityEdited = false
    page.quantity:ClearFocus()
    ns.RefreshUI()
  end)

  Label(s, "Price each", 58, -53)
  page.gold = MoneyBox(s, 40, "Gold")
  page.gold:SetPoint("TOPLEFT", 130, -48)
  page.silver = MoneyBox(s, 26, "Silver")
  page.silver:SetPoint("LEFT", page.gold.coin, "RIGHT", 8, 0)
  page.copper = MoneyBox(s, 26, "Copper")
  page.copper:SetPoint("LEFT", page.silver.coin, "RIGHT", 8, 0)
  local useWall = w.MakeButton(s, "Use wall", 70)
  useWall:SetPoint("LEFT", page.copper.coin, "RIGHT", 6, 0)
  useWall:SetScript("OnClick", function()
    if page.item then ChoosePrice(P.Wall(page.item.id)) end
    ns.RefreshUI()
  end)
  useWall:SetScript("OnEnter", function(self)
    w.ShowTip(self, "Use wall", "Sets Price each to the wall: the lowest price level with real supply behind it.")
  end)
  useWall:SetScript("OnLeave", w.HideTip)
end

-- Middle of the strip: Duration and the Post button
local function BuildPostControls(w, s)
  Label(s, "Duration", POST_X, -4)
  page.durations = {}
  for i, def in ipairs(DURATIONS) do
    local duration = def[1]
    local radio = CreateFrame("CheckButton", nil, s, "UIRadioButtonTemplate")
    radio:SetSize(16, 16)
    radio:SetPoint("TOPLEFT", POST_X - 2 + (i - 1) * 56, -20)
    radio:SetScript("OnClick", function()
      MarketWallDB.cfg.sellDuration = duration
      ns.RefreshUI()
    end)
    local label = w.MakeText(s, "GameFontHighlightSmall")
    label:SetPoint("LEFT", radio, "RIGHT", 2, 0)
    label:SetText(def[2])
    page.durations[duration] = radio
  end

  page.post = w.MakeButton(s, "Post", 160)
  page.post:SetHeight(26)
  page.post:SetPoint("TOPLEFT", POST_X, -44)
  page.post:SetScript("OnClick", function() Post(false) end)
end

-- Right of the strip: what a post earns against a vendor, and the refresh button
local function BuildTotals(w, s)
  local rows = {}
  page.totals = rows
  local function Line(key, text, row)
    local y = -4 - (row - 1) * TOTAL_ROW
    rows[key .. "Label"] = Label(s, text, TOTALS_X, y)
    local value = w.MakeText(s, "GameFontHighlightSmall", "RIGHT")
    value:SetPoint("TOPRIGHT", s, "TOPLEFT", TOTALS_X + TOTALS_WIDTH, y)
    value:SetWidth(100)
    rows[key] = value
    return value
  end
  Line("total", "Total", 1)
  Line("afterCut", "After cut", 2)
  Line("deposit", "Deposit", 3)
  Line("net", "AH net", 4)
  Line("vendor", "Vendor", 5)
  Line("beats", "AH beats vendor by", 6)
  rows.perUnit = w.MakeText(s, "GameFontHighlightSmall")
  rows.perUnit:SetPoint("TOPLEFT", TOTALS_X, -4 - 6 * TOTAL_ROW)
  rows.perUnit:SetWidth(TOTALS_WIDTH)
  rows.perUnit:SetWordWrap(false)

  -- font strings take no mouse, so a frame over the Deposit row carries its tooltip
  local depositTip = CreateFrame("Frame", nil, s)
  depositTip:SetPoint("TOPLEFT", TOTALS_X, -4 - 2 * TOTAL_ROW)
  depositTip:SetSize(TOTALS_WIDTH, TOTAL_ROW)
  depositTip:EnableMouse(true)
  depositTip:SetScript("OnEnter", function(self)
    w.ShowTip(self, "Deposit", "Counted here as a cost, the worst case. The game refunds the deposit when the auction sells, and keeps it if the auction expires or you cancel it.")
  end)
  depositTip:SetScript("OnLeave", w.HideTip)

  local refresh = w.MakeButton(s, "", 26)
  refresh:SetPoint("TOPRIGHT", -4, -2)
  local icon = refresh:CreateTexture(nil, "OVERLAY")
  icon:SetTexture("Interface\\Buttons\\UI-RefreshButton")
  icon:SetSize(14, 14)
  icon:SetPoint("CENTER")
  refresh:SetScript("OnClick", function()
    if selectedID then LoadListings(selectedID, true) end
  end)
  refresh:SetScript("OnEnter", function(self)
    w.ShowTip(self, "Refresh listings", "Loads the auctions listed for this item right now, so the lowest listing and the wall are live.")
  end)
  refresh:SetScript("OnLeave", w.HideTip)
end

local function BuildStrip(w)
  local s = Panel(page, 0, STRIP_TOP, WIDTH, STRIP_HEIGHT)
  page.strip = s
  BuildItemControls(w, s)
  BuildPostControls(w, s)
  BuildTotals(w, s)

  page.pick = w.MakeText(page, "GameFontDisable", "CENTER")
  page.pick:SetPoint("TOPLEFT", 0, STRIP_TOP - 30)
  page.pick:SetPoint("RIGHT")
  page.pick:SetText("Pick an item from your bags below to price it and post it.")

  page.info = w.MakeText(page, "GameFontHighlightSmall")
  page.info:SetPoint("TOPLEFT", 8, INFO_Y)
  page.info:SetWidth(WIDTH - 16)
  page.info:SetWordWrap(false)

  page.warnings = Panel(page, 0, WARNINGS_Y, WIDTH, WARNINGS_HEIGHT)
  local bar = page.warnings:CreateTexture(nil, "BORDER")
  bar:SetColorTexture(1, 0.69, 0.34, 0.8)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("BOTTOMLEFT")
  bar:SetWidth(3)
  page.warning = w.MakeText(page.warnings, "GameFontHighlightSmall")
  page.warning:SetPoint("TOPLEFT", 10, -4)
  page.warning:SetWidth(WIDTH - 20)
  page.warning:SetSpacing(2)
end

-- Bottom tabs under the listings: Current listings and Price history
local function ShowTab(name)
  page.tab = name
  local listings = name == "listings"
  page.auctions:SetShown(listings)
  page.listingsTitle:SetShown(listings and page.item ~= nil)
  page.listingsAge:SetShown(listings)
  page.rowHint:SetShown(listings)
  page.view:SetShown(not listings and page.item ~= nil)
  for key, button in pairs(page.tabs) do
    if key == name then button:LockHighlight() else button:UnlockHighlight() end
  end
end

local function BuildListings(w)
  local r = Panel(page, RIGHT_X, BODY_TOP, RIGHT_WIDTH, BODY_HEIGHT)
  page.listings = r

  page.listingsTitle = w.MakeText(r, "GameFontNormal")
  page.listingsTitle:SetPoint("TOPLEFT", 8, -4)
  page.listingsTitle:SetWidth(RIGHT_WIDTH - 120)
  page.listingsTitle:SetWordWrap(false)
  page.listingsAge = w.MakeText(r, "GameFontHighlightSmall", "RIGHT")
  page.listingsAge:SetPoint("TOPRIGHT", -8, -6)

  page.auctions = w.CreateList(r, LIST_ROWS)
  page.auctions:SetPoint("TOPLEFT", 0, -20)
  page.auctions:SetSize(RIGHT_WIDTH, w.ListHeight(LIST_ROWS))
  page.auctions:SetColumns(AUCTION_COLUMNS)
  page.auctions.empty:SetWidth(RIGHT_WIDTH - 20)
  page.auctions.empty:SetPoint("TOP", 0, -60)
  page.auctions.onClick = function(entry)
    ChoosePrice(entry.price)
    ns.RefreshUI()
  end
  page.rowHint = w.MakeText(r, "GameFontDisableSmall")
  page.rowHint:SetPoint("TOPLEFT", 8, -24 - w.ListHeight(LIST_ROWS))
  page.rowHint:SetText("Click a row to set Price each to that level.")

  local width = RIGHT_WIDTH - 8
  page.view = PV.CreateView(r, { width = width, chartHeight = 70, cellWidth = width / 4, cells = HISTORY_CELLS, ranges = true })
  page.view:SetPoint("TOPLEFT", 4, -2)

  page.tabs = {}
  local previous
  for _, def in ipairs({ { "listings", "Current listings" }, { "history", "Price history" } }) do
    local button = w.MakeButton(r, def[2], 120)
    if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("BOTTOMLEFT", 8, 2) end
    button:SetScript("OnClick", function() ShowTab(def[1]) end)
    page.tabs[def[1]] = button
    previous = button
  end
end

function ns.BuildSellPage(parent)
  local w = ns.widgets
  page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints()

  BuildStrip(w)
  local bags = Panel(page, 0, BODY_TOP, LEFT_WIDTH, BODY_HEIGHT)
  page.bags = bags
  page.grid = ns.SellBags.Grid(bags, LEFT_WIDTH, Select)
  BuildListings(w)
  ShowTab("listings")

  -- bags change after posting, selling or looting; the main frame redraws when dirty
  page:RegisterEvent("BAG_UPDATE_DELAYED")
  page:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
  page:SetScript("OnEvent", function() ui.dirty = true end)
  return page
end
