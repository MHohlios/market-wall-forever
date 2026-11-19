-- MarketWall: market, vendor and disenchant prices on item tooltips
local _, ns = ...

local GREY, GOLD, GREEN, ORANGE = "|cffa3acac", "|cfff5c518", "|cff4fc36b", "|cffffb057"
local Outlet = ns.Outlet

local MIN_SHOWN_CHANCE = 0.01

-- The outlet that pays most for one unit after the cut, by the Sell page's bag-group rule, and
-- whether the market is too thin to trust. No deposit: the tooltip knows no auction duration or
-- bag slot to price one.
local function BestOutlet(id)
  local values = Outlet.Game()(id, 0)
  return ns.SellPricing.Group(values), values.thin
end

local function OutletLabel(name, outlet, best)
  return GOLD .. name .. "|r" .. (outlet == best and " " .. GREEN .. "best|r" or "")
end

-- One decimal, dropped when it is zero: 1.5, 2, 99.5
local function Decimal(x)
  return (string.format("%.1f", x):gsub("%.0$", ""))
end

local function OutletLines(add, id, count)
  local best, thin = BestOutlet(id)
  local wall, day = ns.LatestWall(id)
  if wall then
    local age = ns.Today() - day
    local when = (age == 0 and "today") or (age == 1 and "yesterday") or (age .. " days ago")
    add(OutletLabel("Market", Outlet.AUCTION, best),
      ns.Money(wall) .. " " .. GREY .. "(" .. when .. ")" .. (thin and " (thin market)" or "") .. "|r")
    if count and count > 1 then add(GREY .. "Stack of " .. count .. "|r", ns.Money(wall * count)) end
  end

  local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
  if vendor and vendor > 0 then add(OutletLabel("Vendor", Outlet.VENDOR, best), ns.Money(vendor)) end

  local disenchant = ns.DisenchantValue(id)
  if disenchant then
    add(OutletLabel("Disenchant", Outlet.DISENCHANT, best), ns.Money(disenchant))
  elseif disenchant == false then
    add(OutletLabel("Disenchant", Outlet.DISENCHANT, best), GREY .. "materials not scanned|r")
  end
end

-- One indented line per likely material, most likely first, then where the odds come from.
-- True when it added lines.
local function DisenchantLines(add, id)
  local outcomes, source = ns.DisenchantOutcomes(id)
  if not outcomes then return end
  local shown = {}
  for _, o in ipairs(outcomes) do
    if o.chance >= MIN_SHOWN_CHANCE then shown[#shown + 1] = o end
  end
  table.sort(shown, function(a, b) return a.chance > b.chance end)
  for _, o in ipairs(shown) do
    add("  " .. ns.ColorName(o.id),
      GREY .. Decimal(o.quantity) .. "× · " .. Decimal(o.chance * 100) .. "%|r " .. ns.Money(ns.LatestWall(o.id)))
  end
  add(GREY .. "  odds: " .. source .. "|r", "")
  return true
end

local function MarketContextLines(add, id)
  local wall, day = ns.LatestWall(id)
  if not wall then return end
  local days = ns.DaysOfData(id)
  local flag = ns.LowDataText(days)
  if flag then add(ORANGE .. flag .. "|r", "") end
  -- on an item's first day, a number that cannot be worked out yet says so rather than vanishing
  local missing = days <= 1 and GREY .. "n/a (first scan)|r" or nil

  local label = ns.Today() == day and "Against median" or "Against median (last scan)"
  local diff, word = ns.Versus(wall, ns.StatsFor(id))
  local versus = diff and ns.VersusText(diff, word) or missing
  if versus then add(GREY .. label .. "|r", versus) end

  local PV = ns.PriceView
  local week = PV.Summary(PV.InRange(ns.Series(id), 7, time()))
  local trend = week and week.trend and PV.TrendText(week.trend) or missing
  if trend then add(GREY .. "7-day trend|r", trend) end

  local entry = ns.R().watch[id]
  if entry and entry.buy then
    add(GREY .. "Your buy / sell|r", ns.Money(entry.buy) .. " / " .. (entry.sell and ns.Money(entry.sell) or "-"))
  end
end

-- Size of the stack the tooltip is for, read from the bag slot that owns it.
-- Nil when the tooltip has no bag slot owner or the slot holds a different item.
local function StackCount(tooltip, id)
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  if not (owner and C_Container and C_Container.GetContainerItemInfo) then return nil end
  local bag, slot
  if owner.GetSlotAndBagID then
    slot, bag = owner:GetSlotAndBagID()
  elseif owner.GetParent and owner.GetID then
    local parent = owner:GetParent()
    bag, slot = parent and parent.GetID and parent:GetID(), owner:GetID()
  end
  if not (bag and slot) then return nil end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  return info and info.itemID == id and info.stackCount or nil
end

local function AddLines(tooltip, id)
  if not id or not MarketWallDB then return end
  -- A blank line before the next line added, so a block that adds nothing leaves no gap
  local gap = true
  local function add(left, right)
    if gap then
      tooltip:AddLine(" ")
      gap = false
    end
    tooltip:AddDoubleLine(left, right)
  end

  OutletLines(add, id, StackCount(tooltip, id))
  if DisenchantLines(add, id) then gap = true end
  MarketContextLines(add, id)
end

-- Mob tooltips -------------------------------------------------------------------------------

-- Seen kills, the ones values and Minimum kills count, and the unseen ones beside them
local function KillCount(stats)
  local unseen = stats.kills - stats.seen
  return GREY .. stats.seen .. " kills" .. (unseen > 0 and " (" .. unseen .. " unseen)" or "") .. "|r"
end

-- The lines a mob adds to its tooltip, from Mobs.Stats: { left, right } pairs, or { text } for
-- a single line. Empty for a mob with no record. skinning: whether Optimal includes it.
-- Medians and averages get a block each, so every value lines up on the right edge.
local function MobLines(stats, skinning, minKills)
  if not stats then return {} end
  local lines = { { stats.name or "Kills", KillCount(stats) } }
  if not stats.optimal then
    lines[2] = { GREY .. "Values show from " .. minKills .. " kills.|r" }
    return lines
  end
  local function add(line) lines[#lines + 1] = line end
  local optimal = stats.optimal.label:gsub("^Optimal (.+)$", "Optimal " .. GREY .. "%1|r")
  for _, block in ipairs({ { "median", "Median per kill" }, { "average", "Average per kill" } }) do
    local field = block[1]
    add({ "|cfff5c518" .. block[2] .. "|r" })
    add({ GREY .. "  Vendor|r", ns.Money(stats.vendor[field]) })
    add({ GREY .. "  Market|r", ns.Money(stats.market[field]) })
    if skinning and stats.skinning then add({ GREY .. "  Skinning|r", ns.Money(stats.skinning[field]) }) end
    add({ "  " .. optimal, ns.Money(stats.optimal[field]) })
  end
  add({ GREY .. "  Optimal, without rare drops|r", ns.Money(stats.optimalNoRare.average) })
  if stats.top then
    add({ GREY .. "Top drop:|r " .. ns.ColorName(stats.top.id) .. " " .. ns.ShareText(stats.top.share) .. GREY .. " of kills|r" })
  end
  return lines
end

-- The creature ID under the mouse, nil for players, pets and anything else
local function MouseoverNPC()
  local kind, npc = ns.Kills.ParseGUID(UnitGUID("mouseover"))
  if kind == "npc" then return npc end
end

local function AddMobLines(tooltip)
  if not MarketWallDB then return end
  local npc = MouseoverNPC()
  if not npc then return end
  local lines = MobLines(ns.Mobs.For(npc), ns.Mobs.GameOptions().skinning, ns.Cfg("mobMinKills"))
  if #lines == 0 then return end
  tooltip:AddLine(" ")
  for _, line in ipairs(lines) do
    if line[2] then tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) else tooltip:AddLine(line[1]) end
  end
end

ns.TooltipLines = { Add = AddLines, StackCount = StackCount, Mob = MobLines }   -- exposed for tests

function ns.InitTooltip()
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    pcall(AddLines, tooltip, data and data.id)
  end)
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
    if tooltip ~= GameTooltip then return end
    pcall(AddMobLines, tooltip)
  end)
end
