-- MarketWall: the Ledger view of the search window. For one week or month, for this character
-- or all of them: income, spending and net, each day's net gold as a bar, and income and
-- spending by source. Reads Ledger.lua's roll-ups, and its raw entries for the daily bars.
local _, ns = ...
local Ledger = ns.Ledger

local L = {}
ns.LedgerView = L

local TABLE_ROWS, TABLE_WIDTH, BARS_HEIGHT, BAR_GAP = 8, 362, 56, 4
local GREY, WARN, GAIN, LOSS = ns.COLOR.GREY, ns.COLOR.WARN, ns.COLOR.GAIN, ns.COLOR.LOSS
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

-- Table rows for one side of a roll-up, largest first, then Other and Unrecorded (gold that
-- changed while MarketWall wasn't running), then the total: { { source, label, copper }, ... }.
-- Sources with nothing in the period are left out.
function L.Rows(side)
  local rows, total = {}, 0
  for source, copper in pairs(side) do
    if copper ~= 0 then
      rows[#rows + 1] = { source = source, label = Ledger.LABELS[source] or source, copper = copper }
      total = total + copper
    end
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

local function Sum(side)
  local total = 0
  for _, copper in pairs(side) do total = total + copper end
  return total
end

-- The summary of a roll-up: income, spending, net and the unrecorded part of spending
function L.Summary(roll)
  local income, spending = Sum(roll.income), Sum(roll.spending)
  return { income = income, spending = spending, net = income - spending, unrecorded = roll.spending.offline or 0 }
end

-- The orange note beside the summary, nil when no spending is unrecorded
function L.UnrecordedText(summary)
  if summary.unrecorded <= 0 then return nil end
  return WARN .. ns.MoneyShort(summary.unrecorded) .. " of spending is unrecorded|r" .. GREY
    .. ": gold that changed while MarketWall wasn't running.|r"
end

-- Net gold of each day in the period, from the books' raw entries: { { day =, net = }, ... } in
-- day order, a day with no change at 0. Raw entries are kept Ledger.KEEP_DAYS, so a day older
-- than that has net nil, unknown rather than 0.
function L.Days(books, kind, key, now)
  local function Midday(period) return ns.DayOf(L.PeriodStart(kind, period) + 43200) end   -- clear of clock changes
  local first = Midday(key)
  local count = Midday(L.Step(kind, key, 1)) - first
  local kept = ns.DayOf(now) - Ledger.KEEP_DAYS
  local days = {}
  for i = 1, count do days[i] = { day = first + i - 1, net = first + i - 1 >= kept and 0 or nil } end
  for _, book in ipairs(books) do
    for _, entry in ipairs(book.entries) do
      local day = days[ns.DayOf(entry[1]) - first + 1]
      if day and day.net then day.net = day.net + entry[2] end
    end
  end
  return days
end

-- A day bar's label: the weekday in a week, every fifth date and the first in a month
function L.DayLabel(kind, day)
  local t = ns.DayStart(day) + 43200
  if kind == "week" then return date("%a", t) end
  local n = tonumber(date("%d", t))
  if n == 1 or n % 5 == 0 then return tostring(n) end
  return ""
end

-- The line under the tables: the opening balance and when recording began
function L.OpeningText(books)
  if #books == 0 then return "" end
  local first, total = math.huge, 0
  for _, book in ipairs(books) do
    first = math.min(first, book.opening[1])
    total = total + book.opening[2]
  end
  local whose = #books == 1 and "Opening balance" or ("Opening balances of " .. #books .. " characters")
  return string.format("%s %s, recorded from %s.", whose, ns.Money(total), date("%b %d, %Y", first))
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local function Table(panel, title, tip)
  local list = ns.widgets.CreateList(panel, TABLE_ROWS)
  list:SetSize(TABLE_WIDTH, ns.widgets.ListHeight(TABLE_ROWS))
  list.title, list.tip = title, tip
  return list
end

-- One summary figure: a gold label over a large value
local function Figure(panel, x, label)
  local w = ns.widgets
  local key = w.MakeText(panel, "GameFontNormalSmall")
  key:SetPoint("TOPLEFT", x, -64)
  key:SetText(label)
  local value = w.MakeText(panel, "GameFontHighlightLarge")
  value:SetPoint("TOPLEFT", key, "BOTTOMLEFT", 0, -3)
  return value
end

-- Each day's net gold as a bar from the baseline: green for a gain, red for a loss, today
-- outlined in gold. Bars are scaled to the period's largest day, so one day of data fills it.
local function CreateBars(parent, width)
  local bars = CreateFrame("Frame", nil, parent)
  bars:SetSize(width, BARS_HEIGHT)
  local base = bars:CreateTexture(nil, "BORDER")
  base:SetColorTexture(1, 1, 1, 0.2)
  base:SetHeight(1)
  base:SetPoint("BOTTOMLEFT")
  base:SetPoint("BOTTOMRIGHT")
  bars.bars, bars.labels = {}, {}
  bars.outline = {}
  for i = 1, 4 do
    bars.outline[i] = bars:CreateTexture(nil, "OVERLAY")
    bars.outline[i]:SetColorTexture(1, 0.82, 0, 0.9)
  end

  local function Outline(bar)
    local top, bottom, left, right = unpack(bars.outline)
    top:ClearAllPoints() top:SetHeight(1)
    top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -1, 0) top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 1, 0)
    bottom:ClearAllPoints() bottom:SetHeight(1)
    bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -1, 0) bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 1, 0)
    left:ClearAllPoints() left:SetWidth(1)
    left:SetPoint("TOPRIGHT", bar, "TOPLEFT", 0, 1) left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", 0, -1)
    right:ClearAllPoints() right:SetWidth(1)
    right:SetPoint("TOPLEFT", bar, "TOPRIGHT", 0, 1) right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", 0, -1)
  end

  bars.note = ns.widgets.MakeText(bars, "GameFontDisableSmall", "CENTER")
  bars.note:SetPoint("CENTER")
  bars.note:SetText(string.format("Daily detail is kept for %d days.", Ledger.KEEP_DAYS))

  -- days: L.Days; today: the day to outline; kind: week or month, for the labels. A day with
  -- no detail left has no bar, and the note says why.
  function bars:Draw(days, today, kind)
    local most, unknown = 0, false
    for _, day in ipairs(days) do
      if day.net then most = math.max(most, math.abs(day.net)) else unknown = true end
    end
    self.note:SetShown(unknown)
    local slot = width / math.max(1, #days)
    local outlined = false
    for i = 1, math.max(#days, #self.bars) do
      local day = days[i]
      local bar, label = self.bars[i], self.labels[i]
      if not bar then
        bar = self:CreateTexture(nil, "ARTWORK")
        label = ns.widgets.MakeText(self, "GameFontDisableSmall", "CENTER")
        self.bars[i], self.labels[i] = bar, label
      end
      bar:SetShown(day ~= nil and day.net ~= nil)
      label:SetShown(day ~= nil)
      if day and not day.net then
        label:ClearAllPoints()
        label:SetPoint("TOP", self, "BOTTOMLEFT", (i - 0.5) * slot, -3)
        label:SetText(L.DayLabel(kind, day.day))
      elseif day then
        local height = most > 0 and math.max(1, math.abs(day.net) / most * (BARS_HEIGHT - 2)) or 1
        if day.net < 0 then bar:SetColorTexture(0.88, 0.38, 0.38, 0.8) else bar:SetColorTexture(0.31, 0.76, 0.42, 0.8) end
        bar:ClearAllPoints()
        bar:SetPoint("BOTTOMLEFT", (i - 1) * slot + BAR_GAP / 2, 1)
        bar:SetSize(math.max(1, slot - BAR_GAP), height)
        label:ClearAllPoints()
        label:SetPoint("TOP", bar, "BOTTOM", 0, -3)
        label:SetText(L.DayLabel(kind, day.day))
        if day.day == today then
          Outline(bar)
          outlined = true
        end
      end
    end
    for _, edge in ipairs(self.outline) do edge:SetShown(outlined) end
  end
  return bars
end

-- The Ledger panel, filling parent below the window heading
function L.Build(parent)
  local w = ns.widgets
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.all, panel.kind = false, "week"
  panel.period = nil   -- the period shown, nil for the current one

  panel.whose = w.MakeSwitch(panel, { { key = false, label = "This character" }, { key = true, label = "All characters" } },
    function(all)
      panel.all = all
      panel:Refresh()
    end)
  panel.whose:SetPoint("TOPLEFT", 12, -36)
  panel.kindSwitch = w.MakeSwitch(panel, { { key = "week", label = "Week" }, { key = "month", label = "Month" } },
    function(kind)
      panel.kind, panel.period = kind, nil
      panel:Refresh()
    end)
  panel.kindSwitch:SetPoint("LEFT", panel.whose, "RIGHT", 16, 0)

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

  panel.incomeText = Figure(panel, 14, "Income")
  panel.spendingText = Figure(panel, 150, "Spending")
  panel.netText = Figure(panel, 286, "Net")
  panel.unrecorded = w.MakeText(panel, "GameFontHighlightSmall")
  panel.unrecorded:SetPoint("TOPLEFT", 422, -70)
  panel.unrecorded:SetPoint("RIGHT", -16, 0)
  panel.unrecorded:SetWordWrap(true)

  panel.bars = CreateBars(panel, 732)
  panel.bars:SetPoint("TOPLEFT", 14, -106)

  panel.income = Table(panel, "Income", "Gold received, by where it came from.")
  panel.income:SetPoint("TOPLEFT", 12, -190)
  panel.spending = Table(panel, "Spending", "Gold spent, by what it went on. Unrecorded is gold that changed while MarketWall wasn't running.")
  panel.spending:SetPoint("TOPLEFT", 12 + TABLE_WIDTH + 12, -190)

  panel.opening = w.MakeText(panel, "GameFontDisableSmall")
  panel.opening:SetPoint("BOTTOMLEFT", 14, 12)
  panel.opening:SetPoint("RIGHT", -14, 0)

  -- The total is green for income and red for spending; Unrecorded is orange. A coloured amount
  -- is text, so the row's hover gives its exact value.
  local function Fill(list, side, totalColor)
    list:SetColumns({ { list.title, 240, nil, list.tip }, { "", 122, "RIGHT", "Copper in the period shown.", money = true } })
    local data = {}
    for _, row in ipairs(L.Rows(side)) do
      local total, unrecorded = row.source == "total", row.source == "offline"
      local color = (total and totalColor) or (unrecorded and WARN)
      data[#data + 1] = {
        cells = { unrecorded and (WARN .. row.label .. "|r") or row.label,
          color and (color .. ns.MoneyShort(row.copper) .. "|r") or row.copper },
        tip = color and ns.Money(row.copper) or nil,
        tint = total and TOTAL_TINT or nil,
      }
    end
    list:SetData(data)
  end

  function panel:Refresh()
    self.whose:Select(self.all)
    self.kindSwitch:Select(self.kind)
    local now = time()
    local key = self.period or L.PeriodOf(self.kind, now)
    self.nextButton:SetEnabled(self.period ~= nil)
    self.periodText:SetText(L.PeriodText(self.kind, key, now))

    local books = L.Books(MarketWallDB.ledger, ns.Recording.CharacterKey(), self.all)
    local roll = L.Roll(books, self.kind, key)
    local summary = L.Summary(roll)
    self.incomeText:SetText(GAIN .. ns.MoneyShort(summary.income) .. "|r")
    self.spendingText:SetText(LOSS .. ns.MoneyShort(summary.spending) .. "|r")
    self.netText:SetText((summary.net < 0 and "-" or "") .. ns.MoneyShort(math.abs(summary.net)))
    self.unrecorded:SetText(L.UnrecordedText(summary) or "")
    self.bars:SetShown(#books > 0)
    self.bars:Draw(L.Days(books, self.kind, key, now),ns.DayOf(now), self.kind)
    Fill(self.income, roll.income, GAIN)
    Fill(self.spending, roll.spending, LOSS)
    self.opening:SetText(#books > 0 and L.OpeningText(books)
      or (GREY .. "No gold recorded yet. The ledger opens with this character's gold at its next login.|r"))
  end

  ns.Recording.On("money", ns.SearchChanged)
  return panel
end
