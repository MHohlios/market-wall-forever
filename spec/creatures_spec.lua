local addon = require("spec.helpers.addon")

local WOLF, BOAR = 1234, 5678

local function Guid(npc, spawn)
  return "Creature-0-5250-0-12-" .. npc .. "-" .. (spawn or 1)
end

describe("Creatures", function()
  local ns, C, fire, units

  -- Loads the addon over saved, as a login or /reload does
  local function Login(saved)
    ns, fire = addon.Load()
    _G.MarketWallDB = saved
    fire("ADDON_LOADED", addon.ADDON)
    C = ns.Creatures
  end

  before_each(function()
    units = {}   -- [unit] = { guid, name, family } the stubbed unit API answers with
    _G.UnitGUID = function(unit) return units[unit] and units[unit][1] end
    _G.UnitName = function(unit) return units[unit] and units[unit][2] end
    _G.UnitCreatureFamily = function(unit) return units[unit] and units[unit][3] end
    Login(nil)
  end)

  after_each(function()
    _G.UnitGUID, _G.UnitName, _G.UnitCreatureFamily, _G.issecretvalue = nil, nil, nil, nil
  end)

  describe("Saw", function()
    it("keeps a creature's name and family, and a later name replaces the old one", function()
      local creatures = {}
      C.Saw(creatures, Guid(WOLF), "Timber Wolf", "Wolf")
      C.Saw(creatures, Guid(WOLF, 2), "Elder Timber Wolf", nil)
      assert.same({ [WOLF] = { name = "Elder Timber Wolf", family = "Wolf" } }, creatures)
    end)

    it("ignores players, a missing name and a name that has not loaded yet", function()
      local creatures = {}
      _G.UNKNOWNOBJECT = "Unknown"
      C.Saw(creatures, "Player-4-0000AAAA", "Farmer")
      C.Saw(creatures, Guid(WOLF), nil)
      C.Saw(creatures, Guid(BOAR), "Unknown")
      _G.UNKNOWNOBJECT = nil
      assert.same({}, creatures)
    end)
  end)

  describe("Name", function()
    it("prefers the name last seen, then the recorded one, then the game's creature cache", function()
      local asked = {}
      C.Ask = function(npc) asked[#asked + 1] = npc return npc == BOAR and "Mottled Boar" or nil end
      MarketWallDB.creatures[WOLF] = { name = "Timber Wolf" }
      assert.equal("Timber Wolf", C.Name(WOLF, "Old Wolf Name"))
      assert.equal("Recorded", C.Name(9, "Recorded"))
      assert.same({}, asked)   -- nothing asked while a name is known
      assert.equal("Mottled Boar", C.Name(BOAR))
      assert.is_nil(C.Name(9))
      assert.same({ BOAR, 9 }, asked)
    end)

    it("keeps a name the creature cache gave, so it is asked only once", function()
      local asks = 0
      C.Ask = function() asks = asks + 1 return "Mottled Boar" end
      C.Name(BOAR)
      assert.equal("Mottled Boar", C.Name(BOAR))
      assert.equal(1, asks)
      assert.same({ name = "Mottled Boar" }, MarketWallDB.creatures[BOAR])
    end)
  end)

  describe("in game", function()
    it("records the target, the mouseover and nameplates", function()
      units.target = { Guid(WOLF), "Timber Wolf", "Wolf" }
      units.nameplate3 = { Guid(BOAR), "Mottled Boar" }
      fire("PLAYER_TARGET_CHANGED")
      fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
      assert.same({ [WOLF] = { name = "Timber Wolf", family = "Wolf" }, [BOAR] = { name = "Mottled Boar" } },
        MarketWallDB.creatures)
    end)

    it("ignores secret names and GUIDs", function()
      local secretName, secretGuid = {}, {}
      _G.issecretvalue = function(v) return v == secretName or v == secretGuid end
      units.target = { Guid(WOLF), secretName }
      units.mouseover = { secretGuid, "Mottled Boar" }
      fire("PLAYER_TARGET_CHANGED")
      fire("UPDATE_MOUSEOVER_UNIT")
      assert.same({}, MarketWallDB.creatures)
    end)

    it("names a later kill from a creature seen once, even after a reload", function()
      units.mouseover = { Guid(WOLF, 1), "Timber Wolf" }
      fire("UPDATE_MOUSEOVER_UNIT")
      Login(MarketWallDB)
      units = {}
      fire("PARTY_KILL", "Player-4-0000AAAA", Guid(WOLF, 2))
      fire("PLAYER_LOGOUT")   -- settles every pending kill
      assert.equal("Timber Wolf", MarketWallDB.mobs[WOLF].name)
    end)

    it("names a mob in the Mobs view from a sighting after its kill was recorded", function()
      MarketWallDB.mobs[WOLF] = { kills = { { 100, ns.Kills.EMPTY } },
        life = { kills = 1, looted = 0, empty = 1, unseen = 0, coin = 0, drops = {}, gathered = 0, gather = {} } }
      C.Ask = function() end
      assert.is_nil(ns.Mobs.For(WOLF).name)
      units.target = { Guid(WOLF), "Timber Wolf" }
      fire("PLAYER_TARGET_CHANGED")
      assert.equal("Timber Wolf", ns.Mobs.For(WOLF).name)
    end)
  end)
end)
