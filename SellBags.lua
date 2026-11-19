-- MarketWall: the Sell page's item slots and its bag grid, grouped by best outlet.
local _, ns = ...
local P, Outlet = ns.SellPricing, ns.Outlet

local GREY, GOLD = "|cffa3acac", "|cfff5c518"
local ICON, GAP, HEADER, SCROLL_BAR = 34, 4, 20, 26

local GROUP_TITLES = {
  [Outlet.AUCTION] = "Sell on the auction house",
  [Outlet.DISENCHANT] = "Disenchant",
  [Outlet.VENDOR] = "Vendor",
  [Outlet.NO_DATA] = "No reliable price",
}

local SellBags = {}
ns.SellBags = SellBags

-- The item tooltip, with MarketWall's lines, then one unit through each outlet
local function ShowItemTip(self)
  if not (self.item and GameTooltip and GameTooltip.SetItemByID) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(self.item.id)
  if self.item.values then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(P.OutletLine(self.item.values), 1, 1, 1, true)
  end
  GameTooltip:Show()
end

-- An item icon with its stack count and a border in its quality colour.
-- slot:SetItem(item, selected) with item = { id, count, values = Outlet.Values }.
function SellBags.ItemSlot(parent, size)
  local slot = CreateFrame("Button", nil, parent)
  slot:SetSize(size, size)
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetAllPoints()
  slot.border = slot:CreateTexture(nil, "OVERLAY")
  slot.border:SetTexture("Interface\\Common\\WhiteIconFrame")
  slot.border:SetAllPoints()
  slot.selected = slot:CreateTexture(nil, "OVERLAY", nil, 1)
  slot.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  slot.selected:SetBlendMode("ADD")
  slot.selected:SetAllPoints()
  slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  slot.count:SetPoint("BOTTOMRIGHT", -2, 2)
  local hl = slot:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")
  hl:SetAllPoints()
  slot:SetScript("OnEnter", ShowItemTip)
  slot:SetScript("OnLeave", ns.widgets.HideTip)

  function slot:SetItem(item, selected)
    self.item = item
    self.icon:SetTexture(ns.Icon(item.id))
    self.count:SetText(item.count > 1 and tostring(item.count) or "")
    local quality = C_Item.GetItemInfo and select(3, C_Item.GetItemInfo(item.id))
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    self.border:SetShown(color ~= nil and quality > 1)
    if color then self.border:SetVertexColor(color.r, color.g, color.b) end
    self.selected:SetShown(selected == true)
  end
  return slot
end

-- Bags as icons under one header per outlet group (SellPricing.Groups), scrolled when they do
-- not fit. Fills its parent. onPick(id) runs when an icon is clicked.
function SellBags.Grid(parent, width, onPick)
  local gridWidth = width - SCROLL_BAR - 4
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(gridWidth, 1)
  scroll:SetScrollChild(content)
  local slots, headers = {}, {}
  local columns = math.floor((gridWidth + GAP) / (ICON + GAP))
  scroll.empty = ns.widgets.MakeText(parent, "GameFontDisable", "CENTER")
  scroll.empty:SetPoint("TOP", 0, -60)
  scroll.empty:SetWidth(width - 20)
  scroll.empty:SetText("Nothing in your bags can be sold here.")

  local function Header(i)
    local header = headers[i]
    if header then return header end
    header = CreateFrame("Frame", nil, content)
    header:SetSize(gridWidth, HEADER - 4)
    local bg = header:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.06)
    header.text = ns.widgets.MakeText(header, "GameFontNormalSmall")
    header.text:SetPoint("LEFT", 4, 0)
    headers[i] = header
    return header
  end

  local function Slot(i)
    local slot = slots[i]
    if slot then return slot end
    slot = SellBags.ItemSlot(content, ICON)
    slot:SetScript("OnClick", function(self) onPick(self.item.id) end)
    slots[i] = slot
    return slot
  end

  function scroll:SetGroups(groups, selectedID)
    local y, used = 0, 0
    for g, group in ipairs(groups) do
      local header = Header(g)
      header:SetPoint("TOPLEFT", 0, -y)
      local worth = group.value > 0 and ("  ·  " .. ns.Money(group.value)) or ""
      header.text:SetText(GOLD .. GROUP_TITLES[group.outlet] .. "|r" .. GREY .. "  ·  " .. #group.items .. "|r" .. worth)
      header:Show()
      y = y + HEADER
      for i, item in ipairs(group.items) do
        used = used + 1
        local slot = Slot(used)
        local col, row = (i - 1) % columns, math.floor((i - 1) / columns)
        slot:SetPoint("TOPLEFT", col * (ICON + GAP), -(y + row * (ICON + GAP)))
        slot:SetItem(item, item.id == selectedID)
        slot:Show()
      end
      y = y + math.ceil(#group.items / columns) * (ICON + GAP) + 4
    end
    for i = #groups + 1, #headers do headers[i]:Hide() end
    for i = used + 1, #slots do slots[i]:Hide() end
    content:SetHeight(math.max(1, y))
    self.empty:SetShown(#groups == 0)
  end
  return scroll
end
