-- MarketWall: labelled farm sessions, fed by the recording core (Record.lua).
-- Saved in MarketWallDB, shared by every character:
--   sessions = { session, ... }, oldest first; only the last can still be running
--   sessionGroups = { [activity name] = group name }, renames and merges that apply to every session
-- It reads MarketWallDB.creatures (Creatures.lua) for each mob's name and family.
-- A session is {
--   label, start, stop,         stop is nil while it runs
--   char, name,                 the GUID (Recording.CharacterKey) and name of who started it;
--                               older sessions have char "Name-Realm" and no name
--   paused =, pausedAt =,       seconds paused before now, and when the current pause began
--   loggedOut =,                true when logging out made the current pause
--   lastGain =,                 active seconds into the session of the last gain
--   gaps = { { t, seconds } },  stretches of over GAP active seconds with nothing gained
--   activities = { [key] = { coin =, drops = { [itemID] = qty } } },
--   ended = { vendor =, market =, optimal = },   value earned at the moment it stopped
-- }
-- Activity keys are "npc:<id>" for kills and "fishing", "herbalism", "mining", "skinning",
-- "gathering", "chests" or "quests"; names are worked out when shown, so a creature's family
-- learned later still groups it. Vendor and auction-house sales are never gains: they only reach
-- the cash ledger.
local _, ns = ...

local Sessions = {}
ns.Sessions = Sessions

Sessions.GAP = 600

local NAMES = {
  fishing = "Fishing", herbalism = "Herbalism", mining = "Mining", skinning = "Skinning",
  gathering = "Gathering", chests = "Chests and containers", quests = "Quests",
}

function Sessions.New(label, char, t, name)
  return { label = label, char = char, name = name, start = t, paused = 0, lastGain = 0, gaps = {}, activities = {} }
end

-- An open session started under a character's legacy "Name-Realm" key moves to its GUID key,
-- as its ledger book does (Ledger.Adopt). Returns whether it moved.
function Sessions.Adopt(s, key, legacy, name)
  if not (s and key) or s.stop or s.char ~= legacy then return false end
  s.char, s.name = key, name
  return true
end

-- Seconds the session has run, paused time left out
function Sessions.Duration(s, now)
  return (s.stop or s.pausedAt or now) - s.start - s.paused
end

Sessions.RELOAD_GAP = 120   -- seconds from logout to login that count as a UI reload when the game does not say

-- PauseAt, ResumeAt and StopAt return whether they changed the session. loggedOut marks the
-- pause logging out made, which a UI reload undoes.
function Sessions.PauseAt(s, t, loggedOut)
  if s.stop or s.pausedAt then return false end
  s.pausedAt = t
  s.loggedOut = loggedOut or nil
  return true
end

function Sessions.ResumeAt(s, t)
  if s.stop or not s.pausedAt then return false end
  s.paused = s.paused + t - s.pausedAt
  s.pausedAt, s.loggedOut = nil, nil
  return true
end

-- At login, resumes a session paused by logging out when it was only a UI reload: reloading as
-- the game reports it, or nil to judge by a short gap. Returns whether it resumed.
function Sessions.AfterLogin(s, t, reloading)
  if not s.loggedOut then return false end
  if reloading == nil then reloading = t - s.pausedAt < Sessions.RELOAD_GAP end
  return reloading and Sessions.ResumeAt(s, t)
end

local function MarkGap(s, active, t)
  local gap = active - s.lastGain
  if gap > Sessions.GAP then s.gaps[#s.gaps + 1] = { t, gap } end
  s.lastGain = active
end

function Sessions.StopAt(s, t)
  if s.stop then return false end
  Sessions.ResumeAt(s, t)
  MarkGap(s, Sessions.Duration(s, t), t)
  s.stop = t
  return true
end

-- The activity a core event counts toward, or nil when it is not a farm gain
function Sessions.ActivityOf(event)
  local kind = event.kind
  if kind == "loot" then return event.npc and ("npc:" .. event.npc) or "chests" end
  if kind == "gather" then return event.skill or "gathering" end
  if kind == "fish" then return "fishing" end
  if kind == "quest" then return "quests" end
end

local function Activity(s, key)
  local activity = s.activities[key]
  if not activity then activity = { coin = 0, drops = {} } s.activities[key] = activity end
  return activity
end

-- A loot window shows a corpse's whole coin, but in a party you receive only your share, so
-- loot and fishing coin is counted by AddLootCoin as it reaches your bags
local function CoinOf(event)
  if event.kind == "loot" or event.kind == "fish" then return 0 end
  return event.coin or 0
end

-- Adds a core event's coin and items to a running session. Returns whether it counted.
function Sessions.Add(s, event)
  if s.stop or s.pausedAt then return false end
  local key = Sessions.ActivityOf(event)
  local coin = CoinOf(event)
  if not key or not (coin > 0 or next(event.drops or {})) then return false end
  MarkGap(s, Sessions.Duration(s, event.t), event.t)
  local activity = Activity(s, key)
  activity.coin = activity.coin + coin
  for id, qty in pairs(event.drops or {}) do activity.drops[id] = (activity.drops[id] or 0) + qty end
  return true
end

-- Adds loot coin you received to a running session, split over the activities of the loot
-- window in proportion to the coin each showed. shown: { [activity key] = copper shown }.
function Sessions.AddLootCoin(s, shown, received, t)
  if s.stop or s.pausedAt or received <= 0 then return false end
  local keys, total = {}, 0
  for key, coin in pairs(shown) do
    if coin > 0 then
      keys[#keys + 1] = key
      total = total + coin
    end
  end
  if total == 0 then return false end
  table.sort(keys, function(a, b) return shown[a] > shown[b] or (shown[a] == shown[b] and a < b) end)
  MarkGap(s, Sessions.Duration(s, t), t)
  local left = received
  for i = #keys, 2, -1 do   -- whole copper each; the largest takes what rounding leaves
    local part = math.floor(received * shown[keys[i]] / total)
    Activity(s, keys[i]).coin = Activity(s, keys[i]).coin + part
    left = left - part
  end
  Activity(s, keys[1]).coin = Activity(s, keys[1]).coin + left
  return true
end

-- An activity's own name: beasts by creature family, other mobs by name
function Sessions.ActivityName(key, creatures)
  local npc = tonumber(key:match("^npc:(%d+)$"))
  if not npc then return NAMES[key] or key end
  local creature = creatures[npc] or {}
  return creature.family or creature.name or ("Mob " .. npc)
end

-- The group an activity name is shown under
function Sessions.GroupOf(groups, name)
  return groups[name] or name
end

-- Renames a group, or merges it into another when to is already a group's name. Activities
-- already merged into from move with it.
function Sessions.Rename(groups, from, to)
  to = Sessions.GroupOf(groups, to)
  if from == to then return end
  for name, group in pairs(groups) do
    if group == from then groups[name] = to end
  end
  groups[from] = to
  groups[to] = nil
end

-- The activity names shown under a group other than its own, sorted
function Sessions.Members(groups, group)
  local members = {}
  for name, to in pairs(groups) do
    if to == group then members[#members + 1] = name end
  end
  table.sort(members)
  return members
end

-- Shows a merged or renamed activity under its own name again. Rename keeps groups one level
-- deep, so nothing else points at the name.
function Sessions.Unmerge(groups, name)
  groups[name] = nil
end

local function PerHour(value, seconds)
  return seconds > 0 and value * 3600 / seconds or 0
end

-- Coins plus items, each item at price(id)
local function Worth(activity, price)
  local value = activity.coin
  for id, qty in pairs(activity.drops) do value = value + qty * price(id) end
  return value
end

function Sessions.Value(s, price)
  local value = 0
  for _, activity in pairs(s.activities) do value = value + Worth(activity, price) end
  return value
end

-- Value earned under each lens, as kept when a session ends. lenses: Mobs.Lenses functions.
function Sessions.Values(s, lenses)
  return { vendor = Sessions.Value(s, lenses.vendor), market = Sessions.Value(s, lenses.market),
    optimal = Sessions.Value(s, lenses.optimal) }
end

local function TopItems(drops, price, count)
  local items = {}
  for id, qty in pairs(drops) do items[#items + 1] = { id = id, qty = qty, value = qty * price(id) } end
  table.sort(items, function(a, b) return a.value > b.value or (a.value == b.value and a.id < b.id) end)
  for i = #items, count + 1, -1 do items[i] = nil end
  return items
end

-- What a session earned at price(id), split into its activity groups, largest first.
-- name(key): an activity key's group name.
function Sessions.Report(s, price, name, now)
  local duration = Sessions.Duration(s, now)
  local byName, value, coin = {}, 0, 0
  for key, activity in pairs(s.activities) do
    local groupName = name(key)
    local group = byName[groupName]
    if not group then group = { name = groupName, coin = 0, drops = {} } byName[groupName] = group end
    group.coin = group.coin + activity.coin
    for id, qty in pairs(activity.drops) do group.drops[id] = (group.drops[id] or 0) + qty end
    coin = coin + activity.coin
  end
  local groups = {}
  for _, group in pairs(byName) do
    group.value = Worth(group, price)
    value = value + group.value
    groups[#groups + 1] = group
  end
  table.sort(groups, function(a, b) return a.value > b.value or (a.value == b.value and a.name < b.name) end)
  for _, group in ipairs(groups) do
    group.share = value > 0 and group.value / value or 0
    group.perHour = PerHour(group.value, duration)
    group.top = TopItems(group.drops, price, 3)
  end
  local gapSeconds = 0
  for _, gap in ipairs(s.gaps) do gapSeconds = gapSeconds + gap[2] end
  return { label = s.label, start = s.start, duration = duration, value = value, coin = coin,
    perHour = PerHour(value, duration), groups = groups, gaps = #s.gaps, gapSeconds = gapSeconds, ended = s.ended }
end

-- Sessions, newest first, with label as given (nil for all). value(s): its value earned.
function Sessions.History(list, label, value, now)
  local rows = {}
  for i = #list, 1, -1 do
    local s = list[i]
    if not label or s.label == label then
      local duration = Sessions.Duration(s, now)
      local v = value(s)
      rows[#rows + 1] = { session = s, duration = duration, value = v, perHour = PerHour(v, duration) }
    end
  end
  return rows
end

-- The best and median gold per hour of History rows, nil when there are none
function Sessions.Compare(rows)
  if #rows == 0 then return nil end
  local rates = {}
  for i, row in ipairs(rows) do rates[i] = row.perHour end
  table.sort(rates)
  local n = #rates
  local median = n % 2 == 1 and rates[(n + 1) / 2] or (rates[n / 2] + rates[n / 2 + 1]) / 2
  return { best = rates[n], median = median }
end

-- Every label used, sorted
function Sessions.Labels(list)
  local seen, labels = {}, {}
  for _, s in ipairs(list) do
    if not seen[s.label] then
      seen[s.label] = true
      labels[#labels + 1] = s.label
    end
  end
  table.sort(labels)
  return labels
end

-- In game -----------------------------------------------------------------------------------

local Print = ns.Print

-- The running or paused session, if any
function Sessions.Current()
  local list = MarketWallDB.sessions
  local last = list[#list]
  if last and not last.stop then return last end
end

-- The lens price functions at current prices and settings
function Sessions.GameLenses()
  return ns.Mobs.Lenses(ns.Mobs.GamePrices(), ns.Mobs.GameOptions(), {})
end

local function Name(key)
  return Sessions.GroupOf(MarketWallDB.sessionGroups, Sessions.ActivityName(key, MarketWallDB.creatures))
end

-- A session's report under lens ("vendor", "market" or "optimal") at current prices
function Sessions.ReportFor(s, lens)
  return Sessions.Report(s, Sessions.GameLenses()[lens], Name, time())
end

-- Seconds as H:MM:SS
function Sessions.Clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
end
local Clock = Sessions.Clock

local function Summary(s)
  local report = Sessions.ReportFor(s, "optimal")
  return string.format("%s: %s, %s earned, %s per hour", s.label, Clock(report.duration),
    ns.Money(report.value), ns.Money(report.perHour))
end

function Sessions.Start(label)
  label = strtrim(label or "")
  if label == "" then return Print("Give the session a label: /mw session start <label>") end
  local running = Sessions.Current()
  if running then return Print("Session \"" .. running.label .. "\" is still open; stop it first.") end
  local char = ns.Recording.CharacterKey()
  if not char then return end
  local list = MarketWallDB.sessions
  local s = Sessions.New(label, char, time(), ns.Recording.CharacterName())
  list[#list + 1] = s
  Print("Session \"" .. label .. "\" started.")
  return s
end

function Sessions.Stop()
  local s = Sessions.Current()
  if not s then return Print("No session is running.") end
  Sessions.StopAt(s, time())
  s.ended = Sessions.Values(s, Sessions.GameLenses())
  Print("Session stopped. " .. Summary(s))
  return s
end

function Sessions.Pause()
  local s = Sessions.Current()
  if s and Sessions.PauseAt(s, time()) then Print("Session \"" .. s.label .. "\" paused.") end
end

-- One character per session: only the character who started it can resume it
function Sessions.Resume()
  local s = Sessions.Current()
  if not s then return Print("No session is open.") end
  if s.char ~= ns.Recording.CharacterKey() then
    return Print("Session \"" .. s.label .. "\" belongs to " .. (s.name or s.char) .. "; stop it to start one here.")
  end
  if Sessions.ResumeAt(s, time()) then Print("Session \"" .. s.label .. "\" resumed.") end
end

-- Renames or merges an activity group, for this and every later session
function Sessions.RenameGroup(from, to)
  Sessions.Rename(MarketWallDB.sessionGroups, from, to)
end

function Sessions.UnmergeName(name)
  Sessions.Unmerge(MarketWallDB.sessionGroups, name)
end

function Sessions.Command(text)
  local cmd, rest = string.match(text or "", "^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "start" then return Sessions.Start(rest) end
  if cmd == "stop" then return Sessions.Stop() end
  if cmd == "pause" then return Sessions.Pause() end
  if cmd == "resume" then return Sessions.Resume() end
  local s = Sessions.Current()
  if s then Print((s.pausedAt and "Paused. " or "Running. ") .. Summary(s)) else Print("No session is running.") end
  print("  /mw session start <label> | stop | pause | resume")
end

local function Running()
  local s = Sessions.Current()
  if s and s.char == ns.Recording.CharacterKey() then return s end
end

-- The latest loot window: the coin each activity in it showed, and when it closed. Loot coin
-- counts only while it is open or just after, so coin from a window that recorded nothing, such
-- as Pick Pocket or a corpse reopened, or a party share with no window of yours, never lands on
-- an earlier window's activities.
local lootWindow = { shown = {}, closedAt = 0 }
local COIN_AFTER_CLOSE = 2   -- seconds, as the ledger allows

ns.Recording.On("window", function(event)
  if event.closed then
    if lootWindow.id == event.window then lootWindow.closedAt = event.t end
  else
    lootWindow = { id = event.window, shown = {} }
  end
end)

local function Record(event)
  local s = Running()
  if s then Sessions.Add(s, event) end
  if (event.kind == "loot" or event.kind == "fish") and lootWindow.id == event.window then
    local key = Sessions.ActivityOf(event)
    lootWindow.shown[key] = (lootWindow.shown[key] or 0) + (event.coin or 0)
  end
end
for _, kind in ipairs({ "loot", "gather", "fish", "quest" }) do ns.Recording.On(kind, Record) end

ns.Recording.On("money", function(event)
  local s = Running()
  if not (s and event.source == "loot") then return end
  if lootWindow.closedAt and event.t - lootWindow.closedAt > COIN_AFTER_CLOSE then return end
  Sessions.AddLootCoin(s, lootWindow.shown, event.delta, event.t)
end)

local entered = false

local HANDLERS = {
  PLAYER_LOGOUT = function()   -- also fires on a UI reload
    local s = Running()
    if s then Sessions.PauseAt(s, time(), true) end
  end,
  -- the first one after loading; isReloadingUi is nil on a client that does not pass it
  PLAYER_ENTERING_WORLD = function(_, isReloadingUi)
    local Recording = ns.Recording   -- adopts on every entry, in case the GUID was not known yet
    Sessions.Adopt(Sessions.Current(), Recording.CharacterKey(), Recording.LegacyKey(), Recording.CharacterName())
    if entered then return end   -- zoning
    entered = true
    local s = Running()
    if not s then return end
    local reloading = nil
    if type(isReloadingUi) == "boolean" then reloading = isReloadingUi end
    if Sessions.AfterLogin(s, time(), reloading) then return end
    if s.pausedAt then
      Print("Session \"" .. s.label .. "\" is paused. /mw session resume to carry on, or /mw session stop.")
    end
  end,
}

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, ...) HANDLERS[event](...) end)
