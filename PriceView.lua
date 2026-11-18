-- MarketWall: an item's price chart and stats grid, shared by the Sell page and the search window.
-- Each page picks its grid cells by name, and whether its chart gets the 7 days / 30 days / all switch.
local _, ns = ...
local W = ns.Wall

local PV = {}
ns.PriceView = PV

local DAY = 86400
PV.FLAT = 0.03   -- moves within 3% count as flat
local BLUE, ORANGE, GREY = "|cff7cc0ff", "|cffffb057", "|cffa3acac"

PV.RANGES = { { days = 7, label = "7 days" }, { days = 30, label = "30 days" }, { label = "All" } }

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

-- The points of a series from the last `days` days before `now`; all of them when days is nil
function PV.InRange(series, days, now)
  if not days then return series end
  local from, out = now - days * DAY, {}
  for _, point in ipairs(series) do
    if point.t >= from then out[#out + 1] = point end
  end
  return out
end

-- Average, low, high and trend of the wall over a run of points
function PV.WeekSummary(points)
  if #points == 0 then return nil end
  local sum, lo, hi = 0, math.huge, 0
  for _, p in ipairs(points) do
    sum = sum + p.w
    lo, hi = math.min(lo, p.w), math.max(hi, p.w)
  end
  local trend = #points >= 2 and (points[#points].w / points[1].w - 1) or nil
  return { average = sum / #points, low = lo, high = hi, trend = trend }
end

function PV.TrendText(diff)
  local pct = math.abs(ns.Round(diff * 100)) .. "%"
  local limit = PV.FLAT + 1e-9   -- absorbs float error, so a change of exactly 3% (1000 to 1030) is flat
  if diff < -limit then return BLUE .. "down " .. pct .. "|r" end
  if diff > limit then return ORANGE .. "up " .. pct .. "|r" end
  return "flat"
end

-- Wall and lowest price from the latest listings MarketWall has loaded this session
function PV.LiveWall(id)
  local held = ns.ladders[id]
  if not held or held.total == 0 then return nil end
  return W.Compute(held.ladder, held.total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits"))
end

-- Everything the grid cells read about one item
function PV.Facts(id, now)
  local live, lowest = PV.LiveWall(id)
  local last, lastDay = ns.LatestWall(id)
  local series = ns.Series(id)
  return {
    id = id, now = now, held = ns.ladders[id], live = live, lowest = lowest, last = last, lastDay = lastDay,
    stats = ns.StatsFor(id), series = series, week = PV.WeekSummary(PV.InRange(series, 7, now)),
    history = ns.WallHistory(id), entry = ns.R().watch[id],
  }
end

local function DaysAgo(day)
  local age = ns.Today() - day
  return (age == 0 and "today") or (age == 1 and "yesterday") or (age .. " days ago")
end

-- Grid cells by name: each returns its label and its value, nil when there is nothing to show
PV.CELLS = {
  wallNow = function(f)
    if f.live then return "Wall now (" .. ns.Ago(f.held.t) .. ")", ns.Money(f.live) end
    return "Wall (last scan)", f.last and ns.Money(f.last)
  end,
  lastWall = function(f)
    if f.live then return "Last wall (" .. ns.Ago(f.held.t) .. ")", ns.Money(f.live) end
    if f.last then return "Last wall (" .. DaysAgo(f.lastDay) .. ")", ns.Money(f.last) end
    return "Last wall", nil
  end,
  lowestListing = function(f) return "Lowest listing", f.lowest and ns.Money(f.lowest) end,
  supply = function(f) return "Supply", f.held and f.held.total > 0 and (f.held.total .. " units") or nil end,
  trend = function(f) return "7-day trend", f.week and f.week.trend and PV.TrendText(f.week.trend) end,
  average = function(f) return "7-day average", f.week and ns.Money(f.week.average) end,
  median = function(f)
    return "Median (" .. f.stats.n .. " days)", f.stats.n >= 3 and ns.Money(f.stats.median) or nil
  end,
  normalRange = function(f)
    return "Normal range", f.stats.n >= 3 and (ns.Money(f.stats.p25) .. " - " .. ns.Money(f.stats.p75)) or nil
  end,
  versusMedian = function(f)
    local diff, word = ns.Versus(f.live or f.last, f.stats)
    return "Vs median", diff and ns.VersusText(diff, word)
  end,
  lowHigh = function(f)
    local h = f.history
    return "Lowest / highest", h.low and (ns.Money(h.low) .. " / " .. ns.Money(h.high))
  end,
  days = function(f) return "Days of data", f.history.days > 0 and tostring(f.history.days) or nil end,
  vendor = function(f)
    local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(f.id))
    return "Vendor", vendor and vendor > 0 and ns.Money(vendor) or nil
  end,
  disenchant = function(f)
    local value = ns.DisenchantValue(f.id)
    if value == false then return "Disenchant", GREY .. "not scanned|r" end
    return "Disenchant", value and ns.Money(value)
  end,
  limits = function(f)
    local e = f.entry
    return "Your buy / sell", e and (e.buy or e.sell) and (ns.Money(e.buy) .. " / " .. ns.Money(e.sell)) or nil
  end,
}

-- Label and value text for each named cell
function PV.Cells(facts, keys)
  local out = {}
  for i, key in ipairs(keys) do
    local label, value = PV.CELLS[key](facts)
    out[i] = { label = GREY .. label .. "|r", value = value or GREY .. "-|r" }
  end
  return out
end

-------------------------------------------------------------------------------
-- Widget
-------------------------------------------------------------------------------

local GUTTER, COLUMNS, ROW_HEIGHT = 66, 4, 34

-- layout: width, chartHeight, cellWidth, cells (names), ranges (true adds the range switch)
function PV.CreateView(parent, layout)
  local w = ns.widgets
  local view = CreateFrame("Frame", nil, parent)
  view:SetWidth(layout.width)
  view.days = PV.RANGES[1].days

  local chartTop = -6
  if layout.ranges then
    chartTop = -34
    view.rangeButtons = {}
    local previous
    for i = #PV.RANGES, 1, -1 do
      local range = PV.RANGES[i]
      local button = w.MakeButton(view, range.label, 64)
      if previous then button:SetPoint("RIGHT", previous, "LEFT", -4, 0) else button:SetPoint("TOPRIGHT", 0, -2) end
      button:SetScript("OnClick", function()
        view.days = range.days
        view:Redraw()
      end)
      view.rangeButtons[i] = button
      previous = button
    end
  end

  view.chart = w.CreateChart(view)
  view.chart:SetSize(layout.width - GUTTER, layout.chartHeight)
  view.chart:SetPoint("TOPLEFT", GUTTER, chartTop)
  view.chart.legend:Hide()   -- too wide here; the numbers below describe the lines

  local gridTop = chartTop - layout.chartHeight - 22
  view.cells = {}
  for i = 1, #layout.cells do
    local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
    local label = w.MakeText(view, "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", col * layout.cellWidth, gridTop - row * ROW_HEIGHT)
    label:SetWidth(layout.cellWidth - 4)
    label:SetWordWrap(false)
    local value = w.MakeText(view, "GameFontHighlight")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
    value:SetWidth(layout.cellWidth - 4)
    value:SetWordWrap(false)
    view.cells[i] = { label = label, value = value }
  end
  view:SetHeight(-gridTop + math.ceil(#layout.cells / COLUMNS) * ROW_HEIGHT)

  -- Draw an item, with optional buy and sell lines on the chart
  function view:SetItem(id, buy, sell)
    self.id, self.buy, self.sell = id, buy, sell
    self:Redraw()
  end

  function view:Redraw()
    if not self.id then return end
    local facts = PV.Facts(self.id, time())
    self.chart:Draw(PV.InRange(facts.series, self.days, facts.now), self.buy, self.sell, facts.stats)
    for i, cell in ipairs(PV.Cells(facts, layout.cells)) do
      self.cells[i].label:SetText(cell.label)
      self.cells[i].value:SetText(cell.value)
    end
    for i, button in pairs(self.rangeButtons or {}) do
      if PV.RANGES[i].days == self.days then button:LockHighlight() else button:UnlockHighlight() end
    end
  end

  return view
end
