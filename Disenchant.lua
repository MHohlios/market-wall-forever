-- MarketWall: expected disenchant value, priced from MarketWall's own material walls.
-- Outcome data adapted from Disenchantry (MIT, see LICENSES/Disenchantry.txt). Where an item's
-- odds come from, best first:
--   1. your own disenchants, from MarketWall's disenchant log (DisenchantLog.lua), once there
--      are 20 of them: for the item itself when Forever estimates it, otherwise for its kind
--   2. Forever estimates: specific new crafted items, and new rares (IDs from 200000)
--   3. the classic disenchanting tables (original-era item levels, which Forever uses)
local _, ns = ...

local WEAPON, ARMOR = 2, 4
local UNCOMMON, RARE, EPIC = 2, 3, 4
local NEW_ITEM_ID = 200000      -- Forever's own items start here
local MIN_SAMPLES = 20          -- Disenchantry's threshold for trusting your own results
local SALVAGER_BUFF = 1283701   -- Forever buff that raises disenchant yields
local SALVAGER_MODES = { auto = true, on = true, off = true }

-- Each outcome: { materialID, chance (0-1), average quantity }

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

-- Forever's new low- and mid-level crafts, estimated by Disenchantry's author
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
      { row[3], dust / 100, (row[10] + row[11]) / 2 },
      { essenceID, essence / 100, (row[12] + row[13]) / 2 },
    }
    if row[5] then out[3] = { row[5], (100 - dust - essence) / 100, 1 } end
    return out
  elseif quality == RARE then
    local row = Find(RARE_ROWS, level)
    if not row then return nil end
    if row[4] then return { { row[3], 0.995, 1 }, { row[4], 0.005, 1 } } end
    return { { row[3], 1, 1 } }
  elseif quality == EPIC then
    local row = Find(EPIC_ROWS, level)
    if row then return { { row[3], 1, (row[4] + row[5]) / 2 } } end
  end
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

-- Your own results for the item, under the current Salvager setting
local function Observed(id, quality, level, classID)
  local sample = ns.DisenchantLog.Sample(id, quality, level, classID, SalvagerActive())
  if not sample or sample.count < MIN_SAMPLES then return nil end
  local out = {}
  for materialID, m in pairs(sample.materials) do
    if m.hits > 0 then out[#out + 1] = { materialID, m.hits / sample.count, m.total / m.hits } end
  end
  if #out > 0 then return out, sample.count end
end

-- The outcomes and where they came from: "observed" (with the sample count), "estimate" or "table"
local function Outcomes(id)
  if NO_DISENCHANT[id] or not C_Item.GetItemInfo then return nil end
  local _, _, quality, level, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(id)
  if not (quality and level and classID) then return nil end

  local observed, samples = Observed(id, quality, level, classID)
  if observed then return observed, "observed", samples end
  if CRAFT_ESTIMATES[id] then return CRAFT_ESTIMATES[id], "estimate" end
  if classID ~= WEAPON and classID ~= ARMOR then return nil end
  local weapon = classID == WEAPON
  if quality == RARE and id >= NEW_ITEM_ID then
    local estimate = NewRareEstimate(level, weapon)
    if estimate then return estimate, "estimate" end
    return nil
  end
  local classic = ClassicTable(quality, level, weapon)
  if classic then return classic, "table" end
end

-- Expected copper from disenchanting one item, at each material's latest wall price, and a
-- short note on the source ("your 34 disenchants", "estimate", or nil for the classic table).
-- Nil when the item cannot be disenchanted; false when a likely material has no price yet.
-- With depositOf(materialID), the one-unit deposit to list a material, it also returns the
-- expected deposits to list the materials; a material with no price counts neither.
function ns.DisenchantValue(id, depositOf)
  local outcomes, source, samples = Outcomes(id)
  if not outcomes then return nil end
  local total, deposits = 0, depositOf and 0
  for _, o in ipairs(outcomes) do
    local price = ns.LatestWall(o[1])
    if price then
      total = total + o[2] * o[3] * price
      if deposits then deposits = deposits + o[2] * o[3] * depositOf(o[1]) end
    elseif o[2] >= 0.01 then
      return false
    end
  end
  if source == "observed" then
    return total, "your " .. samples .. " disenchants", deposits   -- already includes any Salvager bonus
  end
  local scale = 1 + SalvagerBonus()
  return total * scale, source == "estimate" and "estimate" or nil, deposits and deposits * scale
end

local SOURCE_NAMES = { estimate = "Forever estimate", table = "classic table" }

-- What disenchanting one item gives: a list of { id, chance (0-1), quantity }, the average
-- quantity including any Salvager bonus as DisenchantValue counts it, and the source's name
-- ("your 34 disenchants", "Forever estimate" or "classic table"). Nil when it cannot be
-- disenchanted.
function ns.DisenchantOutcomes(id)
  local outcomes, source, samples = Outcomes(id)
  if not outcomes then return nil end
  local scale = source == "observed" and 1 or 1 + SalvagerBonus()
  local list = {}
  for _, o in ipairs(outcomes) do
    list[#list + 1] = { id = o[1], chance = o[2], quantity = o[3] * scale }
  end
  return list, source == "observed" and ("your " .. samples .. " disenchants") or SOURCE_NAMES[source]
end

-- The Enchanting skill the classic rules ask for before an item can be disenchanted, by item
-- level: 1 up to level 20, then 25 more for every 5 levels, capped at 225 from level 61
function ns.DisenchantSkill(level)
  if level <= 20 then return 1 end
  return math.min(225, 25 * math.ceil((level - 20) / 5))
end

local ODDS_FROM = { estimate = "Forever estimate" }

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
  local value, note, deposits = ns.DisenchantValue(id, depositOf)
  if not value then return nil end
  value = ns.Outlet.Net(value, cut, deposits)
  local profit = value - price
  local pct = profit / price
  if profit <= 0 then return nil end
  return { id = id, price = price, value = value, profit = profit, pct = pct,
    odds = ODDS_FROM[note] or note or "classic table", skill = ns.DisenchantSkill(level) }
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
