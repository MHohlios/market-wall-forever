-- MarketWall: recording and reading history
local _, ns = ...
local W = ns.Wall
local B = ns.Bait

ns.ladders = {}   -- [itemID] = { ladder=, total=, t=, kind=, auctions= } session only
ns.snipes = {}    -- last full scan results
ns.dips = {}
ns.disenchants = {}

local D_WALL, D_LOW, D_HIGH, D_UNITS, D_MIN, D_PARTS = 1, 2, 3, 4, 5, 6
local ORANGE, GREY = "|cffffb057", "|cffa3acac"

ns.PART_NAMES = { "Night", "Morning", "Afternoon", "Evening" }   -- 0-6, 6-12, 12-18, 18-24 local time
ns.WDAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local cycleCache = {}

local function PartOf(t)
  local hour = tonumber(date("%H", t)) or 0
  return math.floor(hour / 6) + 1
end
ns.PartOf = PartOf

function ns.IsWatched(id)
  return ns.R().watch[id] ~= nil
end

function ns.Watch(id)
  local r = ns.R()
  if r.watch[id] then return end
  local entry = { added = time() }
  local cur = ns.ladders[id]
  local wall
  if cur then wall = W.Compute(cur.ladder, cur.total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits")) end
  if not wall then
    local today = r.days[id] and r.days[id][ns.Today()]
    wall = today and today[D_WALL]
  end
  entry.buy, entry.sell = W.Suggest(wall, ns.StatsFor(id), ns.Cfg("ahCut"))
  r.watch[id] = entry
  if ns.RefreshUI then ns.RefreshUI() end
end

function ns.Unwatch(id)
  local r = ns.R()
  r.watch[id] = nil
  r.snaps[id] = nil
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Chronological list of past daily walls within the baseline window, today excluded
function ns.DayWalls(id)
  local r = ns.R()
  local days = r.days[id]
  local out = {}
  if not days then return out end
  local today = ns.Today()
  local from = today - ns.Cfg("baselineDays")
  local keys = {}
  for day in pairs(days) do
    if day < today and day >= from then keys[#keys + 1] = day end
  end
  table.sort(keys)
  for i = 1, #keys do out[i] = days[keys[i]][D_WALL] end
  return out
end

local function TodayWall(id)
  local days = ns.R().days[id]
  local today = days and days[ns.Today()]
  return today and today[D_WALL]
end

-- Stats over past days; on an item's first day, over today's wall (see W.Stats)
function ns.StatsFor(id)
  return W.Stats(ns.DayWalls(id), TodayWall(id))
end

-- Days of data behind an item's numbers: past days in the baseline window, plus today
function ns.DaysOfData(id)
  return #ns.DayWalls(id) + (TodayWall(id) and 1 or 0)
end

-- "Days before data is reliable", held to 1 through one day past the baseline window, the most
-- days of data an item can have
function ns.ReliableDaysMax()
  return ns.Cfg("baselineDays") + 1
end

function ns.ReliableDays()
  return math.max(1, math.min(ns.ReliableDaysMax(), ns.Cfg("minHistoryDays")))
end

-- True while an item has fewer days of data than "Days before data is reliable"
function ns.IsLowData(days)
  return days < ns.ReliableDays()
end

local function DaysText(days)
  return days .. (days == 1 and " day" or " days")
end

-- The flag shown in orange above an item's numbers while it is low on data; nil with no data or enough
function ns.LowDataText(days)
  if days == 0 or not ns.IsLowData(days) then return nil end
  return "Only " .. DaysText(days) .. " of data · treat these numbers as rough"
end

-- The hover for a list's Data cell
function ns.DataTip(days)
  if not ns.IsLowData(days) then return DaysText(days) .. " of data." end
  return "Only " .. DaysText(days) .. " of data; the normal price may be off."
end

-- A list's Data cell: "3 d", orange while low on data, grey after
function ns.DataBadge(days)
  return (ns.IsLowData(days) and ORANGE or GREY) .. days .. " d|r"
end

-- The badge and its hover in one cell tip, for lists with no room for a Data column
function ns.DataBadgeTip(days)
  return "Data: " .. ns.DataBadge(days) .. "\n" .. ns.DataTip(days)
end

-- For lists with no room for a Data column: the orange " · N d" an Item cell ends with, and the
-- line its hover adds, while the item is low on data; nil for both otherwise
function ns.DataSuffix(days)
  if not ns.LowDataText(days) then return nil end
  return ORANGE .. " · " .. days .. " d|r"
end

function ns.LowDataTip(days)
  return ns.LowDataText(days) and ns.DataTip(days)
end

-- Weekly history is saved as one compact string per item: the first week's start day, then one
-- "wall,wall-low,high-wall" segment per consecutive week, all base 36, and an empty segment for a
-- week with no data. "fqx;2n9,1c,8;;2p1,0,3" is three weeks, the middle one missing.
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function Base36(n)
  local out = ""
  repeat
    local digit = n % 36
    out = DIGITS:sub(digit + 1, digit + 1) .. out
    n = (n - digit) / 36
  until n == 0
  return out
end

-- Weeks, oldest first, each { start=, wall=, low=, high= }, as one string; nil for none
function ns.PackWeeks(weeks)
  if #weeks == 0 then return nil end
  local first = weeks[1].start
  local segments = { Base36(first) }
  for _, week in ipairs(weeks) do
    local position = (week.start - first) / 7 + 2
    for i = #segments + 1, position - 1 do segments[i] = "" end
    segments[position] = Base36(week.wall) .. "," .. Base36(week.wall - week.low) .. "," .. Base36(week.high - week.wall)
  end
  return table.concat(segments, ";")
end

-- First day of the Monday-start week holding a day; day 0, 1 Jan 1970, was a Thursday
local function WeekStart(day)
  return day - (day + 3) % 7
end

-- The weeks in a packed string, oldest first, skipping missing weeks. Empty when the string is
-- missing or malformed.
function ns.UnpackWeeks(text)
  if type(text) ~= "string" then return {} end
  local weeks, start = {}, nil
  for segment in (text .. ";"):gmatch("([^;]*);") do
    if not start then
      start = tonumber(segment, 36)
      if not start or WeekStart(start) ~= start then return {} end
    else
      if segment ~= "" then
        local wall, below, above = segment:match("^(%w+),(%w+),(%w+)$")
        wall, below, above = tonumber(wall or "", 36), tonumber(below or "", 36), tonumber(above or "", 36)
        if not (wall and below and above) then return {} end
        weeks[#weeks + 1] = { start = start, wall = wall, low = wall - below, high = wall + above }
      end
      start = start + 7
    end
  end
  return weeks
end

-- Unpacked weekly history for the chart, parsed again only when the saved string changes
local weekCache = {}   -- [itemID] = { text =, weeks = }
local function CachedWeeks(id)
  local text = ns.R().weeks[id]
  local cached = weekCache[id]
  if not cached or cached.text ~= text then
    cached = { text = text, weeks = ns.UnpackWeeks(text) }
    weekCache[id] = cached
  end
  return cached.weeks
end

-- Points for the chart: per-scan snapshots when we have them, otherwise one point per day.
-- withHistory first adds the weekly points, at mid-week, then the daily points from before the first snapshot.
function ns.Series(id, withHistory)
  local r = ns.R()
  local out = {}
  if withHistory then
    for i, week in ipairs(CachedWeeks(id)) do
      out[i] = { t = ns.DayStart(week.start) + 3.5 * 86400, w = week.wall }
    end
  end
  local snaps = r.snaps[id]
  local useSnaps = snaps and #snaps >= 2
  local days = r.days[id]
  if days and (withHistory or not useSnaps) then
    local before = useSnaps and ns.DayOf(snaps[1][1]) or math.huge
    local keys = {}
    for day in pairs(days) do
      if day < before then keys[#keys + 1] = day end
    end
    table.sort(keys)
    for _, day in ipairs(keys) do
      local d = days[day]
      out[#out + 1] = { t = ns.DayStart(day) + 43200, w = d[D_WALL], m = d[D_MIN], q = d[D_UNITS] }
    end
  end
  if useSnaps then
    for i = 1, #snaps do
      out[#out + 1] = { t = snaps[i][1], w = snaps[i][2], m = snaps[i][3], q = snaps[i][4] }
    end
  end
  return out
end

local function Median(values)
  table.sort(values)
  return W.Percentile(values, 0.5)
end

-- Folds an item's daily records from whole weeks before `cutoff` into one weekly point each:
-- the median, lowest and highest wall. A week straddling the cutoff waits until all its days
-- have passed it. A folded week replaces a saved one with the same start. Keeps the newest
-- retainWeeks weeks.
function ns.FoldWeeks(id, cutoff)
  local r = ns.R()
  local days = r.days[id]
  local limit = WeekStart(cutoff)   -- days before it sit in whole weeks before the cutoff
  local anyExpired = false   -- checked first, as every recorded item comes through here on each scan
  for day in pairs(days) do
    if day < limit then anyExpired = true break end
  end
  if not anyExpired then return end

  local expired = {}   -- [week start] = daily records
  for day, d in pairs(days) do
    if day < limit then
      local week = WeekStart(day)
      expired[week] = expired[week] or {}
      table.insert(expired[week], d)
      days[day] = nil
    end
  end

  local byStart = {}
  for _, week in ipairs(ns.UnpackWeeks(r.weeks[id])) do byStart[week.start] = week end
  for start, records in pairs(expired) do
    local walls, low, high = {}, math.huge, 0
    for i, d in ipairs(records) do
      walls[i] = d[D_WALL]
      low, high = math.min(low, d[D_LOW]), math.max(high, d[D_HIGH])
    end
    byStart[start] = { start = start, wall = ns.Round(Median(walls)), low = low, high = high }
  end
  local weeks = {}
  for _, week in pairs(byStart) do weeks[#weeks + 1] = week end
  table.sort(weeks, function(a, b) return a.start < b.start end)
  local oldest = weeks[#weeks].start - (ns.Cfg("retainWeeks") - 1) * 7
  while weeks[1].start < oldest do table.remove(weeks, 1) end
  r.weeks[id] = ns.PackWeeks(weeks)
end

-- Record one observation of an item's listings. Returns wall, minPrice.
function ns.Record(id, ladder, total, t)
  local r = ns.R()
  local wall, minPrice = W.Compute(ladder, total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits"))
  local watched = r.watch[id]
  if not wall then
    if watched then watched.cur = { t = t, q = 0, under = 0, cost = 0 } end
    return nil, nil
  end

  if watched or total >= ns.Cfg("minRecordSupply") then
    local days = r.days[id]
    if not days then days = {} r.days[id] = days end
    local today = ns.DayOf(t)
    local d = days[today]
    if not d then
      days[today] = { wall, wall, wall, total, minPrice }
    else
      d[D_WALL] = wall
      if wall < d[D_LOW] then d[D_LOW] = wall end
      if wall > d[D_HIGH] then d[D_HIGH] = wall end
      d[D_UNITS] = total
      d[D_MIN] = minPrice
    end
    -- wall price per part of the day, for day/night and weekday patterns
    d = days[today]
    local parts = d[D_PARTS]
    if not parts then parts = {} d[D_PARTS] = parts end
    parts[PartOf(t)] = wall
    cycleCache[id] = nil
    if watched then
      local cutoff = today - 365
      for day in pairs(days) do
        if day < cutoff then days[day] = nil end
      end
    else
      ns.FoldWeeks(id, today - ns.Cfg("retainDays"))
    end
  end

  if watched then
    local snaps = r.snaps[id]
    if not snaps then snaps = {} r.snaps[id] = snaps end
    snaps[#snaps + 1] = { t, wall, minPrice, total }
    local max = ns.Cfg("maxSnaps")
    while #snaps > max do table.remove(snaps, 1) end
    local under, cost = 0, 0
    if watched.buy then under, cost = W.UnitsUnder(ladder, watched.buy) end
    watched.cur = { t = t, w = wall, m = minPrice, q = total, under = under, cost = cost }
  end
  return wall, minPrice
end

-- Stackable items trade as commodities: one price per unit, cheapest units sold first.
-- Nil while the game has not loaded the item's info yet.
function ns.IsCommodity(id)
  local stack = C_Item and C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(id)
  if not stack and GetItemInfo then stack = select(8, GetItemInfo(id)) end
  if not stack then return nil end
  return stack > 1
end

-- Track whether an item's cheapest level looks like bait. Runs on every full scan and live search.
-- isCommodity: true when the caller already knows (a commodity search), else it is looked up.
-- While that is unknown the record stays as it was, so an uncached item keeps its history.
function ns.UpdateBait(id, ladder, wall, stats, t, isCommodity)
  local commodity = isCommodity or ns.IsCommodity(id)
  if commodity == nil then return end
  local r = ns.R()
  if not commodity then
    r.bait[id] = nil
    return
  end
  -- A record that no longer qualifies comes back nil, which clears its saved flag
  local minUnder = B.MinUnder(ns.Cfg("baitMinUnder"))
  r.bait[id] = B.Update(r.bait[id], ladder, wall, stats, minUnder, t)
end

-- One item's snipe and dip in a full scan, each nil when it is not one. Call after ns.Record, with
-- ns.StatsFor: on an item's first scan, snipes resell at today's wall and nothing can dip yet.
function ns.FullScanDeals(id, ladder, total, wall, minPrice, stats, cut)
  local days = ns.DaysOfData(id)
  local snipe, dip
  local ref = stats.median and math.min(wall, stats.median) or wall
  local units, cost, profit, discount = W.Snipe(ladder, wall, cut, ref)
  if units > 0 and profit >= ns.Cfg("minSnipeProfit") and discount >= ns.Cfg("minSnipeDiscount") then
    snipe = { id = id, wall = wall, min = minPrice, units = units, cost = cost, profit = profit, discount = discount, total = total, days = days }
  end
  if W.IsDip(wall, stats, ns.Cfg("dipPct"), cut) then
    dip = { id = id, wall = wall, median = stats.median, under = 1 - wall / stats.median, total = total, days = days,
      profit = stats.median * (1 - cut) - wall }
  end
  return snipe, dip
end

-- Status for a watched item: "buy", "sell", "normal" or "nodata"
function ns.WatchStatus(id)
  local entry = ns.R().watch[id]
  local cur = entry and entry.cur
  if not cur or not cur.w then return "nodata" end
  if (cur.under or 0) > 0 then return "buy" end
  if entry.sell and cur.w >= entry.sell then return "sell" end
  return "normal"
end

-- Recompute "units under" after the buy threshold changes
function ns.RecalcWatch(id)
  local entry = ns.R().watch[id]
  local held = ns.ladders[id]
  if entry and entry.cur and held and entry.buy then
    entry.cur.under, entry.cur.cost = W.UnitsUnder(held.ladder, entry.buy)
  end
end

function ns.AddPosition(id, qty, cost)
  local r = ns.R()
  local pos = r.pos[id] or { qty = 0, cost = 0 }
  pos.qty = pos.qty + qty
  pos.cost = pos.cost + cost
  r.pos[id] = pos
  r.buys[#r.buys + 1] = { t = time(), id = id, qty = qty, unit = ns.Round(cost / qty), total = cost }
  -- running totals for the summary printed when the auction house closes
  local session = ns.session
  session.buys = session.buys + 1
  session.qty = session.qty + qty
  session.cost = session.cost + cost
  local entry = r.watch[id]
  local sell = (entry and entry.sell) or (entry and entry.cur and entry.cur.w)
  if sell then session.resale = session.resale + qty * sell * (1 - ns.Cfg("ahCut")) end
end

-- Day/night and day-of-week pattern for an item. Cached until the item is recorded again.
function ns.Cycle(id)
  if cycleCache[id] then return cycleCache[id] end
  local days = ns.R().days[id]
  local obs = {}
  if days then
    for day, record in pairs(days) do
      local parts = record[D_PARTS]
      if parts then
        local wday = tonumber(date("%w", ns.DayStart(day) + 43200)) + 1
        for part, wall in pairs(parts) do
          obs[#obs + 1] = { day = day, part = part, wday = wday, w = wall }
        end
      end
    end
  end
  local result = W.Cycle(obs)
  cycleCache[id] = result
  return result
end

-- The most recent recorded wall price and its day, or nil when the item has no history
function ns.LatestWall(id)
  local days = ns.R().days[id]
  if not days then return nil end
  local latestDay
  for day in pairs(days) do
    if not latestDay or day > latestDay then latestDay = day end
  end
  if latestDay then return days[latestDay][D_WALL], latestDay end
end

-- How a price compares with the item's median wall: the difference (-0.1 is 10% under)
-- and "low", "high" or "normal". Nil when the item has no wall in the baseline window.
function ns.Versus(price, stats)
  if not price or stats.n == 0 then return nil end
  local diff = price / stats.median - 1
  return diff, (diff < -0.03 and "low") or (diff > 0.03 and "high") or "normal"
end

function ns.VersusText(diff, word)
  local colored = (word == "low" and "|cff7cc0fflow|r") or (word == "high" and "|cffffb057high|r") or word
  return string.format("%+d%% (%s)", ns.Round(diff * 100), colored)
end
