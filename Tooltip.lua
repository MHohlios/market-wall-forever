-- MarketWall: one or two lines on item tooltips
local ADDON, ns = ...

local function AddLines(tooltip, id)
  if not id or not MarketWallDB then return end
  local r = ns.R()
  local days = r.days[id]
  if not days then return end
  local latestDay, latest = nil, nil
  for day, record in pairs(days) do
    if not latestDay or day > latestDay then latestDay, latest = day, record end
  end
  if not latest then return end
  local stats = ns.StatsFor(id)
  local age = ns.Today() - latestDay
  local when = (age == 0 and "today") or (age == 1 and "yesterday") or (age .. " days ago")
  tooltip:AddLine(" ")
  tooltip:AddDoubleLine("|cfff5c518Market wall|r", ns.Money(latest[1]) .. " |cffa3acac(" .. when .. ")|r")
  if stats.n >= 3 then
    tooltip:AddDoubleLine("|cffa3acacNormal range|r", ns.Money(stats.p25) .. " to " .. ns.Money(stats.p75))
    if age == 0 then
      local diff = latest[1] / stats.median - 1
      local word = (diff < -0.03 and "|cff7cc0fflow|r") or (diff > 0.03 and "|cffffb057high|r") or "normal"
      tooltip:AddDoubleLine("|cffa3acacAgainst median|r", string.format("%+d%% (%s)", ns.Round(diff * 100), word))
    end
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
    tooltip:AddDoubleLine("|cffa3acacCheapest / dearest time|r",
      string.format("|cff7cc0ff%s %+d%%|r / |cffffb057%s %+d%%|r",
        ns.PART_NAMES[best], ns.Round((cycle.parts[best].r - 1) * 100),
        ns.PART_NAMES[worst], ns.Round((cycle.parts[worst].r - 1) * 100)))
  end
  local entry = r.watch[id]
  if entry and entry.buy then
    tooltip:AddDoubleLine("|cffa3acacYour buy / sell|r", ns.Money(entry.buy) .. " / " .. (entry.sell and ns.Money(entry.sell) or "-"))
  end
end

function ns.InitTooltip()
  if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local ok = pcall(AddLines, tooltip, data and data.id)
    if not ok then return end
  end)
end
