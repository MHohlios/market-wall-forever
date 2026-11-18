-- MarketWall: the Mobs view of the search window. Every recorded mob and its value per kill
-- under one lens, sorted by median per kill; click a mob for its drop table.
local _, ns = ...

local V = {}
ns.MobsView = V

V.LENSES = { { key = "optimal", label = "Optimal" }, { key = "market", label = "Market" }, { key = "vendor", label = "Vendor" } }

local LIST_ROWS = 16
local GREY, ORANGE = "|cffa3acac", "|cffffb057"

local MOB_COLUMNS = {
  { "Mob", 196, nil, "Every mob you, your pet or your party killed. Click a row for its drop table." },
  { "Kills", 50, "RIGHT", "Kills recorded, including ones someone else looted." },
  { "Median / kill", 90, "RIGHT", "The typical kill under the chosen lens. Kills someone else looted are left out; empty corpses count as 0c." },
  { "Average / kill", 90, "RIGHT", "The long-run value per kill under the chosen lens. Well above the median means rare drops carry the value." },
  { "Without rare", 90, "RIGHT", "Average per kill leaving out drops seen in fewer kills than the rare drop threshold." },
  { "Top drop", 160, nil, "The drop that adds the most value, and the share of kills it drops in." },
  { "Unpriced", 60, "RIGHT", "Drops with no market price yet. They count as 0c in Market until a scan prices them." },
}
local DROP_COLUMNS = {
  { "Item", 230, nil, "Each item this mob dropped, the most value per kill first." },
  { "% of kills", 90, "RIGHT", "The share of looted and empty kills it dropped in." },
  { "Avg quantity", 90, "RIGHT", "How many drop at once, on average, when it drops." },
  { "Vendor", 100, "RIGHT", "One unit's vendor price." },
  { "Market", 100, "RIGHT", "One unit's wall price after the cut, or vendor when the market is thin." },
  { "Optimal", 100, "RIGHT", "The best of vendor, market and, when included, disenchanting." },
}

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

local function Count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- One row per mob from Mobs.All whose name contains the filter, ignoring case. Mobs with values
-- come first, highest median per kill under the lens first; mobs still short of kills follow,
-- most kills first.
function V.Rows(all, lens, filter)
  local want = string.lower(strtrim(filter or ""))
  local rows = {}
  for _, stats in ipairs(all) do
    local name = stats.name or ("NPC " .. stats.npc)
    if want == "" or string.find(string.lower(name), want, 1, true) then
      local value, common = stats[lens], stats[lens .. "NoRare"]
      rows[#rows + 1] = {
        npc = stats.npc, name = name, kills = stats.lifetime,
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

-- Display cells for a mob row; rows short of kills say how many they need
function V.MobCells(row, minKills)
  if not row.median then
    return { row.name, tostring(row.kills), GREY .. "-|r", GREY .. "-|r", GREY .. "-|r", GREY .. "needs " .. minKills .. " kills|r", "" }
  end
  local top = row.top and (ns.ColorName(row.top.id) .. " " .. ns.ShareText(row.top.share)) or GREY .. "-|r"
  local unpriced = row.unpriced > 0 and (ORANGE .. row.unpriced .. "|r") or (GREY .. "0|r")
  return { row.name, tostring(row.kills), ns.Money(row.median), ns.Money(row.average), ns.Money(row.withoutRare), top, unpriced }
end

function V.DropCells(drop)
  return { ns.ColorName(drop.id), ns.ShareText(drop.share), string.format("%.1f", drop.quantity),
    ns.Money(drop.vendor), ns.Money(drop.market), ns.Money(drop.optimal) }
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

  panel.lensButtons = {}
  local previous
  for i, lens in ipairs(V.LENSES) do
    local button = w.MakeButton(panel, lens.label, 72)
    if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 12, -34) end
    button:SetScript("OnClick", function()
      panel.lens = lens.key
      panel.list.offset = 0
      panel:Refresh()
    end)
    panel.lensButtons[i] = button
    previous = button
  end

  panel.filter = w.MakeEdit(panel, 160)
  panel.filter:SetPoint("TOPRIGHT", -16, -35)
  panel.filter:SetScript("OnTextChanged", function()
    panel.list.offset = 0
    panel:Refresh()
  end)
  local filterLabel = w.MakeText(panel, "GameFontDisableSmall", "RIGHT")
  filterLabel:SetPoint("RIGHT", panel.filter, "LEFT", -10, 0)
  filterLabel:SetText("Sorted by median per kill · search")

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
  panel.hint = w.MakeText(panel, "GameFontDisableSmall")
  panel.hint:SetPoint("BOTTOMLEFT", 14, 12)

  function panel:Refresh()
    local dropTable = self.npc ~= nil
    for _, button in ipairs(self.lensButtons) do button:SetShown(not dropTable) end
    self.filter:SetShown(not dropTable)
    filterLabel:SetShown(not dropTable)
    self.back:SetShown(dropTable)
    self.title:SetShown(dropTable)
    if dropTable then
      local stats = ns.Mobs.For(self.npc)
      self.title:SetText((stats.name or ("NPC " .. self.npc)) .. GREY .. " · drop table, " .. stats.seen .. " kills with loot seen|r")
      local data = {}
      for _, drop in ipairs(ns.Mobs.GameDropTable(self.npc)) do data[#data + 1] = { id = drop.id, cells = V.DropCells(drop) } end
      self.list:SetColumns(DROP_COLUMNS)
      self.list:SetData(data, "No drops seen yet.")
      self.hint:SetText("Values are for one unit, at current prices.")
      return
    end
    for i, button in ipairs(self.lensButtons) do
      if V.LENSES[i].key == self.lens then button:LockHighlight() else button:UnlockHighlight() end
    end
    local minKills = ns.Cfg("mobMinKills")
    local data = {}
    for _, row in ipairs(V.Rows(ns.Mobs.All(), self.lens, self.filter:GetText())) do
      data[#data + 1] = { npc = row.npc, cells = V.MobCells(row, minKills) }
    end
    self.list:SetColumns(MOB_COLUMNS)
    local empty = next(MarketWallDB.mobs) and "No recorded mob matches." or "No kills recorded yet. Loot what you kill and each mob's value shows here."
    self.list:SetData(data, empty)
    self.hint:SetText("Click a mob for its drop table. Hover a column title for what it means.")
  end

  return panel
end
