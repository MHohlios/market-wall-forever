-- MarketWall: records kills and what they dropped into the recording core (Record.lua).
-- Forever never fires the combat log for add-ons (registering it even raises a "blocked" popup),
-- so kills come from PARTY_KILL and loot windows, and each loot slot is credited to its corpse
-- through GetLootSourceInfo.
--
-- How a kill settles, in Kills.Classify:
--   looted   you opened its loot: its items and full coin are recorded ("loot")
--   0c       you opened its loot and it was empty ("loot"), or CanLootUnit, asked once about a
--            second after the kill, said it had no loot ("canloot")
--   unseen   CanLootUnit said the loot was not yours, or yours but never opened in WINDOW ("canloot");
--            or CanLootUnit gave no answer and you never opened it in WINDOW (the PRD default, "window")
-- The rule that settled each kill is on the kill event as `via`, and counted in Kills.paths.
local _, ns = ...

local Kills = {}
ns.Kills = Kills

Kills.LOOTED, Kills.EMPTY, Kills.UNSEEN = 1, 2, 3

local WINDOW = 90          -- seconds a kill waits for you to loot it
local CHECK_DELAY = 1      -- seconds after a kill before CanLootUnit is asked, so the loot exists
local CAST_WINDOW = 3      -- seconds after a gathering or Pick Pocket cast in which a loot window is its own
local PICK_POCKET = 921
local FORGET_AFTER = 1800  -- seconds a corpse is remembered for dedupe and repeat loot windows
local MONEY_SLOT = 2       -- LOOT_SLOT_MONEY

-- Skinning, Herb Gathering and Mining, every classic rank, and the skill each belongs to
local GATHER_SPELLS = {
  [8613] = "skinning", [8617] = "skinning", [8618] = "skinning", [10768] = "skinning",
  [2366] = "herbalism", [2368] = "herbalism", [3570] = "herbalism", [11993] = "herbalism",
  [2575] = "mining", [2576] = "mining", [3564] = "mining", [10248] = "mining",
}

-- "npc" or "object" and its ID; nil for players, pets and anything unreadable
function Kills.ParseGUID(guid)
  if type(guid) ~= "string" then return nil end
  local kind = string.match(guid, "^(%a+)%-")
  local id = tonumber(string.match(guid, "^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
  if not id then return nil end
  if kind == "Creature" or kind == "Vehicle" then return "npc", id end
  if kind == "GameObject" then return "object", id end
end

-- Loot that came out of an item: a disenchant (DisenchantLog.lua's) or an opened container
function Kills.IsItemSource(guid)
  return type(guid) == "string" and string.find(guid, "^Item%-") ~= nil
end

local function SourceOf(kind, id)
  return kind and (kind .. ":" .. id) or "unknown"
end

local COPPER_PER = { g = 10000, s = 100, c = 1 }

-- Copper in a coin slot. The text may read "1 Gold\n5 Silver\n3 Copper", "1g 5s", or use coin
-- icons; quantity is used when the text has no amount.
function Kills.ParseCoin(text, quantity)
  if type(text) == "string" then
    text = text:gsub("|T[^|]*[Gg]old[^|]*|t", "g"):gsub("|T[^|]*[Ss]ilver[^|]*|t", "s")
      :gsub("|T[^|]*[Cc]opper[^|]*|t", "c"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
      :gsub("(%d),(%d)", "%1%2")
    local total, found = 0, false
    for amount, unit in text:gmatch("(%d+)%s*(%a)") do
      local per = COPPER_PER[unit:lower()]
      if per then
        total = total + tonumber(amount) * per
        found = true
      end
    end
    if found then return total end
  end
  if type(quantity) == "number" and quantity > 0 then return quantity end
  return 0
end

local function IsCoin(slot)
  return slot.type == MONEY_SLOT or (slot.type == nil and not slot.link and Kills.ParseCoin(slot.text) > 0)
end

-- { {guid, quantity}, ... } from GetLootSourceInfo's flat guid, quantity, guid, quantity list,
-- packed with its length in n because a quantity can be nil
local function Sources(flat)
  local out = {}
  for i = 1, flat.n or #flat, 2 do
    if type(flat[i]) == "string" then out[#out + 1] = { flat[i], tonumber(flat[i + 1]) } end
  end
  return out
end

-- Each source's part of a slot: one source takes the whole slot, several take their own
-- quantities, and an amount with no per-source quantities is split evenly
local function Shares(total, sources)
  if #sources == 0 then return {} end   -- no readable source: the slot cannot be credited
  if #sources == 1 then return { total } end
  local sum, out = 0, {}
  for i, source in ipairs(sources) do
    out[i] = source[2] or 0
    sum = sum + out[i]
  end
  if sum > 0 then return out end
  local each = math.floor(total / #sources)
  for i = 1, #sources do out[i] = each end
  out[1] = out[1] + total - each * #sources
  return out
end

local function Add(share, slot, amount)
  if amount <= 0 then return end
  if IsCoin(slot) then
    share.coin = share.coin + amount
  else
    local id = ns.ItemID(slot.link)
    if id then share.drops[id] = (share.drops[id] or 0) + amount end
  end
end

-- What each corpse in a loot window gave: { [guid] = { coin =, drops = { [itemID] = qty } } }.
-- slots: { type =, link =, text =, quantity =, sources = { guid, qty, guid, qty, ... } }
function Kills.SplitLoot(slots)
  local byGuid = {}
  for _, slot in ipairs(slots) do
    local sources = Sources(slot.sources or {})
    local single = #sources == 1 and sources[1][2]
    local quantity = (single and single > 0) and single or slot.quantity
    local total
    if IsCoin(slot) then
      total = Kills.ParseCoin(slot.text, quantity)
    else
      total = quantity or 1
    end
    for i, amount in ipairs(Shares(total, sources)) do
      local guid = sources[i][1]
      byGuid[guid] = byGuid[guid] or { coin = 0, drops = {} }
      Add(byGuid[guid], slot, amount)
    end
  end
  return byGuid
end

-- Everything in a window regardless of source, for fishing
function Kills.TotalLoot(slots)
  local total = { coin = 0, drops = {} }
  for _, slot in ipairs(slots) do
    local amount = IsCoin(slot) and Kills.ParseCoin(slot.text, slot.quantity) or (slot.quantity or 1)
    Add(total, slot, amount)
  end
  return total
end

-- A pending kill's outcome and the rule that decided it, or nil while it can still be looted.
-- kill.check is CanLootUnit's first answer: "empty", "theirs", "mine", or false for no answer.
function Kills.Classify(kill, now, window)
  if kill.looted then return Kills.LOOTED, "loot" end
  if now - kill.t < window then return nil end
  if kill.check == "empty" then return Kills.EMPTY, "canloot" end
  if kill.check then return Kills.UNSEEN, "canloot" end
  return Kills.UNSEEN, "window"
end

local function Merge(into, drops)
  for id, qty in pairs(drops) do into[id] = (into[id] or 0) + qty end
  return into
end

-- The tracker's state lives in memory only; settled kills reach saved data through Mobs.lua.
-- emit: Recording.Emit. canLoot(guid): "empty", "theirs", "mine" or nil. itemOf(guid): the item ID
-- of an opened container's "Item-..." GUID, or nil when it cannot be known. nameOf(npcID): the
-- creature's name (Creatures.lua), or nil.
function Kills.NewTracker(emit, canLoot, itemOf, nameOf)
  local tracker = {
    pending = {},   -- [guid] = { guid, npc, t, looted, check, coin, drops, gather }
    corpses = {},   -- [guid] = { t =, loot = nil, "partial", "emptied" or "gathered" }
    window = {},    -- corpse guids in the open loot window
    items = {},     -- [item guid] = { t = } for item loot open now or closed with loot left
    itemWindow = {},   -- item guids in the open loot window
    windowID = 0,   -- counts loot windows; loot and fish events carry their window's as `window`
    paths = { loot = 0, canloot = 0, window = 0 },
    lastGather = nil,
  }

  local function NameOf(npc)
    return nameOf and nameOf(npc)
  end

  local function Settle(kill, outcome, via)
    tracker.pending[kill.guid] = nil
    tracker.paths[via] = tracker.paths[via] + 1
    emit({ t = kill.t, kind = "kill", source = SourceOf("npc", kill.npc), guid = kill.guid, npc = kill.npc,
      name = NameOf(kill.npc), outcome = outcome, via = via,
      coin = outcome == Kills.LOOTED and kill.coin or nil, drops = outcome == Kills.LOOTED and kill.drops or nil,
      gather = kill.gather })
  end

  -- Starts tracking a creature's death; each GUID counts once. Returns the pending kill.
  function tracker:Kill(guid, t)
    local kind, npc = Kills.ParseGUID(guid)
    if kind ~= "npc" or self.corpses[guid] then return nil end
    self.corpses[guid] = { t = t }
    local kill = { guid = guid, npc = npc, t = t }
    self.pending[guid] = kill
    return kill
  end

  function tracker:Cast(spellID, t)
    if GATHER_SPELLS[spellID] then self.lastGather, self.gatherSkill = t, GATHER_SPELLS[spellID] end
    if spellID == PICK_POCKET then self.lastPickPocket = t end
  end

  local function Within(castAt, t)
    return castAt and t - castAt <= CAST_WINDOW
  end

  -- Each gather cast is recorded once, so mining a vein twice records both; reopening a gather
  -- window without a new cast adds nothing. skill is nil for a corpse emptied and opened again.
  local function Gather(guid, kind, id, share, t, skill)
    local corpse = tracker.corpses[guid] or { t = t }
    corpse.loot = "gathered"
    tracker.corpses[guid] = corpse
    local kill = tracker.pending[guid]
    if kill then kill.gather = Merge(kill.gather or {}, share.drops) end
    emit({ t = t, kind = "gather", source = SourceOf(kind, id), guid = guid, npc = kind == "npc" and id or nil,
      skill = skill or (kind == "npc" and "skinning" or nil), drops = share.drops })
  end

  -- Whether any source in a window died: a kill was seen for it
  function tracker:FromCorpse(shares)
    for guid in pairs(shares) do
      if self.corpses[guid] then return true end
    end
    return false
  end

  -- A loot window opened. slots as in SplitLoot; target is your target's GUID, which names the
  -- corpse of a window with nothing in it. disenchanting: DisenchantLog.lua took it as a disenchant.
  function tracker:Loot(slots, fishing, t, target, disenchanting)
    self.window, self.itemWindow = {}, {}
    self.windowID = self.windowID + 1
    local window = self.windowID
    emit({ t = t, kind = "window", window = window })   -- even one that records nothing
    -- a cast explains only the first window after it
    local gathering, pickPocket = Within(self.lastGather, t), Within(self.lastPickPocket, t)
    local skill = gathering and self.gatherSkill or nil
    self.lastGather, self.lastPickPocket = nil, nil
    if fishing then
      local total = Kills.TotalLoot(slots)
      emit({ t = t, kind = "fish", source = "fishing", window = window, coin = total.coin, drops = total.drops })
      return
    end
    local opened = target and self.pending[target]
    if #slots == 0 and opened then   -- slots without readable sources leave the kill pending
      self.corpses[target].loot = "emptied"
      Settle(opened, Kills.EMPTY, "loot")
      return
    end
    local shares = Kills.SplitLoot(slots)
    local container, containerGuids = nil, {}
    for guid, share in pairs(shares) do
      if Kills.IsItemSource(guid) then   -- never a mob's loot
        shares[guid] = nil
        -- an item reopened with loot left is neither new loot nor a new disenchant
        self.itemWindow[#self.itemWindow + 1] = guid
        if not self.items[guid] then
          self.items[guid] = { t = t }
          if not disenchanting then
            container = container or { coin = 0, drops = {} }
            container.coin = container.coin + share.coin
            Merge(container.drops, share.drops)
            containerGuids[#containerGuids + 1] = guid
          end
        end
      end
    end
    -- a container opened from your bags; disenchant materials belong to DisenchantLog.lua. Its
    -- item ID is named only when the window holds one container's loot.
    if container then
      local id = #containerGuids == 1 and itemOf and itemOf(containerGuids[1]) or nil
      emit({ t = t, kind = "loot", source = "item", container = id, window = window, coin = container.coin,
        drops = container.drops })
    end
    if pickPocket and not self:FromCorpse(shares) then
      return   -- a living mob's pockets, not its drops
    end
    for guid, share in pairs(shares) do
      local kind, id = Kills.ParseGUID(guid)
      local state = self.corpses[guid] and self.corpses[guid].loot
      if gathering or state == "emptied" then
        Gather(guid, kind, id, share, t, skill)
      elseif not state then   -- a corpse reopened with items left is not new loot
        self.window[#self.window + 1] = guid
        local kill = self.pending[guid] or self:Kill(guid, t)
        local corpse = self.corpses[guid] or { t = t }
        corpse.loot = "partial"
        self.corpses[guid] = corpse
        local npc = kind == "npc" and id or nil
        emit({ t = t, kind = "loot", source = SourceOf(kind, id), window = window, guid = guid, npc = npc,
          name = npc and NameOf(npc), coin = share.coin, drops = share.drops })
        if kill then
          kill.looted, kill.coin, kill.drops = true, share.coin, share.drops
          Settle(kill, Kills.LOOTED, "loot")
        end
      end
    end
  end

  -- The loot window closed; emptied says every slot was taken
  function tracker:Closed(emptied, t)
    emit({ t = t, kind = "window", window = self.windowID, closed = true })
    if emptied then
      for _, guid in ipairs(self.window) do self.corpses[guid].loot = "emptied" end
      -- the next container opened from the same stack shares its GUID, and is new loot
      for _, guid in ipairs(self.itemWindow) do self.items[guid] = nil end
    end
    self.window, self.itemWindow = {}, {}
  end

  -- Called about once a second: asks CanLootUnit once per kill, settles kills whose window has
  -- passed and forgets old corpses. force settles every pending kill, as on logout.
  function tracker:Tick(now, force)
    for guid, kill in pairs(self.pending) do
      if kill.check == nil and now - kill.t >= CHECK_DELAY then kill.check = canLoot(guid) or false end
      local outcome, via = Kills.Classify(kill, now, force and -math.huge or WINDOW)
      if outcome then Settle(kill, outcome, via) end
    end
    for guid, corpse in pairs(self.corpses) do
      if now - corpse.t > FORGET_AFTER and not self.pending[guid] then self.corpses[guid] = nil end
    end
    for guid, item in pairs(self.items) do
      if now - item.t > FORGET_AFTER then self.items[guid] = nil end
    end
  end

  return tracker
end

-- Names the item ID of an opened container from its "Item-..." GUID. The game's answer for the
-- GUID comes first; failing that, the bag item you used just before, only when its GUID matches.
-- A use whose GUID could not be read names nothing, and a use names one container at most.
-- itemIDByGUID(guid): the game's item ID for a GUID, nil when unknown.
function Kills.NewContainerResolver(itemIDByGUID)
  local resolver = {}
  local lastUsed   -- { id =, guid = }

  -- You used a bag item: its item ID and GUID, each nil when unreadable
  function resolver.Used(id, guid)
    lastUsed = id and guid and { id = id, guid = guid } or nil
  end

  function resolver.ItemOf(guid)
    local used = lastUsed
    lastUsed = nil
    return itemIDByGUID(guid) or (used and used.guid == guid and used.id) or nil
  end

  return resolver
end

-- In game -----------------------------------------------------------------------------------

local Readable = ns.Readable

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function ReadCanLoot(guid)
  if not CanLootUnit then return nil end
  local ok, hasLoot, canLoot = pcall(CanLootUnit, guid)
  hasLoot, canLoot = Readable(hasLoot), Readable(canLoot)
  if not ok or type(hasLoot) ~= "boolean" then return nil end
  if not hasLoot then return "empty" end
  return canLoot == true and "mine" or "theirs"
end

local function ReadLootWindow()
  local slots = {}
  for slot = 1, (Readable(GetNumLootItems()) or 0) do
    local _, text, quantity = GetLootSlotInfo(slot)
    local sources = Pack(GetLootSourceInfo(slot))
    for i = 1, sources.n do sources[i] = Readable(sources[i]) end
    slots[slot] = { type = Readable(GetLootSlotType(slot)), link = Readable(GetLootSlotLink(slot)),
      text = Readable(text), quantity = Readable(quantity), sources = sources }
  end
  return slots
end

local function ReadItemIDByGUID(guid)
  if not (C_Item and C_Item.GetItemIDByGUID) then return nil end
  local ok, id = pcall(C_Item.GetItemIDByGUID, guid)
  id = ok and Readable(id)
  return type(id) == "number" and id or nil
end

local function ReadBagItemGUID(bag, slot)
  if not (C_Item and C_Item.GetItemGUID and ItemLocation and ItemLocation.CreateFromBagAndSlot) then return nil end
  local ok, guid = pcall(C_Item.GetItemGUID, ItemLocation:CreateFromBagAndSlot(bag, slot))
  guid = ok and Readable(guid)
  return type(guid) == "string" and guid or nil
end

local resolver = Kills.NewContainerResolver(ReadItemIDByGUID)

if C_Container and C_Container.UseContainerItem and hooksecurefunc then
  hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    resolver.Used(info and info.itemID, ReadBagItemGUID(bag, slot))
  end)
end

local tracker = Kills.NewTracker(function(event) ns.Recording.Emit(event) end, ReadCanLoot, resolver.ItemOf,
  function(npc) return ns.Creatures.Name(npc) end)
Kills.tracker = tracker
Kills.paths = tracker.paths   -- /dump MarketWall.Kills.paths shows which rule settled each kill

local looting, slotCount, cleared = false, 0, {}

local HANDLERS = {
  PARTY_KILL = function(_, victim) tracker:Kill(Readable(victim), time()) end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit == "player" then tracker:Cast(Readable(spellID), time()) end
  end,
  LOOT_READY = function()
    if looting then return end   -- LOOT_READY and LOOT_OPENED both fire for one window
    looting = true
    local slots = ReadLootWindow()
    slotCount, cleared = #slots, {}
    local disenchant = ns.DisenchantLog and ns.DisenchantLog.tracker:Loot(slots, time())
    tracker:Loot(slots, Readable(IsFishingLoot()) == true, time(), Readable(UnitGUID("target")), disenchant == true)
  end,
  LOOT_SLOT_CLEARED = function(slot) cleared[slot] = true end,
  LOOT_CLOSED = function()
    if not looting then return end
    looting = false
    local taken = 0
    for _ in pairs(cleared) do taken = taken + 1 end
    tracker:Closed(taken >= slotCount, time())
  end,
  PLAYER_LOGOUT = function() tracker:Tick(time(), true) end,
}
HANDLERS.LOOT_OPENED = HANDLERS.LOOT_READY

local frame = CreateFrame("Frame")
for event in pairs(HANDLERS) do
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    frame:RegisterUnitEvent(event, "player")
  else
    frame:RegisterEvent(event)
  end
end
frame:SetScript("OnEvent", function(_, event, ...) HANDLERS[event](...) end)

function Kills.Start()
  if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function() tracker:Tick(time()) end)
  end
end
