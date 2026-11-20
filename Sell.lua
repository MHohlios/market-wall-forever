-- MarketWall: the Sell page.
-- Top: the item and what you are about to post, with a status line under Price each, and at
-- the right what the auction house pays against a vendor.
-- Left: any warnings, then your bags as an icon grid, grouped by the best outlet for each item
-- (SellBags.lua).
-- Right: the item's price history, or the auctions listed right now, under two top tabs.
-- Prices and words come from SellPricing.lua.
local _, ns = ...
local P, PV, Outlet = ns.SellPricing, ns.PriceView, ns.Outlet
local ui = ns.ui

local WARN, GREY = ns.COLOR.WARN, ns.COLOR.GREY
local DURATIONS = { { 1, "12h" }, { 2, "24h" }, { 3, "48h" } }

-- The Market tab's page is about 782 x 480 below the navigation row
local WIDTH = 782
local STRIP_TOP, STRIP_HEIGHT = -50, 120
local BODY_TOP = STRIP_TOP - STRIP_HEIGHT - 6
local BODY_HEIGHT = 480 + BODY_TOP
local LEFT_WIDTH, RIGHT_X = 300, 312
local POST_X, POST_WIDTH = 384, 130    -- the strip's Duration and Post column
local ANSWER_X = POST_X + POST_WIDTH + 12
local ANSWER_WIDTH = WIDTH - ANSWER_X - 8
local STATUS_Y = -76                -- the status line, under Price each: up to two lines
-- the answer's breakdown: a row of its own under the status line, ending under the answer
local BREAKDOWN_Y, BREAKDOWN_WIDTH = -104, WIDTH - 58 - 8
local WARNINGS_GAP = 4
local RIGHT_WIDTH = WIDTH - RIGHT_X
local TAB_LINE = 28                 -- the right panel's tabs stand on a line this far below its top
local LIST_ROWS = 11

local AUCTION_COLUMNS = {
  { "Price each", 130, nil, "Each price level listed right now, cheapest first. Click a row to set Price each to it." },
  { "Units", 80, "RIGHT", "Units listed at this price." },
  { "Running total", 110, "RIGHT", "Units listed at this price or cheaper." },
  { "", 150, "RIGHT", cellTip = true },
}
local NOTE_TIP = "Wall: the price level with real supply behind it. Bait?: a few units far under the wall, posted so others copy the price, with the copies posted since. Your price: the level Price each matches."

local page
local selectedID

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

-- Sellable bag items, one entry per item ID: { id, location, count }
local function BagItems()
  local byID, items = {}, {}
  for bag = 0, ns.LastBagIndex() do
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

local function Vendor(id)
  return C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
end

-- The game's deposit, which also teaches Outlet the rate it estimates deposits with elsewhere
local function Deposit(item, quantity)
  local duration = ns.Cfg("sellDuration")
  local deposit
  if IsCommodity(item.location) then
    deposit = C_AuctionHouse.CalculateCommodityDeposit(item.id, duration, quantity)
  else
    deposit = C_AuctionHouse.CalculateItemDeposit(item.location, duration, quantity)
  end
  if not deposit then return 0 end
  local vendor = Vendor(item.id)
  -- the neutral Auction House charges its own deposits, which say nothing about your faction's
  if vendor and not ns.neutralAH then Outlet.LearnDepositRate(duration, deposit, vendor * quantity) end
  return deposit
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

local function ShowAnswer(answer)
  page.answer:SetShown(answer ~= nil)
  if not answer then return end
  page.net:SetText(answer.net)
  page.versus:SetText(answer.versus)
  page.breakdown:SetText(answer.breakdown)
end

-- Warnings sit above the bags, which give up the room they take
local function ShowWarnings(warnings)
  local height = 0
  if #warnings > 0 then
    page.warning:SetText(WARN .. "· " .. table.concat(warnings, "\n· ") .. "|r")
    height = page.warning:GetStringHeight() + 10
    page.warnings:SetHeight(height)
    height = height + WARNINGS_GAP
  end
  page.warnings:SetShown(#warnings > 0)
  page.bags:ClearAllPoints()
  page.bags:SetPoint("TOPLEFT", 0, BODY_TOP - height)
  page.bags:SetHeight(BODY_HEIGHT - height)
end

local function UpdateTotals()
  local price, quantity = ReadInputs()
  page.post:SetEnabled(price ~= nil and ns.CanTrade())
  page.post:SetText(quantity and ("Post " .. quantity) or "Post")
  if not price then
    ShowAnswer(nil)
    page.info:SetText(GREY .. "Enter a price and a quantity from 1 to " .. (page.maxQuantity or 0) .. ".|r")
    ShowWarnings({})
    return
  end
  local totals = Totals(page.item, price, quantity)
  ShowAnswer(P.Answer(totals, quantity, price, ns.Cfg("ahCut")))

  local info = P.InfoLine(price, page.start, P.Wall(page.item.id))
  if page.notes ~= "" then info = (info ~= "" and info .. "  " or "") .. page.notes end
  page.info:SetText(GREY .. info .. "|r")
  local warnings = Warnings(page.item, price, quantity, totals)
  -- shown with the warnings, but not one: posting a young item needs no confirmation
  local lowData = ns.LowDataText(ns.DaysOfData(page.item.id))
  if lowData then table.insert(warnings, 1, lowData) end
  ShowWarnings(warnings)
end

local function Post(confirmed)
  local price, quantity = ReadInputs()
  local item = page.item
  if not price or not ns.CanTrade() then return end
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
  if ns.CanTrade() and not ns.scanState.running and not ns.fullScanRunning and (force or stale) then
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
    local note = P.AuctionNote(tier, wall, bait, price)
    rows[#rows + 1] = {
      price = tier.p,
      highlight = here,
      cells = { ns.Money(tier.p), tostring(tier.q), GREY .. running .. "|r", note },
      cellTips = note ~= "" and { [4] = NOTE_TIP } or nil,
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
  page.view:SetShown(item ~= nil and page.tab == "history")
  if not item then
    page.view.id = nil   -- the item left the bags: drop its chart and stats with the listings
    ShowWarnings({})
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
  page.refresh:SetEnabled(ns.CanTrade())
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
    radio:SetPoint("TOPLEFT", POST_X - 2 + (i - 1) * 46, -20)
    radio:SetScript("OnClick", function()
      MarketWallDB.cfg.sellDuration = duration
      ns.Mobs.Invalidate()   -- the duration prices the deposits in mob values and disenchant deals
      ns.DisenchantDepositsChanged()
      ns.RefreshUI()
    end)
    local label = w.MakeText(s, "GameFontHighlightSmall")
    label:SetPoint("LEFT", radio, "RIGHT", 2, 0)
    label:SetText(def[2])
    page.durations[duration] = radio
  end

  page.post = w.MakeButton(s, "Post", POST_WIDTH)
  page.post:SetHeight(26)
  page.post:SetPoint("TOPLEFT", POST_X, -44)
  page.post:SetScript("OnClick", function() Post(false) end)
end

-- Right of the strip: the answer, what the auction house pays against a vendor, with one line
-- of how it adds up; and the refresh button
local function BuildAnswer(w, s)
  local a = CreateFrame("Frame", nil, s)
  a:SetPoint("TOPLEFT", ANSWER_X, 0)
  a:SetSize(ANSWER_WIDTH, STRIP_HEIGHT)
  page.answer = a
  Label(a, "You get from the auction house", 0, -4)
  page.net = w.MakeText(a, "GameFontNormalLarge")
  page.net:SetPoint("TOPLEFT", 0, -20)
  page.versus = w.MakeText(a, "GameFontHighlightSmall")
  page.versus:SetPoint("TOPLEFT", 0, -42)
  page.versus:SetWidth(ANSWER_WIDTH)   -- a long gold comparison wraps onto a second line
  -- wider than the answer column, reaching left under the Post column, so the line stays one line
  page.breakdown = w.MakeText(a, "GameFontHighlightSmall", "RIGHT")
  page.breakdown:SetPoint("TOPRIGHT", 0, BREAKDOWN_Y)
  page.breakdown:SetWidth(BREAKDOWN_WIDTH)
  page.breakdown:SetWordWrap(false)

  -- font strings take no mouse, so a frame over the breakdown carries the deposit's tooltip
  local depositTip = CreateFrame("Frame", nil, a)
  depositTip:SetPoint("TOPRIGHT", 0, BREAKDOWN_Y + 2)
  depositTip:SetSize(BREAKDOWN_WIDTH, 16)
  depositTip:EnableMouse(true)
  depositTip:SetScript("OnEnter", function(self)
    w.ShowTip(self, "Deposit", "Counted here as a cost, the worst case. The game refunds the deposit when the auction sells, and keeps it if the auction expires or you cancel it.")
  end)
  depositTip:SetScript("OnLeave", w.HideTip)

  local refresh = w.MakeButton(s, "", 26)
  page.refresh = refresh
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
  BuildAnswer(w, s)

  page.info = w.MakeText(s, "GameFontHighlightSmall")
  page.info:SetPoint("TOPLEFT", 58, STATUS_Y)
  page.info:SetSize(ANSWER_X - 58 - 8, STATUS_Y - BREAKDOWN_Y - 2)   -- two lines, above the breakdown
  page.info:SetJustifyV("TOP")

  page.pick = w.MakeText(page, "GameFontDisable", "CENTER")
  page.pick:SetPoint("TOPLEFT", 0, STRIP_TOP - 30)
  page.pick:SetPoint("RIGHT")
  page.pick:SetText("Pick an item from your bags below to price it and post it.")
end

-- Above the bags; ShowWarnings sizes it to its lines
local function BuildWarnings(w)
  page.warnings = Panel(page, 0, BODY_TOP, LEFT_WIDTH, 0)
  page.warnings:Hide()
  local bar = page.warnings:CreateTexture(nil, "BORDER")
  bar:SetColorTexture(1, 0.69, 0.34, 0.8)
  bar:SetPoint("TOPLEFT")
  bar:SetPoint("BOTTOMLEFT")
  bar:SetWidth(3)
  page.warning = w.MakeText(page.warnings, "GameFontHighlightSmall")
  page.warning:SetPoint("TOPLEFT", 10, -5)
  page.warning:SetWidth(LEFT_WIDTH - 16)
  page.warning:SetSpacing(2)
end

-- The right panel's top tabs: Price history and Current listings
local function ShowTab(name)
  page.tab = name
  local listings = name == "listings"
  page.auctions:SetShown(listings)
  page.listingsAge:SetShown(listings)
  page.rowHint:SetShown(listings)
  page.view:SetShown(not listings and page.item ~= nil)
  for key, tab in pairs(page.tabs) do ns.widgets.SelectTab(tab, key == name) end
end

local function BuildListings(w)
  local r = Panel(page, RIGHT_X, BODY_TOP, RIGHT_WIDTH, BODY_HEIGHT)
  page.listings = r
  page.tabs = w.MakeTabRow(r, 8, TAB_LINE, {
    { key = "history", label = "Price history" },
    { key = "listings", label = "Current listings" },
  }, ShowTab)
  -- beside the tabs: how fresh the listings are, or the history's range switch
  local function BesideTabs(region) region:SetPoint("RIGHT", r, "TOPRIGHT", -8, -TAB_LINE / 2 - 2) end

  page.listingsAge = w.MakeText(r, "GameFontHighlightSmall", "RIGHT")
  BesideTabs(page.listingsAge)

  local top = -TAB_LINE - 2
  page.auctions = w.CreateList(r, LIST_ROWS)
  page.auctions:SetPoint("TOPLEFT", 0, top)
  page.auctions:SetSize(RIGHT_WIDTH, w.ListHeight(LIST_ROWS))
  page.auctions:SetColumns(AUCTION_COLUMNS)
  page.auctions.empty:SetWidth(RIGHT_WIDTH - 20)
  page.auctions.empty:SetPoint("TOP", 0, -60)
  page.auctions.onClick = function(entry)
    ChoosePrice(entry.price)
    ns.RefreshUI()
  end
  page.rowHint = w.MakeText(r, "GameFontDisableSmall")
  page.rowHint:SetPoint("TOPLEFT", 8, top - 2 - w.ListHeight(LIST_ROWS))
  page.rowHint:SetText("Click a row to price at that level. Highlighted: where your price would sit.")

  page.view = PV.CreateView(r, { width = RIGHT_WIDTH - 12, height = BODY_HEIGHT + top - 4, ranges = true, placeRanges = BesideTabs })
  page.view:SetPoint("TOPLEFT", 4, top)
end

function ns.BuildSellPage(parent)
  local w = ns.widgets
  page = CreateFrame("Frame", nil, parent)
  page:SetPoint("TOPLEFT", 0, -w.CONTENT_DROP)
  page:SetPoint("BOTTOMRIGHT")

  BuildStrip(w)
  BuildWarnings(w)
  local bags = Panel(page, 0, BODY_TOP, LEFT_WIDTH, BODY_HEIGHT)
  page.bags = bags
  page.grid = ns.SellBags.Grid(bags, LEFT_WIDTH, Select)
  BuildListings(w)
  ShowTab("history")

  -- bags change after posting, selling or looting; the main frame redraws when dirty
  page:RegisterEvent("BAG_UPDATE_DELAYED")
  page:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
  page:SetScript("OnEvent", function() ui.dirty = true end)
  return page
end
