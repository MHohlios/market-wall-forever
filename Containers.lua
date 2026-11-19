-- MarketWall: what each container item, such as a clam, opens into, fed by the recording core's
-- container loot (Kills.lua). Opened loot is never credited back to the kill that dropped the
-- container: clams stack and are opened later. Instead a container dropped by a mob is valued in
-- its Optimal at what it opens into on average (Mobs.lua).
-- Saved in MarketWallDB.containers, shared by every character:
--   [containerItemID] = { opens =, coin =, drops = { [itemID] = qty } }
-- Drops are raw quantities, never values, as in Mobs.lua.
local _, ns = ...

local Containers = {}
ns.Containers = Containers

-- Stores one opened container's loot event
function Containers.Add(containers, event)
  local history = containers[event.container]
  if not history then
    history = { opens = 0, coin = 0, drops = {} }
    containers[event.container] = history
  end
  history.opens = history.opens + 1
  history.coin = history.coin + (event.coin or 0)
  for id, qty in pairs(event.drops or {}) do history.drops[id] = (history.drops[id] or 0) + qty end
end

-- One opening's average worth: its coin plus each content at its best outlet, at prices and opts
-- as Outlet.Priced takes them. Nil without history.
function Containers.OpenedValue(history, prices, opts)
  if not (history and history.opens > 0) then return nil end
  local total = history.coin
  for id, qty in pairs(history.drops) do total = total + qty * ns.Outlet.Priced(prices, opts, id).best end
  return total / history.opens
end

ns.Recording.On("loot", function(event)
  if not event.container then return end
  Containers.Add(MarketWallDB.containers, event)
  ns.Mobs.Invalidate()   -- a mob that drops this container is worth more or less now
  ns.SearchChanged()
end)
