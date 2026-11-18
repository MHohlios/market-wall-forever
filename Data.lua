-- MarketWall: recording and reading history
local ADDON, ns = ...
local W = ns.Wall

ns.ladders = {}   -- [itemID] = { ladder=, total=, t=, kind=, auctions= } session only
ns.snipes = {}    -- last full scan results
ns.dips = {}

local D_WALL, D_LOW, D_HIGH, D_UNITS, D_MIN, D_PARTS = 1, 2, 3, 4, 5, 6

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

function ns.StatsFor(id)
  return W.Stats(ns.DayWalls(id))
end

-- Points for the chart: per-scan snapshots when we have them, otherwise one point per day
function ns.Series(id)
  local r = ns.R()
  local out = {}
  local snaps = r.snaps[id]
  if snaps and #snaps >= 2 then
    for i = 1, #snaps do
      out[i] = { t = snaps[i][1], w = snaps[i][2], m = snaps[i][3], q = snaps[i][4] }
    end
    return out
  end
  local days = r.days[id]
  if not days then return out end
  local keys = {}
  for day in pairs(days) do keys[#keys + 1] = day end
  table.sort(keys)
  for i = 1, #keys do
    local d = days[keys[i]]
    out[i] = { t = ns.DayStart(keys[i]) + 43200, w = d[D_WALL], m = d[D_MIN], q = d[D_UNITS] }
  end
  return out
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
    local cutoff = today - (watched and 365 or ns.Cfg("retainDays"))
    for day in pairs(days) do
      if day < cutoff then days[day] = nil end
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
-- and "low", "high" or "normal". Nil until there are 3 days of history.
function ns.Versus(price, stats)
  if not price or stats.n < 3 then return nil end
  local diff = price / stats.median - 1
  return diff, (diff < -0.03 and "low") or (diff > 0.03 and "high") or "normal"
end

function ns.VersusText(diff, word)
  local colored = (word == "low" and "|cff7cc0fflow|r") or (word == "high" and "|cffffb057high|r") or word
  return string.format("%+d%% (%s)", ns.Round(diff * 100), colored)
end
