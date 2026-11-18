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

function ns.CancelPurchase()
  if pending and pending.kind == "commodity" and C_AuctionHouse.CancelCommoditiesPurchase then
    C_AuctionHouse.CancelCommoditiesPurchase()
  end
  pending = nil
  Unregister()
  if dialog then dialog:Hide() end
end

local function AfterPurchase(id)
  -- refresh the listings for this item so the screen shows what is left
  C_Timer.After(1, function()
    if ns.ahOpen and not ns.scanState.running then ns.StartWatchScan({ id }) end
  end)
end

buyer:SetScript("OnEvent", function(_, event, _unitPrice, totalPrice)
  if not pending then return end
  if event == "COMMODITY_PRICE_UPDATED" then
    if not totalPrice or totalPrice > pending.maxTotal then
      ns.Print("The price moved before the purchase. Nothing was bought. Rescanning.")
      local id = pending.id
      ns.CancelPurchase()
      AfterPurchase(id)
      return
    end
    pending.total = totalPrice
    local d = GetDialog()
    d.text:SetText(string.format("Buy %d x %s\nTotal: %s  (about %s each)\nResale break-even after the cut: %s each",
      pending.qty, ns.Name(pending.id), ns.Money(totalPrice), ns.Money(totalPrice / pending.qty),
      ns.Money(math.ceil((totalPrice / pending.qty) / (1 - ns.Cfg("ahCut"))))))
    d.confirm:SetScript("OnClick", function()
      if pending then
        C_AuctionHouse.ConfirmCommoditiesPurchase(pending.id, pending.qty)
        d:Hide()
      end
    end)
    d:Show()
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    ns.Print("Those units are no longer available. Rescanning.")
    local id = pending.id
    ns.CancelPurchase()
    AfterPurchase(id)
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local id, qty, total = pending.id, pending.qty, pending.total or pending.maxTotal
    ns.AddPosition(id, qty, total)
    ns.Print(string.format("Bought %d x %s for %s.", qty, ns.Name(id), ns.Money(total)))
    pending = nil
    Unregister()
    if dialog then dialog:Hide() end
    AfterPurchase(id)
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    ns.Print("The purchase failed. Nothing was bought.")
    local id = pending.id
    pending = nil
    Unregister()
    if dialog then dialog:Hide() end
    AfterPurchase(id)
  end
end)

-- Buy every unit priced under limit. Needs listings scanned within the last two minutes.
function ns.BuyUnder(id, limit)
  if not ns.ahOpen then ns.Print("Open the auction house first.") return end
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
    pending = { id = id, qty = units, maxTotal = cost, kind = "commodity" }
    for i = 1, #PURCHASE_EVENTS do buyer:RegisterEvent(PURCHASE_EVENTS[i]) end
    C_AuctionHouse.StartCommoditiesPurchase(id, units)
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
