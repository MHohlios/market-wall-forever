-- MarketWall: the Ledger view of the search window. Gold over time, and income and spending by
-- source for one week or month, for this character or all of them. Reads Ledger.lua's roll-ups.
local _, ns = ...
local Ledger = ns.Ledger

local L = {}
ns.LedgerView = L

local TABLE_ROWS, TABLE_WIDTH, CHART_HEIGHT, GUTTER = 9, 362, 110, 66
local GREY = "|cffa3acac"
local LAST = { other = 1, offline = 2 }   -- these sources list last, in this order
local TOTAL_TINT = { 0.96, 0.77, 0.09, 0.10 }

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

-- The books shown: this character's, or every character's
function L.Books(ledger, char, all)
  local books = {}
  if all then
    for _, book in pairs(ledger) do books[#books + 1] = book end
  elseif ledger[char] then
    books[1] = ledger[char]
  end
  return books
end

local FIELD = { week = "weeks", month = "months" }

-- The week (its first day) or month (yyyymm) a time falls in
function L.PeriodOf(kind, t)
  if kind == "week" then return Ledger.WeekOf(t) end
  return Ledger.MonthOf(t)
end

-- The period by periods after key, or before when by is negative
function L.Step(kind, key, by)
  if kind == "week" then return key + 7 * by end
  local months = math.floor(key / 100) * 12 + key % 100 - 1 + by
  return math.floor(months / 12) * 100 + months % 12 + 1
end

function L.PeriodStart(kind, key)
  if kind == "week" then return ns.DayStart(key) end
  return time({ year = math.floor(key / 100), month = key % 100, day = 1, hour = 0 })
end

function L.PeriodText(kind, key, now)
  if key == L.PeriodOf(kind, now) then return kind == "week" and "This week" or "This month" end
  if kind == "week" then return "Week of " .. date("%b %d", L.PeriodStart(kind, key)) end
  return date("%B %Y", L.PeriodStart(kind, key))
end

-- The books' income and spending by source in one period, added up
function L.Roll(books, kind, key)
  local sum = { income = {}, spending = {} }
  for _, book in ipairs(books) do
    local roll = book[FIELD[kind]][key]
    for side, sources in pairs(roll or {}) do
      for source, copper in pairs(sources) do sum[side][source] = (sum[side][source] or 0) + copper end
    end
  end
  return sum
end

-- Table rows for one side of a roll-up, largest first, then Other (always shown) and offline
-- changes, then the total: { { source, label, copper }, ... }
function L.Rows(side)
  local rows, total = {}, 0
  local amounts = { other = 0 }
  for source, copper in pairs(side) do amounts[source] = copper end
  for source, copper in pairs(amounts) do
    rows[#rows + 1] = { source = source, label = Ledger.LABELS[source] or source, copper = copper }
    total = total + copper
  end
  table.sort(rows, function(a, b)
    local x, y = LAST[a.source] or 0, LAST[b.source] or 0
    if x ~= y then return x < y end
    if a.copper ~= b.copper then return a.copper > b.copper end
    return a.label < b.label
  end)
  rows[#rows + 1] = { source = "total", label = "Total", copper = total }
  return rows
end

local function Net(roll)
  local net = 0
  for _, copper in pairs(roll and roll.income or {}) do net = net + copper end
  for _, copper in pairs(roll and roll.spending or {}) do net = net - copper end
  return net
end

-- The books' gold at the end of each period with a change, a point { t, w } each; t is the
-- period's end, or now for the current one. A book counts from the period it opened in.
function L.Balance(books, kind, now)
  local field, keys, seen = FIELD[kind], {}, {}
  for _, book in ipairs(books) do
    for key in pairs(book[field]) do
      if not seen[key] then seen[key] = true keys[#keys + 1] = key end
    end
  end
  table.sort(keys)
  local balances, series = {}, {}
  for _, key in ipairs(keys) do
    local total = 0
    for i, book in ipairs(books) do
      balances[i] = (balances[i] or book.opening[2]) + Net(book[field][key])
      if L.PeriodOf(kind, book.opening[1]) <= key then total = total + balances[i] end
    end
    series[#series + 1] = { t = math.min(now, L.PeriodStart(kind, L.Step(kind, key, 1))), w = total }
  end
  if #series == 0 and #books > 0 then
    local total = 0
    for _, book in ipairs(books) do total = total + book.opening[2] end
    series[1] = { t = now, w = total }
  end
  return series
end

-- The opening balance line
function L.OpeningText(books)
  if #books == 0 then return "" end
  local first, total = math.huge, 0
  for _, book in ipairs(books) do
    first = math.min(first, book.opening[1])
    total = total + book.opening[2]
  end
  local whose = #books == 1 and "Opening balance" or ("Opening balances of " .. #books .. " characters")
  return string.format("%s, recorded from %s: %s. Gold changes that can't be attributed go to Other, so the ledger always matches your gold.",
    whose, date("%b %d, %Y", first), ns.Money(total))
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local function Toggle(panel, previous, label, width, onClick)
  local button = ns.widgets.MakeButton(panel, label, width)
  if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 12, -34) end
  button:SetScript("OnClick", function()
    onClick()
    panel:Refresh()
  end)
  return button
end

local function Highlight(button, on)
  if on then button:LockHighlight() else button:UnlockHighlight() end
end

local function Table(panel, title, tip)
  local list = ns.widgets.CreateList(panel, TABLE_ROWS)
  list:SetSize(TABLE_WIDTH, ns.widgets.ListHeight(TABLE_ROWS))
  list.title, list.tip = title, tip
  return list
end

-- The Ledger panel, filling parent below the window heading
function L.Build(parent)
  local w = ns.widgets
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.all, panel.kind = false, "week"
  panel.period = nil   -- the period shown, nil for the current one

  panel.charButton = Toggle(panel, nil, "This character", 110, function() panel.all = false end)
  panel.allButton = Toggle(panel, panel.charButton, "All characters", 110, function() panel.all = true end)
  local function Kind(kind) return function() panel.kind, panel.period = kind, nil end end
  panel.weekButton = Toggle(panel, panel.allButton, "Week", 64, Kind("week"))
  panel.weekButton:SetPoint("LEFT", panel.allButton, "RIGHT", 16, 0)
  panel.monthButton = Toggle(panel, panel.weekButton, "Month", 64, Kind("month"))

  panel.nextButton = w.MakeButton(panel, ">", 28)
  panel.nextButton:SetPoint("TOPRIGHT", -16, -34)
  panel.periodText = w.MakeText(panel, "GameFontNormal", "CENTER")
  panel.periodText:SetPoint("RIGHT", panel.nextButton, "LEFT", -4, 0)
  panel.periodText:SetWidth(130)
  panel.prevButton = w.MakeButton(panel, "<", 28)
  panel.prevButton:SetPoint("RIGHT", panel.periodText, "LEFT", -4, 0)
  local function Move(by)
    return function()
      local current = L.PeriodOf(panel.kind, time())
      local key = L.Step(panel.kind, panel.period or current, by)
      panel.period = key < current and key or nil
      panel:Refresh()
    end
  end
  panel.prevButton:SetScript("OnClick", Move(-1))
  panel.nextButton:SetScript("OnClick", Move(1))

  panel.chart = w.CreateChart(panel)
  panel.chart:SetSize(736 - GUTTER, CHART_HEIGHT)
  panel.chart:SetPoint("TOPLEFT", 12 + GUTTER, -68)
  panel.chart.legend:Hide()

  panel.income = Table(panel, "Income", "Gold received, by where it came from.")
  panel.income:SetPoint("TOPLEFT", 12, -200)
  panel.spending = Table(panel, "Spending", "Gold spent, by what it went on.")
  panel.spending:SetPoint("TOPLEFT", 12 + TABLE_WIDTH + 12, -200)

  panel.opening = w.MakeText(panel, "GameFontDisableSmall")
  panel.opening:SetPoint("BOTTOMLEFT", 14, 12)
  panel.opening:SetPoint("RIGHT", -14, 0)
  panel.opening:SetWordWrap(true)

  local function Fill(list, side, periodText)
    list:SetColumns({ { list.title, 240, nil, list.tip }, { periodText, 122, "RIGHT", "Copper in the period shown." } })
    local data = {}
    for _, row in ipairs(L.Rows(side)) do
      local total = row.source == "total"
      data[#data + 1] = { cells = { row.label, ns.Money(row.copper) }, tint = total and TOTAL_TINT or nil }
    end
    list:SetData(data)
  end

  function panel:Refresh()
    Highlight(self.charButton, not self.all)
    Highlight(self.allButton, self.all)
    Highlight(self.weekButton, self.kind == "week")
    Highlight(self.monthButton, self.kind == "month")
    local now = time()
    local key = self.period or L.PeriodOf(self.kind, now)
    self.nextButton:SetEnabled(self.period ~= nil)
    local periodText = L.PeriodText(self.kind, key, now)
    self.periodText:SetText(periodText)

    local books = L.Books(MarketWallDB.ledger, ns.Recording.CharacterKey(), self.all)
    self.chart:SetShown(#books > 0)
    self.chart:Draw(L.Balance(books, self.kind, now))
    local roll = L.Roll(books, self.kind, key)
    Fill(self.income, roll.income, periodText)
    Fill(self.spending, roll.spending, periodText)
    self.opening:SetText(#books > 0 and L.OpeningText(books)
      or (GREY .. "No gold recorded yet. The ledger opens with this character's gold at its next login.|r"))
  end

  ns.Recording.On("money", ns.SearchChanged)
  return panel
end
