-- MarketWall: the Sell page, laid out like Auctionator's Selling tab.
-- Top: what you are posting (left) and the item's last 7 days with its key numbers (right).
-- Bottom: what you can sell (left) and the auctions listed right now (right).
local _, ns = ...
local B, PV = ns.Bait, ns.PriceView
local ui = ns.ui

local FLAT = PV.FLAT
local ORANGE, GREY, GOLD = "|cffffb057", "|cffa3acac", "|cfff5c518"
local DURATIONS = { { 1, "12h" }, { 2, "24h" }, { 3, "48h" } }

local LEFT_WIDTH, RIGHT_X, RIGHT_WIDTH = 330, 340, 442
local TOP, BOTTOM_Y, LIST_ROWS = -50, -250, 9
local CELLS = { "wallNow", "lowestListing", "supply", "trend", "average", "median", "normalRange", "versusMedian" }

local BAG_COLUMNS = {
  { "Item", 130, nil, "Items in your bags that can be sold here, most valuable first. Click one to price it." },
  { "Qty", 40, "RIGHT", "How many you have." },
  { "Wall", 80, "RIGHT", "The current wall price, or the last one recorded." },
  { "Vs normal", 80, "RIGHT", "The wall price against the item's median. Blue is low, orange is high." },
}
local AUCTION_COLUMNS = {
  { "Price each", 120, nil, "Each price level listed right now, cheapest first." },
  { "Quantity", 80, "RIGHT", "Units listed at this price." },
  { "Running total", 110, "RIGHT", "Units listed at this price or cheaper." },
  { "Note", 130, "RIGHT", "Wall: the price level with real supply behind it. Bait?: a few units far under the wall, posted so others copy the price, with the copies posted since. The highlighted row is where your price would sit." },
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

local function SuggestedPrice(id)
  return PV.LiveWall(id) or ns.LatestWall(id)
end

-- The Note column: the bait level Bait Detect tracks, or the wall
local function AuctionNote(tier, wall, bait)
  if bait and tier.p == bait.p then return ORANGE .. "bait? " .. B.LevelNote(bait) .. "|r" end
  if tier.p == wall then return GOLD .. "wall|r" end
  return ""
end
ns.SellPricing = { SuggestedPrice = SuggestedPrice, AuctionNote = AuctionNote }   -- exposed for tests

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

-------------------------------------------------------------------------------
-- Posting
-------------------------------------------------------------------------------

local function ReadInputs()
  local price = ns.ParseMoney(page.price:GetText())
  local quantity = tonumber(page.quantity:GetText())
  if not (page.item and price and price > 0 and quantity and quantity >= 1 and quantity <= page.maxQuantity) then
    return nil
  end
  return price, quantity
end

-- Reasons to think twice before posting at this price
local function Warnings(item, price, quantity)
  local warnings = {}
  local cut = ns.Cfg("ahCut")
  local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(item.id))
  local netEach = price * (1 - cut) - Deposit(item, quantity) / quantity
  if vendor and vendor > 0 and netEach < vendor then
    warnings[#warnings + 1] = string.format("Below vendor: %s each after the cut and deposit. A vendor pays %s.",
      ns.Money(netEach), ns.Money(vendor))
  end
  local market = SuggestedPrice(item.id)
  local bait = B.PostWarning(ns.R().bait[item.id], price, FLAT)
  if bait then
    warnings[#warnings + 1] = bait   -- says more than Below market, which it replaces
  elseif market and price < market * (1 - FLAT) then
    warnings[#warnings + 1] = string.format("Below market: %d%% under the %s wall.",
      ns.Round((1 - price / market) * 100), ns.Money(market))
  end
  return warnings
end

local function UpdateTotals()
  local price, quantity = ReadInputs()
  page.post:SetEnabled(price ~= nil and ns.ahOpen)
  if not price then
    page.totals:SetText(GREY .. "Enter a price and a quantity from 1 to " .. (page.maxQuantity or 0) .. ".|r")
    page.warning:SetText("")
    return
  end
  local cut = ns.Cfg("ahCut")
  page.totals:SetText(string.format("Deposit %s    You get %s after the %d%% cut",
    ns.Money(Deposit(page.item, quantity)), ns.Money(price * quantity * (1 - cut)), ns.Round(cut * 100)))
  page.warning:SetText(ORANGE .. table.concat(Warnings(page.item, price, quantity), "\n") .. "|r")
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
  local price = ns.ParseMoney(page.price:GetText())
  local wall = PV.LiveWall(id)
  local bait = ns.R().bait[id]
  local running, marked = 0, false
  for _, tier in ipairs(held and held.ladder or {}) do
    running = running + tier.q
    local here = not marked and price and tier.p >= price
    if here then marked = true end
    rows[#rows + 1] = {
      highlight = here,
      cells = { ns.Money(tier.p), tostring(tier.q), tostring(running), AuctionNote(tier, wall, bait) },
    }
  end
  local empty
  if ns.scanState.running then
    empty = "Loading current auctions..."
  elseif held then
    empty = "Nothing listed right now."
  else
    empty = "No auctions loaded. Press Refresh listings."
  end
  page.auctions:SetData(rows, empty)
end

local function RefreshSelected(item)
  page.item = item
  page.sale:SetShown(item ~= nil)
  page.info:SetShown(item ~= nil)
  page.pick:SetShown(item == nil)
  if not item then
    page.auctions:SetData({}, "")
    return
  end
  local id = item.id
  local entry = ns.R().watch[id]

  page.icon:SetTexture(ns.Icon(id))
  page.title:SetText(ns.ColorName(id))
  local notes = { item.count .. " in bags" }
  if entry and entry.sell then notes[#notes + 1] = "your sell price " .. ns.Money(entry.sell) end
  local pos = ns.R().pos[id]
  if pos and pos.qty > 0 then
    notes[#notes + 1] = "break-even " .. ns.Money(math.ceil((pos.cost / pos.qty) / (1 - ns.Cfg("ahCut"))))
  end
  page.notes:SetText(GREY .. table.concat(notes, "  ·  ") .. "|r")

  page.view:SetItem(id, nil, entry and entry.sell)

  page.maxQuantity = C_AuctionHouse.GetAvailablePostCount(item.location) or item.count
  page.ofQuantity:SetText("of " .. page.maxQuantity)
  if not page.priceEdited and not page.price:HasFocus() then
    local suggested = SuggestedPrice(id)
    page.price:SetText(suggested and ns.Money(suggested) or "")
  end
  if not page.quantityEdited and not page.quantity:HasFocus() then
    page.quantity:SetText(tostring(page.maxQuantity))
  end
  for duration, button in pairs(page.durations) do
    if duration == ns.Cfg("sellDuration") then button:LockHighlight() else button:UnlockHighlight() end
  end
  UpdateTotals()
  RefreshAuctions(id)
end

function ns.RefreshSell()
  if not page then return end
  local rows, current = {}, nil
  for _, item in ipairs(BagItems()) do
    if item.id == selectedID then current = item end
    local wall = SuggestedPrice(item.id)
    local diff, word = ns.Versus(wall, ns.StatsFor(item.id))
    rows[#rows + 1] = {
      id = item.id,
      highlight = item.id == selectedID,
      value = (wall or 0) * item.count,
      name = ns.Name(item.id) or "",
      cells = { ns.ColorName(item.id), tostring(item.count), wall and ns.Money(wall) or GREY .. "-|r", diff and ns.VersusText(diff, word) or "" },
    }
  end
  table.sort(rows, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  page.bags:SetData(rows, "Nothing in your bags can be sold here.")
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
-- Layout
-------------------------------------------------------------------------------

local function Label(parent, text, x, y)
  local label = ns.widgets.MakeText(parent, "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", x, y)
  label:SetText(text)
  return label
end

-- Top left: the item and what you are about to post
local function BuildSale(w)
  local s = CreateFrame("Frame", nil, page)
  s:SetPoint("TOPLEFT", 0, TOP)
  s:SetSize(LEFT_WIDTH, TOP - BOTTOM_Y)
  page.sale = s

  page.icon = s:CreateTexture(nil, "ARTWORK")
  page.icon:SetSize(22, 22)
  page.icon:SetPoint("TOPLEFT", 8, -4)
  page.title = w.MakeText(s, "GameFontNormalLarge")
  page.title:SetPoint("LEFT", page.icon, "RIGHT", 8, 0)
  page.title:SetPoint("RIGHT", s, "RIGHT")
  page.title:SetWordWrap(false)
  page.notes = w.MakeText(s, "GameFontHighlightSmall")
  page.notes:SetPoint("TOPLEFT", 8, -30)
  page.notes:SetWidth(LEFT_WIDTH - 8)
  page.notes:SetWordWrap(false)

  Label(s, "Price each", 8, -48)
  page.price = w.MakeEdit(s, 110)
  page.price:SetPoint("TOPLEFT", 14, -62)
  page.price:SetScript("OnTextChanged", function(_, userInput)
    if userInput then page.priceEdited = true end
    UpdateTotals()
    if page.item then RefreshAuctions(page.item.id) end
  end)
  page.price:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  local useWall = w.MakeButton(s, "Use wall", 76)
  useWall:SetPoint("LEFT", page.price, "RIGHT", 6, 0)
  useWall:SetScript("OnClick", function()
    page.priceEdited = false
    page.price:ClearFocus()
    ns.RefreshUI()
  end)

  Label(s, "Quantity", 226, -48)
  page.quantity = w.MakeEdit(s, 44)
  page.quantity:SetNumeric(true)
  page.quantity:SetPoint("TOPLEFT", 232, -62)
  page.quantity:SetScript("OnTextChanged", function(_, userInput)
    if userInput then page.quantityEdited = true end
    UpdateTotals()
  end)
  page.quantity:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  page.ofQuantity = w.MakeText(s, "GameFontHighlightSmall")
  page.ofQuantity:SetPoint("LEFT", page.quantity, "RIGHT", 4, 0)

  Label(s, "Duration", 8, -94)
  page.durations = {}
  local previous
  for _, def in ipairs(DURATIONS) do
    local duration = def[1]
    local button = w.MakeButton(s, def[2], 50)
    if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 70, -88) end
    button:SetScript("OnClick", function()
      MarketWallDB.cfg.sellDuration = duration
      ns.RefreshUI()
    end)
    page.durations[duration] = button
    previous = button
  end

  page.totals = w.MakeText(s, "GameFontHighlightSmall")
  page.totals:SetPoint("TOPLEFT", 8, -118)
  page.totals:SetWidth(LEFT_WIDTH - 8)
  page.warning = w.MakeText(s, "GameFontHighlightSmall")
  page.warning:SetPoint("TOPLEFT", 8, -134)
  page.warning:SetWidth(LEFT_WIDTH - 8)
  page.warning:SetSpacing(2)

  page.post = w.MakeButton(s, "Post", 140)
  page.post:SetPoint("TOPLEFT", 8, -172)
  page.post:SetScript("OnClick", function() Post(false) end)
  local refresh = w.MakeButton(s, "Refresh listings", 130)
  refresh:SetPoint("LEFT", page.post, "RIGHT", 6, 0)
  refresh:SetScript("OnClick", function()
    if selectedID then LoadListings(selectedID, true) end
  end)
  refresh:SetScript("OnEnter", function(self)
    w.ShowTip(self, "Refresh listings", "Loads the auctions listed for this item right now, so the wall price is live.")
  end)
  refresh:SetScript("OnLeave", w.HideTip)
end

-- Top right: the last 7 days and the numbers that matter
local function BuildInfo()
  local f = CreateFrame("Frame", nil, page)
  f:SetPoint("TOPLEFT", RIGHT_X, TOP)
  f:SetSize(RIGHT_WIDTH, TOP - BOTTOM_Y)
  page.info = f

  page.view = PV.CreateView(f, { width = RIGHT_WIDTH, chartHeight = 100, cellWidth = 110, cells = CELLS })
  page.view:SetPoint("TOPLEFT")
end

function ns.BuildSellPage(parent)
  local w = ns.widgets
  page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints()

  BuildSale(w)
  BuildInfo()

  page.pick = w.MakeText(page, "GameFontDisable", "CENTER")
  page.pick:SetPoint("TOPLEFT", 0, -130)
  page.pick:SetPoint("RIGHT")
  page.pick:SetText("Pick an item from your bags below to see its last 7 days and post it.")

  page.bags = w.CreateList(page, LIST_ROWS)
  page.bags:SetPoint("TOPLEFT", 0, BOTTOM_Y)
  page.bags:SetSize(LEFT_WIDTH, w.ListHeight(LIST_ROWS))
  page.bags:SetColumns(BAG_COLUMNS)
  page.bags.empty:SetWidth(LEFT_WIDTH - 20)
  page.bags.empty:SetPoint("TOP", 0, -60)
  page.bags.onClick = function(entry) Select(entry.id) end

  page.auctions = w.CreateList(page, LIST_ROWS)
  page.auctions:SetPoint("TOPLEFT", RIGHT_X, BOTTOM_Y)
  page.auctions:SetSize(RIGHT_WIDTH, w.ListHeight(LIST_ROWS))
  page.auctions:SetColumns(AUCTION_COLUMNS)
  page.auctions.empty:SetWidth(RIGHT_WIDTH - 20)
  page.auctions.empty:SetPoint("TOP", 0, -60)

  -- bags change after posting, selling or looting; the main frame redraws when dirty
  page:RegisterEvent("BAG_UPDATE_DELAYED")
  page:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
  page:SetScript("OnEvent", function() ui.dirty = true end)
  return page
end
