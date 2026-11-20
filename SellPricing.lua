-- MarketWall: the Sell page's numbers and words: where Price each starts, what the page says
-- about a price, and the warnings before posting. No frames here; Sell.lua draws them.
local _, ns = ...
local B, Outlet = ns.Bait, ns.Outlet

local P = {}
ns.SellPricing = P

local C = ns.COLOR
local WARN, LABEL, VALUE, GAIN, LOSS, GREY = C.WARN, C.LABEL, C.VALUE, C.GAIN, C.LOSS, C.GREY
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
      parts[1] = "Set to the lowest listing, " .. ns.Money(price) .. (start.skipped and " (bait level skipped)" or "") .. "."
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

-- The answer at the top right of the Sell page, from P.Totals: net is what the auction house pays
-- after the cut and deposit; versus compares it with a vendor, green when posting wins and red
-- when the vendor pays as much or more; breakdown is one grey line of how net comes about.
function P.Answer(t, quantity, price, cut)
  local net = (t.net > 0 and VALUE or LOSS) .. ns.Money(t.net) .. "|r"

  local versus
  if not t.beats then
    versus = GREY .. "A vendor won't buy this.|r"
  elseif t.beats > 0 then
    versus = GAIN .. "+" .. ns.Money(t.beats) .. " more than vendor (" .. ns.Money(t.vendor) .. ")|r"
  elseif t.beats < 0 then
    versus = LOSS .. ns.Money(-t.beats) .. " less than vendor (" .. ns.Money(t.vendor) .. ")|r"
  else
    versus = LOSS .. "The same as vendor (" .. ns.Money(t.vendor) .. ")|r"
  end

  -- the cut shown is what is left once the deposit and the rounded net are taken off, so the
  -- line adds up to the net shown above it
  local shownCut = ns.Round(t.total) - ns.Round(t.deposit) - ns.Round(t.net)
  local breakdown = GREY .. string.format("%d × %s = %s · %d%% cut -%s · deposit -%s",
    quantity, ns.MoneyFaded(price), ns.MoneyFaded(t.total), ns.Round(cut * 100),
    ns.MoneyFaded(shownCut), ns.MoneyFaded(t.deposit)) .. "|r"
  return { net = net, versus = versus, breakdown = breakdown }
end

-- The line for a price that matches the item's bait, nil when it does not
function P.BaitMatch(f)
  local bait = B.PostWarning(f.bait, f.price, ns.PriceView.FLAT)
  return bait and "Matches a bait price: " .. bait
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
  local bait = P.BaitMatch(f)
  if bait then add(bait) end
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

-- The price under which a post is too low to make without asking, for a normal low end of
-- reference copper: 70% of it up to 1g, sliding down to 30% of it as the reference grows.
-- The same scale as Auctionator's price warning.
function P.AskThreshold(reference)
  return reference * (0.3 + 0.4 * math.min(1, 10000 / reference))
end

-- The reasons to ask before posting, each one line: the price is under P.AskThreshold of the
-- bottom of the item's normal range, or it matches the item's bait. Every other warning is a
-- note on the page only. f: price; stats; bait.
function P.AskFirst(f)
  local reasons = {}
  local stats = f.stats
  if stats and stats.n > 0 and f.price < P.AskThreshold(stats.p25) then
    reasons[1] = string.format("%s is %d%% under this item's normal range (%s - %s).",
      ns.Money(f.price), ns.Round((stats.p25 - f.price) / stats.p25 * 100), ns.Money(stats.p25), ns.Money(stats.p75))
  end
  local bait = P.BaitMatch(f)
  if bait then reasons[#reasons + 1] = bait end
  return reasons
end

-- One unit through each outlet, for the bag grid's tooltip
function P.OutletLine(v)
  local auction = NONE
  if v.auction then auction = ns.Money(v.auction) .. " after cut and deposit" .. (v.thin and " (thin market)" or "") end
  local vendor = v.vendor > 0 and ns.Money(v.vendor) or NONE
  local disenchant = v.disenchant and ns.Money(v.disenchant) or NONE
  return string.format("AH %s · Vendor %s · Disenchant %s", auction, vendor, disenchant)
end

-- A listing row's note: the bait level Bait Detect tracks or the wall, then "your price" on the
-- level Price each matches exactly
function P.AuctionNote(tier, wall, bait, price)
  local note
  if bait and tier.p == bait.p then
    note = WARN .. "bait? " .. B.LevelNote(bait) .. "|r"
  elseif tier.p == wall then
    note = LABEL .. "wall|r"
  end
  if tier.p == price then note = (note and note .. LABEL .. " · " or LABEL) .. "your price|r" end
  return note or ""
end

-- The bag group for an item: its best outlet, except that an item a vendor won't buy never goes
-- to Vendor. Outlet.Values picks Vendor for it only when the market is thin or the auction house
-- nets nothing, so it has no reliable price and joins the items with no market data.
function P.Group(values)
  if values.outlet == Outlet.VENDOR and values.vendor <= 0 then return Outlet.NO_DATA end
  return values.outlet
end

-- The bag groups in the order the Sell page shows them. The first two always show, even when empty.
local GROUP_ORDER = { Outlet.AUCTION, Outlet.VENDOR, Outlet.DISENCHANT, Outlet.NO_DATA }
local ALWAYS_SHOWN = 2

-- Bags grouped by best outlet (P.Group). items: { id, count, values = Outlet.Values }. Each group:
-- { outlet, items, value }; items most valuable first. Groups keep GROUP_ORDER; the auction house
-- and Vendor groups are always present, the others only when they hold items.
function P.Groups(items)
  local byOutlet = {}
  for _, outlet in ipairs(GROUP_ORDER) do byOutlet[outlet] = { outlet = outlet, items = {}, value = 0 } end
  for _, item in ipairs(items) do
    local group = byOutlet[P.Group(item.values)]
    item.value = item.values.best * item.count
    group.items[#group.items + 1] = item
    group.value = group.value + item.value
  end
  local groups = {}
  for i, outlet in ipairs(GROUP_ORDER) do
    local group = byOutlet[outlet]
    table.sort(group.items, function(a, b)
      if a.value ~= b.value then return a.value > b.value end
      return a.id < b.id
    end)
    if i <= ALWAYS_SHOWN or #group.items > 0 then groups[#groups + 1] = group end
  end
  return groups
end
