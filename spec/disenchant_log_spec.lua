local addon = require("spec.helpers.addon")

local ITEM_SLOT = 1
local ARMOR, UNCOMMON = 4, 2
local STRANGE_DUST, SOUL_DUST, VISION_DUST = 10940, 11083, 11137
local BRACERS = 1001
local LOW_CRAFT = 250620   -- one of Forever's crafts with its own estimate
local BRACERS_ITEM = { id = BRACERS, quality = UNCOMMON, level = 28, classID = ARMOR }
local ITEM_GUID = "Item-5827-0-400000000ABCDEF"
local WOLF_GUID = "Creature-0-5250-0-12-1234-1"

local function Slot(itemID, quantity, guid)
  return { type = ITEM_SLOT, link = "|Hitem:" .. itemID .. "::::|h[x]|h", quantity = quantity,
    sources = { n = 2, guid, quantity } }
end

describe("DisenchantLog", function()
  local ns, Fire, Log

  before_each(function()
    ns, Fire = addon.Load()
    Log = ns.DisenchantLog
    Fire("ADDON_LOADED", addon.ADDON)
  end)

  after_each(function()
    _G.DisenchantryDB, _G.MarketWallDB = nil, nil
  end)

  describe("pairing a cast with its loot", function()
    local events, tracker

    before_each(function()
      events = {}
      tracker = Log.NewTracker(function(e) events[#events + 1] = e end)
    end)

    it("records the next Item-source window after a Disenchant cast", function()
      tracker:Started(BRACERS_ITEM, true)
      tracker:Succeeded(100)
      tracker:Loot({ Slot(SOUL_DUST, 2, ITEM_GUID), Slot(SOUL_DUST, 1, ITEM_GUID) }, 101)
      assert.equal(1, #events)
      assert.same({ t = 101, kind = "disenchant", source = "item:" .. BRACERS, item = BRACERS, quality = UNCOMMON,
        level = 28, classID = ARMOR, salvager = true, materials = { [SOUL_DUST] = 3 } }, events[1])
    end)

    it("explains only the first window after the cast", function()
      tracker:Started(BRACERS_ITEM, false)
      tracker:Succeeded(100)
      tracker:Loot({ Slot(SOUL_DUST, 1, WOLF_GUID) }, 101)   -- a corpse, not the disenchant
      tracker:Loot({ Slot(SOUL_DUST, 1, ITEM_GUID) }, 102)
      assert.same({}, events)
    end)

    it("ignores a window long after the cast, and casts that failed", function()
      tracker:Started(BRACERS_ITEM, false)
      tracker:Succeeded(100)
      tracker:Loot({ Slot(SOUL_DUST, 1, ITEM_GUID) }, 110)
      tracker:Started(BRACERS_ITEM, false)
      tracker:Stopped()
      tracker:Succeeded(200)
      tracker:Loot({ Slot(SOUL_DUST, 1, ITEM_GUID) }, 201)
      assert.same({}, events)
    end)

    it("takes the item from the cast's end when its start named none", function()
      tracker:Started(nil, false)
      tracker:Succeeded(100, BRACERS_ITEM, false)
      tracker:Loot({ Slot(VISION_DUST, 1, ITEM_GUID) }, 101)
      assert.equal(BRACERS, events[1].item)
    end)
  end)

  describe("in game", function()
    local window

    before_each(function()
      window = {}
      _G.GetNumLootItems = function() return #window end
      _G.GetLootSlotInfo = function(i) return nil, "x", window[i].quantity end
      _G.GetLootSourceInfo = function(i) return window[i].guid, window[i].quantity end
      _G.GetLootSlotType = function() return ITEM_SLOT end
      _G.GetLootSlotLink = function(i) return "|Hitem:" .. window[i].id .. "::::|h[x]|h" end
      _G.IsFishingLoot = function() return false end
      _G.UnitGUID = function() return nil end
    end)

    after_each(function()
      _G.GetNumLootItems, _G.GetLootSlotInfo, _G.GetLootSourceInfo, _G.GetLootSlotType = nil, nil, nil, nil
      _G.GetLootSlotLink, _G.IsFishingLoot, _G.UnitGUID = nil, nil, nil
    end)

    it("saves a disenchant as a sample and never as mob loot", function()
      local kinds = {}
      ns.Recording.On("loot", function() kinds[#kinds + 1] = "loot" end)
      ns.Recording.On("kill", function() kinds[#kinds + 1] = "kill" end)
      Log.tracker:Started(BRACERS_ITEM, false)
      Log.tracker:Succeeded(time())
      window = { { id = SOUL_DUST, quantity = 2, guid = ITEM_GUID } }
      Fire("LOOT_READY")
      Fire("LOOT_CLOSED")
      ns.Kills.tracker:Tick(time(), true)
      assert.same({}, kinds)
      assert.same({}, MarketWallDB.mobs)
      local sample = Log.Sample(BRACERS, UNCOMMON, 28, ARMOR, false)
      assert.same({ count = 1, materials = { [SOUL_DUST] = { hits = 1, total = 2 } } }, sample)
    end)

    it("records under the salvagerMode setting, where the odds look it up", function()
      MarketWallDB.cfg.salvagerMode = "on"   -- the buff is not detected
      _G.C_Container = {
        GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end,
        GetContainerItemInfo = function(_, slot) return { itemID = slot == 1 and BRACERS or 2589, isLocked = slot == 1 } end,
      }
      _G.C_Item = { GetItemInfo = function() return "x", "x", UNCOMMON, 28, 1, "", "", 1, "", 0, 0, ARMOR end }
      Fire("UNIT_SPELLCAST_START", "player", "cast", 13262)
      Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 13262)
      window = { { id = SOUL_DUST, quantity = 1, guid = ITEM_GUID } }
      Fire("LOOT_READY")
      _G.C_Container, _G.C_Item = nil, nil
      assert.equal(1, Log.Sample(BRACERS, UNCOMMON, 28, ARMOR, true).count)
      assert.is_nil(Log.Sample(BRACERS, UNCOMMON, 28, ARMOR, false))
    end)
  end)

  describe("Kills tracker", function()
    it("gives Item-source windows to no mob, even without a disenchant cast", function()
      local events = {}
      local tracker = ns.Kills.NewTracker(function(e) events[#events + 1] = e end, function() end)
      tracker:Loot({ Slot(SOUL_DUST, 2, ITEM_GUID) }, false, 100, nil)
      tracker:Tick(1000, true)
      for _, e in ipairs(events) do
        assert.is_nil(e.npc)
        assert.is_true(e.kind == "window" or e.source == "item")   -- an opened container at most
      end
    end)
  end)

  describe("samples", function()
    it("pools classic items by kind, with item levels in fives", function()
      assert.equal("2:26-30:4:normal", Log.SampleKey(BRACERS, 2, 26, 4, false))
      assert.equal("2:26-30:4:normal", Log.SampleKey(1002, 2, 30, 4, false))
      assert.equal("3:31-35:2:salvager", Log.SampleKey(1003, 3, 31, 2, true))
    end)

    it("keeps items with a Forever estimate to themselves", function()
      assert.equal("item:" .. LOW_CRAFT .. ":normal", Log.SampleKey(LOW_CRAFT, UNCOMMON, 10, ARMOR, false))
      assert.equal("item:200001:salvager", Log.SampleKey(200001, 3, 30, ARMOR, true))
      assert.equal("2:26-30:4:normal", Log.SampleKey(200002, UNCOMMON, 28, ARMOR, false))   -- a new green: classic
    end)

    it("counts a material's hits and total quantity", function()
      local event = { kind = "disenchant", item = BRACERS, quality = UNCOMMON, level = 28, classID = ARMOR, salvager = false }
      event.materials = { [SOUL_DUST] = 2 }
      ns.Recording.Emit(event)
      event.materials = { [SOUL_DUST] = 1, [VISION_DUST] = 1 }
      ns.Recording.Emit(event)
      assert.same({ count = 2, materials = { [SOUL_DUST] = { hits = 2, total = 3 }, [VISION_DUST] = { hits = 1, total = 1 } } },
        Log.Sample(BRACERS, UNCOMMON, 28, ARMOR, false))
    end)
  end)

  describe("importing Disenchantry", function()
    local printed

    before_each(function()
      printed = {}
      ns.Print = function(text) printed[#printed + 1] = text end
    end)

    local function Disenchantry(count, hits, total)
      _G.DisenchantryDB = {
        salvagerMode = "on", salvagerBonusPercent = 25,
        disenchantSamples = {
          ["1.15.8:12345:" .. BRACERS .. ":2:28:4:normal"] = {
            count = count, materials = { [SOUL_DUST] = { hits = hits, total = total, min = 1, max = 2 } } },
          ["1.15.8:12345:" .. LOW_CRAFT .. ":2:10:4:normal"] = {
            count = 4, materials = { [STRANGE_DUST] = { hits = 4, total = 10, min = 2, max = 3 } } },
        },
      }
    end

    local function Imported()
      return Log.Sample(BRACERS, UNCOMMON, 28, ARMOR, false)
    end

    it("copies the log and Salvager setting on the first login, and says so", function()
      Disenchantry(30, 30, 45)
      Log.Start()
      assert.same({ count = 30, materials = { [SOUL_DUST] = { hits = 30, total = 45 } } }, Imported())
      assert.same({ count = 4, materials = { [STRANGE_DUST] = { hits = 4, total = 10 } } },
        MarketWallDB.disenchants.samples["item:" .. LOW_CRAFT .. ":normal"])
      assert.is_nil(MarketWallDB.disenchants.samples["2:6-10:4:normal"])
      assert.equal("on", ns.Cfg("salvagerMode"))
      assert.equal(25, ns.Cfg("salvagerBonus"))
      assert.same({ "Imported 34 disenchant results from Disenchantry." }, printed)
    end)

    it("imports nothing on later logins, and keeps MarketWall's own Salvager setting", function()
      Disenchantry(30, 30, 45)
      Log.Start()
      MarketWallDB.cfg.salvagerMode = "off"
      Disenchantry(33, 33, 50)   -- MarketWall recorded these itself
      Log.Start()
      assert.equal(30, Imported().count)
      assert.equal("off", ns.Cfg("salvagerMode"))
      assert.equal(1, #printed)
    end)

    it("does nothing without Disenchantry", function()
      Log.Start()
      assert.is_nil(Imported())
      assert.is_nil(MarketWallDB.disenchants.imported)
      assert.equal("auto", ns.Cfg("salvagerMode"))
      assert.same({}, printed)
    end)
  end)
end)
