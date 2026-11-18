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
Mobs.KEEP_KILLS = KEEP_KILLS

local function Merge(into, drops)
  for id, qty in pairs(drops) do into[id] = (into[id] or 0) + qty end
  return into
end

local function NewMob()
  return { kills = {}, life = { kills = 0, looted = 0, empty = 0, unseen = 0, coin = 0, drops = {}, gathered = 0, gather = {} } }
end

local OUTCOME_COUNTER = { [LOOTED] = "looted", [EMPTY] = "empty", [UNSEEN] = "unseen" }

-- Stores one settled kill event. Returns the kill record.
function Mobs.Add(mobs, event, keep)
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
  while #kills > (keep or KEEP_KILLS) do table.remove(kills, 1) end
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

-- Per-item prices under each lens, each worked out once per call
local function Lenses(prices, opts, unpriced)
  local cache = {}
  local function Of(id)
    local p = cache[id]
    if p then return p end
    local vendor = prices.vendor(id) or 0
    local wall, units = prices.wall(id)
    local market
    if wall and (units or 0) >= opts.minSupply then
      market = wall * (1 - opts.cut)
    elseif wall then
      market = vendor                       -- thin market
    else
      market = 0
      unpriced[id] = true
    end
    local best = math.max(vendor, market)
    local de = opts.disenchant and prices.disenchant(id)
    p = { vendor = vendor, market = market, gathered = best,
      optimal = de and math.max(best, de * (1 - opts.cut)) or best }
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

function Mobs.OptimalLabel(opts)
  local parts = {}
  if opts.skinning then parts[#parts + 1] = "skinning" end
  if opts.disenchant then parts[#parts + 1] = "DE" end
  if #parts == 0 then return "Optimal" end
  return "Optimal (incl. " .. table.concat(parts, ", ") .. ")"
end

-- Value per kill under every lens, from the stored kills at current prices. Unseen kills are
-- left out; 0c kills count. Below opts.minKills seen kills only the counts are returned.
-- prices: vendor(id), wall(id) -> wall, units, disenchant(id) -> copper or nil when not allowed
-- opts: cut, minSupply, disenchant, skinning (include in Optimal), rareShare, minKills
function Mobs.Stats(mob, prices, opts)
  local seen = {}
  for _, kill in ipairs(mob.kills) do
    if kill[K_OUTCOME] ~= UNSEEN then seen[#seen + 1] = kill end
  end
  local stats = { name = mob.name, kills = #mob.kills, lifetime = mob.life.kills, seen = #seen }
  if #seen < opts.minKills then return stats end

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

  local vendor, market, optimal, common, skinning = {}, {}, {}, {}, {}
  for _, kill in ipairs(seen) do
    local coin, drops, gather = kill[K_COIN] or 0, kill[K_DROPS], kill[K_GATHER]
    local skin = gather and Worth(gather, lens.gathered) or 0
    if gather then skinning[#skinning + 1] = skin end
    local extra = opts.skinning and skin or 0
    vendor[#vendor + 1] = coin + Worth(drops, lens.vendor)
    market[#market + 1] = coin + Worth(drops, lens.market)
    optimal[#optimal + 1] = coin + Worth(drops, lens.optimal) + extra
    common[#common + 1] = coin + Worth(drops, lens.optimal, rare) + extra
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
  stats.optimalNoRare = Summary(common)
  if top then stats.top = { id = top, share = dropped[top] / #seen } end
  return stats
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
    minSupply = ns.Cfg("minSupply"),
    disenchant = Included("mobDisenchant", function() return (ns.EnchantingSkill() or 0) > 0 end),
    skinning = Included("mobSkinning",
      function() return (ns.ProfessionSkill(SKINNING_SKILL_LINE, SKINNING_SPELL, "Skinning") or 0) > 0 end),
    rareShare = ns.Cfg("mobRareShare"),
    minKills = ns.Cfg("mobMinKills"),
  }
end

-- Disenchanting counts only for items this character has the skill for, unless set to "always"
function Mobs.GamePrices()
  local always = ns.Cfg("mobDisenchant") == "always"
  local skill = ns.EnchantingSkill() or 0
  return {
    vendor = function(id) return ItemInfo(id, 11) end,
    wall = function(id)
      local wall, _, units = ns.LatestWall(id)
      return wall, units
    end,
    disenchant = function(id)
      local level = ItemInfo(id, 4)
      if not (always or (level and skill >= ns.DisenchantSkill(level))) then return nil end
      return ns.DisenchantValue(id) or nil
    end,
  }
end

-- Stats for one mob at current prices, nil when it has never been killed
function Mobs.For(npc)
  local mob = MarketWallDB.mobs[npc]
  if mob then return Mobs.Stats(mob, Mobs.GamePrices(), Mobs.GameOptions()) end
end

local recent = {}   -- [guid] = { mob, record } for kills stored this session, so later gathers attach

ns.Recording.On("kill", function(event)
  local record = Mobs.Add(MarketWallDB.mobs, event)
  recent[event.guid] = { MarketWallDB.mobs[event.npc], record }
end)

ns.Recording.On("gather", function(event)
  local stored = event.guid and recent[event.guid]
  if stored then Mobs.AddGather(stored[1], stored[2], event.drops) end
end)
