-- MarketWall: market, vendor and disenchant prices on item tooltips
local _, ns = ...

local GREY, GOLD, GREEN, ORANGE = "|cffa3acac", "|cfff5c518", "|cff4fc36b", "|cffffb057"
local Outlet = ns.Outlet

local MIN_SHOWN_CHANCE = 0.01
local CONVERSION = "conversion"   -- the best-tag key for a conversion line

-- An outlet line's left side: the name, the best tag, then any note in grey. The right side
-- holds only the price, so prices line up.
local function OutletLabel(name, outlet, best, note)
  return GOLD .. name .. "|r" .. (outlet == best and " " .. GREEN .. "best|r" or "")
    .. (note and " " .. GREY .. note .. "|r" or "")
end

-- One decimal, dropped when it is zero: 1.5, 2, 99.5
local function Decimal(x)
  return (string.format("%.1f", x):gsub("%.0$", ""))
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
  add(GREY .. "  odds: " .. source .. " · net after the cut and each material's deposit|r", "")
  return true
end

-- What one input nets as its share of the product (Outlet.CONVERSIONS), after the cut and the
-- product's deposit. False when the product has no scanned wall.
local function ConversionValue(conversion, prices, cut)
  local wall = prices.wall(conversion.product)
  if not wall then return false end
  return Outlet.Net(wall, cut, prices.deposit(conversion.product)) / conversion.inputs
end

-- What one unit nets through each outlet, after the cut and an estimated deposit, with the
-- disenchant breakdown under its line. The best of vendor, market and disenchanting follows the
-- Sell page's bag-group rule; a conversion is best when it pays more than all three.
-- True when it added the disenchant breakdown.
local function OutletLines(add, id, count)
  local prices, opts = ns.Mobs.GamePrices(), ns.Mobs.GameOptions()
  local values = Outlet.Priced(prices, opts, id)
  local best, bestValue = ns.SellPricing.Group(values), values.best
  local conversion = Outlet.CONVERSIONS[id]
  local converted = conversion and ConversionValue(conversion, prices, opts.cut)
  if converted and converted > values.best then best, bestValue = CONVERSION, converted end

  if values.vendor > 0 then add(OutletLabel("Vendor", Outlet.VENDOR, best), ns.Money(values.vendor)) end

  if values.auction then
    add(OutletLabel("Market (net)", Outlet.AUCTION, best, values.thin and "(thin market)" or nil),
      ns.Money(values.auction))
  end

  -- shown whether or not disenchanting counts toward the best outlet
  local disenchant, _, deposits = ns.DisenchantValue(id, prices.deposit)
  if disenchant then
    add(OutletLabel("Disenchant (net)", Outlet.DISENCHANT, best, "(" .. ns.Money(disenchant) .. " in mats)"),
      ns.Money(Outlet.Net(disenchant, opts.cut, deposits)))
  elseif disenchant == false then
    add(OutletLabel("Disenchant (net)", Outlet.DISENCHANT, best), GREY .. "materials not scanned|r")
  end
  local breakdown = DisenchantLines(add, id)

  if conversion then
    local product = ns.Name(conversion.product)
    local ratio = "· " .. conversion.inputs .. " " .. conversion.input .. " → 1 " .. conversion.output
    add(OutletLabel("As " .. product .. " (net)", CONVERSION, best, ratio),
      converted and ns.Money(converted) or GREY .. product .. " not scanned|r")
  end

  if count and count > 1 and best ~= Outlet.NO_DATA then
    local suffix = best == CONVERSION and " (as " .. conversion.output .. "s)" or ""
    add(GREY .. "Stack of " .. count .. suffix .. "|r", ns.Money(bestValue * count))
  end

  -- a container you have opened: what one opening gave on average, at each content's best outlet
  local history = MarketWallDB.containers[id]
  local opened = ns.Containers.OpenedValue(history, prices, opts)
  if opened then
    add(GOLD .. "Opens to|r " .. GREY .. "avg (" .. history.opens .. " opened)|r", ns.Money(opened))
  end
  return breakdown
end

local function MarketContextLines(add, id)
  local wall, day = ns.LatestWall(id)
  if not wall then return end
  local flag = ns.LowDataText(ns.DaysOfData(id))
  if flag then add(ORANGE .. flag .. "|r", "") end
  -- a number that cannot be worked out says n/a rather than vanishing, and why on a first scan
  local stats = ns.StatsFor(id)
  local missing = GREY .. (stats.firstScan and "n/a (first scan)" or "n/a") .. "|r"

  local label = ns.Today() == day and "Against median" or "Against median (last scan)"
  local diff, word = ns.Versus(wall, stats)
  add(GREY .. label .. "|r", diff and ns.VersusText(diff, word) or missing)

  local PV = ns.PriceView
  local week = PV.Summary(PV.InRange(ns.Series(id), 7, time()))
  add(GREY .. "7-day trend|r", week and week.trend and PV.TrendText(week.trend) or missing)

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

  if OutletLines(add, id, StackCount(tooltip, id)) then gap = true end
  MarketContextLines(add, id)
end

-- Mob tooltips -------------------------------------------------------------------------------

-- Seen kills, the ones values count, or an orange flag while they are under reliableKills
local function KillCount(seen, reliableKills)
  if seen < reliableKills then return ORANGE .. "< " .. reliableKills .. " kills|r" end
  return GREY .. seen .. " kills|r"
end

-- The lines a mob adds to its tooltip, from Mobs.Stats, as { left, right } pairs: worth per
-- kill under Optimal, each single outlet's median beside the kill count, and the top drop.
-- Empty for a mob with no record or no seen kill. skinning: whether Optimal includes it.
local function MobLines(stats, skinning, reliableKills)
  if not (stats and stats.optimal) then return {} end
  local optimal = stats.optimal
  local outlets = "Vendor " .. ns.Money(stats.vendor.median) .. " · Market " .. ns.Money(stats.market.median)
  if skinning and stats.skinning then outlets = outlets .. " · Skin " .. ns.Money(stats.skinning.median) end
  local lines = {
    { GOLD .. "Worth per kill|r",
      ns.Money(optimal.median) .. " " .. GREY .. "typical|r · " .. ns.Money(optimal.average) .. " " .. GREY .. "avg|r" },
    { GREY .. outlets .. "|r", KillCount(stats.seen, reliableKills) },
  }
  if stats.top then
    local pct = ns.Round(stats.top.share * 100)
    lines[3] = { GREY .. "Top drop|r",
      ns.ColorName(stats.top.id) .. " " .. GREY .. (pct == 0 and "<1" or pct) .. "%|r" }
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
  for _, line in ipairs(lines) do tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) end
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
