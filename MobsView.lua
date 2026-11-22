-- MarketWall: the Mobs view of the search window. Every recorded mob and its value per kill
-- under one lens, sorted by median per kill; click a mob for its drop table.
local _, ns = ...

local V = {}
ns.MobsView = V

V.LENSES = { { key = "optimal", label = "Optimal" }, { key = "market", label = "Market" }, { key = "vendor", label = "Vendor" } }

local LIST_ROWS = 16
local GREY, WARN = ns.COLOR.GREY, ns.COLOR.WARN

local MOB_COLUMNS = {
  { "Mob", 230, nil, "Every mob you, your pet or your party killed. Click a row for its drop table." },
  { "Kills", 60, "RIGHT", "Kills whose loot was seen: looted, or empty at 0c. Kills someone else looted are left out, as they are from the values. Orange: fewer than Kills before reliable, so the values are rough." },
  { "Per kill", 100, "RIGHT", "The typical kill, the median, under the chosen lens. Kills someone else looted are left out; empty corpses count as 0c. Hover a value for the average without rare drops.",
    money = true, answer = true, cellTip = true },
  { "Average", 100, "RIGHT", "The long-run value per kill under the chosen lens. Well above the median means rare drops carry the value.", money = true, grey = true },
  { "Top drop", 246, nil, "The drop that adds the most value, and the share of kills it drops in. An orange note counts drops with no market price yet: they count as 0c in Market until a scan prices them." },
}
local DROP_COLUMNS = {
  { "Item", 230, nil, "Each item this mob dropped, the most value per kill first." },
  { "% of kills", 90, "RIGHT", "The share of looted and empty kills it dropped in." },
  { "Avg quantity", 90, "RIGHT", "How many drop at once, on average, when it drops." },
  { "Vendor", 100, "RIGHT", "One unit's vendor price.", money = true },
  { "Market", 100, "RIGHT", "One unit's wall price after the cut and deposit, thin markets included.", money = true },
  { "Optimal", 100, "RIGHT", "The best of vendor, market and, when included, disenchanting.", money = true },
}

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

local function Count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- What a mob the game never named is called
local function UnknownName(npc)
  return "Unknown mob (" .. npc .. ")"
end

-- One row per mob from Mobs.All whose name contains the filter, ignoring case. Mobs with values
-- come first, highest median per kill under the lens first; mobs with no seen kill follow,
-- most kills first.
function V.Rows(all, lens, filter)
  local want = string.lower(strtrim(filter or ""))
  local rows = {}
  for _, stats in ipairs(all) do
    local name = stats.name or UnknownName(stats.npc)
    if want == "" or string.find(string.lower(name), want, 1, true) then
      local value, common = stats[lens], stats[lens .. "NoRare"]
      rows[#rows + 1] = {
        npc = stats.npc, name = name, unknown = stats.name == nil, kills = stats.seen,
        median = value and value.median, average = value and value.average,
        withoutRare = common and common.average, top = stats.top,
        unpriced = stats.market and Count(stats.market.unpriced),
      }
    end
  end
  table.sort(rows, function(a, b)
    if (a.median ~= nil) ~= (b.median ~= nil) then return a.median ~= nil end
    if a.median and a.median ~= b.median then return a.median > b.median end
    if a.kills ~= b.kills then return a.kills > b.kills end
    return a.name < b.name
  end)
  return rows
end

-- Whether a row has values from fewer seen kills than make them reliable
local function Rough(row, reliableKills)
  return row.median ~= nil and row.kills < reliableKills
end

-- Display cells for a mob row, money as copper for the list to format: Mob, Kills, Per kill,
-- Average, Top drop. An unknown mob's name is grey; a mob with no seen kill has no values and
-- a grey count; the count is orange while the values are rough, like a low-data item's days.
function V.MobCells(row, reliableKills)
  local name = row.unknown and (GREY .. row.name .. "|r") or row.name
  if not row.median then
    return { name, GREY .. row.kills .. "|r", GREY .. "-|r", GREY .. "-|r", GREY .. "-|r" }
  end
  local kills = Rough(row, reliableKills) and (WARN .. row.kills .. "|r") or tostring(row.kills)
  return { name, kills, row.median, row.average, row.top and ns.ColorName(row.top.id) or GREY .. "-|r" }
end

-- What follows the top drop's name and stays visible when the name is cut short: its share of
-- kills in grey, then an orange note when some drops have no market price yet
function V.TopSuffix(row)
  if not row.median then return nil end
  local share = row.top and (" " .. GREY .. ns.ShareText(row.top.share) .. "|r") or ""
  local unpriced = row.unpriced > 0 and (WARN .. " · " .. row.unpriced .. " unpriced|r") or ""
  if share .. unpriced ~= "" then return share .. unpriced end
end

-- The Per kill cell's hover: the average leaving out rare drops
function V.PerKillTip(row)
  if row.withoutRare then return "Average without rare drops: " .. ns.Money(row.withoutRare) end
end

-- The hover for a mob row whose values are rough, nil otherwise
function V.MobTip(row, reliableKills)
  if Rough(row, reliableKills) then return "Fewer than " .. reliableKills .. " kills; values are rough" end
end

function V.DropCells(drop)
  return { ns.ColorName(drop.id), ns.ShareText(drop.share), string.format("%.1f", drop.quantity),
    drop.vendor, drop.market, drop.optimal }
end

-- Raw values per column, for sorting by a header
function V.MobSortValues(row)
  return { row.name, row.kills, row.median, row.average, row.top and row.top.share }
end

function V.DropSortValues(drop)
  return { ns.Name(drop.id), drop.share, drop.quantity, drop.vendor, drop.market, drop.optimal }
end

-- Sorts entries by entry.sort[sort.col], keeping their order on ties; rows with no value go
-- last. No sort keeps the order they came in.
function V.Sort(entries, sort)
  if not sort then return end
  for i, entry in ipairs(entries) do entry.order = i end
  table.sort(entries, function(a, b)
    local x, y = a.sort[sort.col], b.sort[sort.col]
    if x == y then return a.order < b.order end
    if x == nil then return false end
    if y == nil then return true end
    if sort.desc then return x > y end
    return x < y
  end)
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

-- The Mobs panel, filling parent below the window heading
function V.Build(parent)
  local w = ns.widgets
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.lens = "optimal"
  panel.npc = nil   -- the mob whose drop table is open

  local lensLabel = w.MakeText(panel, "GameFontDisableSmall")
  lensLabel:SetPoint("TOPLEFT", 14, -40)
  lensLabel:SetText("Value by")
  panel.lensSwitch = w.MakeSwitch(panel, V.LENSES, function(key)
    panel.lens = key
    panel.list.offset = 0
    panel:Refresh()
  end)
  panel.lensSwitch:SetPoint("LEFT", lensLabel, "RIGHT", 4, 0)

  panel.filter = w.MakeEdit(panel, 220)
  panel.filter:SetPoint("TOPRIGHT", -16, -35)
  panel.filter:SetScript("OnTextChanged", function()
    panel.list.offset = 0
    panel:Refresh()
  end)
  w.SetPlaceholder(panel.filter, "Search mobs")

  panel.back = w.MakeButton(panel, "Back to mobs", 110)
  panel.back:SetPoint("TOPLEFT", 12, -34)
  panel.back:SetScript("OnClick", function()
    panel.npc = nil
    panel:Refresh()
  end)
  panel.title = w.MakeText(panel, "GameFontNormal")
  panel.title:SetPoint("LEFT", panel.back, "RIGHT", 12, 0)

  panel.list = w.CreateList(panel, LIST_ROWS)
  panel.list:SetPoint("TOPLEFT", 12, -62)
  panel.list:SetSize(736, w.ListHeight(LIST_ROWS))
  panel.list.onClick = function(entry)
    if entry.npc then
      panel.npc = entry.npc
      panel.list.offset = 0
      panel:Refresh()
    end
  end
  panel.sorts = {}   -- [mobs or drops] = { col, desc } once a header is clicked
  panel.list.onHeader = function(col)
    local key = panel.npc and "drops" or "mobs"
    local sort = panel.sorts[key]
    if sort and sort.col == col then
      sort.desc = not sort.desc
    else
      panel.sorts[key] = { col = col, desc = col ~= 1 }   -- names A to Z, numbers biggest first
    end
    panel.list.offset = 0
    panel:Refresh()
  end
  panel.hint = w.MakeText(panel, "GameFontDisableSmall")
  panel.hint:SetPoint("BOTTOMLEFT", 14, 12)

  local function Show(columns, data, sort, empty)
    V.Sort(data, sort)
    panel.list:SetColumns(columns, sort and sort.col, sort and sort.desc)
    panel.list:SetData(data, empty)
  end

  function panel:Refresh()
    local dropTable = self.npc ~= nil
    lensLabel:SetShown(not dropTable)
    self.lensSwitch:SetShown(not dropTable)
    self.filter:SetShown(not dropTable)
    self.back:SetShown(dropTable)
    self.title:SetShown(dropTable)
    if dropTable then
      local stats = ns.Mobs.For(self.npc)
      self.title:SetText((stats.name or (GREY .. UnknownName(self.npc) .. "|r")) .. GREY .. " · drop table, " .. stats.seen .. " kills with loot seen|r")
      local data = {}
      for _, drop in ipairs(ns.Mobs.GameDropTable(self.npc)) do
        data[#data + 1] = { id = drop.id, cells = V.DropCells(drop), sort = V.DropSortValues(drop) }
      end
      Show(DROP_COLUMNS, data, self.sorts.drops, "No drops seen yet.")
      self.hint:SetText("Values are for one unit, at current prices.")
      return
    end
    self.lensSwitch:Select(self.lens)
    local reliableKills = ns.Cfg("mobMinKills")
    local data = {}
    for _, row in ipairs(V.Rows(ns.Mobs.All(), self.lens, self.filter:GetText())) do
      data[#data + 1] = { npc = row.npc, cells = V.MobCells(row, reliableKills), sort = V.MobSortValues(row),
        suffixes = { [5] = V.TopSuffix(row) }, cellTips = { [3] = V.PerKillTip(row) },
        tip = V.MobTip(row, reliableKills) }
    end
    local empty = next(MarketWallDB.mobs) and "No recorded mob matches." or "No kills recorded yet. Loot what you kill and each mob's value shows here."
    Show(MOB_COLUMNS, data, self.sorts.mobs, empty)
    self.hint:SetText("Click a mob for its drop table. Hover Per kill for the average without rare drops.")
  end

  return panel
end
