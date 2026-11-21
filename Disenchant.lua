-- MarketWall: expected disenchant value, priced from MarketWall's own material walls.
-- Outcome data adapted from Disenchantry (MIT, see LICENSES/Disenchantry.txt). An item's odds
-- start from a prior: a Forever estimate (specific new crafted items, and new rares with IDs from
-- 200000) or else the classic disenchanting tables (original-era item levels, which Forever
-- uses). Your own disenchants, from MarketWall's disenchant log (DisenchantLog.lua), are blended
-- in as they come: for the item itself when Forever estimates it, otherwise for its kind.
local _, ns = ...

local WEAPON, ARMOR = 2, 4
local UNCOMMON, RARE, EPIC = 2, 3, 4
local NEW_ITEM_ID = 200000      -- Forever's own items start here
-- The prior counts as this many disenchants: 20 of your own would measure a 75% chance only
-- to about ±20% and barely sample a 5% shard
local PRIOR_WEIGHT = 50
local MIN_SAMPLES = 20          -- with no prior, your own results alone count from this many
local SALVAGER_BUFF = 1283701   -- Forever buff that raises disenchant yields
local SALVAGER_MODES = { auto = true, on = true, off = true }
local NO_RESULTS = { hits = 0, total = 0 }

-- One material from a disenchant: its chance (0-1), average quantity when it drops, and the
-- fewest and most in one disenchant, nil when only the average is known
local function Outcome(id, chance, quantity, min, max)
  return { id = id, chance = chance, quantity = quantity, min = min, max = max }
end

-- Uncommon (green) gear: { minLevel, maxLevel, dust, essence, shard, armorDust%, armorEssence%,
-- weaponDust%, weaponEssence%, dustMin, dustMax, essenceMin, essenceMax }. Shards take the rest.
local UNCOMMON_ROWS = {
  { 5, 15, 10940, 10938, nil, 80, 20, 20, 80, 1, 2, 1, 2 },
  { 16, 20, 10940, 10939, 10978, 75, 20, 20, 75, 2, 3, 1, 2 },
  { 21, 25, 10940, 10998, 10978, 75, 15, 15, 75, 4, 6, 1, 2 },
  { 26, 30, 11083, 11082, 11084, 75, 20, 20, 75, 1, 2, 1, 2 },
  { 31, 35, 11083, 11134, 11138, 75, 20, 20, 75, 2, 5, 1, 2 },
  { 36, 40, 11137, 11135, 11139, 75, 20, 20, 75, 1, 2, 1, 2 },
  { 41, 45, 11137, 11174, 11177, 75, 20, 20, 75, 2, 5, 1, 2 },
  { 46, 50, 11176, 11175, 11178, 75, 20, 20, 75, 1, 2, 1, 2 },
  { 51, 55, 11176, 16202, 14343, 75, 20, 22, 75, 2, 5, 1, 2 },
  { 56, 60, 16204, 16203, 14344, 75, 20, 22, 75, 1, 2, 1, 2 },
  { 61, 65, 16204, 16203, 14344, 75, 20, 22, 75, 2, 5, 2, 3 },
}
-- Rare (blue) gear: { minLevel, maxLevel, shard, nexusCrystal }; the crystal is a 0.5% chance
local RARE_ROWS = {
  { 1, 25, 10978 }, { 26, 30, 11084 }, { 31, 35, 11138 }, { 36, 40, 11139 },
  { 41, 45, 11177 }, { 46, 50, 11178 }, { 51, 55, 14343 }, { 56, 80, 14344, 20725 },
}
-- Epic (purple) gear: { minLevel, maxLevel, material, minQuantity, maxQuantity }
local EPIC_ROWS = {
  { 40, 45, 11177, 2, 4 }, { 46, 50, 11178, 2, 4 }, { 51, 55, 14343, 2, 4 },
  { 56, 60, 20725, 1, 1 }, { 61, 88, 20725, 1, 2 },
}
-- Enchanter-made wands cannot be disenchanted
local NO_DISENCHANT = {
  [11287] = true, [11288] = true, [11289] = true, [11290] = true,
  [247789] = true, [249144] = true, [249234] = true, [249232] = true, [249237] = true, [249385] = true,
}

-- Forever's new low- and mid-level crafts, estimated by Disenchantry's author, each material as
-- { materialID, chance, average quantity }
local LOW_CRAFT = { { 10940, 0.80, 2.5 }, { 10938, 0.20, 2.5 } }
local MID_CRAFT = { { 10940, 0.75, 3.5 }, { 10939, 0.20, 2.5 }, { 10978, 0.05, 2 } }
local CRAFT_ESTIMATES = {}
for _, id in ipairs({ 250620, 250482, 250621, 252424, 252425, 252426, 252427, 253885, 253887 }) do
  CRAFT_ESTIMATES[id] = LOW_CRAFT
end
for _, id in ipairs({ 250513, 250514, 250515, 250516, 250517, 250508, 250509, 250510, 250511, 250512, 250489,
  252428, 252429, 252430, 252431, 252432, 252433, 252494, 252495, 252496, 252497, 252498, 252499,
  253889, 253891, 253893, 253895, 253897, 253899, 253901, 253903, 253905, 253907, 253909, 253911,
  253913, 253915, 253917, 253919, 253921, 253923 }) do
  CRAFT_ESTIMATES[id] = MID_CRAFT
end
-- Shards for Forever's new rares above item level 20: { maxLevel, shard }
local NEW_RARE_SHARDS = {
  { 25, 10978 }, { 30, 11084 }, { 35, 11138 }, { 40, 11139 }, { 45, 11177 }, { 50, 11178 }, { 55, 14343 },
}

local function Find(rows, level)
  for _, row in ipairs(rows) do
    if level >= row[1] and level <= row[2] then return row end
  end
end

local function NewRareEstimate(level, weapon)
  if level < 5 or level > 99 then return nil end
  if level <= 15 then
    return { { 10940, weapon and 0.20 or 0.80, 2.5 }, { 10938, weapon and 0.80 or 0.20, 2.5 } }
  end
  if level <= 20 then
    return { { 10940, weapon and 0.20 or 0.75, 3.5 }, { 10939, weapon and 0.75 or 0.20, 2.5 }, { 10978, 0.05, 2 } }
  end
  for _, row in ipairs(NEW_RARE_SHARDS) do
    if level <= row[1] then return { { row[2], 1, 1 } } end
  end
  return { { 14344, 0.995, 1 }, { 20725, 0.005, 1 } }
end

local function ClassicTable(quality, level, weapon)
  if quality == UNCOMMON then
    local row = Find(UNCOMMON_ROWS, level)
    if not row then return nil end
    local dust, essence = row[weapon and 8 or 6], row[weapon and 9 or 7]
    local essenceID = row[4]
    -- Forever: uncommon weapons of item level 21-30 give Greater Magic Essence
    if weapon and level >= 21 and level <= 30 then essenceID = 10939 end
    local out = {
      Outcome(row[3], dust / 100, (row[10] + row[11]) / 2, row[10], row[11]),
      Outcome(essenceID, essence / 100, (row[12] + row[13]) / 2, row[12], row[13]),
    }
    if row[5] then out[3] = Outcome(row[5], (100 - dust - essence) / 100, 1, 1, 1) end
    return out
  elseif quality == RARE then
    local row = Find(RARE_ROWS, level)
    if not row then return nil end
    if row[4] then return { Outcome(row[3], 0.995, 1, 1, 1), Outcome(row[4], 0.005, 1, 1, 1) } end
    return { Outcome(row[3], 1, 1, 1, 1) }
  elseif quality == EPIC then
    local row = Find(EPIC_ROWS, level)
    if row then return { Outcome(row[3], 1, (row[4] + row[5]) / 2, row[4], row[5]) } end
  end
end

-- An estimate's materials as outcomes: averages only
local function Estimated(estimate)
  local out = {}
  for i, e in ipairs(estimate) do out[i] = Outcome(e[1], e[2], e[3]) end
  return out
end

local function HasSalvagerBuff()
  if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return false end
  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SALVAGER_BUFF)
  return ok and type(aura) == "table"
end

-- The salvagerMode setting: "on", "off", or "auto" (the default) whenever the buff is up.
-- Your disenchants are recorded and looked up under it.
function ns.SalvagerActive()
  local mode = ns.Cfg("salvagerMode")
  if not SALVAGER_MODES[mode] then mode = ns.cfgDefaults.salvagerMode end
  if mode == "off" then return false end
  return mode == "on" or HasSalvagerBuff()
end
local SalvagerActive = ns.SalvagerActive

local function SalvagerBonus()
  if not SalvagerActive() then return 0 end
  local bonus = tonumber(ns.Cfg("salvagerBonus")) or 0
  return math.max(0, math.min(1000, bonus)) / 100
end

-- Whether Forever estimates this item's odds itself: its new crafts and its new rares
function ns.HasForeverEstimate(id, quality)
  return CRAFT_ESTIMATES[id] ~= nil or (quality == RARE and id >= NEW_ITEM_ID)
end

-- The prior's outcomes and its name, nil when the item has neither an estimate nor a table row
local function Prior(id, quality, level, classID)
  if CRAFT_ESTIMATES[id] then return Estimated(CRAFT_ESTIMATES[id]), "Forever estimate" end
  if classID ~= WEAPON and classID ~= ARMOR then return nil end
  local weapon = classID == WEAPON
  if quality == RARE and id >= NEW_ITEM_ID then
    local estimate = NewRareEstimate(level, weapon)
    if estimate then return Estimated(estimate), "Forever estimate" end
    return nil
  end
  local classic = ClassicTable(quality, level, weapon)
  if classic then return classic, "Classic table" end
end

-- The prior's quantities with the Salvager bonus, as your own Salvager results already have it
local function Scaled(outcomes, scale)
  local out = {}
  for i, o in ipairs(outcomes) do
    out[i] = Outcome(o.id, o.chance, o.quantity * scale, o.min and o.min * scale, o.max and o.max * scale)
  end
  return out
end

-- Materials only your results have, each at hits / denominator, with their recorded range
local function AddOwnOnly(out, materials, denominator, known)
  for id, m in pairs(materials) do
    if m.hits > 0 and not known[id] then
      out[#out + 1] = Outcome(id, m.hits / denominator, m.total / m.hits, m.min, m.max)
    end
  end
end

-- The prior counted as PRIOR_WEIGHT disenchants, plus your n. A material's chance is its share of
-- all those disenchants, and its average quantity the mean over every time it dropped. Your
-- fewest and most widen the prior's range; a prior with no range (an estimate) keeps none.
local function Blend(prior, materials, n)
  local out, known = {}, {}
  for i, p in ipairs(prior) do
    local own = materials[p.id] or NO_RESULTS
    local weight = PRIOR_WEIGHT * p.chance
    local min = p.min and math.min(p.min, own.min or p.min)
    local max = p.max and math.max(p.max, own.max or p.max)
    out[i] = Outcome(p.id, (weight + own.hits) / (PRIOR_WEIGHT + n),
      (weight * p.quantity + own.total) / (weight + own.hits), min, max)
    known[p.id] = true
  end
  AddOwnOnly(out, materials, PRIOR_WEIGHT + n, known)
  return out
end

local function Disenchants(n)
  return n .. (n == 1 and " disenchant" or " disenchants")
end

-- The outcomes, with any Salvager bonus in their quantities, and where they came from:
-- "Classic table", "Forever estimate", either with " + your 34 disenchants", or "Your 34
-- disenchants" for an item with no prior. Your own results are for the item, under the current
-- Salvager setting.
local function Outcomes(id)
  if NO_DISENCHANT[id] or not C_Item.GetItemInfo then return nil end
  local _, _, quality, level, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(id)
  if not (quality and level and classID) then return nil end

  local sample = ns.DisenchantLog.Sample(id, quality, level, classID, SalvagerActive())
  local n = sample and sample.count or 0
  local materials = sample and sample.materials or {}
  local prior, name = Prior(id, quality, level, classID)
  if not prior then
    if n < MIN_SAMPLES then return nil end
    local out = {}
    AddOwnOnly(out, materials, n, {})
    if #out > 0 then return out, "Your " .. Disenchants(n) end
    return nil
  end
  local blended = Blend(Scaled(prior, 1 + SalvagerBonus()), materials, n)
  if n == 0 then return blended, name end
  return blended, name .. " + your " .. Disenchants(n)
end

-- Expected copper from disenchanting one item, at each material's latest wall price, and the
-- name of where its odds come from, as Outcomes gives it. Nil when the item cannot be
-- disenchanted; false when a likely material has no price yet. With depositOf(materialID), the
-- one-unit deposit to list a material, it also returns the expected deposits to list the
-- materials; a material with no price counts neither.
function ns.DisenchantValue(id, depositOf)
  local outcomes, source = Outcomes(id)
  if not outcomes then return nil end
  local total, deposits = 0, depositOf and 0
  for _, o in ipairs(outcomes) do
    local price = ns.LatestWall(o.id)
    if price then
      total = total + o.chance * o.quantity * price
      if deposits then deposits = deposits + o.chance * o.quantity * depositOf(o.id) end
    elseif o.chance >= 0.01 then
      return false
    end
  end
  return total, source, deposits
end

-- What disenchanting one item gives: a list of { id, chance (0-1), quantity, min, max }, where
-- quantity is the average when it drops and min and max the fewest and most in one disenchant
-- (nil when only the average is known), all with any Salvager bonus as DisenchantValue counts
-- it; and where the odds come from. Nil when it cannot be disenchanted.
function ns.DisenchantOutcomes(id)
  return Outcomes(id)
end

-- The Enchanting skill the classic rules ask for before an item can be disenchanted, by item
-- level: 1 up to level 20, then 25 more for every 5 levels, capped at 225 from level 61
function ns.DisenchantSkill(level)
  if level <= 20 then return 1 end
  return math.min(225, 25 * math.ceil((level - 20) / 5))
end

-- Gear check that needs no server round trip, for filtering a whole scan cheaply
function ns.IsGear(id)
  local classID = select(6, C_Item.GetItemInfoInstant(id))
  return classID == WEAPON or classID == ARMOR
end

-- One disenchant deal: uncommon or better weapons and armor whose net disenchant value, after
-- the cut and the deposits on reselling the materials (Outlet.Net, as the tooltip shows it),
-- beats the price. Nil otherwise, and true as well while the item's data is still loading.
local function Deal(id, price, cut, depositOf)
  local _, _, quality, level, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(id)
  if not quality then return nil, true end
  if not (quality >= UNCOMMON and (classID == WEAPON or classID == ARMOR)) then return nil end
  local value, odds, deposits = ns.DisenchantValue(id, depositOf)
  if not value then return nil end
  value = ns.Outlet.Net(value, cut, deposits)
  local profit = value - price
  local pct = profit / price
  if profit <= 0 then return nil end
  return { id = id, price = price, value = value, profit = profit, pct = pct,
    odds = odds, skill = ns.DisenchantSkill(level) }
end

-- prices: { [itemID] = cheapest buyout }; depositOf(materialID): the one-unit deposit to list a
-- material. Returns the deals, most profit first, before the thresholds (ns.PassesDisenchant),
-- and the prices of items whose data is still loading, to try again once it arrives.
function ns.FindDisenchantDeals(prices, cut, depositOf)
  local deals, loading = {}, {}
  for id, price in pairs(prices) do
    local deal, isLoading = Deal(id, price, cut, depositOf)
    if deal then
      deals[#deals + 1] = deal
    elseif isLoading then
      loading[id] = price
    end
  end
  table.sort(deals, function(a, b) return a.profit > b.profit end)
  return deals, loading
end

-- Whether a deal passes the thresholds in Settings, as they are now
function ns.PassesDisenchant(d)
  return d.profit >= ns.Cfg("minDisenchantProfit") and d.pct >= ns.Cfg("minDisenchantPct")
end

-- Each reader returns a profession's rank, or nil and whether it listed the character's skills
-- without that profession
local function FromProfessions(skillLine)
  if not (GetProfessions and GetProfessionInfo) then return nil, false end
  local first, second = GetProfessions()
  for _, index in pairs({ first, second }) do
    local _, _, rank, _, _, _, line = GetProfessionInfo(index)
    if line == skillLine then return rank end
  end
  return nil, (first or second) ~= nil
end

local function FromSkillLines(spellID, englishName)
  if not (GetNumSkillLines and GetSkillLineInfo) then return nil, false end
  local wanted = (GetSpellInfo and GetSpellInfo(spellID)) or englishName
  local count, collapsed = GetNumSkillLines(), false
  for i = 1, count do
    local name, isHeader, isExpanded, rank = GetSkillLineInfo(i)
    if isHeader and not isExpanded then
      collapsed = true
    elseif name == wanted then
      return rank
    end
  end
  -- a collapsed section could be hiding the profession
  return nil, count > 0 and not collapsed
end

-- This character's rank in a profession, by its skill line and the spell named after it:
-- 0 without the profession, nil when the game will not say
function ns.ProfessionSkill(skillLine, spellID, englishName)
  local rank, listedWithout = FromProfessions(skillLine)
  if rank then return rank end
  local lineRank, linesWithout = FromSkillLines(spellID, englishName)
  if lineRank then return lineRank end
  if listedWithout or linesWithout then return 0 end
end

function ns.EnchantingSkill()
  return ns.ProfessionSkill(333, 7411, "Enchanting")
end
