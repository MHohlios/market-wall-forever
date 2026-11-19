-- MarketWall: the best outlet for one unit of an item: the auction house, a vendor or
-- disenchanting. Mob values' lenses (Mobs.lua) and the Sell page's bag groups share this rule,
-- so the two never disagree.
local _, ns = ...

local Outlet = {}
ns.Outlet = Outlet

Outlet.AUCTION, Outlet.DISENCHANT, Outlet.VENDOR, Outlet.NO_DATA = "auction", "disenchant", "vendor", "nodata"

-- One unit's worth through each outlet, and the best of them.
-- p: vendor (copper or nil), wall (the last recorded wall, nil without history), supplied (the
-- wall has real supply behind it), disenchant (value before the cut, nil when not counted),
-- cut, deposit (per unit, 0 when left out).
-- Returns vendor; auction, the wall after the cut and deposit (nil without a wall); market, the
-- Market lens (auction, or the vendor price when the market is too thin to trust); gathered, the
-- better of vendor and market; disenchant after the cut on its materials; best; outlet; and thin.
function Outlet.Values(p)
  local vendor = p.vendor or 0
  local auction = p.wall and p.wall * (1 - p.cut) - (p.deposit or 0)
  local thin = auction ~= nil and not p.supplied
  local market = 0
  if auction then market = thin and vendor or auction end
  local gathered = math.max(vendor, market)
  local disenchant = p.disenchant and p.disenchant * (1 - p.cut) or nil
  local best = disenchant and math.max(gathered, disenchant) or gathered

  local outlet
  if not p.wall then
    outlet = Outlet.NO_DATA
  elseif disenchant and disenchant > gathered then
    outlet = Outlet.DISENCHANT
  elseif market > vendor then
    outlet = Outlet.AUCTION
  else
    outlet = Outlet.VENDOR
  end
  return { vendor = vendor, auction = auction, market = market, gathered = gathered,
    disenchant = disenchant, best = best, outlet = outlet, thin = thin }
end

-- Outlet.Values for items in game, at the mob values' prices and disenchanting setting, read
-- once for a whole bag: returns a function of the item ID and its deposit for one unit.
function Outlet.Game()
  local prices, opts = ns.Mobs.GamePrices(), ns.Mobs.GameOptions()
  return function(id, deposit)
    local wall, supplied = prices.wall(id)
    return Outlet.Values({ vendor = prices.vendor(id), wall = wall, supplied = supplied,
      disenchant = opts.disenchant and prices.disenchant(id) or nil, cut = opts.cut, deposit = deposit })
  end
end
