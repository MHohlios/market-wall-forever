-- MarketWall: the Market tab
local _, ns = ...
local W = ns.Wall

local ui = { view = "watch", limits = {}, sort = {} }
ns.ui = ui

local ROWS, ROW_H = 16, 20
local BLUE, ORANGE, GREY, GOLD = "|cff7cc0ff", "|cffffb057", "|cffa3acac", "|cfff5c518"

local function MakeButton(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 110, 22)
  b:SetText(text)
  return b
end

local function MakeText(parent, font, justify)
  local t = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  t:SetJustifyH(justify or "LEFT")
  return t
end

local function MakeEdit(parent, width)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

local function Pct(x)
  return string.format("%d%%", ns.Round(x * 100))
end

local function ShowTip(owner, title, body, extra)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  GameTooltip:SetText(title, 1, 0.82, 0)
  if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
  if extra then GameTooltip:AddLine(extra, 0.6, 0.6, 0.6, true) end
  GameTooltip:Show()
end

local function HideTip()
  if GameTooltip then GameTooltip:Hide() end
end

-- Shift-clicking an item while the box has focus hands the item's link to onLink
local function OnLinkInsert(box, onLink)
  local function Insert(link)
    if box:IsVisible() and box:HasFocus() and type(link) == "string" then onLink(link) end
  end
  if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", Insert) end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", Insert) end
end

-------------------------------------------------------------------------------
-- Pop-up menu and text prompt
-------------------------------------------------------------------------------
local MENU_ROW_H, MENU_LINGER = 18, 1.5
local menu

local function MenuButton(i)
  local button = CreateFrame("Button", nil, menu)
  button:SetHeight(MENU_ROW_H)
  button:SetPoint("TOPLEFT", 6, -6 - (i - 1) * MENU_ROW_H)
  button:SetPoint("RIGHT", -6, 0)
  button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  button.text = MakeText(button, "GameFontHighlightSmall")
  button.text:SetPoint("LEFT", 4, 0)
  button:SetScript("OnClick", function(self)
    menu:Hide()
    self.item.onClick()
  end)
  return button
end

-- A menu at the cursor. items: { { text =, onClick = }, ... }; an item with no onClick is a
-- heading, or greyed out when disabled is set. It closes on a choice, on Escape, or once the
-- mouse has been off it for a moment.
local function ShowMenu(items)
  if not menu then
    menu = CreateFrame("Frame", "MarketWallMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    local edge = menu:CreateTexture(nil, "BACKGROUND", nil, 0)
    edge:SetAllPoints()
    edge:SetColorTexture(0.35, 0.29, 0.16, 1)
    local bg = menu:CreateTexture(nil, "BACKGROUND", nil, 1)
    bg:SetPoint("TOPLEFT", 1, -1)
    bg:SetPoint("BOTTOMRIGHT", -1, 1)
    bg:SetColorTexture(0.05, 0.07, 0.07, 0.97)
    menu.buttons = {}
    menu:SetScript("OnUpdate", function(self, dt)
      self.away = self:IsMouseOver() and 0 or self.away + dt
      if self.away > MENU_LINGER then self:Hide() end
    end)
    table.insert(UISpecialFrames, "MarketWallMenu")
  end
  local width = 80
  for i, item in ipairs(items) do
    local button = menu.buttons[i] or MenuButton(i)
    menu.buttons[i] = button
    button.item = item
    local color = (item.disabled and GREY) or (not item.onClick and GOLD) or ""
    button.text:SetText(color .. item.text .. (color ~= "" and "|r" or ""))
    button:SetEnabled(item.onClick ~= nil and not item.disabled)
    button:Show()
    width = math.max(width, button.text:GetStringWidth())
  end
  for i = #items + 1, #menu.buttons do menu.buttons[i]:Hide() end
  menu:SetSize(width + 22, #items * MENU_ROW_H + 12)
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 8, y / scale + 8)
  menu.away = 0
  menu:Show()
end

local function PromptBox(popup)
  return popup.editBox or popup.EditBox or popup:GetEditBox()
end

local function Answer(popup, data)
  local text = strtrim(PromptBox(popup):GetText() or "")
  if text ~= "" then data.onAccept(text) end
end

StaticPopupDialogs["MARKETWALL_PROMPT"] = {
  text = "%s",
  button1 = OKAY,
  button2 = CANCEL,
  hasEditBox = true,
  OnShow = function(self, data)
    local box = PromptBox(self)
    box:SetText(data and data.initial or "")
    box:HighlightText()
    box:SetFocus()
  end,
  OnAccept = Answer,
  EditBoxOnEnterPressed = function(box, data)
    local popup = box:GetParent()
    Answer(popup, data)
    popup:Hide()
  end,
  EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Asks for a line of text, starting from initial; onAccept(text) gets it trimmed, never empty
local function Prompt(question, initial, onAccept)
  StaticPopup_Show("MARKETWALL_PROMPT", question, nil, { initial = initial, onAccept = onAccept })
end

-------------------------------------------------------------------------------
-- Generic list: sortable headers with hover help, icon per row
-------------------------------------------------------------------------------
local function CreateList(parent, rows)
  local size = rows or ROWS
  local list = CreateFrame("Frame", nil, parent)
  list.headers, list.rows, list.data, list.offset = {}, {}, {}, 0
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta)
    local maxOffset = math.max(0, #self.data - size)
    self.offset = math.max(0, math.min(maxOffset, self.offset - delta * 3))
    self:Refresh()
  end)
  for i = 1, size do
    local row = CreateFrame("Button", nil, list)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -22 - (i - 1) * ROW_H)
    row:SetPoint("RIGHT")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bar = row:CreateTexture(nil, "BORDER")   -- an entry's share, as a bar from the left
    row.bar:SetPoint("TOPLEFT")
    row.bar:SetPoint("BOTTOMLEFT")
    row.bar:SetColorTexture(0.96, 0.77, 0.09, 0.18)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 8, 0)
    row.cells = {}
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      local handler = button == "RightButton" and list.onRightClick or list.onClick
      if self.entry and handler then handler(self.entry) end
    end)
    row:SetScript("OnEnter", function(self)
      if self.entry and self.entry.id and GameTooltip and GameTooltip.SetItemByID then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetItemByID(self.entry.id)
        GameTooltip:Show()
      elseif self.entry and self.entry.tip then
        ShowTip(self, self.entry.tip)
      end
    end)
    row:SetScript("OnLeave", HideTip)
    list.rows[i] = row
  end
  list.count = MakeText(list, "GameFontDisableSmall", "RIGHT")
  list.count:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -8, -2)
  list.empty = MakeText(list, "GameFontDisable", "CENTER")
  list.empty:SetPoint("TOP", 0, -90)
  list.empty:SetWidth(560)
  list.empty:SetSpacing(4)

  local function Header(c)
    local header = list.headers[c]
    if header then return header end
    header = CreateFrame("Button", nil, list)
    header:SetHeight(18)
    header.label = MakeText(header, "GameFontNormalSmall")
    header.label:SetAllPoints()
    header.index = c
    header:SetScript("OnClick", function(self)
      if list.onHeader then list.onHeader(self.index) end
    end)
    header:SetScript("OnEnter", function(self)
      if self.tip then ShowTip(self, self.title, self.tip, "Click to sort. Click again to reverse.") end
    end)
    header:SetScript("OnLeave", HideTip)
    list.headers[c] = header
    return header
  end

  -- columns: { {title, width, justify, tip}, ... }   sortCol/sortDesc mark the active sort
  function list:SetColumns(columns, sortCol, sortDesc)
    self.columns = columns
    local x = 8
    for c = 1, math.max(#columns, #self.headers) do
      local col = columns[c]
      local header = Header(c)
      local cellX = (c == 1) and (x + 22) or x
      for i = 1, size do
        local row = self.rows[i]
        if not row.cells[c] then row.cells[c] = MakeText(row, "GameFontHighlightSmall") end
        local cell = row.cells[c]
        if col then
          cell:ClearAllPoints()
          cell:SetPoint("LEFT", row, "LEFT", cellX, 0)
          cell:SetWidth(col[2] - 8 - (cellX - x))
          cell:SetJustifyH(col[3] or "LEFT")
          cell:SetWordWrap(false)
          cell:Show()
        else
          cell:Hide()
        end
      end
      if col then
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", self, "TOPLEFT", x, -2)
        header:SetWidth(col[2] - 8)
        header.label:SetJustifyH(col[3] or "LEFT")
        local arrow = ""
        if sortCol == c then arrow = sortDesc and " v" or " ^" end
        header.label:SetText(col[1] .. arrow)
        header.title, header.tip = col[1], col[4]
        header:Show()
        x = x + col[2]
      else
        header:Hide()
      end
    end
  end

  function list:SetData(data, emptyText)
    self.data = data
    self.emptyText = emptyText
    local maxOffset = math.max(0, #data - size)
    if self.offset > maxOffset then self.offset = maxOffset end
    self:Refresh()
  end

  function list:Refresh()
    local data = self.data
    for i = 1, size do
      local row = self.rows[i]
      local entry = data[i + self.offset]
      row.entry = entry
      if entry then
        for c = 1, #self.columns do row.cells[c]:SetText(entry.cells[c] or "") end
        row.icon:SetTexture(entry.id and ns.Icon(entry.id) or nil)
        row:SetAlpha(entry.dim and 0.45 or 1)
        row.bar:SetShown(entry.bar ~= nil)
        if entry.bar then row.bar:SetWidth(math.max(1, entry.bar * self:GetWidth())) end
        if entry.highlight then
          row.bg:SetColorTexture(0.18, 0.32, 0.45, 0.45)
        elseif entry.tint then
          row.bg:SetColorTexture(entry.tint[1], entry.tint[2], entry.tint[3], entry.tint[4])
        elseif (i + self.offset) % 2 == 0 then
          row.bg:SetColorTexture(1, 1, 1, 0.03)
        else
          row.bg:SetColorTexture(0, 0, 0, 0)
        end
        row:Show()
      else
        row:Hide()
      end
    end
    if #data == 0 then
      self.empty:SetText(self.emptyText or "")
      self.empty:Show()
      self.count:SetText("")
    else
      self.empty:Hide()
      local last = math.min(#data, self.offset + size)
      self.count:SetText(string.format("%d to %d of %d (mouse wheel scrolls)", self.offset + 1, last, #data))
    end
  end
  return list
end

-------------------------------------------------------------------------------
-- Columns and view data. Each entry carries raw values in entry.sort for header sorting.
-------------------------------------------------------------------------------
local WALL_TIP = "The item's real price: the lowest price level that has meaningful supply behind it. A few stray cheap units do not move it."
local WATCH_COLUMNS = {
  { "Item", 170, nil, "Items you are tracking. Click a row for its chart and live listings." },
  { "Wall price", 80, "RIGHT", WALL_TIP },
  { "Lowest", 80, "RIGHT", "The single cheapest listing right now, even if it is only one unit." },
  { "Normal range", 140, "RIGHT", "Where the wall price usually sits: the middle half of its daily history. Shows 'building' until there are 3 days of data." },
  { "Buy below", 80, "RIGHT", "Your buy threshold. Units listed under this price count as deals. Set it on the item's page." },
  { "Sell at", 80, "RIGHT", "Your target resale price. The row says Sell when the wall price reaches it." },
  { "Units under", 75, "RIGHT", "How many units are listed under your buy price as of the last scan." },
  { "Status", 80, "RIGHT", "Buy: units are under your buy price. Sell: the wall reached your sell price. Old: the price has not been scanned recently." },
}
local SNIPE_COLUMNS = {
  { "Item", 200, nil, "Items with listings priced under their wall. Click a row to load live listings before buying." },
  { "Wall price", 90, "RIGHT", WALL_TIP },
  { "Cheapest", 90, "RIGHT", "The lowest listing found in the scan." },
  { "Units", 70, "RIGHT", "Units listed under the wall that would still profit after the auction house cut." },
  { "Cost", 100, "RIGHT", "What it costs to buy all of those units." },
  { "Profit after cut", 120, "RIGHT", "Expected profit if you resell at the normal price, after the auction house cut. Uses the lower of today's wall and the historical median." },
  { "Under normal", 90, "RIGHT", "How far the average cost of those units is below the normal price." },
}
local DIP_COLUMNS = {
  { "Item", 200, nil, "Items whose wall price dropped suddenly compared with their own history." },
  { "Wall now", 90, "RIGHT", WALL_TIP },
  { "Normal", 90, "RIGHT", "The median wall price over the history window." },
  { "Under by", 80, "RIGHT", "How far today's wall is below the normal price." },
  { "Supply", 90, "RIGHT", "Total units listed. More supply means the dip is real, not one seller." },
  { "Profit each", 110, "RIGHT", "Expected profit per unit if the price returns to normal, after the auction house cut." },
  { "History", 90, "RIGHT", "Days of data behind the normal price." },
}
local DISENCHANT_COLUMNS = {
  { "Item", 220, nil, "Weapons and armor, uncommon or better, listed under what disenchanting them is worth. Click a row to load live listings before buying." },
  { "Price", 90, "RIGHT", "The cheapest buyout found in the scan." },
  { "DE value after cut", 130, "RIGHT", "Expected value of the materials from one disenchant, at their wall prices, after the auction house cut on reselling them." },
  { "Profit", 100, "RIGHT", "Disenchant value after cut minus the price." },
  { "Profit %", 80, "RIGHT", "Profit as a share of the price." },
  { "Odds from", 150, nil, "Where the material odds come from: your own disenchants (recorded by MarketWall), a Forever estimate, or the classic disenchanting table." },
}
local COLUMNS = { watch = WATCH_COLUMNS, snipes = SNIPE_COLUMNS, dips = DIP_COLUMNS, disenchant = DISENCHANT_COLUMNS }

local STATUS_TEXT = {
  buy = BLUE .. "Buy|r", sell = ORANGE .. "Sell|r", normal = "Normal", nodata = GREY .. "Not scanned|r",
}
local STATUS_ORDER = { buy = 1, sell = 2, normal = 3, old = 4, nodata = 5 }

local function WatchData()
  local r = ns.R()
  local data = {}
  local staleAfter = ns.Cfg("staleMinutes") * 60
  for id, entry in pairs(r.watch) do
    local cur = entry.cur or {}
    local stats = ns.StatsFor(id)
    local status = ns.WatchStatus(id)
    local statusText = STATUS_TEXT[status]
    local stale = status ~= "nodata" and cur.t and (time() - cur.t > staleAfter)
    if stale then
      status = "old"
      statusText = GREY .. "Old, " .. ns.Ago(cur.t) .. "|r"
    end
    local range = GREY .. "building|r"
    if stats.n >= 3 then range = ns.Money(stats.p25) .. " to " .. ns.Money(stats.p75) end
    local name = ns.Name(id)
    data[#data + 1] = {
      id = id, status = status, name = name, highlight = (status == "buy"), dim = stale,
      cells = {
        ns.ColorName(id), ns.Money(cur.w), ns.Money(cur.m), range,
        entry.buy and ns.Money(entry.buy) or "-", entry.sell and ns.Money(entry.sell) or "-",
        cur.under and tostring(cur.under) or "-", statusText,
      },
      sort = { name, cur.w, cur.m, stats.n >= 3 and stats.p25 or nil, entry.buy, entry.sell, cur.under, -STATUS_ORDER[status] },
    }
  end
  table.sort(data, function(a, b)
    if STATUS_ORDER[a.status] ~= STATUS_ORDER[b.status] then return STATUS_ORDER[a.status] < STATUS_ORDER[b.status] end
    return a.name < b.name
  end)
  return data
end

local function SnipeData()
  local data = {}
  for i = 1, #ns.snipes do
    local s = ns.snipes[i]
    data[i] = { id = s.id,
      cells = { ns.ColorName(s.id), ns.Money(s.wall), ns.Money(s.min), tostring(s.units), ns.Money(s.cost), ns.Money(s.profit), Pct(s.discount) },
      sort = { ns.Name(s.id), s.wall, s.min, s.units, s.cost, s.profit, s.discount },
    }
  end
  return data
end

local function DipData()
  local data = {}
  for i = 1, #ns.dips do
    local d = ns.dips[i]
    data[i] = { id = d.id,
      cells = { ns.ColorName(d.id), ns.Money(d.wall), ns.Money(d.median), Pct(d.under), tostring(d.total), ns.Money(d.profit), d.days .. " days" },
      sort = { ns.Name(d.id), d.wall, d.median, d.under, d.total, d.profit, d.days },
    }
  end
  return data
end

-- Deals this character can disenchant, or all of them when the box is ticked or the skill is
-- unknown. Also returns the skill and how many deals it hides.
local function DisenchantData()
  local skill = ns.EnchantingSkill()
  local showAll = ns.Cfg("disenchantShowAll") or skill == nil
  local data, hidden = {}, 0
  for _, d in ipairs(ns.disenchants) do
    if showAll or d.skill <= skill then
      data[#data + 1] = { id = d.id,
        cells = { ns.ColorName(d.id), ns.Money(d.price), ns.Money(d.value), ns.Money(d.profit), Pct(d.pct), d.odds },
        sort = { ns.Name(d.id), d.price, d.value, d.profit, d.pct, d.odds },
      }
    else
      hidden = hidden + 1
    end
  end
  return data, skill, hidden
end

local function ApplySort(view, data)
  local sort = ui.sort[view]
  if not sort then return end
  local col, desc = sort.col, sort.desc
  table.sort(data, function(a, b)
    local x, y = a.sort[col], b.sort[col]
    if x == y then return a.sort[1] < b.sort[1] end
    if x == nil then return false end   -- rows without a value always go last
    if y == nil then return true end
    if desc then return x > y end
    return x < y
  end)
end

local function HeaderClicked(col)
  local view = ui.view
  local sort = ui.sort[view]
  if sort and sort.col == col then
    sort.desc = not sort.desc
  else
    -- names start A to Z, numbers start biggest first
    ui.sort[view] = { col = col, desc = (col ~= 1) }
  end
  ui.list.offset = 0
  ns.RefreshUI()
end

-------------------------------------------------------------------------------
-- Chart
-------------------------------------------------------------------------------
local function CreateChart(parent)
  local chart = CreateFrame("Frame", nil, parent)
  chart:SetSize(470, 190)
  local bg = chart:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  chart.band = chart:CreateTexture(nil, "BORDER")
  chart.band:SetColorTexture(0.96, 0.77, 0.09, 0.13)
  chart.lines, chart.bars, chart.used, chart.usedBars = {}, {}, 0, 0
  chart.yLabels = { MakeText(chart, "GameFontDisableSmall", "RIGHT"), MakeText(chart, "GameFontDisableSmall", "RIGHT"), MakeText(chart, "GameFontDisableSmall", "RIGHT") }
  chart.yLabels[1]:SetPoint("TOPRIGHT", chart, "TOPLEFT", -4, 0)
  chart.yLabels[2]:SetPoint("RIGHT", chart, "LEFT", -4, 0)
  chart.yLabels[3]:SetPoint("BOTTOMRIGHT", chart, "BOTTOMLEFT", -4, 0)
  chart.xFirst = MakeText(chart, "GameFontDisableSmall", "LEFT")
  chart.xFirst:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -3)
  chart.xLast = MakeText(chart, "GameFontDisableSmall", "RIGHT")
  chart.xLast:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -3)
  chart.note = MakeText(chart, "GameFontDisable", "CENTER")
  chart.note:SetPoint("CENTER")
  chart.legend = MakeText(chart, "GameFontDisableSmall", "LEFT")
  chart.legend:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", -50, -17)
  chart.legend:SetWidth(540)

  local function Line(x1, y1, x2, y2, r, g, b, a, thickness)
    chart.used = chart.used + 1
    local line = chart.lines[chart.used]
    if not line then
      line = chart:CreateLine(nil, "ARTWORK")
      chart.lines[chart.used] = line
    end
    line:SetColorTexture(r, g, b, a)
    line:SetThickness(thickness)
    line:SetStartPoint("BOTTOMLEFT", chart, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", chart, x2, y2)
    line:Show()
  end

  function chart:Draw(series, buy, sell, stats)
    for i = 1, #self.lines do self.lines[i]:Hide() end
    for i = 1, #self.bars do self.bars[i]:Hide() end
    self.used, self.usedBars = 0, 0
    self.band:Hide()
    local width, height = self:GetWidth(), self:GetHeight()
    if #series == 0 then
      self.note:SetText("No history yet. Scan this item to start recording.")
      self.note:Show()
      for i = 1, 3 do self.yLabels[i]:SetText("") end
      self.xFirst:SetText("") self.xLast:SetText("") self.legend:SetText("")
      return
    end
    self.note:Hide()

    local lo, hi, maxQ = math.huge, -math.huge, 0
    local function span(v) if v then if v < lo then lo = v end if v > hi then hi = v end end end
    for i = 1, #series do
      span(series[i].w)
      if series[i].q and series[i].q > maxQ then maxQ = series[i].q end
    end
    span(buy) span(sell)
    if stats and stats.n >= 3 then span(stats.p25) span(stats.p75) end
    local pad = math.max((hi - lo) * 0.12, hi * 0.03, 1)
    lo, hi = math.max(0, lo - pad), hi + pad
    local function Y(v) return math.max(0, math.min(height, (v - lo) / (hi - lo) * height)) end

    local t0, t1 = math.huge, -math.huge
    for i = 1, #series do if series[i].t < t0 then t0 = series[i].t end if series[i].t > t1 then t1 = series[i].t end end
    local function X(t) if t1 <= t0 then return width / 2 end return (t - t0) / (t1 - t0) * width end

    -- supply bars along the bottom
    if maxQ > 0 then
      local barWidth = math.max(2, math.min(14, width / #series * 0.6))
      for i = 1, #series do
        local q = series[i].q
        if q and q > 0 then
          self.usedBars = self.usedBars + 1
          local bar = self.bars[self.usedBars]
          if not bar then
            bar = self:CreateTexture(nil, "BORDER")
            bar:SetColorTexture(0.6, 0.65, 0.65, 0.22)
            self.bars[self.usedBars] = bar
          end
          bar:ClearAllPoints()
          bar:SetPoint("BOTTOM", self, "BOTTOMLEFT", math.max(barWidth / 2, math.min(width - barWidth / 2, X(series[i].t))), 0)
          bar:SetSize(barWidth, math.max(1, q / maxQ * height * 0.28))
          bar:Show()
        end
      end
    end

    if stats and stats.n >= 3 then
      self.band:ClearAllPoints()
      self.band:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, Y(stats.p25))
      self.band:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, Y(stats.p75))
      self.band:Show()
      Line(0, Y(stats.median), width, Y(stats.median), 0.96, 0.77, 0.09, 0.6, 1)
    end
    if buy then Line(0, Y(buy), width, Y(buy), 0.49, 0.75, 1, 0.9, 1) end
    if sell then Line(0, Y(sell), width, Y(sell), 1, 0.69, 0.34, 0.9, 1) end

    if #series == 1 then
      local x = math.max(6, math.min(width - 6, X(series[1].t)))
      Line(x - 6, Y(series[1].w), x + 6, Y(series[1].w), 1, 1, 1, 1, 3)
    else
      for i = 2, #series do
        Line(X(series[i - 1].t), Y(series[i - 1].w), X(series[i].t), Y(series[i].w), 1, 1, 1, 1, 2)
      end
    end

    self.yLabels[1]:SetText(ns.Money(hi))
    self.yLabels[2]:SetText(ns.Money((hi + lo) / 2))
    self.yLabels[3]:SetText(ns.Money(lo))
    self.xFirst:SetText(date("%b %d %H:%M", t0))
    self.xLast:SetText(date("%b %d %H:%M", t1))
    local legend = "White: wall price   " .. BLUE .. "Blue: buy below|r   " .. ORANGE .. "Orange: sell at|r   " .. GOLD .. "Gold band: normal range|r   Bars: supply"
    self.legend:SetText(legend)
  end
  return chart
end
ns.widgets = {
  MakeButton = MakeButton, MakeText = MakeText, MakeEdit = MakeEdit, ShowTip = ShowTip, HideTip = HideTip,
  OnLinkInsert = OnLinkInsert, CreateList = CreateList, CreateChart = CreateChart, ShowMenu = ShowMenu, Prompt = Prompt, ListHeight = function(rows) return 22 + rows * ROW_H end,
}

-------------------------------------------------------------------------------
-- Item page
-------------------------------------------------------------------------------
local function Limits(id)
  local entry = ns.R().watch[id]
  if entry then return entry end
  local l = ui.limits[id]
  if not l then
    l = {}
    local held = ns.ladders[id]
    local wall
    if held then wall = W.Compute(held.ladder, held.total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits")) end
    l.buy, l.sell = W.Suggest(wall, ns.StatsFor(id), ns.Cfg("ahCut"))
    if l.buy then ui.limits[id] = l end
  end
  return l
end

local function RefreshItem()
  local page, id = ui.item, ui.itemID
  if not id then return end
  local held = ns.ladders[id]
  local limits = Limits(id)
  local stats = ns.StatsFor(id)
  local cut = ns.Cfg("ahCut")
  local watched = ns.IsWatched(id)

  page.icon:SetTexture(ns.Icon(id))
  page.title:SetText(ns.ColorName(id))
  page.watch:SetText(watched and "Stop watching" or "Add to watchlist")
  if not page.buy:HasFocus() then page.buy:SetText(limits.buy and ns.Money(limits.buy) or "") end
  if not page.sell:HasFocus() then page.sell:SetText(limits.sell and ns.Money(limits.sell) or "") end

  local wall, minPrice, total
  if held and held.total > 0 then
    wall, minPrice = W.Compute(held.ladder, held.total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits"))
    total = held.total
  end

  -- listings
  for i = 1, #page.ladder do
    local line = page.ladder[i]
    local tier = held and held.ladder[i]
    if tier then
      local text = string.format("%s   x %d", ns.Money(tier.p), tier.q)
      if limits.buy and tier.p < limits.buy then
        text = text .. BLUE .. "  under buy price|r"
      elseif wall and tier.p == wall then
        text = text .. GOLD .. "  wall|r"
      end
      line:SetText(text)
    elseif i == 1 then
      line:SetText(GREY .. (held and "Nothing listed" or "Not scanned yet") .. "|r")
    else
      line:SetText("")
    end
  end
  if held and #held.ladder > #page.ladder then
    page.more:SetText(GREY .. string.format("and %d more price levels", #held.ladder - #page.ladder) .. "|r")
  else
    page.more:SetText("")
  end

  -- facts
  local lines = {}
  if wall then
    local age = ""
    if held.t and time() - held.t > 120 then age = GREY .. "   (" .. ns.Ago(held.t) .. ")|r" end
    lines[#lines + 1] = string.format("Wall price %s    Lowest listing %s    Supply %d units", ns.Money(wall), ns.Money(minPrice), total) .. age
  else
    lines[#lines + 1] = GREY .. "No current listings loaded. Press Refresh with the auction house open.|r"
  end
  if stats.n >= 3 then
    lines[#lines + 1] = string.format("Normal: median %s, range %s to %s, from %d days", ns.Money(stats.median), ns.Money(stats.p25), ns.Money(stats.p75), stats.n)
  else
    lines[#lines + 1] = GREY .. string.format("Normal range needs 3 days of scans (%d so far).", stats.n) .. "|r"
  end
  if held and limits.buy and held.kind ~= "scan" then
    local units, cost = W.UnitsUnder(held.ladder, limits.buy)
    if units > 0 then
      local each = cost / units
      local text = string.format("%sUnder your buy price: %d units for %s|r    Break-even resale %s", BLUE, units, ns.Money(cost), ns.Money(math.ceil(each / (1 - cut))))
      if limits.sell then
        text = text .. string.format("    Profit at sell price %s", ns.Money(units * limits.sell * (1 - cut) - cost))
      end
      lines[#lines + 1] = text
    else
      lines[#lines + 1] = "Nothing is listed under your buy price."
    end
  elseif held and held.kind == "scan" then
    lines[#lines + 1] = GREY .. "Listings are from the last full scan. Press Refresh before buying.|r"
  end
  local pos = ns.R().pos[id]
  if pos and pos.qty > 0 then
    local each = pos.cost / pos.qty
    lines[#lines + 1] = string.format("Bought through this addon: %d units at about %s each. Break-even resale %s.", pos.qty, ns.Money(each), ns.Money(math.ceil(each / (1 - cut))))
  end
  if limits.buy and limits.sell and limits.sell * (1 - cut) <= limits.buy then
    lines[#lines + 1] = ORANGE .. "Warning: selling at that price loses money after the " .. Pct(cut) .. " cut.|r"
  end
  -- day/night and day-of-week pattern
  local cycle = ns.Cycle(id)
  local function Cell(label, g)
    if not g or g.n < 3 then return GREY .. label .. " n/a|r" end
    local diff = ns.Round((g.r - 1) * 100)
    local color = (diff <= -2 and BLUE) or (diff >= 2 and ORANGE) or "|cffffffff"
    return string.format("%s%s %+d%%|r", color, label, diff)
  end
  local parts = {}
  for i = 1, 4 do parts[i] = Cell(ns.PART_NAMES[i], cycle.parts[i]) end
  lines[#lines + 1] = "By time of day:  " .. table.concat(parts, "   ")
  lines[#lines + 1] = "By day:  " .. Cell("Weekdays", cycle.weekday) .. "   " .. Cell("Weekends", cycle.weekend)
    .. GREY .. "    (needs 3 scans per slot; blue is cheaper than normal)|r"
  page.facts:SetText(table.concat(lines, "\n"))

  page.chart:Draw(ns.Series(id), limits.buy, limits.sell, stats)
end

local function SaveLimit(field, box)
  local id = ui.itemID
  if not id then return end
  local value = ns.ParseMoney(box:GetText())
  local limits = Limits(id)
  if value and value > 0 then
    limits[field] = value
    if not ns.IsWatched(id) then ui.limits[id] = limits end
    ns.RecalcWatch(id)
  end
  box:ClearFocus()
  RefreshItem()
end

local function BuildItemPage(parent)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints()
  page.back = MakeButton(page, "< Back", 70)
  page.back:SetPoint("TOPLEFT", 8, -52)
  page.back:SetScript("OnClick", function() ui.Show(ui.lastList or "watch") end)
  page.icon = page:CreateTexture(nil, "ARTWORK")
  page.icon:SetSize(22, 22)
  page.icon:SetPoint("LEFT", page.back, "RIGHT", 12, 0)
  page.title = MakeText(page, "GameFontNormalLarge")
  page.title:SetPoint("LEFT", page.icon, "RIGHT", 8, 0)

  page.chart = CreateChart(page)
  page.chart:SetPoint("TOPLEFT", 70, -84)

  page.facts = MakeText(page, "GameFontHighlightSmall")
  page.facts:SetPoint("TOPLEFT", 12, -322)
  page.facts:SetWidth(530)
  page.facts:SetSpacing(3)

  local right = 560
  local heading = MakeText(page, "GameFontNormalSmall")
  heading:SetPoint("TOPLEFT", right, -82)
  heading:SetText("Listings right now")
  page.ladder = {}
  for i = 1, 10 do
    local line = MakeText(page, "GameFontHighlightSmall")
    line:SetPoint("TOPLEFT", right, -82 - i * 16)
    line:SetWidth(225)
    line:SetWordWrap(false)
    page.ladder[i] = line
  end
  page.more = MakeText(page, "GameFontDisableSmall")
  page.more:SetPoint("TOPLEFT", right, -82 - 11 * 16)

  local buyLabel = MakeText(page, "GameFontNormalSmall")
  buyLabel:SetPoint("TOPLEFT", right, -278)
  buyLabel:SetText("Buy below")
  page.buy = MakeEdit(page, 90)
  page.buy:SetPoint("TOPLEFT", right + 4, -294)
  page.buy:SetScript("OnEnterPressed", function(self) SaveLimit("buy", self) end)
  local sellLabel = MakeText(page, "GameFontNormalSmall")
  sellLabel:SetPoint("TOPLEFT", right + 115, -278)
  sellLabel:SetText("Sell at")
  page.sell = MakeEdit(page, 90)
  page.sell:SetPoint("TOPLEFT", right + 119, -294)
  page.sell:SetScript("OnEnterPressed", function(self) SaveLimit("sell", self) end)
  local hint = MakeText(page, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", right, -318)
  hint:SetWidth(225)
  hint:SetText("Type a price like 80c or 1s 20c, then press Enter.")

  page.buyButton = MakeButton(page, "Buy all under buy price", 220)
  page.buyButton:SetPoint("TOPLEFT", right, -350)
  page.buyButton:SetScript("OnClick", function()
    if ui.itemID then ns.BuyUnder(ui.itemID, Limits(ui.itemID).buy) end
  end)
  page.refresh = MakeButton(page, "Refresh", 105)
  page.refresh:SetPoint("TOPLEFT", right, -376)
  page.refresh:SetScript("OnClick", function()
    if ui.itemID then ns.StartWatchScan({ ui.itemID }) end
  end)
  page.watch = MakeButton(page, "Add to watchlist", 110)
  page.watch:SetPoint("LEFT", page.refresh, "RIGHT", 5, 0)
  page.watch:SetScript("OnClick", function()
    local id = ui.itemID
    if not id then return end
    if ns.IsWatched(id) then
      ns.Unwatch(id)
    else
      local typed = ui.limits[id]
      ns.Watch(id)
      local entry = ns.R().watch[id]
      if typed then
        entry.buy, entry.sell = typed.buy or entry.buy, typed.sell or entry.sell
      end
      ns.RecalcWatch(id)
    end
    RefreshItem()
  end)
  page.sellButton = MakeButton(page, "Sell", 220)
  page.sellButton:SetPoint("TOPLEFT", right, -402)
  page.sellButton:SetScript("OnClick", function()
    if ui.itemID then ns.ShowSell(ui.itemID) end
  end)
  page.sellButton:SetScript("OnEnter", function(self)
    ShowTip(self, "Sell", "Opens the Sell page with this item from your bags selected.")
  end)
  page.sellButton:SetScript("OnLeave", HideTip)
  return page
end

function ui.ShowItem(id)
  ui.itemID = id
  if ui.view ~= "item" then ui.lastList = ui.view end
  ui.Show("item")
  local held = ns.ladders[id]
  if ns.ahOpen and not ns.scanState.running and not ns.fullScanRunning
    and (not held or held.kind == "scan" or time() - held.t > 30) then
    ns.StartWatchScan({ id })
  end
end

-------------------------------------------------------------------------------
-- Settings page
-------------------------------------------------------------------------------
local SETTINGS = {
  { key = "ahCut", label = "Auction house cut", kind = "pct", tip = "The share of each sale the auction house keeps. Used for every profit and break-even number." },
  { key = "wallShare", label = "Wall share", kind = "pct", tip = "How much of an item's total supply a price level must reach, counting up from the cheapest, to be the wall. Higher ignores bigger cheap batches." },
  { key = "minHistoryDays", label = "Days of data required", kind = "int", tip = "Items need this many days of full scans before they can appear in Snipes or Dips." },
  { key = "minSnipeProfit", label = "Minimum snipe profit", kind = "money", tip = "Snipes with less total profit than this, after the cut, are left out." },
  { key = "minSnipeDiscount", label = "Minimum snipe discount", kind = "pct", tip = "Snipe units must cost at least this much less than the normal price." },
  { key = "minDisenchantProfit", label = "Minimum disenchant profit", kind = "money", tip = "Disenchant deals with less profit per item than this, after the cut on the materials, are left out." },
  { key = "minDisenchantPct", label = "Minimum disenchant profit %", kind = "pct", tip = "Disenchant deals must profit at least this share of their price." },
  { key = "dipPct", label = "Dip size", kind = "pct", tip = "How far below its normal price the wall must fall to count as a dip." },
  { key = "minSupply", label = "Minimum supply", kind = "int", tip = "Items with fewer units listed than this are left out of Snipes and Dips, because thin markets give unreliable prices." },
  { key = "staleMinutes", label = "Grey out after (minutes)", kind = "int", tip = "Watchlist rows are greyed out when their last scan is older than this." },
  { key = "autoScan", label = "Daily full scan on open", kind = "bool", tip = "Start a full scan when you open the auction house, if none has run today." },
  { key = "sound", label = "Sound on deals", kind = "bool", tip = "Play a sound when a scan finds units under your buy price or new snipes." },
  { key = "baitSearchGap", label = "Bait search gap (seconds)", kind = "secs", tip = "Bait Detect waits at least this long between searches. Never less than 1 second." },
  { key = "baitMinUnder", label = "Bait: min % under wall", kind = "pct", min = ns.Bait.MIN_UNDER, max = ns.Bait.MAX_UNDER, tip = "Bait Detect flags a cheapest level only when it sits at least this far under the wall. Ordinary undercutting stays close to the wall. 10% to 95%." },
  { key = "baitConfirmPress", label = "Bait confirm press", kind = "bool", tip = "Bait Detect confirms each purchase with its own press of the button. Untick to confirm straight after the price quote." },
  { key = "minimapButton", label = "Minimap button", kind = "bool", tip = "Show the MW button on the minimap, which opens the item search window. /mw minimap does the same." },
  { key = "mobDisenchant", label = "Mob value: disenchanting", kind = "mode", tip = "Include disenchanting in a mob's Optimal value. Auto: when this character has Enchanting. Always suits an enchanter alt." },
  { key = "mobSkinning", label = "Mob value: skinning", kind = "mode", tip = "Include skinning in a mob's Optimal value. Auto: when this character has Skinning." },
  { key = "mobRareShare", label = "Rare drop threshold", kind = "pct", tip = "Drops seen in fewer kills than this count as rare, and are left out of the values without rare drops." },
  { key = "mobMinKills", label = "Kills before values are reliable", kind = "int", tip = "A mob's values show from its first kill with loot seen. Under this many, its kill count shows in orange as a flag that the values are rough." },
  { key = "salvagerMode", label = "Salvager mode", kind = "mode", modes = { "auto", "on", "off" }, tip = "Count Salvager's disenchant bonus. Auto: while the buff is up. Imported once from Disenchantry, so Reset to defaults keeps it." },
  { key = "salvagerBonus", label = "Salvager bonus %", kind = "points", tip = "Extra materials Salvager gives, in percent. Imported once from Disenchantry, so Reset to defaults keeps it." },
}

-- Rows scroll above Reset: they no longer all fit in the frame at this height
local SETTING_ROW_H = 25
local MODES = { "auto", "always", "never" }   -- each click moves to the next; a row's own modes replace these
local MODE_TEXT = { auto = "Auto", always = "Always", never = "Never", on = "On", off = "Off" }

local function NextMode(modes, value)
  for i, mode in ipairs(modes) do
    if mode == value then return modes[i % #modes + 1] end
  end
  return modes[1]
end

local function FormatSetting(def)
  local value = ns.Cfg(def.key)
  if def.kind == "mode" then return MODE_TEXT[value] end
  if def.kind == "pct" then return ns.Round(value * 1000) / 10 .. "%" end
  if def.kind == "points" then return value .. "%" end
  if def.kind == "money" then return ns.Money(value) end
  return tostring(value)
end

local function ParseSetting(def, text)
  if def.kind == "pct" then
    local n = tonumber((text:gsub("%%", "")))
    n = n and n / 100
    if n and n >= (def.min or 0) and n <= (def.max or n) and n < 1 then return n end
  elseif def.kind == "points" then   -- stored as the percent itself, 5 for 5%
    local n = tonumber((text:gsub("%%", "")))
    if n and n >= 0 and n <= 1000 then return n end
  elseif def.kind == "money" then
    local n = ns.ParseMoney(text)
    if n and n >= 0 then return n end
  elseif def.kind == "secs" then
    local n = tonumber(text)
    if n and n >= 1 then return n end
  else
    local n = tonumber(text)
    if n and n >= 0 then return math.floor(n) end
  end
  return nil
end

local function RefreshSettings()
  for _, row in ipairs(ui.settings.rows) do
    if row.def.kind == "bool" then
      row.control:SetChecked(ns.Cfg(row.def.key) and true or false)
    elseif row.def.kind == "mode" or not row.control:HasFocus() then
      row.control:SetText(FormatSetting(row.def))
    end
  end
end

local function SaveSetting(key, value)
  MarketWallDB.cfg[key] = value
  ns.Mobs.Invalidate()   -- prices, the cut and the mob settings all feed mob values
end

local function BuildSettings(parent)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints()
  local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, -56)
  scroll:SetPoint("BOTTOMRIGHT", -28, 40)
  local rows = CreateFrame("Frame", nil, scroll)
  rows:SetSize(760, #SETTINGS * SETTING_ROW_H + 6)
  scroll:SetScrollChild(rows)
  page.rows = {}
  for i, def in ipairs(SETTINGS) do
    local y = -6 - (i - 1) * SETTING_ROW_H
    local label = MakeText(rows, "GameFontNormal")
    label:SetPoint("TOPLEFT", 20, y)
    label:SetText(def.label)
    local control
    if def.kind == "bool" then
      control = CreateFrame("CheckButton", nil, rows, "UICheckButtonTemplate")
      control:SetSize(24, 24)
      control:SetPoint("TOPLEFT", 216, y + 5)
      control:SetScript("OnClick", function(self)
        SaveSetting(def.key, self:GetChecked() and true or false)
        ns.UpdateMinimapButton()
      end)
    elseif def.kind == "mode" then
      control = MakeButton(rows, "", 80)
      control:SetPoint("TOPLEFT", 216, y + 4)
      control:SetScript("OnClick", function(self)
        SaveSetting(def.key, NextMode(def.modes or MODES, ns.Cfg(def.key)))
        self:SetText(FormatSetting(def))
      end)
    else
      control = MakeEdit(rows, 80)
      control:SetPoint("TOPLEFT", 222, y + 3)
      local function Save(self)
        local value = ParseSetting(def, self:GetText())
        if value ~= nil then SaveSetting(def.key, value) end
        self:ClearFocus()
        self:SetText(FormatSetting(def))
      end
      control:SetScript("OnEnterPressed", Save)
      control:SetScript("OnEditFocusLost", function(self)
        local value = ParseSetting(def, self:GetText())
        if value ~= nil then SaveSetting(def.key, value) end
        self:SetText(FormatSetting(def))
      end)
    end
    local help = MakeText(rows, "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 320, y + 2)
    help:SetWidth(430)
    help:SetText(def.tip)
    page.rows[i] = { def = def, control = control }
  end
  local reset = MakeButton(page, "Reset to defaults", 140)
  reset:SetPoint("BOTTOMLEFT", 20, 10)
  reset:SetScript("OnClick", function()
    ns.ResetSettings(MarketWallDB.cfg)
    ns.Mobs.Invalidate()
    RefreshSettings()
    ns.UpdateMinimapButton()
  end)
  local note = MakeText(page, "GameFontDisableSmall")
  note:SetPoint("LEFT", reset, "RIGHT", 12, 0)
  note:SetText("Press Enter after typing a value. Scroll for the mob value and Salvager settings. Changes to Snipes, Dips and Disenchant apply on the next full scan.")
  return page
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function AddFromBox()
  local text = ui.addBox:GetText()
  local id, err = ns.ResolveItem(text)
  if id then
    ui.addBox:SetText("")
    ui.addBox:ClearFocus()
    ui.ShowItem(id)
  else
    ns.Print(err or "Item not found.")
  end
end

function ui.Show(view)
  ui.view = view
  if not ui.frame then return end
  local isItem, isSettings, isSell, isBait = (view == "item"), (view == "settings"), (view == "sell"), (view == "bait")
  local isList = not isItem and not isSettings and not isSell and not isBait
  ui.item:SetShown(isItem)
  ui.settings:SetShown(isSettings)
  ui.sell:SetShown(isSell)
  ui.bait:SetShown(isBait)
  ui.list:SetShown(isList)
  ui.footer:SetShown(view == "watch")
  ui.disenchantFooter:SetShown(view == "disenchant")
  ui.hint:SetShown(isList)
  for name, button in pairs(ui.nav) do
    if name == view or (isItem and name == ui.lastList) then button:LockHighlight() else button:UnlockHighlight() end
  end
  ui.list.offset = 0
  ns.RefreshUI()
end

-- Empty-list text that says how far along the history is
function ui.WaitingText(noneText, neverText)
  if not ns.lastFullScan then
    local r = ns.R()
    if r.lastFull then return "Results are from this session only. Run a full scan to refresh the list.\nLast full scan: " .. ns.Ago(r.lastFull) .. "." end
    return neverText
  end
  local need, have = ns.Cfg("minHistoryDays"), ns.bestHistory or 0
  if have < need then
    local text = string.format("Collecting history: day %d of %d.\nItems appear here once they have %d days of data. Run a full scan each day.", have, need, need)
    if (ns.hiddenSnipes or 0) > 0 then
      text = text .. string.format("\n%d possible snipes are hidden until then.", ns.hiddenSnipes)
    end
    return text
  end
  return noneText
end

local function ListView(view, data, emptyText, hint)
  ApplySort(view, data)
  local sort = ui.sort[view]
  ui.list:SetColumns(COLUMNS[view], sort and sort.col, sort and sort.desc)
  ui.list:SetData(data, emptyText)
  ui.hint:SetText(hint)
end

local function RefreshDisenchant()
  local data, skill, hidden = DisenchantData()
  local empty
  if not ns.lastFullScan then
    empty = ui.WaitingText(nil, "Run a full scan to look for gear listed under its disenchant value.")
  elseif hidden > 0 then
    empty = string.format("No deals at your Enchanting skill. %d more need a higher skill; tick the box below to see them.", hidden)
  else
    empty = "No disenchant deals in the last full scan."
  end
  local skillText = skill and ("Enchanting " .. skill) or (ORANGE .. "Enchanting skill unknown, so every item is shown|r")
  ListView("disenchant", data, empty, skillText .. ". Click a row to load live listings before buying.")
  ui.showAllBox:SetChecked(ns.Cfg("disenchantShowAll") and true or false)
end

function ns.RefreshUI()
  ns.RefreshSearch()   -- the search window stands apart from the auction house
  if not ui.frame or not ui.frame:IsShown() then return end
  local view = ui.view
  if view == "item" then
    RefreshItem()
  elseif view == "settings" then
    RefreshSettings()
  elseif view == "sell" then
    ns.RefreshSell()
  elseif view == "bait" then
    ns.RefreshBait()
  elseif view == "watch" then
    ListView("watch", WatchData(),
      "Your watchlist is empty.\nType an item name below, or shift-click an item into the box, then press Add.",
      "Click a row for its chart and listings. Hover a column title for what it means.")
  elseif view == "snipes" then
    ListView("snipes", SnipeData(),
      ui.WaitingText("No snipes in the last full scan.", "Run a full scan to look for listings priced under the wall."),
      string.format("Only items with %d days of data. Click a row to load live listings before buying.", ns.Cfg("minHistoryDays")))
  elseif view == "dips" then
    ListView("dips", DipData(),
      ui.WaitingText("No dips in the last full scan.", "Run a full scan. Dips compare today's wall price with each item's own history."),
      string.format("Only items with %d days of data. Items sliding for days are left out.", ns.Cfg("minHistoryDays")))
  elseif view == "disenchant" then
    RefreshDisenchant()
  end
  ns.UpdateStatus()
end

-- Status line, progress bar and the Full scan button's cooldown
function ns.UpdateStatus()
  if not ui.status then return end
  local busy = ns.scanState.running or ns.fullScanRunning
  local text = ns.statusText
  if not busy and (not text or not ns.statusTime or GetTime() - ns.statusTime > 8) then
    local r = ns.R()
    text = GREY .. "Full scan: " .. ns.Ago(r.lastFull) .. "    Watchlist scan: " .. ns.Ago(r.lastWatch) .. "|r"
    if not r.lastFull or ns.DayOf(r.lastFull) ~= ns.Today() then
      text = text .. ORANGE .. "    No full scan yet today|r"
    end
  end
  ui.status:SetText(text or "")
  if busy and ns.progress then
    ui.bar:SetValue(ns.progress)
    ui.bar:Show()
  else
    ui.bar:Hide()
  end
  local left = ns.FullScanCooldown()
  if ns.fullScanRunning then
    ui.fullButton:SetText("Scanning...")
    ui.fullButton:Disable()
  elseif left > 0 then
    ui.fullButton:SetText(string.format("Full scan (%d:%02d)", math.floor(left / 60), left % 60))
    ui.fullButton:Disable()
  else
    ui.fullButton:SetText("Full scan")
    ui.fullButton:Enable()
  end
end

local function Build()
  local f = CreateFrame("Frame", "MarketWallFrame", AuctionHouseFrame)
  f:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 4, -24)
  f:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -4, 27)
  f:Hide()
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.07, 0.07, 0.92)
  ui.frame = f

  ui.nav = {}
  local previous
  -- widths fit each label, so eight buttons leave room for the scan buttons on the right
  for _, def in ipairs({ { "watch", "Watchlist", 72 }, { "snipes", "Snipes", 58 }, { "dips", "Dips", 46 }, { "disenchant", "Disenchant", 76 },
    { "bait", "Bait Detect", 80 }, { "sell", "Sell", 44 }, { "settings", "Settings", 64 } }) do
    local b = MakeButton(f, def[2], def[3])
    if previous then b:SetPoint("LEFT", previous, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 8, -6) end
    b:SetScript("OnClick", function() ui.Show(def[1]) end)
    ui.nav[def[1]] = b
    previous = b
  end

  ui.fullButton = MakeButton(f, "Full scan", 116)
  ui.fullButton:SetPoint("TOPRIGHT", -8, -6)
  ui.fullButton:SetScript("OnClick", function() ns.StartFullScan() end)
  ui.fullButton:SetMotionScriptsWhileDisabled(true)
  ui.fullButton:SetScript("OnEnter", function(self)
    local r = ns.R()
    ShowTip(self, "Full scan", "Records the wall price of every item and looks for snipes and dips. The game allows one every 15 minutes.", "Last full scan: " .. ns.Ago(r.lastFull))
  end)
  ui.fullButton:SetScript("OnLeave", HideTip)
  local scan = MakeButton(f, "Scan watchlist", 100)
  scan:SetPoint("RIGHT", ui.fullButton, "LEFT", -4, 0)
  scan:SetScript("OnClick", function() ns.StartWatchScan() end)
  scan:SetScript("OnEnter", function(self)
    ShowTip(self, "Scan watchlist", "Refreshes live listings for the items on your watchlist. Takes a few seconds and has no cooldown.")
  end)
  scan:SetScript("OnLeave", HideTip)

  -- status line with a progress bar behind it
  ui.bar = CreateFrame("StatusBar", nil, f)
  ui.bar:SetPoint("TOPLEFT", 8, -32)
  ui.bar:SetPoint("TOPRIGHT", -8, -32)
  ui.bar:SetHeight(14)
  ui.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  ui.bar:SetStatusBarColor(0.96, 0.77, 0.09, 0.35)
  ui.bar:SetMinMaxValues(0, 1)
  ui.bar:Hide()
  ui.status = MakeText(f, "GameFontHighlightSmall", "LEFT")
  ui.status:SetPoint("TOPLEFT", 12, -33)
  ui.status:SetPoint("TOPRIGHT", -12, -33)
  ui.status:SetWordWrap(false)

  ui.list = CreateList(f)
  ui.list:SetPoint("TOPLEFT", 0, -50)
  ui.list:SetPoint("RIGHT")
  ui.list:SetHeight(22 + ROWS * ROW_H)
  ui.list.onClick = function(entry) ui.ShowItem(entry.id) end
  ui.list.onHeader = HeaderClicked

  ui.hint = MakeText(f, "GameFontDisableSmall")
  ui.hint:SetPoint("TOPLEFT", ui.list, "BOTTOMLEFT", 8, -2)

  ui.footer = CreateFrame("Frame", nil, f)
  ui.footer:SetPoint("BOTTOMLEFT", 0, 4)
  ui.footer:SetPoint("BOTTOMRIGHT", 0, 4)
  ui.footer:SetHeight(26)
  local label = MakeText(ui.footer, "GameFontNormalSmall")
  label:SetPoint("LEFT", 8, 0)
  label:SetText("Add item")
  ui.addBox = MakeEdit(ui.footer, 240)
  ui.addBox:SetPoint("LEFT", label, "RIGHT", 12, 0)
  ui.addBox:SetScript("OnEnterPressed", AddFromBox)
  local add = MakeButton(ui.footer, "Add", 60)
  add:SetPoint("LEFT", ui.addBox, "RIGHT", 6, 0)
  add:SetScript("OnClick", AddFromBox)

  ui.disenchantFooter = CreateFrame("Frame", nil, f)
  ui.disenchantFooter:SetPoint("BOTTOMLEFT", 0, 4)
  ui.disenchantFooter:SetPoint("BOTTOMRIGHT", 0, 4)
  ui.disenchantFooter:SetHeight(26)
  ui.showAllBox = CreateFrame("CheckButton", nil, ui.disenchantFooter, "UICheckButtonTemplate")
  ui.showAllBox:SetSize(24, 24)
  ui.showAllBox:SetPoint("LEFT", 6, 0)
  ui.showAllBox:SetScript("OnClick", function(self)
    MarketWallDB.cfg.disenchantShowAll = self:GetChecked() and true or false
    ui.list.offset = 0
    ns.RefreshUI()
  end)
  local showAllLabel = MakeText(ui.disenchantFooter, "GameFontNormalSmall")
  showAllLabel:SetPoint("LEFT", ui.showAllBox, "RIGHT", 2, 0)
  showAllLabel:SetText("Show items I can't disenchant yet")

  ui.item = BuildItemPage(f)
  ui.item:Hide()
  ui.settings = BuildSettings(f)
  ui.settings:Hide()
  ui.sell = ns.BuildSellPage(f)
  ui.sell:Hide()
  ui.bait = ns.BuildBaitPage(f)
  ui.bait:Hide()

  -- item names and icons arrive late; redraw at most twice a second while that happens.
  -- The same tick keeps the status line and the cooldown on the Full scan button current.
  f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  f:SetScript("OnEvent", function() ui.dirty = true end)
  local elapsed, slow = 0, 0
  f:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 0.5 then
      slow = slow + elapsed
      elapsed = 0
      if ui.dirty then
        ui.dirty = false
        ns.RefreshUI()
      else
        ns.UpdateStatus()
      end
      -- once a minute, redraw the watchlist so rows grey out as they age
      if slow > 60 then
        slow = 0
        if ui.view == "watch" then ns.RefreshUI() end
      end
    end
  end)
  f:SetScript("OnShow", function() ui.Show(ui.view) end)

  OnLinkInsert(ui.addBox, function(link) ui.addBox:SetText(link) end)
end

-- Market is a display mode of its own. It is non-empty, so other tab addons such as
-- Auctionator's (LibAHTab), which hide their pages only on a non-empty mode, step aside too.
local MARKET_MODE = { "MarketWallFrame" }

-- The tab to sit after: Auctionator's last tab when its tabs already exist, else the last
-- Blizzard tab. If Auctionator adds its tabs later, it anchors them after ours instead.
local function TabToFollow(tabs)
  local libAHTab = LibStub and LibStub("LibAHTab-1-0", true)
  local theirs = libAHTab and libAHTab.internalState and libAHTab.internalState.Tabs
  if theirs and #theirs > 0 then return theirs[#theirs] end
  return tabs[#tabs]
end

-- The Market tab. Blizzard's tab-group functions taint the bags, so the tab only borrows
-- the auction house's tab button template and switches the display itself.
local function CreateTab(frame)
  local tabs = AuctionHouseFrame.Tabs
  if not (tabs and tabs[1]) then
    ns.Print("Could not add the Market tab to the auction house.")
    return
  end
  -- The one key we add to AuctionHouseFrame, so its SetDisplayMode can show our page.
  AuctionHouseFrame.MarketWallFrame = frame
  -- The template appends the new button to AuctionHouseFrame.Tabs (parentArray), so the tab
  -- to follow must be read first. We leave our tab in that array rather than edit Blizzard's
  -- table (taint).
  local previousTab = TabToFollow(tabs)
  local tab = CreateFrame("Button", "MarketWallTab", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
  tab:SetText("Market")
  PanelTemplates_TabResize(tab, 20, nil, 70)
  tab:SetPoint("TOPLEFT", previousTab, "TOPRIGHT", 3, 0)
  PanelTemplates_DeselectTab(tab)
  tab:SetScript("OnClick", function()
    AuctionHouseFrame:SetDisplayMode(MARKET_MODE)
    -- Blizzard's code never sees our mode, and a second click switches again
    AuctionHouseFrame.displayMode = nil
    for _, blizzardTab in ipairs(tabs) do PanelTemplates_DeselectTab(blizzardTab) end
    PanelTemplates_SelectTab(tab)
    AuctionHouseFrame:SetTitle("MarketWall")
    frame:Show()
  end)
  -- any other mode, Blizzard's or another addon's empty one, belongs to another tab: step aside
  hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
    if mode ~= MARKET_MODE then
      frame:Hide()
      PanelTemplates_DeselectTab(tab)
    end
  end)
end

function ns.OnAuctionHouseShow()
  if not AuctionHouseFrame then
    C_Timer.After(0.2, ns.OnAuctionHouseShow)
    return
  end
  if not ui.frame then
    Build()
    CreateTab(ui.frame)
  end
  ns.MaybeAutoScan()
end
