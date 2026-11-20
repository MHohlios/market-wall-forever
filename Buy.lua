-- MarketWall: buying. Every purchase is confirmed by a click, as the game requires.
local _, ns = ...
local W = ns.Wall

local pending
local buyer = CreateFrame("Frame")
local dialog

local PURCHASE_EVENTS = {
  "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PRICE_UNAVAILABLE",
  "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED",
}

local function Unregister()
  for i = 1, #PURCHASE_EVENTS do buyer:UnregisterEvent(PURCHASE_EVENTS[i]) end
end

local function GetDialog()
  if dialog then return dialog end
  dialog = CreateFrame("Frame", "MarketWallConfirm", UIParent)
  dialog:SetSize(360, 150)
  dialog:SetPoint("CENTER", 0, 80)
  dialog:SetFrameStrata("DIALOG")
  dialog:EnableMouse(true)
  local bg = dialog:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.07, 0.07, 0.97)
  local edge = dialog:CreateTexture(nil, "BORDER")
  edge:SetPoint("TOPLEFT", -1, 1)
  edge:SetPoint("BOTTOMRIGHT", 1, -1)
  edge:SetColorTexture(0.96, 0.77, 0.09, 0.9)
  bg:SetDrawLayer("ARTWORK")
  dialog.text = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dialog.text:SetPoint("TOPLEFT", 16, -16)
  dialog.text:SetPoint("TOPRIGHT", -16, -16)
  dialog.text:SetJustifyH("LEFT")
  dialog.text:SetSpacing(4)
  dialog.confirm = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  dialog.confirm:SetSize(140, 26)
  dialog.confirm:SetPoint("BOTTOMLEFT", 16, 14)
  dialog.confirm:SetText("Confirm purchase")
  dialog.cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  dialog.cancel:SetSize(100, 26)
  dialog.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
  dialog.cancel:SetText("Cancel")
  dialog.cancel:SetScript("OnClick", function() ns.CancelPurchase() end)
  dialog:Hide()
  return dialog
end

-- note: why, passed to the purchase's onEnd so its owner knows nothing was bought
function ns.CancelPurchase(note)
  local onEnd = pending and pending.onEnd
  if pending and pending.kind == "commodity" and C_AuctionHouse.CancelCommoditiesPurchase then
    C_AuctionHouse.CancelCommoditiesPurchase()
  end
  pending = nil
  Unregister()
  if dialog then dialog:Hide() end
  if onEnd then onEnd(false, note or "Purchase cancelled") end
end

local function AfterPurchase(id)
  -- refresh the listings for this item so the screen shows what is left
  C_Timer.After(1, function()
    if ns.CanTrade() and not ns.scanState.running then ns.StartWatchScan({ id }) end
  end)
end

-- A purchase that ended without buying. Callers with their own onEnd decide what happens next.
local function EndUnbought(message, note)
  local id, onEnd = pending.id, pending.onEnd
  ns.CancelPurchase(note)
  if not onEnd then
    ns.Print(message .. " Rescanning.")
    AfterPurchase(id)
  end
end

function ns.HasPendingPurchase()
  return pending ~= nil
end

-- purchase: what ns.StartCommodityPurchase returned. Confirms only that purchase, once quoted;
-- returns false when it is no longer the one waiting.
function ns.ConfirmPurchase(purchase)
  if not pending or pending ~= purchase or not pending.total then return false end
  C_AuctionHouse.ConfirmCommoditiesPurchase(pending.id, pending.qty)
  if dialog then dialog:Hide() end
  return true
end

local function ShowQuote(totalPrice)
  local d = GetDialog()
  local purchase = pending
  d.text:SetText(string.format("Buy %d x %s\nTotal: %s  (about %s each)\nResale break-even after the cut: %s each",
    pending.qty, ns.Name(pending.id), ns.Money(totalPrice), ns.Money(totalPrice / pending.qty),
    ns.Money(math.ceil((totalPrice / pending.qty) / (1 - ns.Cfg("ahCut"))))))
  d.confirm:SetScript("OnClick", function() ns.ConfirmPurchase(purchase) end)
  d:Show()
end

buyer:SetScript("OnEvent", function(_, event, unitPrice, totalPrice)
  if not pending then return end
  if event == "COMMODITY_PRICE_UPDATED" then
    if pending.onQuote then
      pending.total = totalPrice
      pending.onQuote(unitPrice, totalPrice)
      return
    end
    if not totalPrice or totalPrice > pending.maxTotal then
      EndUnbought("The price moved before the purchase. Nothing was bought.")
      return
    end
    pending.total = totalPrice
    ShowQuote(totalPrice)
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    EndUnbought("Those units are no longer available.", "No longer available")
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local id, qty, total, onEnd = pending.id, pending.qty, pending.total or pending.maxTotal, pending.onEnd
    ns.AddPosition(id, qty, total)
    ns.Print(string.format("Bought %d x %s for %s.", qty, ns.Name(id), ns.Money(total)))
    pending = nil
    Unregister()
    if dialog then dialog:Hide() end
    if onEnd then onEnd(true, string.format("Bought %d for %s", qty, ns.Money(total)), total) else AfterPurchase(id) end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    ns.Print("The purchase failed. Nothing was bought.")
    local id, onEnd = pending.id, pending.onEnd
    pending = nil
    Unregister()
    if dialog then dialog:Hide() end
    if onEnd then onEnd(false, "Purchase failed") else AfterPurchase(id) end
  end
end)

-- Start buying the qty cheapest units of a commodity. The game answers with a price quote.
-- onQuote(unitPrice, totalPrice): optional; replaces the confirm dialog, and the caller then
-- calls ns.ConfirmPurchase or ns.CancelPurchase. onEnd(bought, note, total): optional; replaces the
-- automatic rescan, and also runs when the purchase is cancelled. Returns the purchase, to pass
-- to ns.ConfirmPurchase, or nil when another purchase is still waiting.
function ns.StartCommodityPurchase(id, qty, maxTotal, onQuote, onEnd)
  if pending then return nil end
  pending = { id = id, qty = qty, maxTotal = maxTotal, kind = "commodity", onQuote = onQuote, onEnd = onEnd }
  for i = 1, #PURCHASE_EVENTS do buyer:RegisterEvent(PURCHASE_EVENTS[i]) end
  C_AuctionHouse.StartCommoditiesPurchase(id, qty)
  return pending
end

-- Buy every unit priced under limit. Needs listings scanned within the last two minutes.
function ns.BuyUnder(id, limit)
  local blocked = ns.TradeBlocked()
  if blocked then ns.Print(blocked) return end
  if pending then ns.Print("A purchase is already waiting for confirmation.") return end
  local held = ns.ladders[id]
  if not held or held.kind == "scan" or time() - held.t > 120 then
    ns.Print("Listings are out of date. Rescanning, then press Buy again.")
    if not ns.scanState.running then ns.StartWatchScan({ id }) end
    return
  end
  if not limit then ns.Print("Set a buy price first.") return end

  if held.kind == "commodity" then
    local units, cost = W.UnitsUnder(held.ladder, limit)
    if units == 0 then ns.Print("Nothing is listed under " .. ns.Money(limit) .. ".") return end
    if GetMoney() < cost then
      ns.Print("Not enough gold: that costs " .. ns.Money(cost) .. ".")
      return
    end
    ns.StartCommodityPurchase(id, units, cost)
  elseif held.kind == "item" then
    local auction = held.auctions and held.auctions[1]
    if not auction or auction.unit >= limit then
      ns.Print("Nothing is listed under " .. ns.Money(limit) .. ".")
      return
    end
    if GetMoney() < auction.price then
      ns.Print("Not enough gold: that costs " .. ns.Money(auction.price) .. ".")
      return
    end
    pending = { id = id, qty = auction.qty, maxTotal = auction.price, total = auction.price, kind = "item", auctionID = auction.id }
    local d = GetDialog()
    d.text:SetText(string.format("Buy %d x %s\nTotal: %s\nThis buys the cheapest single auction.",
      auction.qty, ns.Name(id), ns.Money(auction.price)))
    d.confirm:SetScript("OnClick", function()
      if pending and pending.kind == "item" then
        C_AuctionHouse.PlaceBid(pending.auctionID, pending.maxTotal)
        ns.AddPosition(pending.id, pending.qty, pending.maxTotal)
        local bought = pending.id
        pending = nil
        d:Hide()
        AfterPurchase(bought)
      end
    end)
    d:Show()
  else
    ns.Print("Nothing is listed for this item right now.")
  end
end
