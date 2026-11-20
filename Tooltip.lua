-- MarketWall: market, vendor and disenchant prices on item tooltips
local _, ns = ...

local GREY, GOLD, ORANGE = "|cffa3acac", "|cfff5c518", "|cffffb057"
-- The item block: the best outlet bright, every other row faded, Shift's detail dimmer still
local HEADING, HINT = "|cff2fa39d", "|cff5d6464"
local BRIGHT, WHITE, FADED, DIM = "|cff3fe6d6", "|cffffffff", "|cff868d8d", "|cff6f7676"
local ROW, DETAIL = "  ", "      "   -- indents under the heading and under a row
local Outlet = ns.Outlet

local MIN_SHOWN_CHANCE = 0.01
local CONVERSION = "conversion"   -- the best outlet's key for a conversion

-- A row's right side in its colour: copper as money, its coins darkened unless the row is
-- bright, or text such as "no price" as given
local function Price(value, color)
  if type(value) == "string" then return color .. value .. "|r" end
  return color .. (color == WHITE and ns.Money(value) or ns.MoneyFaded(value)) .. "|r"
end

-- One outlet's row: bright when it is the best, faded otherwise, with any note after the label.
-- The right side holds only the price, so prices line up.
local function OutletRow(add, label, outlet, best, value, note)
  local bright = outlet == best
  add(ROW .. (bright and BRIGHT or FADED) .. label .. "|r" .. (note and " " .. FADED .. note .. "|r" or ""),
    Price(value, bright and WHITE or FADED))
end

local function FadedRow(add, label, value)
  add(ROW .. FADED .. label .. "|r", Price(value, FADED))
end

-- One decimal, dropped when it is zero: 1.5, 2, 99.5
local function Decimal(x)
  return (string.format("%.1f", x):gsub("%.0$", ""))
end

-- One dim line per likely material under the Disenchant row, most likely first: its chance, its
-- name and its latest wall
local function DisenchantLines(add, id)
  local outcomes = ns.DisenchantOutcomes(id)
  if not outcomes then return end
  local shown = {}
  for _, o in ipairs(outcomes) do
    if o.chance >= MIN_SHOWN_CHANCE then shown[#shown + 1] = o end
  end
  table.sort(shown, function(a, b) return a.chance > b.chance end)
  for _, o in ipairs(shown) do
    add(DETAIL .. DIM .. Decimal(o.chance * 100) .. "% " .. ns.Name(o.id) .. "|r", Price(ns.LatestWall(o.id), DIM))
  end
end

-- What one input nets as its share of the product (Outlet.CONVERSIONS), after the cut and the
-- product's deposit, and whether the product's market is too thin to trust. False when the
-- product has no scanned wall.
local function ConversionValue(conversion, prices, cut)
  local wall, supplied = prices.wall(conversion.product)
  if not wall then return false end
  return Outlet.Net(wall, cut, prices.deposit(conversion.product)) / conversion.inputs, not supplied
end

-- The bright row and what one unit nets there. It follows the Sell page's bag-group rule, except
-- that an item with no market data goes to the better of vendor and disenchanting (counted only
-- when that setting is on). A conversion is best when it pays more. NO_DATA when nothing pays.
local function BestOutlet(values, converted, convertedThin)
  if converted and not convertedThin and converted > values.best then return CONVERSION, converted end
  local best = ns.SellPricing.Group(values)
  if best == Outlet.NO_DATA then
    if values.disenchant and values.disenchant > math.max(values.vendor, 0) then
      best = Outlet.DISENCHANT
    elseif values.vendor > 0 then
      best = Outlet.VENDOR
    end
  end
  return best, values.best
end

-- One row per outlet in a fixed order, each at what one unit nets after the cut and an estimated
-- deposit, then the stack and what a container opens to. details adds the disenchant materials
-- and the conversion's recipe. True when the item has something to price.
local function OutletLines(add, id, count, details)
  local prices, opts = ns.Mobs.GamePrices(), ns.Mobs.GameOptions()
  local values = Outlet.Priced(prices, opts, id)
  local conversion = Outlet.CONVERSIONS[id]
  local converted, convertedThin
  if conversion then converted, convertedThin = ConversionValue(conversion, prices, opts.cut) end
  local best, bestValue = BestOutlet(values, converted, convertedThin)

  OutletRow(add, "Market", Outlet.AUCTION, best, values.auction or "no price", values.thin and "(thin market)" or nil)

  if values.vendor > 0 then OutletRow(add, "Vendor", Outlet.VENDOR, best, values.vendor) end

  -- shown whether or not disenchanting counts toward the best outlet
  local disenchant, _, deposits = ns.DisenchantValue(id, prices.deposit)
  if disenchant ~= nil then
    OutletRow(add, "Disenchant", Outlet.DISENCHANT, best,
      disenchant and Outlet.Net(disenchant, opts.cut, deposits) or "materials not scanned")
    if details then DisenchantLines(add, id) end
  end

  if conversion then
    local product = ns.Name(conversion.product)
    OutletRow(add, "Make " .. product, CONVERSION, best, converted or product .. " not scanned",
      convertedThin and "(thin market)" or nil)
    if details then
      add(DETAIL .. DIM .. conversion.inputs .. " " .. conversion.input .. " → 1 " .. conversion.output .. "|r", "")
    end
  end

  if count and count > 1 and best ~= Outlet.NO_DATA then
    local suffix = best == CONVERSION and " (as " .. conversion.output .. "s)" or ""
    FadedRow(add, "Stack of " .. count .. suffix, bestValue * count)
  end

  -- a container you have opened: what one opening gave on average, at each content's best outlet
  local history = MarketWallDB.containers[id]
  local opened = ns.Containers.OpenedValue(history, prices, opts)
  if opened then FadedRow(add, "Opens to avg (" .. history.opens .. " opened)", opened) end
  return values.auction ~= nil or values.vendor > 0 or disenchant ~= nil or conversion ~= nil or opened ~= nil
end

local function LowDataFlag(add, id)
  if not ns.LatestWall(id) then return end
  local flag = ns.LowDataText(ns.DaysOfData(id))
  if flag then add(ROW .. ORANGE .. flag .. "|r", "") end
end

local function MarketContextLines(add, id)
  local wall, day = ns.LatestWall(id)
  if not wall then return end
  -- a number that cannot be worked out says n/a rather than vanishing, and why on a first scan
  local stats = ns.StatsFor(id)
  local missing = stats.firstScan and "n/a (first scan)" or "n/a"

  local label = ns.Today() == day and "Against median" or "Against median (last scan)"
  local diff, word = ns.Versus(wall, stats)
  FadedRow(add, label, diff and ns.VersusText(diff, word) or missing)

  local PV = ns.PriceView
  local week = PV.Summary(PV.InRange(ns.Series(id), 7, time()))
  FadedRow(add, "7-day trend", week and week.trend and PV.TrendText(week.trend) or missing)

  local entry = ns.R().watch[id]
  if entry and entry.buy then
    FadedRow(add, "Your buy / sell", ns.MoneyFaded(entry.buy) .. " / " .. (entry.sell and ns.MoneyFaded(entry.sell) or "-"))
  end
end

-- Whether holding Shift would add anything: disenchant materials, a conversion's recipe or the
-- market context
local function HasDetail(id)
  return ns.DisenchantOutcomes(id) ~= nil or Outlet.CONVERSIONS[id] ~= nil or ns.LatestWall(id) ~= nil
end

-- Crafting ----------------------------------------------------------------------------------

local GAIN, LOSS = ns.COLOR.GAIN, ns.COLOR.LOSS
local MARKET_WORDS = { deep = "Deep", steady = "Steady", thin = "Thin", nodata = "No data" }

-- Crafting numbers as tooltip text, shared with the trainer rows (Trainer.lua)
local CraftingText = {}

function CraftingText.Profit(profit)
  if not profit then return GREY .. "no data|r" end
  if profit > 0 then return GAIN .. "+" .. ns.Money(profit) .. "|r" end
  return LOSS .. ns.Money(profit) .. "|r"
end

function CraftingText.Market(market)
  local word = MARKET_WORDS[market.level]
  if market.level == ns.Crafting.NO_DATA then return GREY .. word .. "|r" end
  return word .. " · " .. market.units .. " listed"
end

function CraftingText.Payback(payback)
  if payback == ns.Crafting.NEVER then return LOSS .. "never|r" end
  if not payback then return GREY .. "no data|r" end
  return payback .. (payback == 1 and " craft" or " crafts")
end

-- The Crafting block, after the MarketWall block: what a pattern teaches and earns. Payback is
-- left out once this character knows the recipe.
local function PatternLines(tooltip, add, id)
  local recipe, profession = ns.Professions.ByPattern(id)
  if not recipe then return end
  local evaluation = ns.Professions.Evaluate(recipe, ns.Professions.Context(profession))
  local function row(label, value) add(ROW .. FADED .. label .. "|r", value) end
  tooltip:AddLine(" ")
  add(HEADING .. "Crafting|r", "")
  row("Teaches", recipe.name .. (recipe.skill and " (" .. recipe.skill .. ")" or ""))
  row("Profit per craft", CraftingText.Profit(evaluation.profit))
  row("Market", CraftingText.Market(evaluation.market))
  if not recipe.known then
    local at = evaluation.learnCost and " at " .. ns.MoneyFaded(evaluation.learnCost) or ""
    row("Pays back" .. at, CraftingText.Payback(evaluation.payback))
  end
  row("You", recipe.known and GAIN .. "Known|r" or "Not known")
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

-- The MarketWall block: the heading, the outlet rows, and with Shift held the detail. Nothing for
-- an item with nothing to price, such as a hearthstone. Then a pattern's Crafting block.
local function AddLines(tooltip, id)
  if not id or not MarketWallDB then return end
  local function add(left, right) tooltip:AddDoubleLine(left, right) end
  local details = IsShiftKeyDown()

  -- the outlet rows wait until they show the item has a price, below the heading and the flag
  local rows = {}
  local priced = OutletLines(function(left, right) rows[#rows + 1] = { left, right } end,
    id, StackCount(tooltip, id), details)
  if priced then
    tooltip:AddLine(" ")
    add(HEADING .. "MarketWall|r", not details and HasDetail(id) and HINT .. "Shift: details|r" or "")
    LowDataFlag(add, id)
    for _, row in ipairs(rows) do add(row[1], row[2]) end
    if details then MarketContextLines(add, id) end
  end
  PatternLines(tooltip, add, id)
end

local function RedrawOnShift(_, _, key)
  if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
  for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tooltip:IsShown() and tooltip.RefreshData and tooltip:GetItem() then tooltip:RefreshData() end
  end
end

-- Mob tooltips -------------------------------------------------------------------------------

-- Seen kills, the ones values count, in orange and marked rough while they are under reliableKills
local function KillCount(seen, reliableKills)
  local kills = seen .. (seen == 1 and " kill" or " kills")
  if seen < reliableKills then return ORANGE .. kills .. ", rough|r" end
  return GREY .. kills .. "|r"
end

-- The lines a mob adds to its tooltip, from Mobs.Stats, as { left, right } pairs: worth per
-- kill (Optimal's median) alone, then its average beside the kill count, and the top drop.
-- Empty for a mob with no record or no seen kill.
local function MobLines(stats, reliableKills)
  if not (stats and stats.optimal) then return {} end
  local lines = {
    { GOLD .. "Worth per kill|r", WHITE .. ns.Money(stats.optimal.median) .. "|r" },
    { GREY .. "Average " .. ns.MoneyFaded(stats.optimal.average) .. "|r", KillCount(stats.seen, reliableKills) },
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
  local lines = MobLines(ns.Mobs.For(npc), ns.Cfg("mobMinKills"))
  if #lines == 0 then return end
  tooltip:AddLine(" ")
  for _, line in ipairs(lines) do tooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) end
end

ns.CraftingText = CraftingText
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
  local shift = CreateFrame("Frame")
  shift:RegisterEvent("MODIFIER_STATE_CHANGED")
  shift:SetScript("OnEvent", RedrawOnShift)
end
