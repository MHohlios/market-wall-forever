local addon = require("spec.helpers.addon")

local CREATURE = "Creature-0-5250-0-12-1525-0000ABCDEF"
local OTHER_CREATURE = "Creature-0-5250-0-12-1526-0000ABCDF0"
local PLAYER = "Player-5250-0ABC1234"
local NODE = "GameObject-0-5250-0-12-1731-0000ABCDEF"

describe("probe", function()
  local ns

  before_each(function() ns = addon.Load() end)

  describe("ProbeParseGUID", function()
    it("keeps the ID of creatures and objects", function()
      assert.same({ "Creature", 1525 }, { ns.ProbeParseGUID(CREATURE) })
      assert.same({ "GameObject", 1731 }, { ns.ProbeParseGUID(NODE) })
    end)

    it("reduces players to their kind", function()
      assert.same({ "Player" }, { ns.ProbeParseGUID(PLAYER) })
    end)

    it("is nil for anything that is not a GUID string", function()
      assert.is_nil(ns.ProbeParseGUID(nil))
      assert.is_nil(ns.ProbeParseGUID(42))
    end)
  end)

  describe("ProbeMoneyContext", function()
    it("lists open windows and events within the window, sorted", function()
      local open = { taxi = false, merchant = true }
      local seen = { quest = 9, loot = 11.5, mail = 7.9 }
      assert.same({ "loot", "merchant", "quest" }, ns.ProbeMoneyContext(10, open, seen, 2))
    end)

    it("is empty when nothing is open or recent", function()
      assert.same({}, ns.ProbeMoneyContext(10, { trade = false }, { quest = 1 }, 2))
    end)
  end)

  describe("a run", function()
    local fire, clock, money, globals

    local function Stub(name, value)
      globals[#globals + 1] = name
      _G[name] = value
    end

    before_each(function()
      ns, fire = addon.Load()
      fire("ADDON_LOADED", addon.ADDON)
      ns.Print = function() end
      clock, money, globals = 100, 5000, {}
      Stub("GetTime", function() return clock end)
      Stub("GetMoney", function() return money end)
      Stub("UnitGUID", function(unit) if unit == "target" then return CREATURE end end)
      Stub("UnitIsDead", function() return false end)
    end)

    after_each(function()
      for _, name in ipairs(globals) do _G[name] = nil end
    end)

    local function ChangeMoney(amount)
      money = money + amount
      fire("PLAYER_MONEY")
    end

    it("records nothing until started", function()
      ChangeMoney(10)
      assert.is_nil(MarketWallDB.probe)
    end)

    it("attributes a money change to the open window", function()
      ns.ProbeCommand("start")
      fire("MERCHANT_SHOW")
      clock = 105
      ChangeMoney(-250)
      assert.same({ t = 5, delta = -250, ctx = { "merchant" } }, MarketWallDB.probe.money[2])
    end)

    it("adds an event that follows the money change within two seconds", function()
      ns.ProbeCommand("start")
      clock = 110
      ChangeMoney(800)
      clock = 111.5
      fire("QUEST_TURNED_IN", 123, 0, 800)
      clock = 113
      fire("CHAT_MSG_SYSTEM", "text")
      assert.same({ "quest" }, MarketWallDB.probe.money[2].ctx)
    end)

    it("counts events and keeps only argument types", function()
      ns.ProbeCommand("start")
      fire("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].", "", "", "", "Someone")
      local record = MarketWallDB.probe.events.CHAT_MSG_LOOT
      assert.equal(1, record.count)
      assert.same({ "string,string,string,string,string" }, record.samples)
    end)

    it("summarises an area loot without saving any GUID", function()
      Stub("GetNumLootItems", function() return 2 end)
      Stub("IsFishingLoot", function() return false end)
      Stub("GetLootSlotType", function() return 1 end)
      Stub("GetLootSlotLink", function() return "|Hitem:2589::|h[Linen Cloth]|h" end)
      Stub("GetLootSlotInfo", function() return 0, "Linen Cloth", 1 end)   -- read by the kill tracker
      Stub("GetLootSourceInfo", function(slot)
        if slot == 1 then return CREATURE, 1, OTHER_CREATURE, 1 end
        return PLAYER, 1
      end)
      ns.ProbeCommand("start")
      fire("LOOT_READY")
      fire("LOOT_OPENED")

      local loots = MarketWallDB.probe.loots
      assert.equal(1, #loots)
      assert.equal(3, loots[1].sourceCount)
      assert.is_true(loots[1].targetMatched)
      assert.same({ "Creature:1525", "Creature:1526" }, loots[1].slots[1].kinds)
      assert.same({ "Player" }, loots[1].slots[2].kinds)
      assert.equal(2589, loots[1].slots[1].item)

      local function NoGUIDs(value)
        if type(value) == "table" then
          for k, v in pairs(value) do NoGUIDs(k) NoGUIDs(v) end
        elseif type(value) == "string" then
          assert.is_nil(value:find("%a+%-%d+%-"), "a GUID was saved: " .. value)
        end
      end
      NoGUIDs(MarketWallDB.probe)
    end)

    it("records a targeted unit's death with its creature ID", function()
      ns.ProbeCommand("start")
      _G.UnitIsDead = function() return true end
      fire("UNIT_FLAGS", "target")
      local death = MarketWallDB.probe.deaths[1]
      assert.same({ "flags", "readable", "Creature", 1525 }, { death.via, death.guid, death.kind, death.npc })
    end)

    it("marks secret values and stores none of them", function()
      local secret = {}
      Stub("issecretvalue", function(v) return v == secret end)
      ns.ProbeCommand("start")
      money = secret
      fire("PLAYER_MONEY")
      assert.equal("secret", MarketWallDB.probe.money[2].delta)
      assert.equal(1, MarketWallDB.probe.apis.GetMoney.returns["table*"])
    end)

    it("detects a secret value after many plain ones", function()
      local secret = {}
      Stub("issecretvalue", function(v) return v == secret end)
      Stub("GetItemInfo", function() return 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, secret end)
      ns.ProbeCommand("start")
      local api = MarketWallDB.probe.apis.GetItemInfo
      assert.equal(1, api.secret)
      assert.equal(string.rep("number,", 12) .. "table*", next(api.returns))
    end)

    it("records an API that errors and one that is missing", function()
      Stub("GetProfessions", function() error("blocked") end)
      ns.ProbeCommand("start")
      local apis = MarketWallDB.probe.apis
      assert.equal(1, apis.GetProfessions.errors)
      assert.is_false(apis.CanLootUnit.exists)
    end)
  end)
end)
