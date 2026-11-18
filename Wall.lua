-- MarketWall: pure price logic. No game API in this file so it can be tested outside the game.
local _, ns = ...
local W = {}
ns.Wall = W

-- map: [unitPrice] = units  ->  sorted array { {p=, q=}, ... } ascending by price, and total units
function W.SortLadder(map)
  local ladder, total = {}, 0
  for price, qty in pairs(map) do
    ladder[#ladder + 1] = { p = price, q = qty }
    total = total + qty
  end
  table.sort(ladder, function(a, b) return a.p < b.p end)
  return ladder, total
end

-- The wall is the first price level where the running unit count reaches a real share of supply.
-- A couple of stray cheap units never reach that share, so they never become "the price".
function W.Compute(ladder, total, share, minUnits)
  if not ladder or #ladder == 0 or total <= 0 then return nil, nil end
  local need = math.max(math.ceil(total * share), math.min(minUnits, math.ceil(total / 2)))
  if need < 1 then need = 1 end
  local running = 0
  for i = 1, #ladder do
    running = running + ladder[i].q
    if running >= need then
      return ladder[i].p, ladder[1].p
    end
  end
  return ladder[#ladder].p, ladder[1].p
end

-- Units priced strictly below limit, and what they cost in total
function W.UnitsUnder(ladder, limit)
  local units, cost = 0, 0
  if not ladder or not limit then return 0, 0 end
  for i = 1, #ladder do
    local tier = ladder[i]
    if tier.p < limit then
      units = units + tier.q
      cost = cost + tier.q * tier.p
    else
      break
    end
  end
  return units, cost
end

-- Snipe: units below the wall that still profit when resold at the wall after the cut
-- ref: the price to assume for resale (defaults to the wall). Pass the lower of wall and
-- historical median so a wall that is itself inflated today does not create fake profit.
function W.Snipe(ladder, wall, cut, ref)
  if not wall then return 0, 0, 0, 0 end
  ref = ref or wall
  local resale = ref * (1 - cut)
  local units, cost = 0, 0
  for i = 1, #ladder do
    local tier = ladder[i]
    if tier.p < wall and tier.p < resale then
      units = units + tier.q
      cost = cost + tier.q * tier.p
    else
      break
    end
  end
  if units == 0 then return 0, 0, 0, 0 end
  local profit = units * resale - cost
  local discount = 1 - (cost / units) / ref
  return units, cost, profit, discount
end

-- f in 0..1 on an ascending array, linear interpolation
function W.Percentile(sorted, f)
  local n = #sorted
  if n == 0 then return nil end
  if n == 1 then return sorted[1] end
  local pos = 1 + (n - 1) * f
  local lo = math.floor(pos)
  local hi = math.min(lo + 1, n)
  local frac = pos - lo
  return sorted[lo] + (sorted[hi] - sorted[lo]) * frac
end

local function sortedCopy(values, from, to)
  local out = {}
  for i = from, to do out[#out + 1] = values[i] end
  table.sort(out)
  return out
end

-- walls: chronological array of past daily wall prices (today excluded)
function W.Stats(walls)
  local n = #walls
  if n == 0 then return { n = 0 } end
  local all = sortedCopy(walls, 1, n)
  local recent = sortedCopy(walls, math.max(1, n - 2), n)
  return {
    n = n,
    median = W.Percentile(all, 0.5),
    p25 = W.Percentile(all, 0.25),
    p75 = W.Percentile(all, 0.75),
    low = all[1],
    high = all[n],
    recent = W.Percentile(recent, 0.5),
  }
end

-- Dip: today's wall is well under a baseline that was not already sliding
function W.IsDip(wall, stats, dipPct, minDays, cut)
  if not wall or not stats or stats.n < minDays then return false, "history" end
  if wall > stats.median * (1 - dipPct) then return false, "normal" end
  if wall >= stats.p25 then return false, "normal" end
  if stats.recent < stats.median * 0.95 then return false, "falling" end
  if stats.median * (1 - cut) <= wall then return false, "noprofit" end
  return true, "dip"
end

-- Suggested thresholds for a newly watched item
function W.Suggest(wall, stats, cut)
  local buy, sell
  if stats and stats.n >= 3 then
    buy, sell = math.floor(stats.p25), math.ceil(stats.p75)
  elseif wall then
    buy, sell = math.floor(wall * 0.95), math.ceil(wall * 1.10)
  else
    return nil, nil
  end
  -- never suggest a pair that loses money after the cut
  local minSell = math.ceil(buy / (1 - cut)) + 1
  if sell < minSell then sell = minSell end
  return buy, sell
end
