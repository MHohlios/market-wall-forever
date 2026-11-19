-- MarketWall: per-mob kill records, fed by the recording core, and their value per kill.
-- Saved in MarketWallDB.mobs, shared by every character: [npcID] = {
--   name =,
--   kills = { { t, outcome, coin, drops, gather }, ... },   the last KEEP_KILLS, oldest first
--   life = { kills, looted, empty, unseen, coin, drops = {}, gathered, gather = {} },
-- }
-- outcome is Kills.LOOTED, EMPTY (0c) or UNSEEN. coin and drops are set only on looted kills,
-- gather only on kills you skinned or gathered. Drops are raw { [itemID] = qty }, never values.
local _, ns = ...

local Mobs = {}
ns.Mobs = Mobs

local LOOTED, EMPTY, UNSEEN = ns.Kills.LOOTED, ns.Kills.EMPTY, ns.Kills.UNSEEN
local K_OUTCOME, K_COIN, K_DROPS, K_GATHER = 2, 3, 4, 5   -- [1] is the time
local KEEP_KILLS = 1000
local SKINNING_SKILL_LINE, SKINNING_SPELL = 393, 8613

local function Merge(into, drops)
  for id, qty in pairs(drops) do into[id] = (into[id] or 0) + qty end
  return into
end

local function NewMob()
  return { kills = {}, life = { kills = 0, looted = 0, empty = 0, unseen = 0, coin = 0, drops = {}, gathered = 0, gather = {} } }
end

local OUTCOME_COUNTER = { [LOOTED] = "looted", [EMPTY] = "empty", [UNSEEN] = "unseen" }

-- Stores one settled kill event. Returns the kill record.
function Mobs.Add(mobs, event)
  local mob = mobs[event.npc]
  if not mob then mob = NewMob() mobs[event.npc] = mob end
  if event.name then mob.name = event.name end
  local record = { event.t, event.outcome }
  local life = mob.life
  life.kills = life.kills + 1
  life[OUTCOME_COUNTER[event.outcome]] = life[OUTCOME_COUNTER[event.outcome]] + 1
  if event.outcome == LOOTED then
    record[K_COIN] = event.coin or 0
    if event.drops and next(event.drops) then record[K_DROPS] = event.drops end
    life.coin = life.coin + record[K_COIN]
    Merge(life.drops, event.drops or {})
  end
  if event.gather and next(event.gather) then
    record[K_GATHER] = event.gather
    life.gathered = life.gathered + 1
    Merge(life.gather, event.gather)
  end
  local kills = mob.kills
  kills[#kills + 1] = record
  while #kills > KEEP_KILLS do table.remove(kills, 1) end
  return record
end

-- Adds a gather that came after its kill settled
function Mobs.AddGather(mob, record, drops)
  if not record[K_GATHER] then
    record[K_GATHER] = {}
    mob.life.gathered = mob.life.gathered + 1
  end
  Merge(record[K_GATHER], drops)
  Merge(mob.life.gather, drops)
end

-- Values ------------------------------------------------------------------------------------

local function Median(values)
  table.sort(values)
  local n = #values
  if n % 2 == 1 then return values[(n + 1) / 2] end
  return (values[n / 2] + values[n / 2 + 1]) / 2
end

local function Average(values)
  local sum = 0
  for _, v in ipairs(values) do sum = sum + v end
  return sum / #values
end

local function Summary(values)
  if #values == 0 then return nil end
  return { median = Median(values), average = Average(values), n = #values }
end

local function Worth(drops, price, skip)
  local total = 0
  for id, qty in pairs(drops or {}) do
    if not (skip and skip[id]) then total = total + qty * price(id) end
  end
  return total
end

-- Per-item prices under each lens, each worked out once per call. Farm sessions price with it
-- too, and the Sell page groups bags by the same rule (Outlet.lua). With prices.opened(id), a
-- container's history (Containers.lua), Optimal opens a container when that beats selling it.
local function Lenses(prices, opts, unpriced)
  local cache = {}
  local function Of(id)
    local p = cache[id]
    if p then return p end
    local v = ns.Outlet.Priced(prices, opts, id)
    if not v.auction then unpriced[id] = true end
    local opened = prices.opened and ns.Containers.OpenedValue(prices.opened(id), prices, opts)
    p = { vendor = v.vendor, market = v.market, gathered = v.gathered, optimal = math.max(v.best, opened or 0) }
    cache[id] = p
    return p
  end
  return {
    vendor = function(id) return Of(id).vendor end,
    market = function(id) return Of(id).market end,
    gathered = function(id) return Of(id).gathered end,
    optimal = function(id) return Of(id).optimal end,
  }
end

Mobs.Lenses = Lenses

function Mobs.OptimalLabel(opts)
  local parts = {}
  if opts.skinning then parts[#parts + 1] = "skinning" end
  if opts.disenchant then parts[#parts + 1] = "DE" end
  if #parts == 0 then return "Optimal" end
  return "Optimal (incl. " .. table.concat(parts, ", ") .. ")"
end

-- Value per kill under every lens, from the stored kills at current prices. Unseen kills are
-- left out; 0c kills count. With no seen kill only the counts are returned.
-- vendorNoRare, marketNoRare and optimalNoRare leave out drops seen in under opts.rareShare of kills.
-- prices: vendor(id), wall(id) -> wall and whether it has real supply, deposit(id) -> one unit's
-- auction deposit, disenchant(id) -> its materials' walls and their deposits, or nil when not allowed,
-- and optionally opened(id) -> a container's opened history (see Lenses)
-- opts: cut, disenchant, skinning (include in Optimal), rareShare
local function SeenKills(mob)
  local seen = {}
  for _, kill in ipairs(mob.kills) do
    if kill[K_OUTCOME] ~= UNSEEN then seen[#seen + 1] = kill end
  end
  return seen
end

function Mobs.Stats(mob, prices, opts)
  local seen = SeenKills(mob)
  local stats = { name = mob.name, kills = #mob.kills, lifetime = mob.life.kills, seen = #seen }
  if #seen == 0 then return stats end

  local unpriced = {}
  local lens = Lenses(prices, opts, unpriced)

  -- how many seen kills dropped each item, and its total Optimal value
  local dropped, worth = {}, {}
  for _, kill in ipairs(seen) do
    for id, qty in pairs(kill[K_DROPS] or {}) do
      dropped[id] = (dropped[id] or 0) + 1
      worth[id] = (worth[id] or 0) + qty * lens.optimal(id)
    end
  end
  local rare = {}
  for id, count in pairs(dropped) do
    if count / #seen < opts.rareShare then rare[id] = true end
  end

  local vendor, market, optimal, skinning = {}, {}, {}, {}
  local vendorCommon, marketCommon, optimalCommon = {}, {}, {}
  for _, kill in ipairs(seen) do
    local coin, drops, gather = kill[K_COIN] or 0, kill[K_DROPS], kill[K_GATHER]
    local skin = gather and Worth(gather, lens.gathered) or 0
    if gather then skinning[#skinning + 1] = skin end
    local extra = opts.skinning and skin or 0
    vendor[#vendor + 1] = coin + Worth(drops, lens.vendor)
    market[#market + 1] = coin + Worth(drops, lens.market)
    optimal[#optimal + 1] = coin + Worth(drops, lens.optimal) + extra
    vendorCommon[#vendorCommon + 1] = coin + Worth(drops, lens.vendor, rare)
    marketCommon[#marketCommon + 1] = coin + Worth(drops, lens.market, rare)
    optimalCommon[#optimalCommon + 1] = coin + Worth(drops, lens.optimal, rare) + extra
  end

  local top
  for id, total in pairs(worth) do
    if not top or total > worth[top] then top = id end
  end

  stats.vendor = Summary(vendor)
  stats.market = Summary(market)
  stats.market.unpriced = unpriced
  stats.skinning = Summary(skinning)
  stats.optimal = Summary(optimal)
  stats.optimal.label = Mobs.OptimalLabel(opts)
  stats.vendorNoRare = Summary(vendorCommon)
  stats.marketNoRare = Summary(marketCommon)
  stats.optimalNoRare = Summary(optimalCommon)
  if top then stats.top = { id = top, share = dropped[top] / #seen } end
  return stats
end

-- Each item the seen kills dropped: the share of seen kills it dropped in, its average quantity
-- when it drops, and one unit's value under each lens. Most value per kill first, under Optimal.
function Mobs.DropTable(mob, prices, opts)
  local seen = SeenKills(mob)
  local lens = Lenses(prices, opts, {})
  local dropped, total = {}, {}
  for _, kill in ipairs(seen) do
    for id, qty in pairs(kill[K_DROPS] or {}) do
      dropped[id] = (dropped[id] or 0) + 1
      total[id] = (total[id] or 0) + qty
    end
  end
  local rows = {}
  for id, count in pairs(dropped) do
    rows[#rows + 1] = { id = id, share = count / #seen, quantity = total[id] / count,
      vendor = lens.vendor(id), market = lens.market(id), optimal = lens.optimal(id) }
  end
  table.sort(rows, function(a, b)
    local x, y = a.share * a.quantity * a.optimal, b.share * b.quantity * b.optimal
    if x ~= y then return x > y end
    return a.id < b.id
  end)
  return rows
end

-- In game -----------------------------------------------------------------------------------

-- "auto", "always" or "never" from a setting, with auto deciding on whether the skill is known
local function Included(setting, hasSkill)
  local mode = ns.Cfg(setting)
  if mode == "always" then return true end
  if mode == "never" then return false end
  return hasSkill()
end

local function ItemInfo(id, field)
  return C_Item.GetItemInfo and select(field, C_Item.GetItemInfo(id))
end

function Mobs.GameOptions()
  return {
    cut = ns.Cfg("ahCut"),
    disenchant = Included("mobDisenchant", function() return (ns.EnchantingSkill() or 0) > 0 end),
    skinning = Included("mobSkinning",
      function() return (ns.ProfessionSkill(SKINNING_SKILL_LINE, SKINNING_SPELL, "Skinning") or 0) > 0 end),
    rareShare = ns.Cfg("mobRareShare"),
  }
end

-- Disenchanting counts only for items this character has the skill for, unless set to "always".
-- Deposits are estimated at the Sell page's duration, once per item for these prices' lifetime.
function Mobs.GamePrices()
  local always = ns.Cfg("mobDisenchant") == "always"
  local skill = ns.EnchantingSkill() or 0
  local duration = ns.Cfg("sellDuration")
  local deposits = {}
  local function Deposit(id)
    local deposit = deposits[id]
    if not deposit then
      deposit = ns.EstimateDeposit(id, duration)
      deposits[id] = deposit
    end
    return deposit
  end
  return {
    vendor = function(id) return ItemInfo(id, 11) end,
    wall = function(id)
      return ns.LatestWall(id), ns.R().supplied[id] == true
    end,
    deposit = Deposit,
    disenchant = function(id)
      local level = ItemInfo(id, 4)
      if not (always or (level and skill >= ns.DisenchantSkill(level))) then return nil end
      local value, _, materialDeposits = ns.DisenchantValue(id, Deposit)
      if value then return value, materialDeposits end
    end,
  }
end

-- GamePrices with what each container opens into, for mob values only. Farm sessions leave it
-- out, as they count a container's contents when it is opened, and so does the Sell page.
function Mobs.MobPrices()
  local prices = Mobs.GamePrices()
  prices.opened = function(id) return MarketWallDB.containers[id] end
  return prices
end

local cache = {}   -- [npcID] = stats, or false for a mob never killed

-- Stats for one mob at current prices, nil when it has never been killed. Cached until the mob
-- gets a new kill, or Mobs.Invalidate after a scan or a settings change.
function Mobs.For(npc)
  local stats = cache[npc]
  if stats == nil then
    local mob = MarketWallDB.mobs[npc]
    stats = mob and Mobs.Stats(mob, Mobs.MobPrices(), Mobs.GameOptions()) or false
    cache[npc] = stats
  end
  return stats or nil
end

function Mobs.Invalidate()
  cache = {}
end

-- Stats for every recorded mob, each with its npc ID
function Mobs.All()
  local all = {}
  for npc in pairs(MarketWallDB.mobs) do
    local stats = Mobs.For(npc)
    stats.npc = npc
    all[#all + 1] = stats
  end
  return all
end

function Mobs.GameDropTable(npc)
  return Mobs.DropTable(MarketWallDB.mobs[npc], Mobs.MobPrices(), Mobs.GameOptions())
end

local recent = {}   -- [guid] = { mob, record } for kills stored this session, so later gathers attach

ns.Recording.On("kill", function(event)
  local record = Mobs.Add(MarketWallDB.mobs, event)
  recent[event.guid] = { MarketWallDB.mobs[event.npc], record }
  cache[event.npc] = nil
  ns.SearchChanged()
end)

ns.Recording.On("gather", function(event)
  local stored = event.guid and recent[event.guid]
  if stored then
    Mobs.AddGather(stored[1], stored[2], event.drops)
    cache[event.npc] = nil
    ns.SearchChanged()
  end
end)

-- Vendor prices and item levels arrive late after login, and professions may not be known at
-- first hover: stats priced without them are dropped, and recomputed when next asked for
local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loader:RegisterEvent("SKILL_LINES_CHANGED")
loader:SetScript("OnEvent", Mobs.Invalidate)
