-- MarketWall: market, vendor and disenchant prices on item tooltips
local _, ns = ...

local GREY = "|cffa3acac"

local function MarketLines(add, id)
  local wall, day = ns.LatestWall(id)
  if not wall then return end
  local age = ns.Today() - day
  local when = (age == 0 and "today") or (age == 1 and "yesterday") or (age .. " days ago")
  add("|cfff5c518Market wall|r", ns.Money(wall) .. " " .. GREY .. "(" .. when .. ")|r")

  local stats = ns.StatsFor(id)
  local diff, word = ns.Versus(wall, stats)
  if diff then
    add(GREY .. "Normal range|r", ns.Money(stats.p25) .. " to " .. ns.Money(stats.p75))
    add(GREY .. (age == 0 and "Against median" or "Against median (last scan)") .. "|r", ns.VersusText(diff, word))
  end

  local cycle = ns.Cycle(id)
  local best, worst
  for part = 1, 4 do
    local g = cycle.parts[part]
    if g and g.n >= 3 then
      if not best or g.r < cycle.parts[best].r then best = part end
      if not worst or g.r > cycle.parts[worst].r then worst = part end
    end
  end
  if best and worst and best ~= worst and cycle.parts[worst].r - cycle.parts[best].r >= 0.03 then
    add(GREY .. "Cheapest / dearest time|r",
      string.format("|cff7cc0ff%s %+d%%|r / |cffffb057%s %+d%%|r",
        ns.PART_NAMES[best], ns.Round((cycle.parts[best].r - 1) * 100),
        ns.PART_NAMES[worst], ns.Round((cycle.parts[worst].r - 1) * 100)))
  end

  local entry = ns.R().watch[id]
  if entry and entry.buy then
    add(GREY .. "Your buy / sell|r", ns.Money(entry.buy) .. " / " .. (entry.sell and ns.Money(entry.sell) or "-"))
  end
end

local function AddLines(tooltip, id)
  if not id or not MarketWallDB then return end
  local spaced = false
  local function add(left, right)
    if not spaced then
      tooltip:AddLine(" ")
      spaced = true
    end
    tooltip:AddDoubleLine(left, right)
  end

  MarketLines(add, id)

  local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
  if vendor and vendor > 0 then add(GREY .. "Vendor|r", ns.Money(vendor)) end

  local disenchant, source = ns.DisenchantValue(id)
  if disenchant then
    add(GREY .. "Disenchant" .. (source and " (" .. source .. ")" or "") .. "|r", ns.Money(disenchant))
  elseif disenchant == false then
    add(GREY .. "Disenchant|r", GREY .. "materials not scanned|r")
  end
end

function ns.InitTooltip()
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    pcall(AddLines, tooltip, data and data.id)
  end)
end
