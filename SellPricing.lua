-- MarketWall: the Sell page's numbers and words: where Price each starts, what the page says
-- about a price, and the warnings before posting. No frames here; Sell.lua draws them.
local _, ns = ...
local B, Outlet = ns.Bait, ns.Outlet

local P = {}
ns.SellPricing = P

local ORANGE, GOLD, GREEN, RED = "|cffffb057", "|cfff5c518", "|cff4fc36b", "|cffe06060"
local NONE = "—"

-- The wall to compare a price with: live when listings are loaded, else the last recorded one
function P.Wall(id)
  return ns.PriceView.LiveWall(id) or ns.LatestWall(id)
end

-- Where Price each starts: the lowest level listed now, past a level Bait Detect has flagged,
-- or the last recorded wall without live listings. Returns { price, source = "lowest" or
-- "wall", skipped = whether a bait level was passed over }, or nil with no price at all.
-- skipped with source "wall" means every level listed was flagged bait.
function P.StartingPrice(id)
  local held = ns.ladders[id]
  local bait = ns.R().bait[id]
  local skipped = false
  for _, tier in ipairs(held and held.ladder or {}) do
    if B.Flagged(bait) and tier.p == bait.p then
      skipped = true
    else
      return { price = tier.p, source = "lowest", skipped = skipped }
    end
  end
  local wall = ns.LatestWall(id)
  if wall then return { price = wall, source = "wall", skipped = skipped } end
end

-- Where the price came from and how it sits against the wall. Under the wall is information,
-- never a warning: the price is the player's call.
function P.InfoLine(price, start, wall)
  local parts = {}
  if start and price == start.price then
    if start.source == "lowest" then
      parts[1] = "Price set to the lowest listing, " .. ns.Money(price) .. (start.skipped and " (bait level skipped)" or "") .. "."
    elseif start.skipped then
      parts[1] = "Every level listed is flagged bait, so the price starts at the last recorded wall, " .. ns.Money(price) .. "."
    else
      parts[1] = "No listings loaded, so the price starts at the last recorded wall, " .. ns.Money(price) .. "."
    end
  end
  if wall and price < wall then
    local subject = #parts > 0 and "That's" or "This price is"
    local pct = ns.Round((1 - price / wall) * 100)
    local how = pct >= 1 and (pct .. "% under") or "just under"
    parts[#parts + 1] = string.format("%s %s the %s wall.", subject, how, ns.Money(wall))
  end
  return table.concat(parts, " ")
end

-- What a post earns against selling the same units to a vendor. The deposit counts as a cost:
-- the worst case, since the game refunds it when the auction sells. vendorEach is nil or 0 for an
-- item with no vendor price, which leaves vendor, beats and the vendor side of the per-unit line out.
function P.Totals(price, quantity, deposit, vendorEach, cut)
  local total = price * quantity
  local afterCut = total * (1 - cut)
  local net = afterCut - deposit
  local t = { total = total, afterCut = afterCut, deposit = deposit, net = net, netEach = net / quantity }
  if vendorEach and vendorEach > 0 then
    t.vendorEach = vendorEach
    t.vendor = vendorEach * quantity
    t.beats = net - t.vendor
  end
  return t
end

-- "AH beats vendor by": green with a plus when posting wins, red when the vendor pays as much
-- or more, a dash for an item with no vendor price
function P.BeatsText(t)
  if not t.beats then return "—" end
  local plain = ns.Money(t.beats):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  if t.beats > 0 then return GREEN .. "+" .. plain .. "|r" end
  return RED .. plain .. "|r"
end

-- The warnings that apply to posting at a price, each one line. f: price; totals (P.Totals);
-- stats (ns.StatsFor); bait (the Bait Detect record); outlet (Outlet.Values for the item).
function P.Warnings(f)
  local warnings = {}
  local function add(text) warnings[#warnings + 1] = text end
  local stats = f.stats
  if stats and stats.n > 0 and f.price < stats.p25 then
    add(string.format("Below expected: %s is under this item's normal range (%s - %s).",
      ns.Money(f.price), ns.Money(stats.p25), ns.Money(stats.p75)))
  end
  local totals = f.totals
  if totals and totals.beats and totals.beats <= 0 then   -- the same test that turns the totals red
    add(string.format("A vendor pays %s: %s each, against %s after the cut and deposit.",
      totals.beats < 0 and "more" or "as much", ns.Money(totals.vendorEach), ns.Money(totals.netEach)))
  end
  local bait = B.PostWarning(f.bait, f.price, ns.PriceView.FLAT)
  if bait then add("Matches a bait price: " .. bait) end
  local outlet = f.outlet
  local group = outlet and P.Group(outlet)
  if group == Outlet.NO_DATA and outlet.auction then
    add("No reliable price: the market is too thin to price.")
  elseif group == Outlet.DISENCHANT then
    add(string.format("Best outlet is disenchanting: %s each after fees, more than the auction house or a vendor.",
      ns.Money(outlet.disenchant)))
  elseif group == Outlet.VENDOR then
    add(outlet.thin
      and "Best outlet is a vendor: the market is too thin to trust."
      or string.format("Best outlet is a vendor: %s each, at least what the auction house pays after fees.", ns.Money(outlet.vendor)))
  end
  return warnings
end

-- One unit through each outlet, for the bag grid's tooltip
function P.OutletLine(v)
  local auction = NONE
  if v.auction then auction = ns.Money(v.auction) .. " after cut and deposit" .. (v.thin and " (thin market)" or "") end
  local vendor = v.vendor > 0 and ns.Money(v.vendor) or NONE
  local disenchant = v.disenchant and ns.Money(v.disenchant) or NONE
  return string.format("AH %s · Vendor %s · Disenchant %s", auction, vendor, disenchant)
end

-- The Note column: the bait level Bait Detect tracks, or the wall
function P.AuctionNote(tier, wall, bait)
  if bait and tier.p == bait.p then return ORANGE .. "bait? " .. B.LevelNote(bait) .. "|r" end
  if tier.p == wall then return GOLD .. "wall|r" end
  return ""
end

-- The bag group for an item: its best outlet, except that an item a vendor won't buy never goes
-- to Vendor. Outlet.Values picks Vendor for it only when the market is thin or the auction house
-- nets nothing, so it has no reliable price and joins the items with no market data.
function P.Group(values)
  if values.outlet == Outlet.VENDOR and values.vendor <= 0 then return Outlet.NO_DATA end
  return values.outlet
end

-- Bags grouped by best outlet (P.Group). items: { id, count, values = Outlet.Values }. Each group:
-- { outlet, items, value }; items and groups most valuable first, empty groups left out.
function P.Groups(items)
  local byOutlet, groups = {}, {}
  for _, item in ipairs(items) do
    local key = P.Group(item.values)
    local group = byOutlet[key]
    if not group then
      group = { outlet = key, items = {}, value = 0 }
      byOutlet[key] = group
      groups[#groups + 1] = group
    end
    item.value = item.values.best * item.count
    group.items[#group.items + 1] = item
    group.value = group.value + item.value
  end
  local function Before(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.id or a.outlet) < (b.id or b.outlet)
  end
  for _, group in ipairs(groups) do table.sort(group.items, Before) end
  table.sort(groups, Before)
  return groups
end
