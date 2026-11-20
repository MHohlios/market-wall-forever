-- MarketWall: the Sessions view of the search window. History lists every farm session; click
-- one, or open the running one, for its value earned and its activities under one lens.
-- Right-click a session, or its "...", to relabel, merge, shorten, delete, or stop it while it
-- runs. Right-click an activity to rename, merge or unmerge its group.
local _, ns = ...
local Sessions = ns.Sessions

local V = {}
ns.SessionsView = V

V.RECENT_LABELS = 5   -- labels the minimap menu offers to start again
local LIST_ROWS, ACTIVITY_ROWS, TOP_ITEMS = 16, 13, 2
local STAT_WIDTH, MORE_WIDTH = 146, 36
local GREY, GAIN, WARN, LABEL, LOSS = ns.COLOR.GREY, ns.COLOR.GAIN, ns.COLOR.WARN, ns.COLOR.LABEL, ns.COLOR.LOSS
local KEEP = "The Ledger and Mobs keep their records."

local HISTORY_COLUMNS = {
  { "Label", 220, nil, "What you farmed. Click a session for its activities; right-click it to edit it." },
  { "Date", 120, nil, "When it started." },
  { "Duration", 100, "RIGHT", "Time it ran, paused time left out." },
  { "Value earned", 130, "RIGHT", "Coins plus items gained, at current prices under the chosen lens.", money = true },
  { "Gold / hour", 130, "RIGHT", "Value earned per hour of running time.", money = true, answer = true },
  { "", MORE_WIDTH, "CENTER" },
}
local ACTIVITY_COLUMNS = {
  { "Activity", 180, nil, "Kills by creature family or name, gathering, fishing, chests and quests. Right-click to rename, merge or unmerge." },
  { "Share", 60, "RIGHT", "Its part of the session's value earned." },
  { "Value", 110, "RIGHT", "Coins plus items gained from it, at current prices under the chosen lens.", money = true },
  { "Gold / hour", 110, "RIGHT", "Its value per hour of the session's running time.", money = true, answer = true },
  { "Top items", 270, nil, "The items that added the most value." },
}

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

function V.StateText(s)
  if s.stop then return nil end
  return s.pausedAt and (WARN .. "paused|r") or (GAIN .. "running|r")
end

-- The running tracker's lines for a session and its Sessions.Report
function V.TrackerText(s, report)
  return {
    title = s.label .. "  " .. V.StateText(s),
    elapsed = Sessions.Clock(report.duration),
    value = ns.Money(report.value),
    perHour = ns.Money(report.perHour),
  }
end

-- Up to count labels, the most recently used first
function V.RecentLabels(list, count)
  local seen, labels = {}, {}
  for i = #list, 1, -1 do
    local label = list[i].label
    if not seen[label] then
      seen[label] = true
      labels[#labels + 1] = label
      if #labels == count then break end
    end
  end
  return labels
end

-- "Turtle Scale x31, Feather x18" for a group's top items
function V.TopText(top)
  local parts = {}
  for i = 1, math.min(TOP_ITEMS, #top) do parts[i] = ns.ColorName(top[i].id) .. " x" .. top[i].qty end
  if #parts == 0 then return GREY .. "coins only|r" end
  return table.concat(parts, ", ")
end

-- List entries for a report's activity groups, largest first
function V.ActivityEntries(report)
  local entries = {}
  for i, group in ipairs(report.groups) do
    entries[i] = {
      group = group.name,
      bar = group.share,
      cells = { group.name, ns.ShareText(group.share), group.value, group.perHour, V.TopText(group.top) },
      sort = { group.name, group.share, group.value, group.perHour, group.top[1] and group.top[1].value },
    }
  end
  return entries
end

local function When(s)
  return date("%b %d, %H:%M", s.start)
end

-- The header line: label, start and duration, and its state while open
function V.HeaderText(s, report)
  local text = s.label .. GREY .. " · " .. When(s) .. " · " .. Sessions.DurationText(report.duration) .. "|r"
  local state = V.StateText(s)
  return state and (text .. "  " .. state) or text
end

-- The stats row for a report under a lens: { { label, value }, ... }
function V.Stats(report, lens)
  local gaps = report.gaps == 0 and "0"
    or string.format("%d (%d min)", report.gaps, math.floor(report.gapSeconds / 60))
  return {
    { "Value earned (current prices)", ns.Money(report.value) },
    -- a stopped session may have none: stopped before they were kept, or merged with one that was
    { "At session end", report.ended and ns.Money(report.ended[lens]) or (GREY .. (report.open and "still open" or "-") .. "|r") },
    { "Gold / hour", ns.Money(report.perHour) },
    { "Coins looted", ns.Money(report.coin) },
    { "Gaps over 10 min", gaps },
  }
end

-- History list entries for sessions with label (nil for all), newest first, with their rows
-- for Sessions.Compare. value(s): a session's value earned.
function V.HistoryEntries(list, label, value, now)
  local rows = Sessions.History(list, label, value, now)
  local entries = {}
  for i, row in ipairs(rows) do
    local s = row.session
    local state = V.StateText(s)
    entries[i] = {
      session = s,
      cells = { s.label .. (state and ("  " .. state) or ""), When(s), Sessions.DurationText(row.duration),
        row.value, row.perHour, "" },
      sort = { s.label, s.start, row.duration, row.value, row.perHour },
    }
  end
  return entries, rows
end

-- The best and median gold per hour of one label's runs; nil for all labels or no runs
function V.CompareText(label, rows)
  local compare = label and Sessions.Compare(rows)
  if not compare then return nil end
  return string.format("%d runs.  Best %s / hour.  Median %s / hour.", #rows, ns.Money(compare.best), ns.Money(compare.median))
end

-- The label dropdown's choices: { label =, runs = } for every label, sorted
function V.LabelChoices(list)
  local runs = {}
  for _, s in ipairs(list) do runs[s.label] = (runs[s.label] or 0) + 1 end
  local choices = {}
  for i, label in ipairs(Sessions.Labels(list)) do choices[i] = { label = label, runs = runs[label] } end
  return choices
end

function V.RunsText(runs)
  return GREY .. " · " .. runs .. (runs == 1 and " run|r" or " runs|r")
end

-- What a session's row menu offers, in order: { kind =, text =, target = }. Kinds: label,
-- merge (target: the session to merge into), duration, delete; and pause, resume and stop in
-- place of merge, duration and delete while the session is open.
function V.MenuChoices(list, s)
  local choices = { { kind = "label", text = "Change label..." } }
  if not s.stop then
    choices[#choices + 1] = s.pausedAt and { kind = "resume", text = "Resume" } or { kind = "pause", text = "Pause" }
    choices[#choices + 1] = { kind = "stop", text = "Stop" }
    return choices
  end
  for _, target in ipairs(Sessions.MergeTargets(list, s)) do
    choices[#choices + 1] = { kind = "merge", target = target,
      text = "Merge into " .. target.label .. GREY .. " · " .. date("%b %d", target.start) .. "|r..." }
  end
  choices[#choices + 1] = { kind = "duration", text = "Edit duration..." }
  choices[#choices + 1] = { kind = "delete", text = "Delete session...", color = LOSS }
  return choices
end

-- The delete confirmation: what goes and what stays. value: the session's value earned.
function V.DeleteText(s, value)
  return string.format("Delete the session \"%s\" from %s?", s.label, When(s)),
    string.format("Its %s and %s of loot leave Sessions. %s", Sessions.DurationText(Sessions.Duration(s)), ns.Money(value), KEEP)
end

function V.MergeText(from, into)
  return string.format("Merge \"%s\" (%s) into \"%s\" (%s)?", from.label, When(from), into.label, When(into)),
    string.format("Their times and loot add up under \"%s\", from the earlier start. %s", into.label, KEEP)
end

-- Seconds from typed minutes, "44", or hours and minutes, "1:12"; nil unless above zero, and
-- for hours and minutes unless the minutes are under 60
function V.ParseDuration(text)
  local hours, minutes = string.match(text, "^(%d+):(%d%d)$")
  if hours then
    hours, minutes = tonumber(hours), tonumber(minutes)
    if minutes > 59 then return nil end
    minutes = hours * 60 + minutes
  else
    minutes = tonumber(string.match(text, "^%d+$"))
  end
  return minutes and minutes > 0 and minutes * 60 or nil
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local function GroupMenu(panel, name, report)
  local items = { { text = name } }
  items[#items + 1] = { text = "Rename...", onClick = function()
    ns.widgets.Prompt("Rename \"" .. name .. "\" to (an existing group's name merges them):", name, function(to)
      Sessions.RenameGroup(name, to)
      panel:Refresh()
    end)
  end }
  for _, group in ipairs(report.groups) do
    if group.name ~= name then
      items[#items + 1] = { text = "Merge into " .. group.name, onClick = function()
        Sessions.RenameGroup(name, group.name)
        panel:Refresh()
      end }
    end
  end
  for _, member in ipairs(Sessions.Members(MarketWallDB.sessionGroups, name)) do
    items[#items + 1] = { text = "Unmerge " .. member, onClick = function()
      Sessions.UnmergeName(member)
      panel:Refresh()
    end }
  end
  ns.widgets.ShowMenu(items)
end

-- Session edits change MarketWallDB.sessions only; see Sessions.lua's Editing
local function SessionMenu(panel, s)
  local w, list = ns.widgets, MarketWallDB.sessions
  local function Done() panel:Refresh() end
  local actions = {
    label = function()
      w.Prompt("New label for this session:", s.label, function(to) s.label = to Done() end)
    end,
    pause = function() Sessions.Pause() Done() end,
    resume = function() Sessions.Resume() Done() end,
    stop = function() Sessions.Stop() Done() end,
    duration = function()
      w.Prompt("Running time in minutes, or hours:minutes:", tostring(math.floor(Sessions.Duration(s) / 60)), function(text)
        local seconds = V.ParseDuration(text)
        if not seconds then return ns.Print("Type the running time in minutes, such as 44, or as 1:12.") end
        Sessions.SetDuration(s, seconds)
        Done()
      end)
    end,
    delete = function()
      local question, detail = V.DeleteText(s, Sessions.Value(s, Sessions.GameLenses()[panel.lens]))
      w.Confirm(question, detail, "Delete", function() Sessions.Delete(list, s) Done() end)
    end,
  }
  local items = { { text = s.label .. " · " .. date("%b %d", s.start) } }
  for _, choice in ipairs(V.MenuChoices(list, s)) do
    local onClick = actions[choice.kind]
    if choice.kind == "merge" then
      onClick = function()
        local question, detail = V.MergeText(s, choice.target)
        w.Confirm(question, detail, "Merge", function() Sessions.Merge(list, s, choice.target) Done() end)
      end
    end
    items[#items + 1] = { text = choice.text, color = choice.color, onClick = onClick }
  end
  w.ShowMenu(items)
end

local function RenameLabel(panel, from)
  ns.widgets.Prompt("Rename \"" .. from .. "\" on every session that has it, to:", from, function(to)
    Sessions.RenameLabel(MarketWallDB.sessions, from, to)
    if panel.label == from then panel.label = to end
    panel:Refresh()
  end)
end

local function LabelMenu(panel)
  local function Pick(label) return function() panel.label = label panel.list.offset = 0 panel:Refresh() end end
  local choices = V.LabelChoices(MarketWallDB.sessions)
  local items = { { text = "Labels" }, { text = "All labels", color = panel.label == nil and LABEL, onClick = Pick(nil) } }
  for _, choice in ipairs(choices) do
    items[#items + 1] = { text = choice.label .. V.RunsText(choice.runs),
      color = panel.label == choice.label and LABEL, onClick = Pick(choice.label) }
  end
  items[#items + 1] = { text = "Rename a label...", disabled = #choices == 0, onClick = function()
    local which = { { text = "Rename which label?" } }
    for _, choice in ipairs(choices) do
      which[#which + 1] = { text = choice.label, onClick = function() RenameLabel(panel, choice.label) end }
    end
    ns.widgets.ShowMenu(which)
  end }
  ns.widgets.ShowMenu(items)
end

-- A "..." button over each history row's last cell, opening the row's menu
local function AddMoreButtons(panel)
  for _, row in ipairs(panel.list.rows) do
    local more = CreateFrame("Button", nil, row)
    more:SetSize(MORE_WIDTH - 8, 18)
    more:SetPoint("RIGHT", -4, 0)
    more:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    local text = ns.widgets.MakeText(more, "GameFontDisableSmall", "CENTER")
    text:SetAllPoints()
    text:SetText("...")
    more:SetScript("OnClick", function() if row.entry then SessionMenu(panel, row.entry.session) end end)
  end
end

-- The Sessions panel, filling parent below the window heading
function V.Build(parent)
  local w = ns.widgets
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.lens = "optimal"
  panel.session = Sessions.Current()   -- the session shown, nil for the history
  panel.label = nil                    -- the history's label filter, nil for all
  panel.sorts = {}                     -- [history or activities] = { col, desc } once a header is clicked

  panel.lensSwitch = w.MakeSwitch(panel, ns.MobsView.LENSES, function(key)
    panel.lens = key
    panel:Refresh()
  end)
  panel.lensSwitch:SetPoint("TOPRIGHT", -16, -36)
  local lensLabel = w.MakeText(panel, "GameFontDisableSmall", "RIGHT")
  lensLabel:SetPoint("RIGHT", panel.lensSwitch, "LEFT", -6, 0)
  lensLabel:SetText("Value by")

  -- History: label filter and the comparison of one label's runs
  panel.labelButton = w.MakeDropdown(panel, 180)
  panel.labelButton:SetPoint("TOPLEFT", 12, -34)
  panel.labelButton:SetScript("OnClick", function() LabelMenu(panel) end)
  panel.compare = w.MakeText(panel, "GameFontHighlightSmall")
  panel.compare:SetPoint("LEFT", panel.labelButton, "RIGHT", 12, 0)

  -- One session: back to the history, its header and stats
  panel.back = w.MakeButton(panel, "All sessions", 110)
  panel.back:SetPoint("TOPLEFT", 12, -34)
  panel.back:SetScript("OnClick", function() panel:ShowSession(nil) end)
  panel.title = w.MakeText(panel, "GameFontNormal")
  panel.title:SetPoint("LEFT", panel.back, "RIGHT", 12, 0)
  panel.title:SetPoint("RIGHT", lensLabel, "LEFT", -8, 0)
  panel.title:SetWordWrap(false)
  panel.stats = {}
  for i = 1, 5 do
    local label = w.MakeText(panel, "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", 14 + (i - 1) * STAT_WIDTH, -66)
    label:SetWidth(STAT_WIDTH - 6)
    label:SetWordWrap(false)
    local value = w.MakeText(panel, "GameFontHighlight")
    value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -3)
    panel.stats[i] = { label = label, value = value }
  end

  panel.list = w.CreateList(panel, LIST_ROWS)
  panel.list:SetPoint("TOPLEFT", 12, -62)
  panel.list:SetSize(736, w.ListHeight(LIST_ROWS))
  panel.list.onClick = function(entry)
    if entry.session then panel:ShowSession(entry.session) end
  end
  panel.list.onRightClick = function(entry) SessionMenu(panel, entry.session) end
  panel.list.onHeader = function(col)
    if col == #HISTORY_COLUMNS then return end
    local sort = panel.sorts.history
    if sort and sort.col == col then sort.desc = not sort.desc else panel.sorts.history = { col = col, desc = col ~= 1 } end
    panel:Refresh()
  end
  AddMoreButtons(panel)

  panel.activities = w.CreateList(panel, ACTIVITY_ROWS)
  panel.activities:SetPoint("TOPLEFT", 12, -106)
  panel.activities:SetSize(736, w.ListHeight(ACTIVITY_ROWS))
  panel.activities.onRightClick = function(entry) GroupMenu(panel, entry.group, panel.report) end
  panel.activities.onHeader = function(col)
    local sort = panel.sorts.activities
    if sort and sort.col == col then sort.desc = not sort.desc else panel.sorts.activities = { col = col, desc = col ~= 1 } end
    panel:Refresh()
  end

  panel.hint = w.MakeText(panel, "GameFontDisableSmall")
  panel.hint:SetPoint("BOTTOMLEFT", 14, 12)

  -- s: the session to show, nil for the history
  function panel:ShowSession(s)
    self.session = s
    self.activities.offset = 0
    self:Refresh()
  end

  -- Whether the shown numbers change by the second: a running session is on screen
  function panel:Live()
    local current = Sessions.Current()
    return current ~= nil and not current.pausedAt and (self.session == nil or self.session == current)
  end

  local function Show(list, columns, data, sort, empty)
    ns.MobsView.Sort(data, sort)
    list:SetColumns(columns, sort and sort.col, sort and sort.desc)
    list:SetData(data, empty)
  end

  function panel:Refresh()
    self.lensSwitch:Select(self.lens)
    local one = self.session ~= nil
    self.labelButton:SetShown(not one)
    self.compare:SetShown(not one)
    self.list:SetShown(not one)
    self.back:SetShown(one)
    self.title:SetShown(one)
    self.activities:SetShown(one)
    for _, stat in ipairs(self.stats) do
      stat.label:SetShown(one)
      stat.value:SetShown(one)
    end
    local now = time()
    if one then
      self.report = Sessions.ReportFor(self.session, self.lens)
      self.title:SetText(V.HeaderText(self.session, self.report))
      for i, stat in ipairs(V.Stats(self.report, self.lens)) do
        self.stats[i].label:SetText(stat[1])
        self.stats[i].value:SetText(stat[2])
      end
      Show(self.activities, ACTIVITY_COLUMNS, V.ActivityEntries(self.report), self.sorts.activities,
        "Nothing gained yet. Loot, gather, fish, open chests or hand in quests while the session runs.")
      self.hint:SetText("Right-click an activity to rename, merge or unmerge it. Groups apply to every session.")
      return
    end
    local price = Sessions.GameLenses()[self.lens]
    local entries, rows = V.HistoryEntries(MarketWallDB.sessions, self.label, function(s) return Sessions.Value(s, price) end, now)
    self.labelButton:SetLabel(self.label or "All labels")
    self.compare:SetText(V.CompareText(self.label, rows) or (GREY .. "Pick a label to compare its runs.|r"))
    Show(self.list, HISTORY_COLUMNS, entries, self.sorts.history,
      "No sessions yet. Right-click the minimap button, or /mw session start <label>.")
    self.hint:SetText("Values follow current prices. Click a session for its activities; right-click or ... to edit it.")
  end

  return panel
end
