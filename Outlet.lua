-- MarketWall: the best outlet for one unit of an item: the auction house, a vendor or
-- disenchanting, after the auction house's fees. Mob values' lenses (Mobs.lua), farm sessions,
-- the item tooltip and the Sell page's bag groups share this rule, so they never disagree.
local _, ns = ...

local Outlet = {}
ns.Outlet = Outlet

Outlet.AUCTION, Outlet.DISENCHANT, Outlet.VENDOR, Outlet.NO_DATA = "auction", "disenchant", "vendor", "nodata"

-- What selling at a listed price leaves: the price after the cut, less the deposit. The game
-- refunds the deposit when the auction sells, so this is the worst case.
function Outlet.Net(listed, cut, deposit)
  return listed * (1 - cut) - deposit
end

-- One unit's worth through each outlet, and the best of them.
-- p: vendor (copper or nil), wall (the last recorded wall, nil without history), supplied (the
-- wall has real supply behind it), disenchant (its materials' walls, nil when not counted),
-- disenchantDeposit (the deposits to list those materials), cut, deposit (per unit). Deposits
-- are 0 when left out.
-- Returns vendor; auction, the wall after the cut and deposit (nil without a wall); market, the
-- Market lens (auction, or the vendor price when the market is too thin to trust); gathered, the
-- better of vendor and market; disenchant after the cut and deposits on its materials; best;
-- outlet; and thin.
function Outlet.Values(p)
  local vendor = p.vendor or 0
  local auction = p.wall and Outlet.Net(p.wall, p.cut, p.deposit or 0)
  local thin = auction ~= nil and not p.supplied
  local market = 0
  if auction then market = thin and vendor or auction end
  local gathered = math.max(vendor, market)
  local disenchant = p.disenchant and Outlet.Net(p.disenchant, p.cut, p.disenchantDeposit or 0) or nil
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

-- Outlet.Values for an item at prices (Mobs.GamePrices or a test's) and options (cut,
-- disenchant). deposit: the real one for one unit, or nil for prices.deposit's estimate.
function Outlet.Priced(prices, opts, id, deposit)
  local wall, supplied = prices.wall(id)
  local disenchant, disenchantDeposit
  if opts.disenchant then disenchant, disenchantDeposit = prices.disenchant(id) end
  return Outlet.Values({ vendor = prices.vendor(id), wall = wall, supplied = supplied,
    disenchant = disenchant, disenchantDeposit = disenchantDeposit, cut = opts.cut,
    deposit = deposit or prices.deposit(id) })
end

-- Outlet.Values for items in game, at the mob values' prices and disenchanting setting, read
-- once for a whole bag: returns a function of the item ID and, when known, its real deposit for
-- one unit.
function Outlet.Game()
  local prices, opts = ns.Mobs.GamePrices(), ns.Mobs.GameOptions()
  return function(id, deposit)
    return Outlet.Priced(prices, opts, id, deposit)
  end
end

-- Deposits ----------------------------------------------------------------------------------

-- The game prices deposits only at the auction house, as a share of the vendor price that grows
-- with the duration. Until a real deposit teaches MarketWall the rate, it assumes the standard
-- 15% per 12 hours. Learned rates are saved in MarketWallDB.depositRate[duration].
Outlet.DEFAULT_DEPOSIT_RATES = { 0.15, 0.30, 0.60 }   -- 12h, 24h, 48h
-- Deposits are whole copper: smaller posts round too much to learn a rate from
local MIN_LEARNING_VALUE = 100

function Outlet.DepositRate(duration)
  return MarketWallDB.depositRate[duration] or Outlet.DEFAULT_DEPOSIT_RATES[duration]
end

-- Keeps the rate of a real deposit for vendorValue copper of items, the latest one winning
function Outlet.LearnDepositRate(duration, deposit, vendorValue)
  if vendorValue >= MIN_LEARNING_VALUE then MarketWallDB.depositRate[duration] = deposit / vendorValue end
end

-- The deposit for one unit of an item away from the auction house: 0 without a vendor price
function ns.EstimateDeposit(id, duration)
  local vendor = C_Item.GetItemInfo and select(11, C_Item.GetItemInfo(id)) or 0
  return vendor * Outlet.DepositRate(duration)
end
