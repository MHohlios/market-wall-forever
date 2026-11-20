-- MarketWall: core, settings, helpers
local ADDON, ns = ...
MarketWall = ns

ns.cfgDefaults = {
  wallShare = 0.05,        -- share of total supply a price level needs (cumulative) to count as the wall
  wallMinUnits = 5,        -- minimum units for a wall on thin items
  ahCut = 0.05,            -- auction house cut on sales
  minSupply = 20,          -- full-scan snipes/dips need at least this many units listed
  minSnipeProfit = 100,    -- copper, total profit after cut
  minSnipeDiscount = 0.10, -- snipe units must average this far under the wall
  dipPct = 0.10,           -- wall must be this far under its median to be a dip
  minDisenchantProfit = 5000, -- copper per item, net disenchant value (after cut and deposits) minus price
  minDisenchantPct = 0.20,    -- that profit as a share of the price
  disenchantShowAll = false,  -- Disenchant list also shows items above your Enchanting skill
  salvagerMode = "auto",      -- Salvager's disenchant bonus: "auto" (while the buff is up), "on", "off"
  salvagerBonus = 0,          -- that bonus, in percent; both start from Disenchantry's on first import
  minHistoryDays = 5,      -- "Days before data is reliable": fewer days of data flag an item as low-data
  baselineDays = 14,       -- days used for the normal price
  retainDays = 30,         -- daily history kept for unwatched items
  retainWeeks = 52,        -- weekly points kept for unwatched items, folded from their expired days
  minRecordSupply = 5,     -- unwatched items with fewer units are not recorded
  maxSnaps = 400,          -- per-scan snapshots kept per watched item
  sound = true,
  autoScan = true,         -- start the daily full scan when the auction house opens
  staleMinutes = 60,       -- watchlist prices older than this are greyed out
  sellDuration = 2,        -- last auction duration picked on the Sell page: 1 = 12h, 2 = 24h, 3 = 48h
  baitSearchGap = 1.0,     -- seconds between Bait Detect searches; never less than 1
  baitConfirmPress = true, -- Bait Detect confirms each purchase with its own press
  baitMinUnder = 0.50,     -- bait must sit at least this far under the wall; held to 10% to 95%
  minimapButton = true,    -- show the MW button on the minimap
  mobDisenchant = "auto",  -- disenchanting in a mob's Optimal value: "auto" (with Enchanting), "always", "never"
  mobSkinning = "auto",    -- skinning in a mob's Optimal value: "auto" (with Skinning), "always", "never"
  mobRareShare = 0.02,     -- drops seen in fewer than this share of kills count as rare
  mobMinKills = 10,        -- seen kills under this flag a mob's values as rough
}

-- Settings Reset to defaults leaves alone: imported once from Disenchantry, which never imports again
ns.KEPT_ON_RESET = { salvagerMode = true, salvagerBonus = true }

function ns.ResetSettings(cfg)
  for key in pairs(cfg) do
    if not ns.KEPT_ON_RESET[key] then cfg[key] = nil end
  end
end

-- The last bag index to scan for "all my bags": the backpack, the equipped bags and the reagent bag. Never the bank.
function ns.LastBagIndex()
  return NUM_TOTAL_EQUIPPED_BAG_SLOTS or ((NUM_BAG_SLOTS or 4) + (NUM_REAGENTBAG_SLOTS or 0))
end

local function Print(...)
  print("|cfff5c518MarketWall|r:", ...)
end
ns.Print = Print

function ns.Round(x)
  return math.floor(x + 0.5)
end

-- A share as a percent, with one decimal under 10%: "4.2%", "31%"
function ns.ShareText(share)
  local pct = share * 100
  if pct < 10 then return string.format("%.1f%%", pct) end
  return string.format("%d%%", ns.Round(pct))
end

-- The coins shown for a copper amount, and whether it was negative. Copper-only amounts leave
-- out gold and silver; zero silver and copper still show once there is gold.
local function CoinParts(c)
  c = ns.Round(c)
  local neg = c < 0
  if neg then c = -c end
  local g = math.floor(c / 10000)
  local s = math.floor((c % 10000) / 100)
  local k = c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = { g, "g" } end
  if g > 0 or s > 0 then parts[#parts + 1] = { s, "s" } end
  parts[#parts + 1] = { k, "c" }
  return parts, neg
end

local COIN_ICON = {
  g = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:0|t",
  s = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:0:0|t",
  c = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:0:0|t",
}

local function JoinCoins(c, mark, dropCopperOverGold)
  if not c then return "-" end
  if dropCopperOverGold and math.abs(c) >= 10000 then
    c = (c < 0 and -1 or 1) * ns.Round(math.abs(c) / 100) * 100   -- to the nearest silver, either sign
  end
  local parts, neg = CoinParts(c)
  if dropCopperOverGold and #parts == 3 then parts[3] = nil end
  local out = {}
  for i, part in ipairs(parts) do out[i] = part[1] .. mark(part[2]) end
  return (neg and "-" or "") .. table.concat(out, " ")
end

-- For display: the number then its coin icon, in the colour of the surrounding text
function ns.Money(c)
  return JoinCoins(c, function(unit) return COIN_ICON[unit] end)
end

-- Coin icons tinted darker, so they fade with grey text. A tint needs the full texture form:
-- size, offset, texture size, coordinates, then r:g:b out of 255.
local FADED_COIN_ICON = {}
for unit, icon in pairs(COIN_ICON) do
  FADED_COIN_ICON[unit] = icon:gsub(":0:0:0:0|t$", ":0:0:0:0:64:64:0:64:0:64:128:128:128|t")
end

-- ns.Money for faded text: the same numbers, with the coin icons darkened to match
function ns.MoneyFaded(c)
  return JoinCoins(c, function(unit) return FADED_COIN_ICON[unit] end)
end

-- For chart axis labels, which have a narrow gutter: at 1g and over, copper is left out ("12g 34s")
function ns.MoneyShort(c)
  return JoinCoins(c, function(unit) return COIN_ICON[unit] end, true)
end

-- Letters instead of icons ("1g 41s 23c"), for edit boxes and anything ParseMoney reads back
function ns.MoneyText(c)
  return JoinCoins(c, function(unit) return unit end)
end

local MONEY_PART = "(%d*%.?%d+)%s*([gsc])"
local COPPER_PER = { g = 10000, s = 100, c = 1 }

-- Accepts "80c", "1s 20c", "2g", "1g5s", "1.5g", or a plain copper number. Fractions of a
-- copper are dropped. Anything else, including negative amounts, is nil.
function ns.ParseMoney(text)
  if not text then return nil end
  text = string.lower((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  local plain = tonumber(text)
  if plain then
    if plain < 0 then return nil end
    return math.floor(plain)
  end
  local leftover, parts = string.gsub(text, MONEY_PART, "")
  if parts == 0 or string.find(leftover, "%S") then return nil end
  local total = 0
  for num, unit in string.gmatch(text, MONEY_PART) do
    total = total + tonumber(num) * COPPER_PER[unit]
  end
  return math.floor(total + 1e-9)
end

-- Days are counted in local time, so "today" flips at your midnight, not at midnight UTC
local tzOffset
local function Offset()
  if tzOffset then return tzOffset end
  local ok, value = pcall(function()
    local now = time()
    return time(date("*t", now)) - time(date("!*t", now))
  end)
  tzOffset = (ok and type(value) == "number") and value or 0
  return tzOffset
end

function ns.DayOf(t)
  return math.floor((t + Offset()) / 86400)
end

function ns.DayStart(day)
  return day * 86400 - Offset()
end

function ns.Today()
  return ns.DayOf(time())
end

function ns.Ago(t)
  if not t then return "never" end
  local s = time() - t
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. " min ago" end
  if s < 86400 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

function ns.Icon(id)
  if C_Item and C_Item.GetItemIconByID then
    local icon = C_Item.GetItemIconByID(id)
    if icon then return icon end
  end
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
    if icon then return icon end
  end
  return 134400
end

function ns.ColorName(id)
  local name = ns.Name(id)
  local quality = C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color and color.hex then return color.hex .. name .. "|r" end
  if color and color.r then
    return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name)
  end
  return name
end

ns.session = { qty = 0, cost = 0, resale = 0, buys = 0 }

local function SessionSummary()
  local s = ns.session
  if s.buys > 0 then
    local text = string.format("This visit: %d purchase(s), %d units, %s spent.", s.buys, s.qty, ns.Money(s.cost))
    if s.resale > 0 then
      text = text .. " Expected profit at your sell prices: " .. ns.Money(s.resale - s.cost) .. "."
    end
    Print(text)
  end
  ns.session = { qty = 0, cost = 0, resale = 0, buys = 0 }
end

function ns.Realm()
  return (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "Unknown"
end

-- Per-realm data table
function ns.R()
  if ns.realmData then return ns.realmData end
  local db = MarketWallDB
  local key = ns.Realm()
  db.realms[key] = db.realms[key] or {}
  local r = db.realms[key]
  r.names = r.names or {}   -- [itemID] = name
  r.watch = r.watch or {}   -- [itemID] = { buy=, sell=, added=, cur={t,w,m,q,under,cost} }
  r.days = r.days or {}     -- [itemID] = { [day] = { wall, lowWall, highWall, units, minPrice } }
  r.weeks = r.weeks or {}   -- [itemID] = packed weekly history, see ns.PackWeeks in Data.lua
  r.snaps = r.snaps or {}   -- [itemID] = { {t, wall, minPrice, units}, ... } watched items only
  r.pos = r.pos or {}       -- [itemID] = { qty=, cost= } bought through the addon
  r.buys = r.buys or {}     -- { {t, id, qty, unit, total}, ... } every purchase through the addon
  r.bait = r.bait or {}     -- [itemID] = bait record, see Bait.lua; overwritten each scan
  r.recent = r.recent or {} -- item IDs looked up in the search window, newest first
  r.supplied = r.supplied or {}   -- [itemID] = true with minSupply units at the latest search or full scan, which replaces it
  ns.realmData = r
  return r
end

function ns.Cfg(key)
  local v = MarketWallDB and MarketWallDB.cfg and MarketWallDB.cfg[key]
  if v == nil then v = ns.cfgDefaults[key] end
  return v
end

function ns.Name(id)
  local r = ns.R()
  if r.names[id] then return r.names[id] end
  local name
  if C_Item and C_Item.GetItemInfo then name = C_Item.GetItemInfo(id) elseif GetItemInfo then name = GetItemInfo(id) end
  if name then
    r.names[id] = name
    return name
  end
  if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return "item:" .. id
end

-- The item ID in an item link, nil for anything else
function ns.ItemID(link)
  return type(link) == "string" and tonumber(string.match(link, "item:(%d+)")) or nil
end

-- Resolve user text to an item ID: link, number, or name known from scans
function ns.ResolveItem(text)
  if not text or text == "" then return nil end
  local id = ns.ItemID(text) or tonumber(text)
  if id then return id end
  local want = string.lower(strtrim(text))
  local r = ns.R()
  local exact, partial, count = nil, nil, 0
  local matches = {}
  for itemID, name in pairs(r.names) do
    local lname = string.lower(name)
    if lname == want then exact = itemID end
    if string.find(lname, want, 1, true) then
      partial = itemID
      count = count + 1
      if #matches < 8 then matches[#matches + 1] = name end
    end
  end
  if exact then return exact end
  if count == 1 then return partial end
  if C_Item and C_Item.GetItemInfoInstant then
    local instant = C_Item.GetItemInfoInstant(text)
    if instant then return instant end
  end
  if count > 1 then
    table.sort(matches)
    return nil, "Several items match: " .. table.concat(matches, ", ") .. (count > #matches and ", ..." or "")
  end
  return nil, "Item not found. Shift-click the item into the box, or run a full scan first so names are known."
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("AUCTION_HOUSE_SHOW")
frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    MarketWallDB = MarketWallDB or {}
    MarketWallDB.version = MarketWallDB.version or 1
    MarketWallDB.cfg = MarketWallDB.cfg or {}
    MarketWallDB.realms = MarketWallDB.realms or {}
    MarketWallDB.mobs = MarketWallDB.mobs or {}   -- kill records per mob, see Mobs.lua
    MarketWallDB.disenchants = MarketWallDB.disenchants or {}   -- your disenchant results, see DisenchantLog.lua
    MarketWallDB.containers = MarketWallDB.containers or {}   -- what containers opened into, see Containers.lua
    MarketWallDB.ledger = MarketWallDB.ledger or {}   -- cash ledger per character, see Ledger.lua
    MarketWallDB.sessions = MarketWallDB.sessions or {}   -- farm sessions, see Sessions.lua
    MarketWallDB.sessionGroups = MarketWallDB.sessionGroups or {}
    MarketWallDB.creatures = MarketWallDB.creatures or {}
    MarketWallDB.depositRate = MarketWallDB.depositRate or {}   -- learned auction deposit rates, see Outlet.lua
    MarketWallDB.crafting = MarketWallDB.crafting or {}   -- known recipes per character, see Professions.lua
  elseif event == "PLAYER_LOGIN" then
    ns.realmData = nil
    ns.R()
    if ns.InitTooltip then ns.InitTooltip() end
    if ns.InitMinimapButton then ns.InitMinimapButton() end
    if ns.Kills then ns.Kills.Start() end
    if ns.DisenchantLog then ns.DisenchantLog.Start() end
  elseif event == "AUCTION_HOUSE_SHOW" then
    ns.ahOpen = true
    if ns.OnAuctionHouseShow then ns.OnAuctionHouseShow() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ns.ahOpen = false
    if ns.OnAuctionHouseClosed then ns.OnAuctionHouseClosed() end
    SessionSummary()
  end
end)

SLASH_MARKETWALL1 = "/mw"
SLASH_MARKETWALL2 = "/marketwall"
SlashCmdList["MARKETWALL"] = function(msg)
  msg = strtrim(msg or "")
  local cmd, rest = string.match(msg, "^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "add" then
    local id, err = ns.ResolveItem(rest)
    if id then ns.Watch(id) Print("Watching " .. ns.Name(id)) else Print(err or "Item not found.") end
  elseif cmd == "remove" then
    local id = ns.ResolveItem(rest)
    if id then ns.Unwatch(id) Print("Removed " .. ns.Name(id)) end
  elseif cmd == "scan" then
    ns.StartWatchScan()
  elseif cmd == "full" then
    ns.StartFullScan()
  elseif cmd == "set" then
    local key, value = string.match(rest, "^(%S+)%s+(%S+)$")
    if key and ns.cfgDefaults[key] ~= nil then
      local default = ns.cfgDefaults[key]
      if type(default) == "boolean" then
        MarketWallDB.cfg[key] = (value == "true" or value == "on" or value == "1")
      elseif type(default) == "string" then
        MarketWallDB.cfg[key] = string.lower(value)
      else
        MarketWallDB.cfg[key] = tonumber(value) or default
      end
      Print(key .. " = " .. tostring(MarketWallDB.cfg[key]))
      ns.UpdateMinimapButton()
      ns.Mobs.Invalidate()   -- the cut and the mob settings feed mob values
    else
      Print("Settings:")
      for k, d in pairs(ns.cfgDefaults) do
        print("  " .. k .. " = " .. tostring(ns.Cfg(k)) .. " (default " .. tostring(d) .. ")")
      end
    end
  elseif cmd == "minimap" then
    MarketWallDB.cfg.minimapButton = not ns.Cfg("minimapButton")
    ns.UpdateMinimapButton()
    Print(ns.Cfg("minimapButton") and "Minimap button shown." or "Minimap button hidden. /mw minimap shows it again.")
  elseif cmd == "search" then
    ns.ToggleSearch(true)
  elseif cmd == "resetpos" then
    local id = ns.ResolveItem(rest)
    if id then ns.R().pos[id] = nil Print("Position cleared for " .. ns.Name(id)) end
  elseif cmd == "probe" then
    ns.ProbeCommand(rest)
  elseif cmd == "session" then
    ns.Sessions.Command(rest)
  else
    Print("Open the auction house and use the Market tab. Commands:")
    print("  /mw add <item link, id or name>   watch an item")
    print("  /mw remove <item>                 stop watching")
    print("  /mw scan                          scan the watchlist")
    print("  /mw full                          full market scan")
    print("  /mw set <setting> <value>         change a setting, /mw set lists them")
    print("  /mw resetpos <item>               clear your tracked position")
    print("  /mw probe start|stop|status       record what the client exposes for kills, loot, money and trainers")
    print("  /mw search                        open the item search window")
    print("  /mw minimap                       hide or show the minimap button")
    print("  /mw session start <label>|stop|pause|resume   a farm session; /mw session shows the running one")
  end
end
