-- MarketWall: the Market tab
local _, ns = ...
local W = ns.Wall

local ui = { view = "watch", limits = {}, sort = { snipes = { col = 6, desc = true } } }   -- Snipes by Profit
ns.ui = ui

local ROWS, ROW_H = 16, 20
local PORTRAIT_CLEAR, TAB_BOTTOM = 58, 32   -- the Market tab row: past the portrait, its bottom on the status line
-- The scan buttons sit at the right end of the status line, under the tabs. Views that open right under
-- that line start CONTENT_DROP lower than the status line's own bottom so they stay clear of the buttons.
local SCAN_BUTTONS_TOP, CONTENT_DROP = 33, 6
local CONTENT_TOP = 50 + CONTENT_DROP
local BUY, GAIN, WARN, GREY, LABEL = ns.COLOR.BUY, ns.COLOR.GAIN, ns.COLOR.WARN, ns.COLOR.GREY, ns.COLOR.LABEL

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

-- Blizzard's top tab, sized to its label. Tabs are views; actions stay red buttons.
local TAB_PADDING = 12
local function FitTab(tab) PanelTemplates_TabResize(tab, TAB_PADDING) end
local function MakeTab(parent, text)
  local tab = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
  tab:SetText(text)
  tab:SetScript("OnShow", FitTab)   -- in place of the template's own sizing, which runs wider
  FitTab(tab)
  PanelTemplates_DeselectTab(tab)
  return tab
end

-- The selected tab joins the panel under it, with gold label text rather than Blizzard's white
local function SelectTab(tab, selected)
  if selected then
    PanelTemplates_SelectTab(tab)
    tab:SetDisabledFontObject(GameFontNormalSmall)
  else
    PanelTemplates_DeselectTab(tab)
  end
end

-- A row of tabs whose bottoms sit on a line across parent, y below its top, from x. The line
-- runs under them, so the selected tab reads as joined to the panel. Returns the tabs by key.
local TAB_LINE = { 0.35, 0.27, 0.13, 1 }
local function MakeTabRow(parent, x, y, defs, onSelect)
  local line = parent:CreateTexture(nil, "BACKGROUND", nil, 2)
  line:SetColorTexture(TAB_LINE[1], TAB_LINE[2], TAB_LINE[3], TAB_LINE[4])
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 0, -y)
  line:SetPoint("TOPRIGHT", 0, -y)
  local tabs, previous = {}, nil
  for _, def in ipairs(defs) do
    local tab = MakeTab(parent, def.label)
    if previous then tab:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 0, 0) else tab:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", x, -y) end
    tab:SetScript("OnClick", function() onSelect(def.key) end)
    tabs[def.key] = tab
    previous = tab
  end
  return tabs
end

-- A small text switch, in place of a row of buttons: the options side by side, the selected one
-- gold and underlined, the others grey. options: { { key, label } }; onSelect(key) runs when the
-- player picks another option. The switch is as wide as its labels; anchor it by any point.
local SWITCH_GAP, SWITCH_HEIGHT = 10, 16
local function MakeSwitch(parent, options, onSelect)
  local switch = CreateFrame("Frame", nil, parent)
  switch:SetHeight(SWITCH_HEIGHT)
  switch.buttons = {}
  local x = 0
  for i, option in ipairs(options) do
    local button = CreateFrame("Button", nil, switch)
    button.key, button.label = option.key, option.label
    button.text = MakeText(button, "GameFontHighlightSmall")
    button.text:SetPoint("LEFT")
    button.text:SetText(option.label)
    local width = button.text:GetStringWidth()
    button:SetSize(width, SWITCH_HEIGHT)
    button:SetPoint("LEFT", x, 0)
    x = x + width + SWITCH_GAP
    button.underline = button:CreateTexture(nil, "ARTWORK")
    button.underline:SetColorTexture(1, 0.82, 0, 1)
    button.underline:SetHeight(1)
    button.underline:SetPoint("BOTTOMLEFT")
    button.underline:SetPoint("BOTTOMRIGHT")
    button:SetScript("OnClick", function(self)
      if switch.selected == self.key then return end
      switch:Select(self.key)
      onSelect(self.key)
    end)
    button:SetScript("OnEnter", function(self)
      if switch.selected ~= self.key then self.text:SetText(self.label) end
    end)
    button:SetScript("OnLeave", function() switch:Select(switch.selected) end)
    switch.buttons[i] = button
  end
  switch:SetWidth(math.max(0, x - SWITCH_GAP))

  function switch:Select(key)
    self.selected = key
    for _, button in ipairs(self.buttons) do
      local on = button.key == key
      button.text:SetText((on and LABEL or GREY) .. button.label .. "|r")
      button.underline:SetShown(on)
    end
  end
  return switch
end

local function Pct(x)
  return string.format("%d%%", ns.Round(x * 100))
end

-- How long ago t was, for a table cell: "20 min", "2 h", "3 d"
local function ShortAge(t)
  local s = time() - t
  if s < 3600 then return math.max(1, math.floor(s / 60)) .. " min" end
  if s < 86400 then return math.floor(s / 3600) .. " h" end
  return math.floor(s / 86400) .. " d"
end

local function ShowTip(owner, title, body, extra)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOP")
  if title == "" then   -- an untitled column's hover: the body leads, with no empty title line
    GameTooltip:SetText(body, 1, 1, 1, 1, true)
  else
    GameTooltip:SetText(title, 1, 0.82, 0)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
  end
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

-- A menu at the cursor. items: { { text =, onClick =, color = }, ... }; an item with no onClick
-- is a heading, or greyed out when disabled is set; color (an ns.COLOR code) tints a choice, such
-- as red for one that deletes. It closes on a choice, on Escape, or once the mouse has been off
-- it for a moment.
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
    local color = (item.disabled and GREY) or (not item.onClick and LABEL) or item.color or ""
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

StaticPopupDialogs["MARKETWALL_CONFIRM"] = {
  text = "%s",
  button2 = CANCEL,
  OnAccept = function(_, data) data.onAccept() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- Asks before something that cannot be undone: the question, a grey line on what it means, and
-- an accept button named for the action. onAccept() runs only on that button.
local function Confirm(question, detail, accept, onAccept)
  StaticPopupDialogs.MARKETWALL_CONFIRM.button1 = accept
  StaticPopup_Show("MARKETWALL_CONFIRM", question .. "\n\n" .. GREY .. detail .. "|r", nil, { onAccept = onAccept })
end

-------------------------------------------------------------------------------
-- Dropdown button and placeholder text
-------------------------------------------------------------------------------

-- A button that reads as a dropdown: a dark box, its text on the left, an arrow on the right.
-- Set its OnClick to show a menu; dropdown:SetLabel(text) sets the text.
local function MakeDropdown(parent, width)
  local dropdown = CreateFrame("Button", nil, parent)
  dropdown:SetSize(width, 22)
  local edge = dropdown:CreateTexture(nil, "BACKGROUND", nil, 0)
  edge:SetAllPoints()
  edge:SetColorTexture(0.42, 0.35, 0.23, 1)
  local bg = dropdown:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetColorTexture(0, 0, 0, 0.85)
  dropdown:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  local arrow = dropdown:CreateTexture(nil, "ARTWORK")
  arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
  arrow:SetSize(20, 20)
  arrow:SetPoint("RIGHT", 1, 0)
  dropdown.text = MakeText(dropdown, "GameFontHighlightSmall")
  dropdown.text:SetPoint("LEFT", 8, 0)
  dropdown.text:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
  dropdown.text:SetWordWrap(false)
  function dropdown:SetLabel(text) self.text:SetText(text) end
  return dropdown
end

-- Grey text inside an empty edit box, saying what to type; it hides while the box has focus or text
local function SetPlaceholder(box, text)
  local placeholder = MakeText(box, "GameFontDisableSmall")
  placeholder:SetPoint("LEFT", 2, 0)
  placeholder:SetPoint("RIGHT", -4, 0)
  placeholder:SetWordWrap(false)
  placeholder:SetText(text)
  local function Update() placeholder:SetShown(box:GetText() == "" and not box:HasFocus()) end
  box:HookScript("OnTextChanged", Update)
  box:HookScript("OnEditFocusGained", Update)
  box:HookScript("OnEditFocusLost", Update)
  Update()
end

-------------------------------------------------------------------------------
-- Generic list: sortable headers with hover help, icon per row
-------------------------------------------------------------------------------

-- Text, then a suffix that always stays visible: the text loses characters from its end, behind
-- an ellipsis, until both fit the cell. Keeps a colour code wrapped around the text.
local function FitText(cell, text, suffix)
  local color, plain = text:match("^(|c%x%x%x%x%x%x%x%x)(.*)|r$")
  plain = plain or text
  local function Show(shown)
    cell:SetText((color and color .. shown .. "|r" or shown) .. suffix)
  end
  Show(plain)
  local limit = cell:GetWidth()
  while plain ~= "" and cell:GetStringWidth() > limit do
    plain = plain:gsub("[\1-\127\192-\255][\128-\191]*$", "")   -- one whole UTF-8 character
    Show(plain .. "…")
  end
end
-- A cell's text in its column's colour: green for the answer column, grey for supporting
-- numbers, white otherwise. Text that brings its own colour keeps it.
local function ColumnColor(col, text)
  if text == "" or text:find("^|c") then return text end
  if col.answer then return GAIN .. text .. "|r" end
  if col.grey then return GREY .. text .. "|r" end
  return text
end

-- A thin scrollbar just outside a list's right edge, so it never covers the last column; a list
-- needs SCROLLBAR_W of room to its right. Shown only while there are more rows than fit.
-- Dragging it sets the list's offset; the mouse wheel still scrolls too.
local SCROLLBAR_W = 8
local function CreateScrollBar(list)
  local bar = CreateFrame("Slider", nil, list)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(SCROLLBAR_W)
  bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, -22)
  bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT")
  bar:SetValueStep(1)
  bar:SetObeyStepOnDrag(true)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.06)
  local thumb = bar:CreateTexture(nil, "ARTWORK")
  thumb:SetColorTexture(0.96, 0.77, 0.09, 0.55)
  thumb:SetSize(SCROLLBAR_W, 28)
  bar:SetThumbTexture(thumb)
  bar:SetScript("OnValueChanged", function(_, value)
    if list.syncingBar then return end   -- the list moving the bar, not the player
    local offset = math.floor(value + 0.5)
    if offset ~= list.offset then
      list.offset = offset
      list:Refresh()
    end
  end)
  bar:Hide()
  return bar
end

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
  list.scrollBar = CreateScrollBar(list)
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
    row.cells, row.hits = {}, {}
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      local handler = button == "RightButton" and list.onRightClick or list.onClick
      if self.entry and handler then handler(self.entry) end
    end)
    row:SetScript("OnEnter", function(self)
      if self.entry and self.entry.id and GameTooltip and GameTooltip.SetItemByID then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetItemByID(self.entry.id)
        if self.entry.itemTip then GameTooltip:AddLine(self.entry.itemTip, 1, 0.69, 0.34, true) end
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
  -- an empty list hides its column titles and shows this, about mid-height
  list.empty = MakeText(list, "GameFontDisable", "CENTER")
  list.empty:SetPoint("TOP", 0, -math.floor(size * ROW_H * 0.4))
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

  -- A cell's hover text: a money cell's exact amount when the cell rounds it, then the row's
  -- own text for the cell from entry.cellTips
  local function CellTip(entry, c)
    local tip = entry.cellTips and entry.cellTips[c]
    local copper = list.columns[c].money and type(entry.cells[c]) == "number" and entry.cells[c]
    if copper and ns.Money(copper) ~= ns.MoneyShort(copper) then
      tip = tip and (ns.Money(copper) .. "\n" .. tip) or ns.Money(copper)
    end
    return tip
  end

  -- A hover area over one row's cell, for columns marked cellTip or money. Clicks pass through
  -- to the row; with nothing to say about the cell, the row's own hover shows.
  local function CellHit(row, c)
    local hit = row.hits[c]
    if hit then return hit end
    hit = CreateFrame("Frame", nil, row)
    hit:SetMouseMotionEnabled(true)
    hit:SetMouseClickEnabled(false)
    hit:SetScript("OnEnter", function(self)
      local tip = row.entry and CellTip(row.entry, c)
      if tip then ShowTip(self, self.title, tip) else row:GetScript("OnEnter")(row) end
    end)
    hit:SetScript("OnLeave", HideTip)
    row.hits[c] = hit
    return hit
  end

  -- columns: { {title, width, justify, tip, cellTip = true?, money = true?, answer = true?,
  -- grey = true?}, ... }   sortCol/sortDesc mark the active sort. A money column's cells hold
  -- copper, shown in the compact form, or nil for a dash, or text to show as it is. The answer
  -- column, one per table, is green and a size larger; grey columns hold supporting numbers.
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
          cell:SetFontObject(col.answer and "GameFontHighlight" or "GameFontHighlightSmall")
          cell:SetWordWrap(false)
          cell:Show()
        else
          cell:Hide()
        end
        if col and (col.cellTip or col.money) then
          local hit = CellHit(row, c)
          hit:ClearAllPoints()
          hit:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
          hit:SetSize(col[2], ROW_H)
          hit.title = col[1]
          hit:Show()
        elseif row.hits[c] then
          row.hits[c]:Hide()
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
        for c = 1, #self.columns do
          local suffix = entry.suffixes and entry.suffixes[c]
          local text = entry.cells[c]
          if self.columns[c].money and type(text) ~= "string" then text = ns.MoneyShort(text) end
          text = ColumnColor(self.columns[c], text or "")
          if suffix then FitText(row.cells[c], text, suffix) else row.cells[c]:SetText(text) end
        end
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
    for c, header in ipairs(self.headers) do header:SetShown(#data > 0 and self.columns[c] ~= nil) end
    self.empty:SetText(#data == 0 and self.emptyText or "")
    self.empty:SetShown(#data == 0)
    -- a list longer than it shows says which rows are on screen, "1–16 of 105", and scrolls
    local scrolls = #data > size
    self.count:SetText(scrolls and string.format("%d–%d of %d", self.offset + 1, self.offset + size, #data) or "")
    self.scrollBar:SetShown(scrolls)
    if scrolls then
      -- a shrinking range clamps the bar's old value; that must not move the list
      self.syncingBar = true
      self.scrollBar:SetMinMaxValues(0, #data - size)
      self.scrollBar:SetValue(self.offset)
      self.syncingBar = false
    end
  end
  return list
end

-------------------------------------------------------------------------------
-- Columns and view data. Each entry carries raw values in entry.sort for header sorting.
-------------------------------------------------------------------------------
local WALL_TIP = "The item's real price: the lowest price level that has meaningful supply behind it. A few stray cheap units do not move it."
-- An Item column's hover says a low-data item ends its name with an orange " · N d".
-- cellTip: rows carry a hover text for this column's cells in entry.cellTips.
local LOW_DATA_TIP = "An orange \" · N d\" after a name: only N days of data, fewer than the \"Days before data is reliable\" setting, so the normal price may be off."
local WATCH_COLUMNS = {
  { "Item", 152, nil, "Items you are tracking. Click a row for its chart and live listings. " .. LOW_DATA_TIP },
  { "Wall", 80, "RIGHT", WALL_TIP, money = true },
  { "Lowest", 80, "RIGHT", "The single cheapest listing right now, even if it is only one unit.", money = true, grey = true },
  { "Normal range", 150, "RIGHT", "Where the wall price usually sits: the middle half of its daily history. On an item's first day, today's wall. Hover a cell for the exact range and the item's days of data.", cellTip = true, grey = true },
  { "Buy below", 80, "RIGHT", "Your buy threshold. Units listed under this price count as deals. Set it on the item's page.", money = true },
  { "Sell at", 80, "RIGHT", "Your target resale price. The row says Sell when the wall price reaches it.", money = true },
  { "Under buy", 70, "RIGHT", "How many units are listed under your buy price as of the last scan." },
  { "Status", 85, "RIGHT", "Buy: units are under your buy price. Sell: the wall reached your sell price. Old: the price has not been scanned recently, with its age. A dash: nothing to do.", answer = true },
}
local SNIPE_COLUMNS = {
  { "Item", 220, nil, "Items with listings priced under their wall. Click a row to load live listings before buying. " .. LOW_DATA_TIP },
  { "Cheapest", 90, "RIGHT", "The lowest listing found in the scan.", money = true },
  { "Units", 55, "RIGHT", "Units listed under the wall that would still profit after the auction house cut." },
  { "Cost", 95, "RIGHT", "What it costs to buy all of those units.", money = true, grey = true },
  { "Sells at (wall)", 110, "RIGHT", WALL_TIP, money = true, grey = true },
  { "Profit", 110, "RIGHT", "Expected profit if you resell at the normal price, after the auction house cut. Uses the lower of today's wall and the historical median.", money = true, answer = true },
  { "Under normal", 100, "RIGHT", "How far the average cost of those units is below the normal price." },
}
local DIP_COLUMNS = {
  { "Item", 260, nil, "Items whose wall price dropped suddenly compared with their own history. " .. LOW_DATA_TIP },
  { "Wall now", 95, "RIGHT", WALL_TIP, money = true },
  { "Normal", 95, "RIGHT", "The median wall price over the history window.", money = true, grey = true },
  { "Under by", 80, "RIGHT", "How far today's wall is below the normal price." },
  { "Supply", 80, "RIGHT", "Total units listed. More supply means the dip is real, not one seller.", grey = true },
  { "Profit each", 110, "RIGHT", "Expected profit per unit if the price returns to normal, after the auction house cut.", money = true, answer = true },
}
local DISENCHANT_COLUMNS = {
  { "Item", 220, nil, "Weapons and armor, uncommon or better, listed under what disenchanting them is worth. Click a row to load live listings before buying." },
  { "Price", 90, "RIGHT", "The cheapest buyout found in the scan.", money = true },
  { "Net DE value", 130, "RIGHT", "Expected value of the materials from one disenchant, at their wall prices, after the auction house cut and the deposit to list each material, as the item tooltip's Disenchant (net) shows it.", money = true, grey = true },
  { "Profit", 100, "RIGHT", "Net disenchant value minus the price.", money = true, answer = true },
  { "Profit %", 80, "RIGHT", "Profit as a share of the price." },
  { "Odds from", 150, nil, "Where the material odds come from: your own disenchants (recorded by MarketWall), a Forever estimate, or the classic disenchanting table.", grey = true },
}
local COLUMNS = { watch = WATCH_COLUMNS, snipes = SNIPE_COLUMNS, dips = DIP_COLUMNS, disenchant = DISENCHANT_COLUMNS }
ui.COLUMNS = COLUMNS   -- for specs

-- The Status answer: green Buy and Sell, a grey dash when there is nothing to do
local STATUS_TEXT = {
  buy = GAIN .. "Buy|r", sell = GAIN .. "Sell|r", normal = GREY .. "-|r", nodata = GREY .. "Not scanned|r",
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
      statusText = WARN .. "Old · " .. ShortAge(cur.t) .. "|r"
    end
    local range, exactRange = "building", nil
    if stats.n > 0 then
      range = ns.MoneyShort(stats.p25) .. " – " .. ns.MoneyShort(stats.p75)
      exactRange = ns.Money(stats.p25) .. " to " .. ns.Money(stats.p75)
    end
    local under = cur.under and tostring(cur.under) or "-"
    if under == "0" or under == "-" then under = GREY .. under .. "|r" end
    local name = ns.Name(id)
    local days = ns.DaysOfData(id)
    data[#data + 1] = {
      id = id, status = status, name = name, highlight = (status == "buy"), dim = stale,
      cells = { ns.ColorName(id), cur.w, cur.m, range, entry.buy, entry.sell, under, statusText },
      sort = { name, cur.w, cur.m, stats.n > 0 and stats.p25 or nil, entry.buy, entry.sell, cur.under, -STATUS_ORDER[status] },
      suffixes = { ns.DataSuffix(days) }, itemTip = ns.LowDataTip(days),
      cellTips = { [4] = exactRange and (exactRange .. "\n" .. ns.DataBadgeTip(days)) or ns.DataBadgeTip(days) },
    }
  end
  table.sort(data, function(a, b)
    if STATUS_ORDER[a.status] ~= STATUS_ORDER[b.status] then return STATUS_ORDER[a.status] < STATUS_ORDER[b.status] end
    return a.name < b.name
  end)
  return data
end
ui.WatchData = WatchData   -- for specs

-- The lists show the last full scan's candidates that pass the thresholds as they are now
local function SnipeData()
  local data = {}
  for i, s in ipairs(ns.Passing(ns.snipes, ns.PassesSnipe)) do
    data[i] = { id = s.id,
      cells = { ns.ColorName(s.id), s.min, tostring(s.units), s.cost, s.wall, s.profit, Pct(s.discount) },
      sort = { ns.Name(s.id), s.min, s.units, s.cost, s.wall, s.profit, s.discount },
      suffixes = { ns.DataSuffix(s.days) }, itemTip = ns.LowDataTip(s.days),
    }
  end
  return data
end
ui.SnipeData = SnipeData   -- for specs

local function DipData()
  local data = {}
  for i, d in ipairs(ns.Passing(ns.dips, ns.PassesDip)) do
    data[i] = { id = d.id,
      cells = { ns.ColorName(d.id), d.wall, d.median, Pct(d.under), tostring(d.total), d.profit },
      sort = { ns.Name(d.id), d.wall, d.median, d.under, d.total, d.profit },
      suffixes = { ns.DataSuffix(d.days) }, itemTip = ns.LowDataTip(d.days),
    }
  end
  return data
end
ui.DipData = DipData   -- for specs

-- Deals that pass the thresholds and this character can disenchant, or all that pass when the
-- box is ticked or the skill is unknown. Also returns the skill and how many passing deals it hides.
local function DisenchantData()
  local skill = ns.EnchantingSkill()
  local showAll = ns.Cfg("disenchantShowAll") or skill == nil
  local data, hidden = {}, 0
  for _, d in ipairs(ns.Passing(ns.DisenchantDeals(), ns.PassesDisenchant)) do
    if showAll or d.skill <= skill then
      data[#data + 1] = { id = d.id,
        cells = { ns.ColorName(d.id), d.price, d.value, d.profit, Pct(d.pct), d.odds },
        sort = { ns.Name(d.id), d.price, d.value, d.profit, d.pct, d.odds },
      }
    else
      hidden = hidden + 1
    end
  end
  return data, skill, hidden
end
ui.DisenchantData = DisenchantData   -- for specs

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
    if stats and stats.n > 0 then span(stats.p25) span(stats.p75) end
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

    if stats and stats.n > 0 then
      self.band:ClearAllPoints()
      self.band:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, Y(stats.p25))
      self.band:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, Y(stats.p75))
      self.band:Show()
      Line(0, Y(stats.median), width, Y(stats.median), 0.96, 0.77, 0.09, 0.6, 1)
    end
    if buy then Line(0, Y(buy), width, Y(buy), 0.49, 0.75, 1, 0.9, 1) end
    if sell then Line(0, Y(sell), width, Y(sell), 0.31, 0.76, 0.42, 0.9, 1) end

    if #series == 1 then
      local x = math.max(6, math.min(width - 6, X(series[1].t)))
      Line(x - 6, Y(series[1].w), x + 6, Y(series[1].w), 1, 1, 1, 1, 3)
    else
      for i = 2, #series do
        Line(X(series[i - 1].t), Y(series[i - 1].w), X(series[i].t), Y(series[i].w), 1, 1, 1, 1, 2)
      end
    end

    self.yLabels[1]:SetText(ns.MoneyShort(hi))
    self.yLabels[2]:SetText(ns.MoneyShort((hi + lo) / 2))
    self.yLabels[3]:SetText(ns.MoneyShort(lo))
    self.xFirst:SetText(date("%b %d %H:%M", t0))
    self.xLast:SetText(date("%b %d %H:%M", t1))
    local legend = "White: wall price   " .. BUY .. "Blue: buy below|r   " .. GAIN .. "Green: sell at|r   " .. LABEL .. "Gold band: normal range|r   Bars: supply"
    self.legend:SetText(legend)
  end
  return chart
end
ns.widgets = {
  MakeButton = MakeButton, MakeText = MakeText, MakeEdit = MakeEdit, ShowTip = ShowTip, HideTip = HideTip,
  OnLinkInsert = OnLinkInsert, CreateList = CreateList, ShortAge = ShortAge, MakeTabRow = MakeTabRow, SelectTab = SelectTab, MakeSwitch = MakeSwitch, FitText = FitText, CreateChart = CreateChart, ShowMenu = ShowMenu, Prompt = Prompt, Confirm = Confirm,
  MakeDropdown = MakeDropdown, SetPlaceholder = SetPlaceholder, ListHeight = function(rows) return 22 + rows * ROW_H end,
  CONTENT_DROP = CONTENT_DROP,
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
  if not page.buy:HasFocus() then page.buy:SetText(limits.buy and ns.MoneyText(limits.buy) or "") end
  if not page.sell:HasFocus() then page.sell:SetText(limits.sell and ns.MoneyText(limits.sell) or "") end

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
        text = text .. BUY .. "  under buy price|r"
      elseif wall and tier.p == wall then
        text = text .. LABEL .. "  wall|r"
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
  local lowData = ns.LowDataText(ns.DaysOfData(id))
  if lowData then lines[#lines + 1] = WARN .. lowData .. "|r" end
  if stats.n > 0 then
    lines[#lines + 1] = string.format("Normal: median %s, range %s to %s, from %d %s", ns.Money(stats.median), ns.Money(stats.p25), ns.Money(stats.p75), stats.n, stats.n == 1 and "day" or "days")
  else
    lines[#lines + 1] = GREY .. "No normal range yet: no scans in the history window.|r"
  end
  if held and limits.buy and held.kind ~= "scan" then
    local units, cost = W.UnitsUnder(held.ladder, limits.buy)
    if units > 0 then
      local each = cost / units
      local text = string.format("%sUnder your buy price: %d units for %s|r    Break-even resale %s", BUY, units, ns.Money(cost), ns.Money(math.ceil(each / (1 - cut))))
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
    lines[#lines + 1] = WARN .. "Warning: selling at that price loses money after the " .. Pct(cut) .. " cut.|r"
  end
  -- day/night and day-of-week pattern
  local cycle = ns.Cycle(id)
  local function Cell(label, g)
    if not g or g.n < 3 then return GREY .. label .. " n/a|r" end
    local diff = ns.Round((g.r - 1) * 100)
    local color = diff <= -2 and BUY or ns.COLOR.VALUE
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
-- Three-way modes as stored, shown as Auto / On / Off
local MOB_MODES = { { key = "auto", label = "Auto" }, { key = "always", label = "On" }, { key = "never", label = "Off" } }
local SALVAGER_MODES = { { key = "auto", label = "Auto" }, { key = "on", label = "On" }, { key = "off", label = "Off" } }
-- The deal thresholds filter the last full scan's list each time it is shown
local ON_LAST_SCAN = " Applies to the last full scan right away, and can also be set above its list."

-- Every setting, in named groups laid out in two columns. A label stays short because its
-- group names the subject; note is the few words beside it, tip the full text on hover.
local SETTING_GROUPS = {
  { title = "Prices and data", column = 1, settings = {
    { key = "ahCut", label = "Auction house cut", kind = "pct", note = "Used in every profit number",
      tip = "The share of each sale the auction house keeps. Used for every profit and break-even number." },
    { key = "wallShare", label = "Wall share", kind = "pct", note = "Supply a level needs to be the wall",
      tip = "How much of an item's total supply a price level must reach, counting up from the cheapest, to be the wall. Higher ignores bigger cheap batches." },
    { key = "minHistoryDays", label = "Days before data is reliable", kind = "int", min = 1, max = ns.cfgDefaults.baselineDays + 1, note = "Fewer days get the orange badge",
      tip = "Items with fewer days of scans than this get an orange low-data flag. It only sets the flag; nothing is hidden. 1 to " .. (ns.cfgDefaults.baselineDays + 1) .. "." },
    { key = "minSupply", label = "Minimum supply", kind = "int", note = "Thinner markets are left out",
      tip = "Items with fewer units listed than this are left out of Snipes and Dips, because thin markets give unreliable prices." .. ON_LAST_SCAN },
  } },
  { title = "Snipes and Dips", column = 1, settings = {
    { key = "minSnipeProfit", label = "Minimum snipe profit", kind = "money", note = "After the cut",
      tip = "Snipes with less total profit than this, after the cut, are left out." .. ON_LAST_SCAN },
    { key = "minSnipeDiscount", label = "Minimum snipe discount", kind = "pct", note = "Under the normal price",
      tip = "Snipe units must cost at least this much less than the normal price." .. ON_LAST_SCAN },
    { key = "dipPct", label = "Dip size", kind = "pct", note = "How far the wall must fall",
      tip = "How far below its normal price the wall must fall to count as a dip." .. ON_LAST_SCAN },
  } },
  { title = "Disenchant", column = 1, settings = {
    { key = "minDisenchantProfit", label = "Minimum profit", kind = "money", note = "Per item, after cut and deposits",
      tip = "Disenchant deals with less profit per item than this, after the cut and deposits on the materials, are left out." .. ON_LAST_SCAN },
    { key = "minDisenchantPct", label = "Minimum profit %", kind = "pct", note = "Of the item's price",
      tip = "Disenchant deals must profit at least this share of their price." .. ON_LAST_SCAN },
    { key = "salvagerMode", label = "Salvager", kind = "mode", modes = SALVAGER_MODES, note = "Count Salvager's bonus",
      tip = "Count Salvager's disenchant bonus. Auto: while the buff is up. Imported once from Disenchantry, so Reset to defaults keeps it." },
    { key = "salvagerBonus", label = "Salvager bonus", kind = "points", note = "Imported from Disenchantry",
      tip = "Extra materials Salvager gives, in percent. Imported once from Disenchantry, so Reset to defaults keeps it." },
  } },
  { title = "Scanning and alerts", column = 2, settings = {
    { key = "autoScan", label = "Daily full scan on open", kind = "bool", note = "If none has run today",
      tip = "Start a full scan when you open the auction house, if none has run today." },
    { key = "sound", label = "Sound on deals", kind = "bool", note = "Buys and new snipes",
      tip = "Play a sound when a scan finds units under your buy price or new snipes." },
    { key = "staleMinutes", label = "Grey out watchlist after", kind = "int", unit = "min", note = "Since its last scan",
      tip = "Watchlist rows are greyed out when their last scan is older than this many minutes." },
  } },
  { title = "Bait Detect", column = 2, settings = {
    { key = "baitSearchGap", label = "Search gap", kind = "secs", unit = "s", note = "Never less than 1 second",
      tip = "Bait Detect waits at least this many seconds between searches. Never less than 1 second." },
    { key = "baitMinUnder", label = "Minimum under the wall", kind = "pct", min = ns.Bait.MIN_UNDER, max = ns.Bait.MAX_UNDER, note = "10% to 95%",
      tip = "Bait Detect flags a cheapest level only when it sits at least this far under the wall. Ordinary undercutting stays close to the wall. 10% to 95%." },
    { key = "baitConfirmPress", label = "Confirm each purchase", kind = "bool", note = "With its own button press",
      tip = "Bait Detect confirms each purchase with its own press of the button. Untick to confirm straight after the price quote." },
  } },
  { title = "Mob values", column = 2, settings = {
    { key = "mobDisenchant", label = "Disenchanting", kind = "mode", modes = MOB_MODES, note = "In Optimal value",
      tip = "Include disenchanting in a mob's Optimal value. Auto: when this character has Enchanting. On suits an enchanter alt." },
    { key = "mobSkinning", label = "Skinning", kind = "mode", modes = MOB_MODES, note = "In Optimal value",
      tip = "Include skinning in a mob's Optimal value. Auto: when this character has Skinning." },
    { key = "mobRareShare", label = "Rare drop threshold", kind = "pct", note = "Rarer drops are left out",
      tip = "Drops seen in fewer kills than this count as rare, and are left out of the values without rare drops." },
    { key = "mobMinKills", label = "Kills before reliable", kind = "int", note = "Fewer kills get the badge",
      tip = "A mob's values show from its first kill with loot seen. Under this many, an orange kill count after its name flags the values as rough." },
  } },
  { title = "Interface", column = 2, settings = {
    { key = "minimapButton", label = "Minimap button", kind = "bool", note = "Or type /mw",
      tip = "Show the MW button on the minimap, which opens the item search window. /mw minimap does the same." },
  } },
}
ui.settingGroups = SETTING_GROUPS

-- Two columns that fit without scrolling: each one a stack of group titles and rows. The left
-- one is wider for its longer notes; controlX clears the column's longest name.
local SETTING_COLUMNS = { { x = 8, width = 414, controlX = 164 }, { x = 428, width = 358, controlX = 158 } }
local SETTING_TITLE_H, SETTING_ROW_H = 24, 23
local SETTING_EDIT_W, SETTING_NOTE_GAP = 54, 6
local SETTING_SWITCH_W = 80   -- room for the Auto / On / Off switch, which is as wide as its labels

local function FormatSetting(def)
  local value = ns.Cfg(def.key)
  if def.kind == "pct" then return ns.Round(value * 1000) / 10 .. "%" end
  if def.kind == "points" then return value .. "%" end
  if def.kind == "money" then return ns.MoneyText(value) end
  if def.unit then return value .. " " .. def.unit end
  return tostring(value)
end

local function ParseSetting(def, text)
  if def.unit then text = text:gsub("%s*" .. def.unit .. "%s*$", "") end
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
    n = n and math.floor(n)
    if n and n >= (def.min or 0) and n <= (def.max or n) then return n end
  end
  return nil
end
ui.ParseSetting = ParseSetting

local function RefreshSettings()
  for _, row in ipairs(ui.settings.rows) do
    if row.def.kind == "bool" then
      row.control:SetChecked(ns.Cfg(row.def.key) and true or false)
    elseif row.def.kind == "mode" then
      row.control:Select(ns.Cfg(row.def.key))
    elseif not row.control:HasFocus() then
      row.control:SetText(FormatSetting(row.def))
    end
  end
end

local function SaveSetting(key, value)
  MarketWallDB.cfg[key] = value
  ns.Mobs.Invalidate()   -- prices, the cut and the mob settings all feed mob values
end

-- The full tip shows while the pointer is anywhere on the row, its control included. Hooked,
-- so a control's own hover behavior (the switch's) keeps running.
local function TipOnHover(frame, def)
  frame:HookScript("OnEnter", function() ShowTip(frame, def.label, def.tip) end)
  frame:HookScript("OnLeave", HideTip)
end

-- A box for one setting, on the Settings page or over a list: it saves what it reads, on Enter
-- or on leaving the box, shows the stored value again, then calls onSaved if given
function ui.SettingEdit(parent, def, onSaved)
  local edit = MakeEdit(parent, SETTING_EDIT_W)
  local function Save(self)
    local value = ParseSetting(def, self:GetText() or "")
    if value ~= nil then SaveSetting(def.key, value) end
    return value ~= nil
  end
  -- Shown only once the typed text is saved, so the rounded display is never saved again
  local function Show(self, saved)
    self:SetText(FormatSetting(def))
    if saved and onSaved then onSaved() end
  end
  edit:SetScript("OnEnterPressed", function(self)
    local saved = Save(self)
    self:ClearFocus()   -- leaving the box saves the same typed text again
    Show(self, saved)
  end)
  edit:SetScript("OnEditFocusLost", function(self) Show(self, Save(self)) end)
  TipOnHover(edit, def)
  return edit
end

-- The row's control, anchored left at the control column, and its width
local function SettingControl(row, def, controlX)
  if def.kind == "bool" then
    local box = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("LEFT", controlX - 4, 0)
    box:SetScript("OnClick", function(self)
      SaveSetting(def.key, self:GetChecked() and true or false)
      ns.UpdateMinimapButton()
    end)
    TipOnHover(box, def)
    return box, 20
  elseif def.kind == "mode" then
    local switch = MakeSwitch(row, def.modes, function(key) SaveSetting(def.key, key) end)
    switch:SetPoint("LEFT", controlX, 0)
    for _, button in ipairs(switch.buttons) do TipOnHover(button, def) end
    return switch, SETTING_SWITCH_W
  end
  local edit = ui.SettingEdit(row, def)
  edit:SetPoint("LEFT", controlX + 6, 0)
  return edit, SETTING_EDIT_W + 6
end

local function BuildSettingRow(page, def, column, y)
  local row = CreateFrame("Frame", nil, page)
  row:SetSize(column.width, SETTING_ROW_H)
  row:SetPoint("TOPLEFT", column.x, y)
  row:EnableMouse(true)
  TipOnHover(row, def)
  local label = MakeText(row, "GameFontHighlight")
  label:SetPoint("LEFT", 0, 0)
  label:SetText(def.label)
  local control, controlWidth = SettingControl(row, def, column.controlX)
  local noteX = column.controlX + controlWidth + SETTING_NOTE_GAP
  local note = MakeText(row, "GameFontDisableSmall")
  note:SetPoint("LEFT", noteX, 0)
  note:SetWidth(column.width - noteX)
  note:SetWordWrap(false)
  note:SetText(def.note)
  return { def = def, control = control }
end

local function BuildSettingGroupTitle(page, title, column, y)
  local text = MakeText(page, "GameFontHighlight")
  text:SetPoint("TOPLEFT", column.x, y - 4)
  text:SetText(LABEL .. title .. "|r")
  local rule = page:CreateTexture(nil, "ARTWORK")
  rule:SetColorTexture(TAB_LINE[1], TAB_LINE[2], TAB_LINE[3], TAB_LINE[4])
  rule:SetSize(column.width, 1)
  rule:SetPoint("TOPLEFT", column.x, y - SETTING_TITLE_H + 3)
end

local function BuildSettings(parent)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints()
  page.rows = {}
  local columnY = { -CONTENT_TOP, -CONTENT_TOP }
  for _, group in ipairs(SETTING_GROUPS) do
    local column, y = SETTING_COLUMNS[group.column], columnY[group.column]
    BuildSettingGroupTitle(page, group.title, column, y)
    y = y - SETTING_TITLE_H
    for _, def in ipairs(group.settings) do
      page.rows[#page.rows + 1] = BuildSettingRow(page, def, column, y)
      y = y - SETTING_ROW_H
    end
    columnY[group.column] = y
  end

  local reset = MakeButton(page, "Reset to defaults", 140)
  reset:SetPoint("BOTTOMLEFT", SETTING_COLUMNS[1].x, 10)
  reset:SetScript("OnClick", function()
    ns.ResetSettings(MarketWallDB.cfg)
    ns.Mobs.Invalidate()
    RefreshSettings()
    ns.UpdateMinimapButton()
  end)
  local hint = MakeText(page, "GameFontDisableSmall", "RIGHT")
  hint:SetPoint("BOTTOMRIGHT", -16, 16)
  hint:SetText("Hover a setting for its full description. Press Enter to apply a typed value.")
  return page
end

-------------------------------------------------------------------------------
-- Tune rows: a deal list's thresholds right over it, the same settings as on the Settings page
-------------------------------------------------------------------------------
local TUNE_H = 24
local TUNE_SETTINGS = {
  snipes = { { key = "minSnipeProfit", label = "Min profit" }, { key = "minSnipeDiscount", label = "Min discount" } },
  dips = { { key = "dipPct", label = "Dip size" }, { key = "minSupply", label = "Min supply" } },
  disenchant = { { key = "minDisenchantProfit", label = "Min profit" }, { key = "minDisenchantPct", label = "Min profit %" } },
}

local function SettingDef(key)
  for _, group in ipairs(SETTING_GROUPS) do
    for _, def in ipairs(group.settings) do
      if def.key == key then return def end
    end
  end
end

-- A threshold changed: the list re-filters the last full scan from its top
local function Retune()
  ui.list.offset = 0
  ns.RefreshUI()
end

-- Puts a list's thresholds back to their defaults
function ui.ResetTune(view)
  for _, setting in ipairs(TUNE_SETTINGS[view]) do MarketWallDB.cfg[setting.key] = nil end
  Retune()
end

local function BuildResetLink(row, view)
  local link = CreateFrame("Button", nil, row)
  link:SetSize(34, TUNE_H)
  local text = MakeText(link, "GameFontNormalSmall")
  text:SetPoint("LEFT")
  text:SetText("Reset")
  link:SetScript("OnClick", function() ui.ResetTune(view) end)
  link:SetScript("OnEnter", function(self)
    text:SetTextColor(1, 1, 1)
    ShowTip(self, "Reset", "Puts this screen's values back to their defaults.")
  end)
  link:SetScript("OnLeave", function()
    text:SetTextColor(1, 0.82, 0)
    HideTip()
  end)
  return link
end

local function BuildTuneRow(parent, view)
  local row = CreateFrame("Frame", nil, parent)
  row:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
  row:SetPoint("RIGHT")
  row:SetHeight(TUNE_H)
  row.edits = {}
  local previous
  for _, setting in ipairs(TUNE_SETTINGS[view]) do
    local label = MakeText(row, "GameFontNormalSmall")
    if previous then label:SetPoint("LEFT", previous, "RIGHT", 18, 0) else label:SetPoint("LEFT", 12, 0) end
    label:SetText(setting.label)
    local def = SettingDef(setting.key)
    local edit = ui.SettingEdit(row, def, Retune)
    edit:SetPoint("LEFT", label, "RIGHT", 10, 0)
    row.edits[#row.edits + 1] = { def = def, edit = edit }
    previous = edit
  end
  local note = MakeText(row, "GameFontDisableSmall")
  note:SetPoint("LEFT", previous, "RIGHT", 18, 0)
  note:SetText("Applies to the last scan right away ·")
  BuildResetLink(row, view):SetPoint("LEFT", note, "RIGHT", 4, 0)
  return row
end

local function RefreshTune(row)
  for _, item in ipairs(row.edits) do
    if not item.edit:HasFocus() then item.edit:SetText(FormatSetting(item.def)) end
  end
end
ui.BuildTuneRow, ui.RefreshTune = BuildTuneRow, RefreshTune   -- for specs

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
  local isItem, isSettings, isSell, isBait, isCrafting = (view == "item"), (view == "settings"), (view == "sell"), (view == "bait"), (view == "crafting")
  local isList = not isItem and not isSettings and not isSell and not isBait and not isCrafting
  ui.item:SetShown(isItem)
  ui.settings:SetShown(isSettings)
  ui.sell:SetShown(isSell)
  ui.bait:SetShown(isBait)
  ui.crafting:SetShown(isCrafting)
  ui.list:SetShown(isList)
  for name, row in pairs(ui.tune) do row:SetShown(name == view) end
  ui.list:ClearAllPoints()
  ui.list:SetPoint("TOPLEFT", 0, -CONTENT_TOP - (ui.tune[view] and TUNE_H or 0))
  ui.list:SetPoint("RIGHT", -SCROLLBAR_W, 0)
  ui.footer:SetShown(view == "watch")
  ui.hint:SetShown(isList and view ~= "watch")   -- the watchlist's hint sits in its Add row
  for name, tab in pairs(ui.nav) do
    local backToList = isItem and name == ui.lastList
    SelectTab(tab, name == view or backToList)
    if backToList then tab:Enable() end   -- selecting disables a tab; this one leads back from the item page
  end
  ui.list.offset = 0
  ns.RefreshUI()
end

-- An empty list's message: a white headline, then grey detail under it
local function EmptyText(title, body)
  return ns.COLOR.VALUE .. title .. "|r" .. (body and ("\n" .. body) or "")
end
ns.widgets.EmptyText = EmptyText

-- Empty-list text: noneText after a full scan this session, else when to run one
function ui.WaitingText(noneText, neverText)
  if not ns.lastFullScan then
    local r = ns.R()
    if r.lastFull then return EmptyText("Results are from this session only.", "Run a full scan to refresh the list. Last full scan: " .. ns.Ago(r.lastFull) .. ".") end
    return EmptyText(neverText)
  end
  return EmptyText(noneText)
end

-- "1 snipe", "105 snipes"
local function Count(n, noun)
  return n .. " " .. noun .. (n == 1 and "" or "s")
end

-- A deal list's count for the status line: "41 of 103 snipes", or "103 snipes" when all pass
function ui.CountOf(shown, total, noun)
  if shown == total then return Count(total, noun) end
  return shown .. " of " .. Count(total, noun)
end

-- An empty deal list's message: that nothing passes the thresholds, or ui.WaitingText's
local function DealsEmptyText(total, noun, noneText, neverText)
  if total == 0 then return ui.WaitingText(noneText, neverText) end
  return EmptyText("No " .. noun .. "s pass these thresholds.",
    Count(total, noun) .. " in the last full scan; lower the values above to see them.")
end

-- note: the view's own part of the status line, such as its count
local function ListView(view, data, emptyText, hint, note)
  ApplySort(view, data)
  local sort = ui.sort[view]
  ui.list:SetColumns(COLUMNS[view], sort and sort.col, sort and sort.desc)
  ui.list:SetData(data, emptyText)
  ui.hint:SetText(hint)
  ui.statusNote = note
end

-- Why the Disenchant list is empty, and what the controls above it do about it. hidden: deals
-- that pass the thresholds but need more skill; total: the last full scan's deals before both.
function ui.DisenchantEmptyText(skill, hidden, total)
  if not ns.lastFullScan then
    return ui.WaitingText(nil, "Run a full scan to look for gear listed under its disenchant value.")
  end
  local title, body = "No disenchant deals in the last full scan.", {}
  if hidden > 0 then
    title = "No deals at your Enchanting skill."
  elseif total > 0 then
    title = "No deals pass these thresholds."
    body[1] = Count(total, "deal") .. " in the last full scan; lower the values above to see them."
  end
  if skill == 0 then body[#body + 1] = "Your Enchanting is 0, so only items you can't disenchant yet would show." end
  if hidden > 0 then body[#body + 1] = string.format("%s in the last scan need more skill; tick the box to see them.", Count(hidden, "deal")) end
  return EmptyText(title, #body > 0 and table.concat(body, "\n") or nil)
end

local function RefreshDisenchant()
  local data, skill, hidden = DisenchantData()
  local total = #ns.DisenchantDeals()
  -- the status line ends before the scan buttons, so its note stays short; the hint explains
  local skillNote = skill and ("Enchanting " .. ns.COLOR.VALUE .. skill .. "|r") or (WARN .. "Enchanting unknown|r")
  local hint = "Click a row to load live listings before buying."
  if not skill then hint = hint .. " Your Enchanting skill is unknown, so every item is shown." end
  ListView("disenchant", data, ui.DisenchantEmptyText(skill, hidden, total), hint,
    ui.CountOf(#data, total, "deal") .. " · " .. skillNote)
  ui.showAllBox:SetChecked(ns.Cfg("disenchantShowAll") and true or false)
end

local function RefreshWatch()
  local data = WatchData()
  ListView("watch", data,
    EmptyText("Your watchlist is empty.", "Add items you buy or sell often, and MarketWall tells you when to buy and when to sell."))
  ui.footer.hint:SetShown(#data > 0)
end

function ns.RefreshUI()
  ns.RefreshSearch()   -- the search window stands apart from the auction house
  if not ui.frame or not ui.frame:IsShown() then return end
  ui.statusNote = nil
  local view = ui.view
  if view == "item" then
    RefreshItem()
  elseif view == "settings" then
    RefreshSettings()
  elseif view == "sell" then
    ns.RefreshSell()
  elseif view == "bait" then
    ns.RefreshBait()
  elseif view == "crafting" then
    ui.crafting:Refresh()
  elseif view == "watch" then
    RefreshWatch()
  elseif view == "snipes" then
    local data = SnipeData()
    ListView("snipes", data,
      DealsEmptyText(#ns.snipes, "snipe", "No snipes in the last full scan.", "Run a full scan to look for listings priced under the wall."),
      "Click a row to load live listings before buying. " .. WARN .. "Orange days|r: little data, normal price may be off.",
      ui.CountOf(#data, #ns.snipes, "snipe"))
  elseif view == "dips" then
    local data = DipData()
    ListView("dips", data,
      DealsEmptyText(#ns.dips, "dip", "No dips in the last full scan.", "Run a full scan. Dips compare today's wall price with each item's own history."),
      "Items need a day of history before they can dip; items sliding for days are left out.",
      ui.CountOf(#data, #ns.dips, "dip"))
  elseif view == "disenchant" then
    RefreshDisenchant()
  end
  if ui.tune[view] then RefreshTune(ui.tune[view]) end
  ns.UpdateStatus()
end

-- The idle status line: "Full scan just now · Watchlist scan never · 105 snipes", grey with
-- the times in white. Bait Detect's list comes from full scans and its own live searches.
function ui.StatusLine()
  local r = ns.R()
  local function Value(text) return "|r" .. ns.COLOR.VALUE .. text .. "|r" .. GREY end
  local parts = { "Full scan " .. Value(ns.Ago(r.lastFull)) }
  if ui.view == "bait" then
    parts[1] = parts[1] .. ", updated by live searches"
  else
    parts[#parts + 1] = "Watchlist scan " .. Value(ns.Ago(r.lastWatch))
  end
  parts[#parts + 1] = ui.statusNote
  local text = GREY .. table.concat(parts, " · ") .. "|r"
  if not r.lastFull or ns.DayOf(r.lastFull) ~= ns.Today() then
    text = text .. GREY .. " · |r" .. WARN .. "No full scan yet today|r"
  end
  return text
end

-- Status line, progress bar and the Full scan button's cooldown
function ns.UpdateStatus()
  if not ui.status then return end
  local busy = ns.scanState.running or ns.fullScanRunning
  local text = ns.statusText
  if not busy and (not text or not ns.statusTime or GetTime() - ns.statusTime > 8) then
    text = ui.StatusLine()
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
    ui.fullButton:SetText(string.format("Full scan %d:%02d", math.floor(left / 60), left % 60))
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

  -- the tabs start right of the auction house portrait, which covers the frame's top-left corner
  ui.nav = MakeTabRow(f, PORTRAIT_CLEAR, TAB_BOTTOM, {
    { key = "watch", label = "Watchlist" }, { key = "snipes", label = "Snipes" }, { key = "dips", label = "Dips" },
    { key = "disenchant", label = "Disenchant" }, { key = "bait", label = "Bait Detect" }, { key = "sell", label = "Sell" },
    { key = "crafting", label = "Crafting" }, { key = "settings", label = "Settings" },
  }, ui.Show)

  ui.fullButton = MakeButton(f, "Full scan", 116)
  ui.fullButton:SetPoint("TOPRIGHT", -8, -SCAN_BUTTONS_TOP)
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

  -- status line with a progress bar behind it, ending before the scan buttons
  ui.bar = CreateFrame("StatusBar", nil, f)
  ui.bar:SetPoint("LEFT", f, "TOPLEFT", 8, -SCAN_BUTTONS_TOP - 11)
  ui.bar:SetPoint("RIGHT", scan, "LEFT", -8, 0)
  ui.bar:SetHeight(14)
  ui.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  ui.bar:SetStatusBarColor(0.96, 0.77, 0.09, 0.35)
  ui.bar:SetMinMaxValues(0, 1)
  ui.bar:Hide()
  ui.status = MakeText(f, "GameFontHighlightSmall", "LEFT")
  ui.status:SetPoint("LEFT", f, "TOPLEFT", 12, -SCAN_BUTTONS_TOP - 11)
  ui.status:SetPoint("RIGHT", scan, "LEFT", -12, 0)
  ui.status:SetWordWrap(false)

  ui.list = CreateList(f)
  ui.list:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
  ui.list:SetPoint("RIGHT", -SCROLLBAR_W, 0)
  ui.list:SetHeight(22 + ROWS * ROW_H)
  ui.list.onClick = function(entry) ui.ShowItem(entry.id) end
  ui.list.onHeader = HeaderClicked

  ui.hint = MakeText(f, "GameFontDisableSmall")
  ui.hint:SetPoint("TOPLEFT", ui.list, "BOTTOMLEFT", 8, -2)

  ui.footer = CreateFrame("Frame", nil, f)
  ui.footer:SetPoint("BOTTOMLEFT", 0, 4)
  ui.footer:SetPoint("BOTTOMRIGHT", 0, 4)
  ui.footer:SetHeight(26)
  local label = MakeText(ui.footer, "GameFontDisableSmall")
  label:SetPoint("LEFT", 12, 0)
  label:SetText("Add item")
  ui.addBox = MakeEdit(ui.footer, 360)
  ui.addBox:SetPoint("LEFT", label, "RIGHT", 12, 0)
  ui.addBox:SetScript("OnEnterPressed", AddFromBox)
  local placeholder = MakeText(ui.addBox, "GameFontDisableSmall")
  placeholder:SetPoint("LEFT", 2, 0)
  placeholder:SetText("Type a name or shift-click an item")
  local function UpdatePlaceholder(box) placeholder:SetShown(box:GetText() == "" and not box:HasFocus()) end
  for _, event in ipairs({ "OnTextChanged", "OnEditFocusGained", "OnEditFocusLost" }) do
    ui.addBox:HookScript(event, UpdatePlaceholder)   -- the template's own focus handling stays
  end
  local add = MakeButton(ui.footer, "Add", 60)
  add:SetPoint("LEFT", ui.addBox, "RIGHT", 6, 0)
  add:SetScript("OnClick", AddFromBox)
  ui.footer.hint = MakeText(ui.footer, "GameFontDisableSmall", "RIGHT")
  ui.footer.hint:SetPoint("RIGHT", -12, 0)
  ui.footer.hint:SetText("Click a row for its chart and listings.")

  ui.tune = {}
  for view in pairs(TUNE_SETTINGS) do ui.tune[view] = BuildTuneRow(f, view) end
  -- Disenchant's row ends with its skill filter
  local showAllLabel = MakeText(ui.tune.disenchant, "GameFontNormalSmall")
  showAllLabel:SetPoint("RIGHT", -12, 0)
  showAllLabel:SetText("Show items I can't disenchant yet")
  ui.showAllBox = CreateFrame("CheckButton", nil, ui.tune.disenchant, "UICheckButtonTemplate")
  ui.showAllBox:SetSize(24, 24)
  ui.showAllBox:SetPoint("RIGHT", showAllLabel, "LEFT", -2, 0)
  ui.showAllBox:SetScript("OnClick", function(self)
    MarketWallDB.cfg.disenchantShowAll = self:GetChecked() and true or false
    Retune()
  end)

  ui.item = BuildItemPage(f)
  ui.item:Hide()
  ui.settings = BuildSettings(f)
  ui.settings:Hide()
  ui.sell = ns.BuildSellPage(f)
  ui.sell:Hide()
  ui.bait = ns.BuildBaitPage(f)
  ui.bait:Hide()
  -- clicking a pattern opens its item page, which loads its live listings; buying stays a press
  ui.crafting = ns.CraftingView.Build(f, { top = -CONTENT_TOP, onPattern = ui.ShowItem })
  ui.crafting:Hide()

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
