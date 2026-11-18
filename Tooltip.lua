-- MarketWall: market, vendor and disenchant prices on item tooltips
local _, ns = ...

local GREY = "|cffa3acac"

local function MarketLines(add, id, count)
  local wall, day = ns.LatestWall(id)
  if not wall then return end
  local age = ns.Today() - day
  local when = (age == 0 and "today") or (age == 1 and "yesterday") or (age .. " days ago")
  add("|cfff5c518Market wall|r", ns.Money(wall) .. " " .. GREY .. "(" .. when .. ")|r")
  if count and count > 1 then add(GREY .. "Stack of " .. count .. "|r", ns.Money(wall * count)) end

  local stats = ns.StatsFor(id)
  local diff, word = ns.Versus(wall, stats)
  if diff then
    add(GREY .. "Normal range|r", ns.Money(stats.p25) .. " to " .. ns.Money(stats.p75))
    add(GREY .. (age == 0 and "Against median" or "Against median (last scan)") .. "|r", ns.VersusText(diff, word))
  end

  local PV = ns.PriceView
  local week = PV.Summary(PV.InRange(ns.Series(id), 7, time()))
  if week and week.trend then add(GREY .. "7-day trend|r", PV.TrendText(week.trend)) end

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
  local spaced = false
  local function add(left, right)
    if not spaced then
      tooltip:AddLine(" ")
      spaced = true
    end
    tooltip:AddDoubleLine(left, right)
  end

  MarketLines(add, id, StackCount(tooltip, id))

  local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id))
  if vendor and vendor > 0 then add(GREY .. "Vendor|r", ns.Money(vendor)) end

  local disenchant, source = ns.DisenchantValue(id)
  if disenchant then
    add(GREY .. "Disenchant" .. (source and " (" .. source .. ")" or "") .. "|r", ns.Money(disenchant))
  elseif disenchant == false then
    add(GREY .. "Disenchant|r", GREY .. "materials not scanned|r")
  end
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
