-- MarketWall: a temporary, read-only probe of what Forever exposes for kills, loot and money.
-- Off until "/mw probe start". It records only counts, types, secret-ness, spell and item IDs
-- and creature IDs into MarketWallDB.probe, never chat text, names or other players' GUIDs.
-- Delete this file, its TOC line and the "probe" slash command once Phase 5 is designed.
local _, ns = ...

local MONEY_WINDOW = 2    -- seconds either side of a money change that count as its context
local POLL_SECONDS = 0.25 -- how often the targeted unit is checked for death
local PARTY_SECONDS = 10  -- how often party1 is probed
local MAX_SAMPLES, MAX_SIGNATURES = 3, 5
local MAX_LOOTS, MAX_MONEY, MAX_DEATHS, MAX_SPELLS, MAX_SLOTS = 100, 200, 100, 100, 20
local MAX_ERROR = 160
local SAMPLE_ITEM = 2589  -- Linen Cloth, for the item-info checks

local EVENTS = {
  "UNIT_DIED", "PARTY_KILL", "UNIT_HEALTH", "UNIT_FLAGS", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CLEARED", "LOOT_CLOSED", "CHAT_MSG_LOOT", "CHAT_MSG_MONEY",
  "UNIT_SPELLCAST_SUCCEEDED", "COMBAT_LOG_EVENT_UNFILTERED",
  "PLAYER_MONEY", "MERCHANT_SHOW", "MERCHANT_CLOSED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
  "TAXIMAP_OPENED", "TAXIMAP_CLOSED", "TRAINER_SHOW", "TRAINER_CLOSED", "QUEST_TURNED_IN",
  "TRADE_SHOW", "TRADE_CLOSED", "TRADE_ACCEPT_UPDATE", "CHAT_MSG_SYSTEM",
}

-- Events registered for one unit only
local UNIT_EVENTS = { UNIT_HEALTH = "target", UNIT_SPELLCAST_SUCCEEDED = "player" }

-- The money context each event marks: { tag, open } where open is true or false for windows
local CONTEXT = {
  MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
  MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false }, MAIL_INBOX_UPDATE = { "mail" },
  TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
  TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
  TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade", false }, TRADE_ACCEPT_UPDATE = { "trade" },
  LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false }, LOOT_SLOT_CLEARED = { "loot" },
  QUEST_TURNED_IN = { "quest" }, CHAT_MSG_MONEY = { "chatMoney" }, CHAT_MSG_SYSTEM = { "system" },
}

-- Kind and ID from a GUID. Only creatures, vehicles and objects keep their ID; every other kind,
-- players included, is reduced to its kind.
function ns.ProbeParseGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind = string.match(guid, "^(%a+)%-")
  if kind == "Creature" or kind == "Vehicle" or kind == "GameObject" then
    return kind, tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
  end
  return kind
end

-- Sorted tags of windows open now or events seen within `window` seconds of time t
function ns.ProbeMoneyContext(t, open, seen, window)
  local tags = {}
  for tag, isOpen in pairs(open) do
    if isOpen then tags[tag] = true end
  end
  for tag, at in pairs(seen) do
    if math.abs(t - at) <= window then tags[tag] = true end
  end
  local list = {}
  for tag in pairs(tags) do list[#list + 1] = tag end
  table.sort(list)
  return list
end

local log           -- MarketWallDB.probe while running
local frame         -- created on the first start, so a probe never started registers nothing
local running = false
local clockStart
local target, open, seen, lastMoney, lastKillGUID, looting   -- in memory only, never saved

local function Now()
  return math.floor((GetTime() - clockStart) * 10 + 0.5) / 10
end

local function Append(list, item, cap, name)
  if #list < cap then
    list[#list + 1] = item
  else
    log.dropped[name] = (log.dropped[name] or 0) + 1
  end
end

local function Secret(v)
  local check = _G.issecretvalue
  if not check then return false end
  local ok, secret = pcall(check, v)
  return ok and secret == true
end

-- A value's type, with "*" when it is secret
local function Describe(v)
  return type(v) .. (Secret(v) and "*" or "")
end

-- A number or boolean safe to save, "secret" for a secret value, otherwise nil
local function Plain(v)
  if Secret(v) then return "secret" end
  local kind = type(v)
  if kind == "number" or kind == "boolean" then return v end
  return nil
end

-- Readable as a plain string: not secret and a string
local function ReadableString(v)
  return not Secret(v) and type(v) == "string"
end

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function Signature(values, first)
  local parts = {}
  for i = first, values.n do parts[#parts + 1] = Describe(values[i]) end
  return table.concat(parts, ",")
end

local function TrimError(err)
  return string.sub(tostring(err), 1, MAX_ERROR)
end

local function Resolve(path)
  local value = _G
  for key in string.gmatch(path, "[^%.]+") do
    if type(value) ~= "table" then return nil end
    value = value[key]
  end
  return value
end

local function Api(label, path)
  local api = log.apis[label]
  if not api then
    api = { calls = 0, errors = 0, secret = 0, returns = {}, signatures = 0, otherReturns = 0 }
    log.apis[label] = api
  end
  api.exists = type(Resolve(path)) == "function"
  return api
end

-- Calls path(...) under pcall and records the outcome under label. Returns the values, or nothing.
local function Call(label, path, ...)
  local api = Api(label, path)
  if not api.exists then return end
  api.calls = api.calls + 1
  local result = Pack(pcall(Resolve(path), ...))
  if not result[1] then
    api.errors = api.errors + 1
    api.err = api.err or TrimError(result[2])
    return
  end
  local signature = Signature(result, 2)
  if string.find(signature, "*", 1, true) then api.secret = api.secret + 1 end
  if api.returns[signature] then
    api.returns[signature] = api.returns[signature] + 1
  elseif api.signatures < MAX_SIGNATURES then
    api.signatures = api.signatures + 1
    api.returns[signature] = 1
  else
    api.otherReturns = api.otherReturns + 1
  end
  return unpack(result, 2, result.n)
end

local function NoteContext(tag, isOpen, at)
  if isOpen ~= nil then open[tag] = isOpen end
  seen[tag] = at
  -- A money change shortly before this event gets this tag too
  for i = #log.money, math.max(1, #log.money - 4), -1 do
    local entry = log.money[i]
    if at - entry.t <= MONEY_WINDOW then
      local present = false
      for _, existing in ipairs(entry.ctx) do present = present or existing == tag end
      if not present then
        entry.ctx[#entry.ctx + 1] = tag
        table.sort(entry.ctx)
      end
    end
  end
end

local function GUIDState(guid)
  if guid == nil then return "nil" end
  if Secret(guid) then return "secret" end
  return type(guid) == "string" and "readable" or type(guid)
end

local function ReadTarget()
  local guid = Call("UnitGUID(target)", "UnitGUID", "target")
  local dead = Call("UnitIsDead(target)", "UnitIsDead", "target")
  Call("UnitIsTapDenied(target)", "UnitIsTapDenied", "target")
  target.guid = ReadableString(guid) and guid or nil
  target.alive = nil
  if not Secret(dead) and dead ~= nil then target.alive = not dead end
end

local function RecordDeath(via)
  local guid = Call("UnitGUID(target)", "UnitGUID", "target")
  local kind, npc
  if ReadableString(guid) then
    kind, npc = ns.ProbeParseGUID(guid)
    lastKillGUID = guid
  end
  local death = {
    t = Now(), via = via, guid = GUIDState(guid), kind = kind, npc = npc,
    tapDenied = Plain(Call("UnitIsTapDenied(target)", "UnitIsTapDenied", "target")),
  }
  if ReadableString(guid) then
    death.canLoot = Signature(Pack(Call("CanLootUnit", "CanLootUnit", guid)), 1)
    if C_Timer and C_Timer.After then
      C_Timer.After(1.5, function()
        if running then death.canLootLater = Signature(Pack(Call("CanLootUnit", "CanLootUnit", guid)), 1) end
      end)
    end
  end
  Append(log.deaths, death, MAX_DEATHS, "deaths")
end

-- Records a death when the targeted unit's UnitIsDead flips from false to true
local function CheckTarget(via)
  local dead = Call("UnitIsDead(target)", "UnitIsDead", "target")
  if Secret(dead) or dead == nil then return end
  if dead and target.alive then RecordDeath(via) end
  target.alive = not dead
end

local function RecordLoot(via)
  local count = Call("GetNumLootItems", "GetNumLootItems")
  local entry = {
    t = Now(), via = via, n = Plain(count), slots = {},
    fishing = Plain(Call("IsFishingLoot", "IsFishingLoot")),
  }
  local targetGUID = Call("UnitGUID(target)", "UnitGUID", "target")
  local sources, distinct = {}, 0
  local slots = (type(count) == "number" and not Secret(count)) and math.min(count, MAX_SLOTS) or 0
  for slot = 1, slots do
    local link = Call("GetLootSlotLink", "GetLootSlotLink", slot)
    Call("GetLootSlotInfo", "GetLootSlotInfo", slot)
    local record = {
      type = Plain(Call("GetLootSlotType", "GetLootSlotType", slot)),
      item = ReadableString(link) and tonumber(string.match(link, "item:(%d+)")) or nil,
      sources = 0, kinds = {},
    }
    local found = Pack(Call("GetLootSourceInfo", "GetLootSourceInfo", slot))
    for i = 1, found.n, 2 do
      local guid = found[i]
      record.sources = record.sources + 1
      record.guids = GUIDState(guid)
      if ReadableString(guid) then
        if not sources[guid] then
          sources[guid] = true
          distinct = distinct + 1
        end
        local kind, id = ns.ProbeParseGUID(guid)
        record.kinds[#record.kinds + 1] = id and (kind .. ":" .. id) or kind or "?"
      end
    end
    entry.slots[slot] = record
  end
  entry.sourceCount = distinct
  if ReadableString(targetGUID) then entry.targetMatched = sources[targetGUID] == true end
  if lastKillGUID then entry.lastKillMatched = sources[lastKillGUID] == true end
  Append(log.loots, entry, MAX_LOOTS, "loots")
end

local function RecordMoney()
  local money = Call("GetMoney", "GetMoney")
  local at = Now()
  local entry = { t = at, ctx = ns.ProbeMoneyContext(at, open, seen, MONEY_WINDOW) }
  if Secret(money) then
    entry.delta = "secret"
  elseif type(money) == "number" then
    if lastMoney then entry.delta = money - lastMoney end
    lastMoney = money
  end
  Append(log.money, entry, MAX_MONEY, "money")
end

local function RecordSpell(unit, _, spellID)
  if unit ~= "player" then return end
  if Secret(spellID) then
    log.spellsSecret = log.spellsSecret + 1
  elseif type(spellID) == "number" then
    if log.spells[spellID] then
      log.spells[spellID] = log.spells[spellID] + 1
    else
      local count = 0
      for _ in pairs(log.spells) do count = count + 1 end
      if count < MAX_SPELLS then log.spells[spellID] = 1 else log.dropped.spells = (log.dropped.spells or 0) + 1 end
    end
  end
end

local HANDLERS = {
  PLAYER_TARGET_CHANGED = ReadTarget,
  UPDATE_MOUSEOVER_UNIT = function()
    Call("UnitGUID(mouseover)", "UnitGUID", "mouseover")
    Call("UnitIsDead(mouseover)", "UnitIsDead", "mouseover")
  end,
  UNIT_HEALTH = function(unit) if unit == "target" then CheckTarget("health") end end,
  UNIT_FLAGS = function(unit) if unit == "target" then CheckTarget("flags") end end,
  LOOT_READY = function() if not looting then looting = true RecordLoot("LOOT_READY") end end,
  LOOT_OPENED = function() if not looting then looting = true RecordLoot("LOOT_OPENED") end end,
  LOOT_CLOSED = function() looting = false end,
  PLAYER_MONEY = RecordMoney,
  UNIT_SPELLCAST_SUCCEEDED = RecordSpell,
  COMBAT_LOG_EVENT_UNFILTERED = function()
    if log.events.COMBAT_LOG_EVENT_UNFILTERED.count <= 20 then
      Call("CombatLogGetCurrentEventInfo", "CombatLogGetCurrentEventInfo")
    end
  end,
}

local function OnEvent(_, event, ...)
  local record = log.events[event]
  record.count = record.count + 1
  record.first = record.first or Now()
  if #record.samples < MAX_SAMPLES then record.samples[#record.samples + 1] = Signature(Pack(...), 1) end
  local context = CONTEXT[event]
  local handler = HANDLERS[event]
  local ok, err = pcall(function(...)
    if context then NoteContext(context[1], context[2], Now()) end
    if handler then handler(...) end
  end, ...)
  if not ok then
    record.handlerErrors = (record.handlerErrors or 0) + 1
    record.handlerErr = record.handlerErr or TrimError(err)
  end
end

local function OnUpdate(_, elapsed)
  target.poll = target.poll + elapsed
  target.party = target.party + elapsed
  if target.poll >= POLL_SECONDS then
    target.poll = 0
    CheckTarget("poll")
  end
  if target.party >= PARTY_SECONDS then
    target.party = 0
    Call("UnitGUID(party1)", "UnitGUID", "party1")
    Call("UnitIsDead(party1)", "UnitIsDead", "party1")
  end
end

-- One pass over every API at start, so missing ones show up even if their moment never comes
local function ProbeApis()
  for _, name in ipairs({ "issecretvalue", "canaccessvalue", "issecrettable", "hasanysecretvalues" }) do
    log.secretChecks[name] = type(_G[name]) == "function"
  end
  for _, unit in ipairs({ "target", "mouseover", "party1" }) do
    Call("UnitGUID(" .. unit .. ")", "UnitGUID", unit)
    Call("UnitIsDead(" .. unit .. ")", "UnitIsDead", unit)
  end
  Call("UnitIsTapDenied(target)", "UnitIsTapDenied", "target")
  Call("CombatLogGetCurrentEventInfo", "CombatLogGetCurrentEventInfo")
  -- Called only inside their moment: here just whether they exist
  for _, name in ipairs({ "CanLootUnit", "GetLootSourceInfo", "GetNumLootItems", "GetLootSlotInfo",
      "GetLootSlotLink", "GetLootSlotType", "IsFishingLoot" }) do
    Api(name, name)
  end
  Call("GetMoney", "GetMoney")
  Call("GetItemInfo", "GetItemInfo", SAMPLE_ITEM)
  Call("C_Item.GetItemInfo", "C_Item.GetItemInfo", SAMPLE_ITEM)
  Call("GetProfessions", "GetProfessions")
  Call("GetNumSkillLines", "GetNumSkillLines")
  Call("GetSkillLineInfo", "GetSkillLineInfo", 1)
end

local function RegisterEvents()
  for _, event in ipairs(EVENTS) do
    local record = { count = 0, samples = {} }
    log.events[event] = record
    local unit = UNIT_EVENTS[event]
    local ok, err
    if unit and frame.RegisterUnitEvent then
      ok, err = pcall(frame.RegisterUnitEvent, frame, event, unit)
      record.scope = unit
    else
      ok, err = pcall(frame.RegisterEvent, frame, event)
    end
    record.registered = ok
    if not ok then record.err = TrimError(err) end
  end
end

local function Start()
  log = {
    startedAt = time(), client = {},
    secretChecks = {}, apis = {}, events = {}, loots = {}, money = {}, deaths = {},
    spells = {}, spellsSecret = 0, dropped = {},
  }
  MarketWallDB.probe = log
  clockStart = GetTime()
  target, open, seen, lastMoney, lastKillGUID, looting = { poll = 0, party = 0 }, {}, {}, nil, nil, false
  frame = frame or CreateFrame("Frame")
  frame:SetScript("OnEvent", OnEvent)
  log.client.version, log.client.build = Call("GetBuildInfo", "GetBuildInfo")
  ProbeApis()
  RecordMoney()   -- the starting balance, so the first change has a delta
  ReadTarget()
  RegisterEvents()
  frame:SetScript("OnUpdate", OnUpdate)
  running = true
end

local function Stop()
  frame:UnregisterAllEvents()
  frame:SetScript("OnUpdate", nil)
  frame:SetScript("OnEvent", nil)
  log.stoppedAt = time()
  log.seconds = Now()
  running = false
end

local function SortedKeys(t, keep)
  local keys = {}
  for k, v in pairs(t) do
    if keep(v) then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

local function Status()
  local saved = MarketWallDB and MarketWallDB.probe
  if not saved then
    ns.Print("No probe data. /mw probe start begins a new run.")
    return
  end
  local seconds = running and Now() or saved.seconds or 0
  ns.Print(string.format("Probe %s, %d min recorded. %d loots, %d money changes, %d deaths.",
    running and "running" or "stopped", math.floor(seconds / 60), #saved.loots, #saved.money, #saved.deaths))
  local fired = {}
  for _, event in ipairs(SortedKeys(saved.events, function(e) return e.count > 0 end)) do
    fired[#fired + 1] = event .. " " .. saved.events[event].count
  end
  print("  Fired: " .. (#fired > 0 and table.concat(fired, ", ") or "none"))
  local silent = SortedKeys(saved.events, function(e) return e.registered and e.count == 0 end)
  print("  Never fired: " .. (#silent > 0 and table.concat(silent, ", ") or "none"))
  local refused = SortedKeys(saved.events, function(e) return not e.registered end)
  if #refused > 0 then print("  Could not register: " .. table.concat(refused, ", ")) end
  local missing = SortedKeys(saved.apis, function(a) return not a.exists end)
  print("  Missing APIs: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
  local secret = SortedKeys(saved.apis, function(a) return a.secret > 0 end)
  print("  Secret returns: " .. (#secret > 0 and table.concat(secret, ", ") or "none")
    .. (saved.secretChecks.issecretvalue and "" or " (issecretvalue is missing, so secrets go undetected)"))
  local failing = SortedKeys(saved.apis, function(a) return a.errors > 0 end)
  if #failing > 0 then print("  Erroring APIs: " .. table.concat(failing, ", ")) end
end

function ns.ProbeCommand(arg)
  arg = string.lower(arg or "")
  if arg == "start" then
    if running then Stop() end
    Start()
    ns.Print("Probe started. Play normally, then /mw probe stop and log out.")
  elseif arg == "stop" then
    if running then
      Stop()
      ns.Print("Probe stopped. Log out or /reload to save it.")
    else
      ns.Print("The probe is not running.")
    end
  else
    Status()
  end
end
