-- MarketWall: an item's price chart and stats block, shared by the Sell page and the search window.
-- Under the chart: a row of large stats, each shown only when it has a value, and one grey line
-- summarizing the range the chart's 7 days / 30 days / All switch picks.
local _, ns = ...
local W = ns.Wall

local PV = {}
ns.PriceView = PV

local DAY = 86400
PV.FLAT = 0.03   -- moves within 3% count as flat
local WARN, GREY, LABEL = ns.COLOR.WARN, ns.COLOR.GREY, ns.COLOR.LABEL
-- Trend arrows as icons: the game's fonts have no arrow characters
PV.UP, PV.DOWN = "|TInterface\\Buttons\\Arrow-Up-Up:0:0|t", "|TInterface\\Buttons\\Arrow-Down-Up:0:0|t"

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

-- Count, average, median, low, high and trend of the wall over a run of points, and when it starts
function PV.Summary(points)
  if #points == 0 then return nil end
  local sum, walls = 0, {}
  for i, p in ipairs(points) do
    sum = sum + p.w
    walls[i] = p.w
  end
  table.sort(walls)
  local trend = #points >= 2 and (points[#points].w / points[1].w - 1) or nil
  return {
    n = #points, average = sum / #points, median = W.Percentile(walls, 0.5), low = walls[1], high = walls[#walls],
    trend = trend, from = points[1].t,
  }
end

function PV.TrendText(diff)
  local pct = math.abs(ns.Round(diff * 100)) .. "%"
  local limit = PV.FLAT + 1e-9   -- absorbs float error, so a change of exactly 3% (1000 to 1030) is flat
  if diff < -limit then return PV.DOWN .. " " .. pct end
  if diff > limit then return PV.UP .. " " .. pct end
  return "flat"
end

-- Wall and lowest price from the latest listings MarketWall has loaded this session
function PV.LiveWall(id)
  local held = ns.ladders[id]
  if not held or held.total == 0 then return nil end
  return W.Compute(held.ladder, held.total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits"))
end

-- Everything the stats read about one item. With a chart range (an entry of PV.RANGES),
-- `chart` holds the full history's points in that range and `range` summarizes them.
function PV.Facts(id, now, range)
  local live = PV.LiveWall(id)
  local last, lastDay = ns.LatestWall(id)
  local series = ns.Series(id)
  local facts = {
    id = id, now = now, held = ns.ladders[id], live = live, last = last, lastDay = lastDay,
    stats = ns.StatsFor(id), series = series, week = PV.Summary(PV.InRange(series, 7, now)), entry = ns.R().watch[id],
  }
  if range then
    facts.chart = PV.InRange(ns.Series(id, true), range.days, now)
    facts.range = PV.Summary(facts.chart)
  end
  return facts
end

local function DaysAgo(day)
  local age = ns.Today() - day
  return (age == 0 and "Today") or (age == 1 and "Yesterday") or (age .. " days ago")
end

local function Plural(n, word) return n .. " " .. word .. (n == 1 and "" or "s") end

-- The large stats in order: each returns its label and its value, nil when it has no value
local STATS = {
  function(f)
    if f.live then return "Now", ns.Money(f.live) end
    if f.last then return DaysAgo(f.lastDay), ns.Money(f.last) end
  end,
  -- compact, so a gold range fits
  function(f)
    if f.stats.n > 0 then return "Normal range", ns.MoneyShort(f.stats.p25) .. " – " .. ns.MoneyShort(f.stats.p75) end
  end,
  function(f)
    if f.stats.n > 0 then return "Median", ns.Money(f.stats.median) end
  end,
  function(f)
    if f.week and f.week.trend then return "7-day trend", PV.TrendText(f.week.trend) end
  end,
  function(f)
    local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(f.id))
    if vendor and vendor > 0 then return "Vendor", ns.Money(vendor) end
  end,
  function(f)
    local value = ns.DisenchantValue(f.id)   -- false while its materials are not scanned
    if value then return "Disenchant", ns.Money(value) end
  end,
  function(f)
    local e = f.entry
    if e and (e.buy or e.sell) then return "Your buy / sell", ns.Money(e.buy) .. " / " .. ns.Money(e.sell) end
  end,
}

-- The large stats that have a value: { label, value }, in a fixed order
function PV.Stats(facts)
  local out = {}
  for _, stat in ipairs(STATS) do
    local label, value = stat(facts)
    if label then out[#out + 1] = { label = label, value = value } end
  end
  return out
end

-- One grey line about the chart's range: "Min · Max · Average · N points over N days", or nil
-- for a range with no points
function PV.RangeLine(facts)
  local r = facts.range
  if not r then return nil end
  local days = ns.DayOf(facts.now) - ns.DayOf(r.from) + 1
  return GREY .. string.format("Min %s · Max %s · Average %s · %s over %s",
    ns.MoneyFaded(r.low), ns.MoneyFaded(r.high), ns.MoneyFaded(r.average), Plural(r.n, "point"), Plural(days, "day")) .. "|r"
end

-------------------------------------------------------------------------------
-- Widget
-------------------------------------------------------------------------------

local GUTTER = 66                   -- the chart's price labels, left of it
local AXIS_HEIGHT = 22              -- the chart's date labels, under it
local FLAG_HEIGHT, STAT_HEIGHT, STAT_GAP, LINE_HEIGHT = 16, 34, 18, 16

-- Lays the stats out left to right in container, starting a new row when one would pass width.
-- cells grows to hold them; the unused ones hide. Returns the number of rows.
local function PlaceStats(container, cells, stats, width)
  local x, row = 0, 0
  for i, stat in ipairs(stats) do
    local cell = cells[i]
    if not cell then
      cell = { label = ns.widgets.MakeText(container, "GameFontNormalSmall"), value = ns.widgets.MakeText(container, "GameFontHighlight") }
      cell.value:SetPoint("TOPLEFT", cell.label, "BOTTOMLEFT", 0, -3)
      cells[i] = cell
    end
    cell.label:SetText(LABEL .. stat.label .. "|r")
    cell.value:SetText(stat.value)
    local cellWidth = math.max(cell.label:GetStringWidth(), cell.value:GetStringWidth())
    if x > 0 and x + cellWidth > width then x, row = 0, row + 1 end
    cell.label:ClearAllPoints()
    cell.label:SetPoint("TOPLEFT", x, -row * STAT_HEIGHT)
    cell.label:Show()
    cell.value:Show()
    x = x + cellWidth + STAT_GAP
  end
  for i = #stats + 1, #cells do
    cells[i].label:Hide()
    cells[i].value:Hide()
  end
  return #stats > 0 and row + 1 or 0
end

-- layout: width; chartHeight for a fixed chart, the view's height then following the stats, or
-- height for a fixed view whose chart takes what the stats leave; ranges (true adds the range
-- switch); placeRanges(switch), to anchor the switch outside the view rather than over the chart
function PV.CreateView(parent, layout)
  local w = ns.widgets
  local view = CreateFrame("Frame", nil, parent)
  view:SetSize(layout.width, layout.height or 1)
  view.range = PV.RANGES[1]

  local chartTop = -6
  if layout.ranges then
    local options = {}
    for i, range in ipairs(PV.RANGES) do options[i] = { key = i, label = range.label } end
    view.ranges = w.MakeSwitch(view, options, function(i)
      view.range = PV.RANGES[i]
      view:Redraw()
    end)
    view.ranges:Select(1)
    if layout.placeRanges then
      layout.placeRanges(view.ranges)
    else
      view.ranges:SetPoint("TOPRIGHT", 0, -2)
      chartTop = -24
    end
  end

  view.chart = w.CreateChart(view)
  view.chart:SetSize(layout.width - GUTTER, layout.chartHeight or 1)
  view.chart:SetPoint("TOPLEFT", GUTTER, chartTop)
  view.chart.legend:Hide()   -- too wide here; the numbers below describe the lines

  view.flag = w.MakeText(view, "GameFontHighlightSmall")
  view.flag:SetWidth(layout.width)
  view.flag:SetWordWrap(false)
  local statsWidth = layout.width - GUTTER
  view.stats = CreateFrame("Frame", nil, view)
  view.stats:SetSize(statsWidth, 1)
  view.cells = {}
  view.rangeLine = w.MakeText(view, "GameFontHighlightSmall")
  view.rangeLine:SetWidth(statsWidth)
  view.rangeLine:SetWordWrap(false)

  function view:SetItem(id, buy, sell)
    self.id, self.buy, self.sell = id, buy, sell
    self:Redraw()
  end

  -- Stack the chart, the low-data flag, the stats rows and the range line from the top
  local function Arrange(self, flagShown, rows)
    local below = AXIS_HEIGHT + (flagShown and FLAG_HEIGHT or 0) + rows * STAT_HEIGHT + LINE_HEIGHT
    local chartHeight = layout.chartHeight or (layout.height + chartTop - below)
    self.chart:SetHeight(chartHeight)
    local y = chartTop - chartHeight - AXIS_HEIGHT
    self.flag:ClearAllPoints()
    self.flag:SetPoint("TOPLEFT", 0, y)
    if flagShown then y = y - FLAG_HEIGHT end
    self.stats:ClearAllPoints()
    self.stats:SetPoint("TOPLEFT", GUTTER, y)
    y = y - rows * STAT_HEIGHT
    self.rangeLine:ClearAllPoints()
    self.rangeLine:SetPoint("TOPLEFT", GUTTER, y)
    if not layout.height then self:SetHeight(-y + LINE_HEIGHT) end
  end
  Arrange(view, false, 1)

  function view:Redraw()
    if not self.id then return end
    -- the range switch reaches back past the snapshots into the daily and weekly history
    local facts = PV.Facts(self.id, time(), layout.ranges and self.range)
    local flag = ns.LowDataText(ns.DaysOfData(self.id))
    self.flag:SetText(flag and WARN .. flag .. "|r" or "")
    self.rangeLine:SetText(PV.RangeLine(facts) or "")
    Arrange(self, flag ~= nil, PlaceStats(self.stats, self.cells, PV.Stats(facts), statsWidth))
    self.chart:Draw(facts.chart or PV.InRange(facts.series, self.range.days, facts.now), self.buy, self.sell, facts.stats)
  end

  return view
end
