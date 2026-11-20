-- MarketWall: the Bait Detect page.
-- Left: commodities that look baited. Right: the selected item's live listings and one action
-- button. Each press of the button (or its key binding) does exactly one search or one buy.
local _, ns = ...
local W, B = ns.Wall, ns.Bait
local widgets = ns.widgets
local MakeButton, MakeText, MakeEdit = widgets.MakeButton, widgets.MakeText, widgets.MakeEdit

local WARN, GREY = ns.COLOR.WARN, ns.COLOR.GREY
local LIST_WIDTH, RIGHT_X, RIGHT_WIDTH = 420, 432, 350
local LIST_ROWS, LADDER_ROWS = 15, 8
local SEARCHES_SHOWN_LIMIT = 100
local BINDING = "MARKETWALL_BAIT_ACTION"
local UNDER_TINT = { 0.31, 0.76, 0.42, 0.10 }

-- Names shown in Key Bindings for the binding in Bindings.xml
BINDING_HEADER_MARKETWALL = "MarketWall"
BINDING_NAME_MARKETWALL_BAIT_ACTION = "Bait Detect: search or buy"

local COLUMNS = {
  { "Item", 112, nil, "Commodities whose cheapest price level looks like bait: thin supply under the wall, below the item's normal range. Dimmed until a second scan or a live search sees it again." },
  { "Bait", 75, "RIGHT", "The bait price. Hover a cell for how many units were first seen at it.", cellTip = true, money = true },
  { "Wall", 75, "RIGHT", "The item's real price: the lowest price level with meaningful supply behind it. Hover a cell for the item's days of data.", cellTip = true, money = true, grey = true },
  { "Under", 50, "RIGHT", "How far the bait price is under the wall." },
  { "Copies", 52, "RIGHT", "Units posted at the bait price since it first appeared. Green: copies are piling up; those are the cheap units worth buying.", answer = true },
  { "Seen", 56, "RIGHT", "How long ago the bait price first appeared, or \"seen once\" until a second sighting confirms it.", grey = true },
}
local SEEN_ONCE_HINT = "Seen once: one scan found it. Click to search it live and confirm."
local COPIES_HINT = "Green copies: units piling up at the bait price, the ones worth buying."
ns.BaitColumns = COLUMNS   -- for specs

local page
local selectedID
local button = B.NewButton()
local thresholds, buyBait, spent = {}, {}, {}   -- per item, this session
local searched = {}                              -- per item: B.Snapshot of its last live search
local searches = {}                              -- GetTime() of each search, last minute only
local lastSearch                                 -- GetTime() of the last search, for any item

local function Gap()
  return math.max(1, ns.Cfg("baitSearchGap"))
end

local function SearchesThisMinute()
  local now = GetTime()
  while searches[1] and now - searches[1] > 60 do table.remove(searches, 1) end
  return #searches
end

local function Record(id)
  return ns.R().bait[id]
end

-- Plans come from the item's last live search, never from the saved record a full scan may change.
-- Only bait that search confirmed is bought against: without it the plan is empty.
local function Plan(id)
  local seen = searched[id]
  if not (seen and seen.bait) then return B.Plan({}, nil) end
  return B.Plan(seen.ladder, thresholds[id], seen.bait, not buyBait[id])
end

local function Action()
  local action, wait = B.NextAction(button, GetTime(), Gap(), C_AuctionHouse.IsThrottledMessageSystemReady(), lastSearch)
  if action == "search" and (ns.scanState.running or ns.fullScanRunning) then return "scan" end
  return action, wait
end

local function UpdateButton()
  if not page or not selectedID then return end
  local action, wait = Action()
  local label
  if action == "scan" then
    label = "Waiting for the current scan"
  else
    label = B.Label(button, ns.Name(selectedID), action, wait)
  end
  page.action:SetText(label)
  local key = GetBindingKey and GetBindingKey(BINDING)
  local keyText = key and ("Key binding: " .. key .. " works like the button.")
    or "Set a key in Key Bindings > AddOns > MarketWall."
  page.readout:SetText(string.format("%s   Spent on this item this session: %s   Searches this minute: %d of %d",
    keyText, ns.Money(spent[selectedID] or 0), SearchesThisMinute(), SEARCHES_SHOWN_LIMIT))
end

-------------------------------------------------------------------------------
-- Pressing the button
-------------------------------------------------------------------------------
local function OnSearched(id, state, answered)
  local held = ns.ladders[id]
  if answered then
    searched[id] = (held and held.kind == "commodity") and B.Snapshot(held.ladder, Record(id)) or nil
  end
  if id ~= selectedID or state ~= button then return end
  if not answered then
    B.Unanswered(state)
  elseif held and held.kind == "item" then
    B.Finished(state, "Not a commodity")
  elseif not (searched[id] and searched[id].bait) then
    B.Finished(state, "Not confirmed as bait")
  elseif B.Found(state, Plan(id), thresholds[id]) and ns.Cfg("sound") and PlaySound then
    PlaySound((SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master")
  end
  ns.RefreshUI()
end

local function Search()
  local id, state = selectedID, button
  if not ns.SearchNow(id, function(answered) OnSearched(id, state, answered) end) then
    B.Unanswered(state)   -- nothing sent; the next press tries again
    return
  end
  lastSearch = GetTime()
  B.Searched(state)
  searches[#searches + 1] = lastSearch
end

local function Buy()
  local id, state = selectedID, button
  local plan, threshold = state.plan, state.threshold
  if GetMoney() < plan.cost then
    B.Finished(state, "Not enough gold")
    return
  end
  local function OnQuote(unitPrice, total)
    local ok, reason = B.QuoteOK(unitPrice, total, plan.qty, threshold, plan.leaveAt)
    local needPress = ns.Cfg("baitConfirmPress")
    B.Quoted(state, total, ok, reason, needPress, GetTime())
    if not ok then
      ns.CancelPurchase(reason)
    elseif not needPress then
      ns.ConfirmPurchase(state.purchase)
    end
    ns.RefreshUI()
  end
  local function OnEnd(bought, note, total)
    if bought then spent[id] = (spent[id] or 0) + total end
    B.Finished(state, note)
    ns.RefreshUI()
  end
  B.Started(state, GetTime())
  state.purchase = ns.StartCommodityPurchase(id, plan.qty, plan.qty * threshold, OnQuote, OnEnd)
  if not state.purchase then B.Finished(state, "Another purchase is waiting") end
end

-- The button's click and the key binding both land here
function ns.BaitPress()
  if not page or not page:IsVisible() or not selectedID then
    ns.Print("Open the Market tab's Bait Detect page and pick an item first.")
    return
  end
  if not ns.ahOpen then ns.Print("Open the auction house first.") return end
  local action = Action()
  if action == "search" then
    Search()
  elseif action == "buy" then
    Buy()
  elseif action == "confirm" then
    if ns.ConfirmPurchase(button.purchase) then
      B.Confirmed(button, GetTime())
    else
      B.Finished(button, "Purchase cancelled")
    end
  elseif action == "reset" then
    ns.CancelPurchase("No answer from the game")
    B.Finished(button, "No answer from the game")   -- also when nothing was left waiting
  end
  ns.RefreshUI()
end

local function Select(id)
  if ns.HasPendingPurchase() and id ~= selectedID then
    ns.Print("Finish or cancel the current purchase first.")
    return
  end
  if id ~= selectedID then
    selectedID = id
    button = B.NewButton()
    local record = Record(id)
    if not thresholds[id] and record then thresholds[id] = record.p end
  end
  -- the click is the press: it searches when a search is allowed, and never buys
  if ns.ahOpen and Action() == "search" then Search() end
  ns.RefreshUI()
end

local function Replan()
  if selectedID and B.Replan(button, Plan(selectedID), thresholds[selectedID]) then
    ns.CancelPurchase("Limit changed")
  end
  ns.RefreshUI()
end

-------------------------------------------------------------------------------
-- Drawing
-------------------------------------------------------------------------------
-- Every record, confirmed ones first. Rows seen once are dimmed and read "seen once".
local function ListData()
  local items = {}
  for id, record in pairs(ns.R().bait) do
    items[#items + 1] = { id = id, record = record }
  end
  table.sort(items, function(a, b) return B.Before(a.record, b.record) end)
  local data = {}
  for i, item in ipairs(items) do
    local r, copies = item.record, B.Copies(item.record)
    local confirmed = B.Flagged(r)
    local days = ns.DaysOfData(item.id)
    data[i] = {
      id = item.id, highlight = (item.id == selectedID), dim = not confirmed, confirmed = confirmed,
      cells = {
        ns.ColorName(item.id), r.p, r.w, string.format("%d%%", ns.Round(B.Under(r) * 100)),
        -- the answer is green only while copies pile up on confirmed bait
        (confirmed and copies > 0) and tostring(copies) or ns.COLOR.VALUE .. copies .. "|r",
        confirmed and widgets.ShortAge(r.first) or "seen once",
      },
      suffixes = { ns.DataSuffix(days) }, itemTip = ns.LowDataTip(days),
      cellTips = { [2] = string.format("%d unit%s first seen at this price.", r.u, r.u == 1 and "" or "s"), [3] = ns.DataBadgeTip(days) },
    }
  end
  return data
end
ns.BaitListData = ListData   -- for specs

local function EmptyText()
  if not ns.R().lastFull then return widgets.EmptyText("Run a full scan to look for baited items.") end
  return widgets.EmptyText("Nothing looks baited right now.", string.format("An item shows here when a scan finds its cheapest level at least %d%% under the wall and below its normal range.",
    ns.Round(ns.Bait.MinUnder(ns.Cfg("baitMinUnder")) * 100)))
end

local function DrawLadder(id, held, wall)
  local record, threshold = Record(id), thresholds[id]
  local ladder = held and held.ladder or {}
  for i = 1, LADDER_ROWS do
    local line, level = page.ladder[i], ladder[i]
    if level then
      local note, color = "", ""
      if record and level.p == record.p then
        note = "bait " .. B.LevelNote(record)
        color = WARN
      elseif wall and level.p == wall then
        note = GREY .. "wall|r"
      end
      line.price:SetText(color .. ns.Money(level.p) .. "|r")
      line.units:SetText(color .. level.q .. "|r")
      line.note:SetText(color .. note .. "|r")
      if threshold and level.p <= threshold then
        line.bg:SetColorTexture(UNDER_TINT[1], UNDER_TINT[2], UNDER_TINT[3], UNDER_TINT[4])
      else
        line.bg:SetColorTexture(0, 0, 0, 0)
      end
      line:Show()
    elseif i == 1 then
      line.price:SetText(GREY .. (held and "Nothing listed" or "Not searched yet") .. "|r")
      line.units:SetText("")
      line.note:SetText("")
      line.bg:SetColorTexture(0, 0, 0, 0)
      line:Show()
    else
      line:Hide()
    end
  end
end

local function DrawDetail()
  local shown = selectedID ~= nil
  page.detail:SetShown(shown)
  page.pick:SetShown(not shown)
  if not shown then return end
  local id = selectedID
  local held = ns.ladders[id]
  local record = Record(id)
  local stats = ns.StatsFor(id)

  local age = (held and held.kind ~= "scan") and ("searched " .. ns.Ago(held.t)) or "not searched yet"
  page.title:SetText(ns.ColorName(id) .. GREY .. " · live auctions, " .. age .. "|r")

  local wall
  if held and held.total > 0 then wall = W.Compute(held.ladder, held.total, ns.Cfg("wallShare"), ns.Cfg("wallMinUnits")) end
  local parts = { "Wall " .. ns.Money(wall) }
  if stats.n > 0 then
    parts[#parts + 1] = "Median " .. ns.Money(stats.median)
    parts[#parts + 1] = "Normal range " .. ns.Money(stats.p25) .. " to " .. ns.Money(stats.p75)
  else
    parts[#parts + 1] = GREY .. "No normal range yet|r"
  end
  if record then
    parts[#parts + 1] = string.format("Bait first seen %s, %d unit%s", ns.Ago(record.first), record.u, record.u == 1 and "" or "s")
  end
  page.stats:SetText(table.concat(parts, "    "))

  DrawLadder(id, held, wall)
  local plan = Plan(id)
  if plan.blocked > 0 then
    page.blocked:SetText(GREY .. string.format("%d more at or below your price sit above the bait. The game sells the cheapest units first, so choose Buy bait to take them.", plan.blocked) .. "|r")
  else
    page.blocked:SetText("")
  end

  if not page.threshold:HasFocus() then page.threshold:SetText(thresholds[id] and ns.MoneyText(thresholds[id]) or "") end
  page.leave:SetChecked(not buyBait[id])
  page.take:SetChecked(buyBait[id] and true or false)
  UpdateButton()
end

-- "1 possibly baited · 2 seen once", leaving out a zero count; nil with no rows at all
local function StatusNote(confirmed, seenOnce)
  local parts = {}
  if confirmed > 0 then parts[#parts + 1] = confirmed .. " possibly baited" end
  if seenOnce > 0 then parts[#parts + 1] = seenOnce .. " seen once" end
  return parts[1] and table.concat(parts, " · ") or nil
end

function ns.RefreshBait()
  if not page then return end
  local data = ListData()
  local confirmed = 0
  for _, row in ipairs(data) do
    if row.confirmed then confirmed = confirmed + 1 end
  end
  local seenOnce = #data - confirmed
  ns.ui.statusNote = StatusNote(confirmed, seenOnce)
  page.hint:SetText(seenOnce > 0 and SEEN_ONCE_HINT or COPIES_HINT)
  page.list:SetData(data, EmptyText())
  DrawDetail()
end

-------------------------------------------------------------------------------
-- Building
-------------------------------------------------------------------------------
local function BuildLadder(parent, y)
  local header = MakeText(parent, "GameFontNormalSmall")
  header:SetPoint("TOPLEFT", 0, y)
  header:SetText("Price                         Units        Note")
  local lines = {}
  for i = 1, LADDER_ROWS do
    local line = CreateFrame("Frame", nil, parent)
    line:SetSize(RIGHT_WIDTH, 16)
    line:SetPoint("TOPLEFT", 0, y - 2 - i * 16)
    line.bg = line:CreateTexture(nil, "BACKGROUND")
    line.bg:SetAllPoints()
    line.price = MakeText(line, "GameFontHighlightSmall")
    line.price:SetPoint("LEFT", 4, 0)
    line.units = MakeText(line, "GameFontHighlightSmall", "RIGHT")
    line.units:SetPoint("LEFT", 150, 0)
    line.units:SetWidth(50)
    line.note = MakeText(line, "GameFontHighlightSmall")
    line.note:SetPoint("LEFT", 218, 0)
    lines[i] = line
  end
  return lines
end

local function SaveThreshold(box)
  local value = ns.ParseMoney(box:GetText())
  if selectedID and value and value > 0 then thresholds[selectedID] = value end
  box:ClearFocus()
  Replan()
end

local function BuildDetail(parent)
  local detail = CreateFrame("Frame", nil, parent)
  detail:SetPoint("TOPLEFT", RIGHT_X, -50)
  detail:SetSize(RIGHT_WIDTH, 440)

  page.title = MakeText(detail, "GameFontNormal")
  page.title:SetPoint("TOPLEFT", 0, -2)
  page.title:SetWidth(RIGHT_WIDTH)
  page.title:SetWordWrap(false)
  page.stats = MakeText(detail, "GameFontHighlightSmall")
  page.stats:SetPoint("TOPLEFT", 0, -22)
  page.stats:SetWidth(RIGHT_WIDTH)
  page.stats:SetSpacing(2)

  page.ladder = BuildLadder(detail, -54)
  page.blocked = MakeText(detail, "GameFontHighlightSmall")
  page.blocked:SetPoint("TOPLEFT", 0, -202)
  page.blocked:SetWidth(RIGHT_WIDTH)

  local label = MakeText(detail, "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", 0, -234)
  label:SetText("Buy at or below")
  page.threshold = MakeEdit(detail, 90)
  page.threshold:SetPoint("LEFT", label, "RIGHT", 10, 0)
  page.threshold:SetScript("OnEnterPressed", SaveThreshold)
  local hint = MakeText(detail, "GameFontDisableSmall")
  hint:SetPoint("LEFT", page.threshold, "RIGHT", 8, 0)
  hint:SetText("Starts at the bait price. Press Enter.")

  local function Radio(text, x, isBuy)
    local radio = CreateFrame("CheckButton", nil, detail, "UIRadioButtonTemplate")
    radio:SetPoint("TOPLEFT", x, -256)
    radio:SetScript("OnClick", function()
      if selectedID then buyBait[selectedID] = isBuy or nil end
      Replan()
    end)
    local radioLabel = MakeText(detail, "GameFontHighlightSmall")
    radioLabel:SetPoint("LEFT", radio, "RIGHT", 4, 0)
    radioLabel:SetText(text)
    return radio
  end
  page.leave = Radio("Leave bait", 0, false)
  page.take = Radio("Buy bait", 110, true)

  page.action = MakeButton(detail, "", RIGHT_WIDTH)
  page.action:SetHeight(34)
  page.action:SetPoint("TOPLEFT", 0, -282)
  page.action:SetScript("OnClick", ns.BaitPress)

  page.readout = MakeText(detail, "GameFontDisableSmall")
  page.readout:SetPoint("TOPLEFT", 0, -322)
  page.readout:SetWidth(RIGHT_WIDTH)

  local note = MakeText(detail, "GameFontNormalSmall")
  note:SetPoint("TOPLEFT", 0, -352)
  note:SetWidth(RIGHT_WIDTH)
  note:SetText(WARN .. "Press the key yourself. Turbo keys, auto-clickers and macro software can get your account banned. MarketWall never searches or buys on its own.|r")

  -- the waiting countdown and the searches readout change every second
  local elapsed = 0
  detail:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed > 0.2 then
      elapsed = 0
      UpdateButton()
    end
  end)
  return detail
end

function ns.BuildBaitPage(parent)
  page = CreateFrame("Frame", nil, parent)
  page:SetPoint("TOPLEFT", 0, -widgets.CONTENT_DROP)
  page:SetPoint("BOTTOMRIGHT")

  page.list = widgets.CreateList(page, LIST_ROWS)
  page.list:SetPoint("TOPLEFT", 0, -50)
  page.list:SetSize(LIST_WIDTH, widgets.ListHeight(LIST_ROWS))
  page.list:SetColumns(COLUMNS)
  page.list.empty:SetWidth(LIST_WIDTH - 20)
  page.list.onClick = function(entry) Select(entry.id) end

  page.hint = MakeText(page, "GameFontDisableSmall")
  page.hint:SetPoint("TOPLEFT", page.list, "BOTTOMLEFT", 8, -2)
  page.hint:SetWidth(LIST_WIDTH - 90)   -- leaves the list's "1–15 of N" its room on the right
  page.hint:SetText(COPIES_HINT)

  page.pick = MakeText(page, "GameFontDisable", "CENTER")
  page.pick:SetPoint("TOPLEFT", RIGHT_X, -160)
  page.pick:SetWidth(RIGHT_WIDTH)
  page.pick:SetText("Click an item on the left to search its live auctions.")

  page.detail = BuildDetail(page)
  return page
end
