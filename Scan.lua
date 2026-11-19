-- MarketWall: watchlist scans (targeted searches) and full market scans (replicate)
local _, ns = ...
local W = ns.Wall

local COMMODITY_SORTS = { { sortOrder = 0, reverseSort = false } }
local SEARCH_TIMEOUT = 8
local MAX_TRIES = 3
local MAX_MORE = 8

local scanner = CreateFrame("Frame")
local state = { queue = {}, active = nil, total = 0, done = 0 }
ns.scanState = state

local function Status(text, fraction)
  ns.statusText = text
  ns.statusTime = GetTime()
  ns.progress = fraction
  if ns.UpdateStatus then ns.UpdateStatus() end
end

local function FinishWatchScan(aborted)
  scanner:SetScript("OnUpdate", nil)
  scanner:UnregisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  scanner:UnregisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  state.active = nil
  state.queue = {}
  state.running = false
  if aborted then
    Status("Scan stopped")
  else
    local r = ns.R()
    local deals = 0
    for id in pairs(r.watch) do
      if ns.WatchStatus(id) == "buy" then deals = deals + 1 end
    end
    if state.alert then r.lastWatch = time() end
    if deals > 0 and state.alert then
      Status(deals .. " watched item(s) under your buy price")
      ns.Print(deals .. " watched item(s) are under your buy price.")
      if ns.Cfg("sound") and PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master")
      end
    else
      Status("Scan complete")
    end
  end
  ns.Mobs.Invalidate()   -- new walls and supply change what drops are worth
  if ns.RefreshUI then ns.RefreshUI() end
  local cb = state.onDone
  state.onDone = nil
  if cb then cb(not aborted and state.answered) end
end

local function NextItem()
  local id = table.remove(state.queue, 1)
  if not id then
    FinishWatchScan(false)
    return
  end
  state.active = {
    id = id,
    key = C_AuctionHouse.MakeItemKey(id),
    phase = "send",
    tries = 0,
    more = 0,
    started = GetTime(),
  }
  Status(string.format("Scanning %d of %d: %s", state.done + 1, state.total, ns.Name(id)), state.done / state.total)
end

local function CompleteItem(ladderMap, kind, auctions)
  local a = state.active
  if not a then return end
  -- a single-try search that got no answer proves nothing about the listings: record nothing
  if kind ~= "none" or not state.once then
    local ladder, total = W.SortLadder(ladderMap)
    local now = time()
    ns.ladders[a.id] = { ladder = ladder, total = total, t = now, kind = kind, auctions = auctions }
    ns.R().supplied[a.id] = total >= ns.Cfg("minSupply") or nil   -- the latest search decides, until the next full scan
    local wall = ns.Record(a.id, ladder, total, now)
    ns.UpdateBait(a.id, ladder, wall, ns.StatsFor(a.id), now, kind == "commodity")
    state.answered = true
  end
  state.done = state.done + 1
  state.active = nil
  if ns.RefreshUI then ns.RefreshUI() end
  NextItem()
end

local function ReadCommodity(id)
  local map = {}
  local n = C_AuctionHouse.GetNumCommoditySearchResults(id) or 0
  for i = 1, n do
    local info = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
    if info and info.unitPrice and info.quantity and info.quantity > 0 then
      map[info.unitPrice] = (map[info.unitPrice] or 0) + info.quantity
    end
  end
  return map
end

local function ReadItems(key)
  local map, auctions = {}, {}
  local n = C_AuctionHouse.GetNumItemSearchResults(key) or 0
  for i = 1, n do
    local info = C_AuctionHouse.GetItemSearchResultInfo(key, i)
    if info and info.buyoutAmount and info.buyoutAmount > 0 then
      local qty = info.quantity or 1
      if qty < 1 then qty = 1 end
      local unit = math.ceil(info.buyoutAmount / qty)
      map[unit] = (map[unit] or 0) + qty
      auctions[#auctions + 1] = { id = info.auctionID, price = info.buyoutAmount, unit = unit, qty = qty }
    end
  end
  table.sort(auctions, function(x, y) return x.unit < y.unit end)
  return map, auctions
end

local function Retry()
  local a = state.active
  a.tries = a.tries + 1
  if state.once or a.tries >= MAX_TRIES then
    -- nothing listed, or the server never answered: record as empty and move on
    CompleteItem({}, "none")
  else
    a.phase = "send"
    a.started = GetTime()
  end
end

-- Scanned gear whose item data was still loading when the full scan ended: { [itemID] = price }
local loadingGear = {}

-- Prices one item from loadingGear now its data has arrived, and slots any deal into the
-- Disenchant list by profit. The Market tab redraws on the same event.
local function AddLoadedGear(id)
  local price = loadingGear[id]
  if not price then return end
  loadingGear[id] = nil
  if not next(loadingGear) then scanner:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
  local deal = ns.FindDisenchantDeals({ [id] = price }, ns.Cfg("ahCut"), ns.Cfg("minDisenchantProfit"), ns.Cfg("minDisenchantPct"))[1]
  if not deal then return end
  local at = #ns.disenchants + 1
  for i, d in ipairs(ns.disenchants) do
    if deal.profit > d.profit then at = i break end
  end
  table.insert(ns.disenchants, at, deal)
end

scanner:SetScript("OnEvent", function(_, event, arg1)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    ns.OnReplicateReady()
    return
  end
  if event == "GET_ITEM_INFO_RECEIVED" then
    AddLoadedGear(arg1)
    return
  end
  local a = state.active
  if not a or a.phase ~= "wait" then return end
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if arg1 ~= a.id then return end
    local has = C_AuctionHouse.HasSearchResults(a.key)
    local full = C_AuctionHouse.HasFullCommoditySearchResults(a.id)
    local qty = C_AuctionHouse.GetCommoditySearchResultsQuantity(a.id) or 0
    if (not has) or (not full and qty == 0) then
      Retry()
    elseif not full and a.more < MAX_MORE then
      a.more = a.more + 1
      a.deadline = GetTime() + SEARCH_TIMEOUT
      C_AuctionHouse.RequestMoreCommoditySearchResults(a.id)
    else
      CompleteItem(ReadCommodity(a.id), "commodity")
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if type(arg1) ~= "table" or arg1.itemID ~= a.id then return end
    local has = C_AuctionHouse.HasSearchResults(arg1)
    local full = C_AuctionHouse.HasFullItemSearchResults(arg1)
    local qty = C_AuctionHouse.GetItemSearchResultsQuantity(arg1) or 0
    if (not has) or (not full and qty == 0) then
      Retry()
    elseif not full and a.more < MAX_MORE then
      a.more = a.more + 1
      a.deadline = GetTime() + SEARCH_TIMEOUT
      C_AuctionHouse.RequestMoreItemSearchResults(arg1)
    else
      local map, auctions = ReadItems(arg1)
      CompleteItem(map, "item", auctions)
    end
  end
end)

local Step
local function OnUpdate()
  -- one failure must never repeat every frame: stop the scan and report it once
  local ok, err = pcall(Step)
  if not ok then
    FinishWatchScan(true)
    ns.Print("Scan stopped by an error: " .. tostring(err))
  end
end

Step = function()
  if not ns.ahOpen then
    FinishWatchScan(true)
    return
  end
  local a = state.active
  if not a then return end
  local now = GetTime()
  if a.phase == "send" then
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    -- searches for items whose key info is not cached yet get dropped by the client
    if not C_AuctionHouse.GetItemKeyInfo(a.key) and now - a.started < 4 then return end
    -- price-ascending works for both stackable goods and single items; results are re-sorted locally anyway
    C_AuctionHouse.SendSearchQuery(a.key, COMMODITY_SORTS, false)
    a.phase = "wait"
    a.deadline = now + SEARCH_TIMEOUT
  elseif a.phase == "wait" and now > a.deadline then
    Retry()
  end
end

-- ids: optional list of item IDs. Default is the whole watchlist.
-- onDone(answered): answered is false when the scan was stopped or a single-try search got no answer.
-- once: send one search per item, never retry, and record nothing when it gets no answer.
function ns.StartWatchScan(ids, onDone, once)
  if not ns.ahOpen then
    ns.Print("Open the auction house first.")
    return
  end
  if state.running or ns.fullScanRunning then
    ns.Print("A scan is already running.")
    return
  end
  local queue = {}
  if ids then
    for i = 1, #ids do queue[i] = ids[i] end
  else
    for id in pairs(ns.R().watch) do queue[#queue + 1] = id end
    table.sort(queue)
  end
  if #queue == 0 then
    ns.Print("Your watchlist is empty. Add an item first.")
    return
  end
  state.queue = queue
  state.total = #queue
  state.done = 0
  state.running = true
  state.onDone = onDone
  state.once = once
  state.answered = false
  state.alert = (ids == nil)
  scanner:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  scanner:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  scanner:SetScript("OnUpdate", OnUpdate)
  NextItem()
end

-- One search for one item, sent during this press or not at all, so nothing waits to go out
-- later. Returns false, sending nothing, while the game throttles searches or the item's key
-- info is still loading. Otherwise Step sends the query before this returns.
function ns.SearchNow(id, onDone)
  if not C_AuctionHouse.IsThrottledMessageSystemReady() then return false end
  if not C_AuctionHouse.GetItemKeyInfo(C_AuctionHouse.MakeItemKey(id)) then return false end
  ns.StartWatchScan({ id }, onDone, true)
  Step()
  return true
end

function ns.OnAuctionHouseClosed()
  if state.running then FinishWatchScan(true) end
  if ns.fullScanRunning then
    ns.fullScanRunning = false
    scanner:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    Status("Full scan stopped: auction house closed")
  end
  if ns.CancelPurchase then ns.CancelPurchase() end
end

-------------------------------------------------------------------------------
-- Full market scan
-------------------------------------------------------------------------------
local REPLICATE_COOLDOWN = 15 * 60

function ns.FullScanCooldown()
  local last = MarketWallDB.lastReplicate or 0
  local left = REPLICATE_COOLDOWN - (time() - last)
  if left < 0 then left = 0 end
  return left
end

-- Turn accumulated { [itemID] = { [unitPrice] = units } } into records, snipes, dips and disenchant deals
local function Finalize(maps, names, stamp)
  local r = ns.R()
  local ids = {}
  for id in pairs(maps) do ids[#ids + 1] = id end
  for id, name in pairs(names) do r.names[id] = name end
  local snipes, dips = {}, {}
  local gearPrices = {}   -- cheapest buyout of each weapon and armor item, for disenchant deals
  local supplied = {}     -- items with at least minSupply units listed, for mob values
  local cut = ns.Cfg("ahCut")
  local minSupply = ns.Cfg("minSupply")
  local index = 1
  local STEP = 300
  local ticker
  ticker = C_Timer.NewTicker(0, function()
    local last = math.min(index + STEP - 1, #ids)
    for i = index, last do
      local id = ids[i]
      local ladder, total = W.SortLadder(maps[id])
      -- recorded first, so an item's first scan has today's wall to fall back on
      local wall, minPrice = ns.Record(id, ladder, total, stamp)
      local stats = ns.StatsFor(id)
      ns.UpdateBait(id, ladder, wall, stats, stamp)
      if ns.IsGear(id) then gearPrices[id] = ladder[1].p end
      if total >= minSupply then supplied[id] = true end
      if wall then
        if r.watch[id] then
          ns.ladders[id] = { ladder = ladder, total = total, t = stamp, kind = "scan" }
        end
        if total >= minSupply then
          local snipe, dip = ns.FullScanDeals(id, ladder, total, wall, minPrice, stats, cut)
          if snipe then snipes[#snipes + 1] = snipe end
          if dip then dips[#dips + 1] = dip end
        end
      end
    end
    index = last + 1
    Status(string.format("Full scan: analysing %d of %d items", math.min(index - 1, #ids), #ids), 0.6 + 0.4 * math.min(index - 1, #ids) / math.max(1, #ids))
    if index > #ids then
      ticker:Cancel()
      table.sort(snipes, function(a, b) return a.profit > b.profit end)
      table.sort(dips, function(a, b) return a.under > b.under end)
      -- items with nothing listed any more have no bait level left
      for id in pairs(r.bait) do
        if not maps[id] then r.bait[id] = nil end
      end
      ns.snipes, ns.dips = snipes, dips
      -- after the loop, so materials are priced at today's walls
      ns.disenchants, loadingGear = ns.FindDisenchantDeals(gearPrices, cut, ns.Cfg("minDisenchantProfit"), ns.Cfg("minDisenchantPct"))
      if next(loadingGear) then
        scanner:RegisterEvent("GET_ITEM_INFO_RECEIVED")
      else
        scanner:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
      end
      ns.lastFullScan = stamp
      r.lastFull = stamp
      r.supplied = supplied
      ns.Mobs.Invalidate()
      ns.fullScanRunning = false
      Status(string.format("Full scan complete: %d items, %d snipes, %d dips", #ids, #snipes, #dips))
      ns.Print(string.format("Full scan complete: %d items recorded, %d snipes, %d dips.", #ids, #snipes, #dips))
      if #snipes > 0 and ns.Cfg("sound") and PlaySound then
        PlaySound((SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master")
      end
      if ns.RefreshUI then ns.RefreshUI() end
    end
  end)
end

function ns.OnReplicateReady()
  scanner:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  if not ns.fullScanRunning then return end
  local count = C_AuctionHouse.GetNumReplicateItems() or 0
  local maps, names = {}, {}
  local index = 0
  local STEP = 1000
  local stamp = time()
  local ticker
  ticker = C_Timer.NewTicker(0, function()
    if not ns.fullScanRunning then ticker:Cancel() return end
    local last = math.min(index + STEP, count)
    for i = index, last - 1 do
      local name, _, qty, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
      if itemID and qty and qty > 0 and buyout and buyout > 0 then
        local unit = math.ceil(buyout / qty)
        local map = maps[itemID]
        if not map then map = {} maps[itemID] = map end
        map[unit] = (map[unit] or 0) + qty
        if name and name ~= "" and not names[itemID] then names[itemID] = name end
      end
    end
    index = last
    Status(string.format("Full scan: reading %d of %d auctions", index, count), 0.1 + 0.5 * index / math.max(1, count))
    if index >= count then
      ticker:Cancel()
      Finalize(maps, names, stamp)
    end
  end)
end

function ns.StartFullScan()
  if not ns.ahOpen then
    ns.Print("Open the auction house first.")
    return
  end
  if state.running or ns.fullScanRunning then
    ns.Print("A scan is already running.")
    return
  end
  local left = ns.FullScanCooldown()
  if left > 0 then
    ns.Print(string.format("The game allows one full scan every 15 minutes. Next one in %d min %d sec.", math.floor(left / 60), left % 60))
    return
  end
  ns.fullScanRunning = true
  MarketWallDB.lastReplicate = time()
  scanner:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  Status("Full scan: waiting for the server (this can take a minute)", 0.05)
  C_AuctionHouse.ReplicateItems()
end

-- Start today's full scan when the auction house opens, if none has run today
function ns.MaybeAutoScan()
  if not ns.Cfg("autoScan") then return end
  local r = ns.R()
  if r.lastFull and ns.DayOf(r.lastFull) == ns.Today() then return end
  if ns.FullScanCooldown() > 0 then return end
  C_Timer.After(3, function()
    if ns.ahOpen and not ns.fullScanRunning and not state.running then
      ns.Print("Starting today's full scan.")
      ns.StartFullScan()
    end
  end)
end
