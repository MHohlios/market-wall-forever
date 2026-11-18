-- MarketWall: the item search window. Opens from the minimap button, anywhere in the world.
-- Left: the search box, matching names and recent searches. Right: the item's chart and stats.
local _, ns = ...
local PV = ns.PriceView

local S = {}
ns.ItemSearch = S

local MATCHES, RECENT = 8, 10
local WIDTH, HEIGHT, SIDE_WIDTH, MAIN_X = 760, 460, 180, 210
local SIDE_ROWS, ROW_HEIGHT, LISTING_LINES = 20, 16, 5
local CELLS = { "lastWall", "median", "normalRange", "average", "trend", "lowHigh", "days", "vendor", "disenchant", "limits" }
local GREY, GOLD = "|cffa3acac", "|cfff5c518"

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

-- Item IDs whose known name contains the text, ignoring case: exact names first, then names
-- that start with it, then the rest, each alphabetically. At most `limit` of them.
function S.Match(names, text, limit)
  local want = string.lower(strtrim(text or ""))
  if want == "" then return {} end
  local found = {}
  for id, name in pairs(names) do
    local lower = string.lower(name)
    local at = string.find(lower, want, 1, true)
    if at then
      local rank = (lower == want and 1) or (at == 1 and 2) or 3
      found[#found + 1] = { id = id, rank = rank, name = lower }
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  local ids = {}
  for i = 1, math.min(limit, #found) do ids[i] = found[i].id end
  return ids
end

-- Put an item at the front of the recent list, once, keeping at most `cap`
function S.Remember(list, id, cap)
  for i = #list, 1, -1 do
    if list[i] == id then table.remove(list, i) end
  end
  table.insert(list, 1, id)
  while #list > cap do table.remove(list) end
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------

local win
local selectedID

local function LoadListings(id)
  local held = ns.ladders[id]
  local stale = not held or held.kind == "scan" or time() - held.t > 30
  if ns.ahOpen and stale and not ns.scanState.running and not ns.fullScanRunning then
    ns.StartWatchScan({ id })
  end
end

local function Select(id)
  selectedID = id
  S.Remember(ns.R().recent, id, RECENT)
  LoadListings(id)
  ns.RefreshSearch()
end

local function OnEnter()
  local text = win.box:GetText()
  local id, err = S.Match(ns.R().names, text, 1)[1], nil
  if not id then id, err = ns.ResolveItem(text) end
  if id then
    win.box:ClearFocus()
    Select(id)
  elseif text ~= "" then
    ns.Print(err or "Item not found.")
  end
end

-- Side list rows: a heading, then matches; a heading, then recent searches
local function SideEntries()
  local entries = {}
  local text = strtrim(win.box:GetText())
  if text ~= "" then
    entries[#entries + 1] = { heading = "Matches" }
    local matches = S.Match(ns.R().names, text, MATCHES)
    for _, id in ipairs(matches) do entries[#entries + 1] = { id = id } end
    if #matches == 0 then entries[#entries + 1] = { heading = "No item MarketWall has seen" } end
  end
  local recent = ns.R().recent
  if #recent > 0 then
    entries[#entries + 1] = { heading = "Recent" }
    for _, id in ipairs(recent) do entries[#entries + 1] = { id = id } end
  end
  return entries
end

local function RefreshSide()
  local entries = SideEntries()
  for i, row in ipairs(win.rows) do
    local entry = entries[i]
    row.id = entry and entry.id
    row:SetShown(entry ~= nil)
    if entry and entry.heading then
      row.text:SetText(GREY .. entry.heading .. "|r")
    elseif entry then
      row.text:SetText(ns.ColorName(entry.id))
    end
    row:EnableMouse(row.id ~= nil)
    if row.id and row.id == selectedID then row:LockHighlight() else row:UnlockHighlight() end
  end
end

local function ListingsText(id)
  if not ns.ahOpen then return GREY .. "Live listings load when the auction house is open.|r" end
  local held = ns.ladders[id]
  if not held then
    return GREY .. (ns.scanState.running and "Loading current auctions..." or "No auctions loaded.") .. "|r"
  end
  if #held.ladder == 0 then return GREY .. "Nothing listed right now.|r" end
  local wall = PV.LiveWall(id)
  local lines = { "Listings " .. GREY .. "(" .. ns.Ago(held.t) .. ")|r" }
  for i = 1, math.min(LISTING_LINES, #held.ladder) do
    local tier = held.ladder[i]
    lines[#lines + 1] = string.format("%s   x %d", ns.Money(tier.p), tier.q) .. (tier.p == wall and GOLD .. "  wall|r" or "")
  end
  if #held.ladder > LISTING_LINES then
    lines[#lines + 1] = GREY .. string.format("and %d more price levels", #held.ladder - LISTING_LINES) .. "|r"
  end
  return table.concat(lines, "\n")
end

local function RefreshItem()
  local id = selectedID
  win.view:SetShown(id ~= nil)
  win.item:SetShown(id ~= nil)
  win.pick:SetShown(id == nil)
  if not id then return end
  local entry = ns.R().watch[id]
  win.icon:SetTexture(ns.Icon(id))
  win.title:SetText(ns.ColorName(id))
  win.view:SetItem(id, entry and entry.buy, entry and entry.sell)
  win.watch:SetText(entry and "Stop watching" or "Add to watchlist")
  win.listings:SetText(ListingsText(id))
end

function ns.RefreshSearch()
  if not (win and win:IsShown()) then return end
  RefreshSide()
  RefreshItem()
end

local function SideRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(SIDE_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 12, -64 - (i - 1) * ROW_HEIGHT)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.text = ns.widgets.MakeText(row, "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", 4, 0)
  row.text:SetPoint("RIGHT", -4, 0)
  row.text:SetWordWrap(false)
  row:SetScript("OnClick", function(self) if self.id then Select(self.id) end end)
  return row
end

local function SavePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint()
  MarketWallDB.searchPos = { point, relativePoint, x, y }
end

local function Build()
  local w = ns.widgets
  local f = CreateFrame("Frame", "MarketWallSearchFrame", UIParent)
  f:SetSize(WIDTH, HEIGHT)
  local pos = MarketWallDB.searchPos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER") end
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition(self)
  end)
  f:Hide()
  table.insert(UISpecialFrames, "MarketWallSearchFrame")   -- Escape closes it
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.07, 0.07, 0.95)
  local edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  edge:SetPoint("TOPLEFT", -2, 2)
  edge:SetPoint("BOTTOMRIGHT", 2, -2)
  edge:SetColorTexture(0.35, 0.29, 0.16, 1)
  win = f

  local heading = w.MakeText(f, "GameFontNormal")
  heading:SetPoint("TOPLEFT", 12, -10)
  heading:SetText("MarketWall · Item prices")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  f.rows = {}
  for i = 1, SIDE_ROWS do f.rows[i] = SideRow(f, i) end
  f.box = w.MakeEdit(f, SIDE_WIDTH - 6)
  f.box:SetPoint("TOPLEFT", 18, -36)
  f.box:SetScript("OnTextChanged", RefreshSide)
  f.box:SetScript("OnEnterPressed", OnEnter)
  w.OnLinkInsert(f.box, function(link)
    local id = tonumber(string.match(link, "item:(%d+)"))
    if not id then return end
    f.box:SetText(ns.Name(id))
    f.box:ClearFocus()
    Select(id)
  end)
  local hint = w.MakeText(f, "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 14, 12)
  hint:SetWidth(SIDE_WIDTH)
  hint:SetText("Type a name, or shift-click any item link.")

  f.pick = w.MakeText(f, "GameFontDisable", "CENTER")
  f.pick:SetPoint("TOPLEFT", MAIN_X, -180)
  f.pick:SetPoint("RIGHT", -20, 0)
  f.pick:SetText("Search for an item to see its price history.")

  f.item = CreateFrame("Frame", nil, f)
  f.item:SetPoint("TOPLEFT", MAIN_X, -34)
  f.item:SetPoint("BOTTOMRIGHT", -14, 10)
  f.icon = f.item:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(22, 22)
  f.icon:SetPoint("TOPLEFT", 0, -2)
  f.title = w.MakeText(f.item, "GameFontNormalLarge")
  f.title:SetPoint("LEFT", f.icon, "RIGHT", 8, 0)
  f.title:SetWidth(300)
  f.title:SetWordWrap(false)

  local mainWidth = WIDTH - MAIN_X - 14
  f.view = PV.CreateView(f.item, { width = mainWidth, chartHeight = 140, cellWidth = mainWidth / 4, cells = CELLS, ranges = true })
  f.view:SetPoint("TOPLEFT")

  f.watch = w.MakeButton(f.item, "Add to watchlist", 130)
  f.watch:SetPoint("TOPLEFT", f.view, "BOTTOMLEFT", 0, -6)
  f.watch:SetScript("OnClick", function()
    if ns.IsWatched(selectedID) then ns.Unwatch(selectedID) else ns.Watch(selectedID) end   -- both redraw
  end)
  f.listings = w.MakeText(f.item, "GameFontHighlightSmall")
  f.listings:SetPoint("TOPLEFT", f.watch, "TOPRIGHT", 14, -4)
  f.listings:SetPoint("RIGHT")
  f.listings:SetSpacing(2)

  -- names and icons arrive late; listings change when the auction house opens or closes
  f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  f:RegisterEvent("AUCTION_HOUSE_SHOW")
  f:RegisterEvent("AUCTION_HOUSE_CLOSED")
  f:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" and selectedID then
      C_Timer.After(0, function() LoadListings(selectedID) end)   -- after Core marks the house open
    end
    f.dirty = true
  end)
  local elapsed = 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 0.5 then
      elapsed = 0
      if f.dirty then
        f.dirty = false
        ns.RefreshSearch()
      end
    end
  end)
  f:SetScript("OnShow", ns.RefreshSearch)
end

-- Open or close the window; open always opens
function ns.ToggleSearch(open)
  if not win then Build() end
  if win:IsShown() and not open then
    win:Hide()
  else
    win:Show()
    if selectedID then LoadListings(selectedID) end
  end
end
