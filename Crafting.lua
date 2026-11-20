-- MarketWall: pure crafting logic, what one recipe costs and earns at given prices. No game API in
-- this file so it can be tested outside the game; Professions.lua reads recipes and prices in game.
--
-- A recipe, from a bundled table (Recipes/*.lua), this character's profession window, or both
-- merged by Crafting.Merge:
--   product   item ID made
--   made      units made per craft, the average when the game makes a range
--   reagents  { { id, count }, ... }
--   name      the recipe's name, as trainers and the profession window show it
--   skill     required skill, nil when unknown
--   skillUp   { yellow, green, grey } ranks where skill-ups get rarer, nil when unknown
--   pattern   item ID of the pattern or plans that teach it, nil when not taught by an item
--   source    where it is learned: { kind = "trainer" | "vendor" | "drop" | "quest", cost =
--             copper for trainer and vendor, limited = true for limited vendor supply }
--   colour    the profession window's skill colour, for known recipes
--   known     true when this character knows it; forever, true for Forever-only products
local _, ns = ...
local Outlet = ns.Outlet

local Crafting = {}
ns.Crafting = Crafting

Crafting.DEEP, Crafting.STEADY, Crafting.THIN, Crafting.NO_DATA = "deep", "steady", "thin", "nodata"
Crafting.RED, Crafting.ORANGE, Crafting.YELLOW, Crafting.GREEN, Crafting.GREY = "red", "orange", "yellow", "green", "grey"
Crafting.NEVER = "never"
Crafting.FIRST_FOREVER_ITEM = 200000   -- item IDs from here on exist only on WoW Forever

-- Mats cost --------------------------------------------------------------------------------

-- What one craft's reagents cost: a vendor-sold reagent at its vendor buy price, any other at its
-- wall. Returns the total, nil when any reagent has no price, and each reagent's line:
-- { id, count, unit, cost, source = "vendor" | "wall" }, with unit, cost and source nil unpriced.
-- prices: wall(id) as in Outlet.Priced; buy(id): the vendor's price, nil when no vendor sells it.
function Crafting.Cost(recipe, prices)
  local total, lines = 0, {}
  for i, reagent in ipairs(recipe.reagents) do
    local id, count = reagent[1], reagent[2]
    local unit, source = prices.buy(id), "vendor"
    if not unit then unit, source = prices.wall(id), "wall" end
    if not unit then source = nil end
    lines[i] = { id = id, count = count, unit = unit, cost = unit and unit * count, source = source }
    total = total and unit and total + unit * count
  end
  return total, lines
end

-- Market ------------------------------------------------------------------------------------

-- Deep needs twice the units the default "supplied" rule asks for (minSupply, 20), so a few crafts
-- sold a day leave the market supplied, and a record on 5 of the last 7 days, so the listings come
-- back nearly every day you scan rather than once.
local DEEP_UNITS, DEEP_DAYS, WINDOW_DAYS = 40, 5, 7
local D_UNITS = 4   -- in a daily record, see Data.lua

-- How easy a product is to sell, from its listings: the auction house reports no sales. days is
-- the product's daily records (r.days[id]), today the current day, supplied whether its latest
-- listings had real supply (the rule Outlet uses for thin markets). Returns { level, units on the
-- latest recorded day, recent = days with a record in the last 7 }.
function Crafting.Market(days, today, supplied)
  local latest, recent = nil, 0
  for day in pairs(days or {}) do
    if not latest or day > latest then latest = day end
    if day > today - WINDOW_DAYS and day <= today then recent = recent + 1 end
  end
  if not latest then return { level = Crafting.NO_DATA, units = 0, recent = 0 } end
  local units = days[latest][D_UNITS] or 0
  local level = Crafting.STEADY
  if not supplied then
    level = Crafting.THIN
  elseif units >= DEEP_UNITS and recent >= DEEP_DAYS then
    level = Crafting.DEEP
  end
  return { level = level, units = units, recent = recent }
end

-- Learning ----------------------------------------------------------------------------------

-- What learning a recipe costs: its pattern's wall when listed, else the vendor's or trainer's
-- price. Returns the cost and "wall", "vendor" or "trainer"; nil for a drop or quest with no wall.
function Crafting.LearnCost(recipe, prices)
  local wall = recipe.pattern and prices.wall(recipe.pattern)
  if wall then return wall, "wall" end
  local source = recipe.source
  if source and source.cost and (source.kind == "vendor" or source.kind == "trainer") then
    return source.cost, source.kind
  end
end

-- Crafts until the profit pays back the learn cost, rounded up; Crafting.NEVER when a craft makes
-- no profit; nil when either is unknown
function Crafting.Payback(learnCost, profit)
  if not (learnCost and profit) then return nil end
  if profit <= 0 then return Crafting.NEVER end
  return math.ceil(learnCost / profit)
end

-- Skill colour ------------------------------------------------------------------------------

-- The skill-up colour at a rank: red below the required skill, then the profession window's
-- colour for a known recipe, else the table's thresholds. Nil when nothing says.
function Crafting.SkillColour(recipe, rank)
  if rank and recipe.skill and rank < recipe.skill then return Crafting.RED end
  if recipe.colour then return recipe.colour end
  local up = recipe.skillUp
  if not (rank and up) then return nil end
  if rank < up[1] then return Crafting.ORANGE end
  if rank < up[2] then return Crafting.YELLOW end
  if rank < up[3] then return Crafting.GREEN end
  return Crafting.GREY
end

-- One recipe --------------------------------------------------------------------------------

-- A recipe's numbers at given prices. at:
--   prices, opts  as for Outlet.Priced, with prices.buy(id) as for Crafting.Cost
--   days(id)      the item's daily records, today the current day (for Crafting.Market)
--   rank          the player's skill in the profession, nil when unknown
-- Returns { recipe, cost, mats (Crafting.Cost's lines), outlet (Outlet.Values for one unit),
-- net, profit, margin, market, learnCost, learnSource, payback, colour }. cost, net, profit,
-- margin and payback are nil when unknown: net is unknown when no outlet prices the product.
function Crafting.Evaluate(recipe, at)
  local cost, mats = Crafting.Cost(recipe, at.prices)
  local outlet = Outlet.Priced(at.prices, at.opts, recipe.product)
  local unpriced = outlet.outlet == Outlet.NO_DATA and outlet.best == 0
  local net = not unpriced and outlet.best * recipe.made or nil
  local profit = cost and net and net - cost
  local _, supplied = at.prices.wall(recipe.product)
  local learnCost, learnSource = Crafting.LearnCost(recipe, at.prices)
  return {
    recipe = recipe, cost = cost, mats = mats, outlet = outlet, net = net, profit = profit,
    margin = profit and cost > 0 and profit / cost or nil,
    market = Crafting.Market(at.days(recipe.product), at.today, supplied),
    learnCost = learnCost, learnSource = learnSource, payback = Crafting.Payback(learnCost, profit),
    colour = Crafting.SkillColour(recipe, at.rank),
  }
end

-- Ranking -----------------------------------------------------------------------------------

local function Unsure(evaluation)
  local level = evaluation.market.level
  return level == Crafting.THIN or level == Crafting.NO_DATA
end

-- Sorts evaluations in place, most profit first and unknown profit last. At equal profit, thin
-- markets and those with no data come after the rest; then by product, so the order is stable.
function Crafting.Rank(evaluations)
  table.sort(evaluations, function(a, b)
    if a.profit ~= b.profit then
      if not a.profit or not b.profit then return b.profit == nil end
      return a.profit > b.profit
    end
    if Unsure(a) ~= Unsure(b) then return Unsure(b) end
    return a.recipe.product < b.recipe.product
  end)
  return evaluations
end

-- Merging -----------------------------------------------------------------------------------

local function Copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

-- This character's known recipes ([product] = recipe) with a bundled table's (a list), one entry
-- per product. A known recipe's own fields win; the table fills in the rest (skill, skillUp,
-- pattern, source). Each entry is a copy flagged known and forever.
function Crafting.Merge(known, bundled)
  local byProduct, list = {}, {}
  for _, recipe in ipairs(bundled or {}) do
    local entry = Copy(recipe)
    entry.known = false
    byProduct[recipe.product] = entry
    list[#list + 1] = entry
  end
  for product, recipe in pairs(known or {}) do
    local entry = byProduct[product]
    if not entry then
      entry = {}
      list[#list + 1] = entry
    end
    for k, v in pairs(recipe) do entry[k] = v end
    entry.product, entry.known = product, true
  end
  for _, entry in ipairs(list) do entry.forever = entry.product >= Crafting.FIRST_FOREVER_ITEM end
  return list
end
