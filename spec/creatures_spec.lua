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

  describe("Ask", function()
    local cache, links, now, realCreateFrame

    -- A hidden tooltip as the game builds it: a creature link shows the cached name, or no lines
    -- when the cache lacks it. Clearing drops the lines, but the first line keeps its old text.
    local function Tooltip()
      local lines = 0
      local firstLine = { text = nil }
      function firstLine.GetText() return firstLine.text end
      _G.MarketWallCreatureScanTextLeft1 = firstLine
      local tooltip = setmetatable({}, { __index = function() return function() end end })
      function tooltip.ClearLines() lines = 0 end
      function tooltip.NumLines() return lines end
      function tooltip.SetHyperlink(_, link)
        links[#links + 1] = link
        local name = cache[tonumber(link:match("^unit:Creature%-0%-0%-0%-0%-(%d+)%-"))]
        if name then lines, firstLine.text = 1, name end
      end
      return tooltip
    end

    before_each(function()
      cache, links, now = {}, {}, 1000
      _G.time = function() return now end
      realCreateFrame = _G.CreateFrame
      _G.CreateFrame = function(kind, ...)
        if kind == "GameTooltip" then return Tooltip() end
        return realCreateFrame(kind, ...)
      end
    end)

    after_each(function()
      _G.time, _G.CreateFrame, _G.MarketWallCreatureScanTextLeft1 = os.time, realCreateFrame, nil
    end)

    it("saves the name the creature cache gives", function()
      cache[BOAR] = "Mottled Boar"
      assert.equal("Mottled Boar", C.Name(BOAR))
      assert.same({ "unit:Creature-0-0-0-0-" .. BOAR .. "-0000000000" }, links)
      assert.same({ name = "Mottled Boar" }, MarketWallDB.creatures[BOAR])
    end)

    it("saves nothing when the cache does not know the creature", function()
      assert.is_nil(C.Name(BOAR))
      assert.is_nil(MarketWallDB.creatures[BOAR])
    end)

    it("never names a creature from a line left by an earlier scan", function()
      cache[BOAR] = "Mottled Boar"
      C.Name(BOAR)
      assert.is_nil(C.Name(WOLF))
      assert.is_nil(MarketWallDB.creatures[WOLF])
    end)

    it("ignores a secret name", function()
      cache[BOAR] = "Mottled Boar"
      _G.issecretvalue = function(v) return v == "Mottled Boar" end
      assert.is_nil(C.Name(BOAR))
      assert.is_nil(MarketWallDB.creatures[BOAR])
    end)

    it("asks again for a creature only after a minute", function()
      assert.is_nil(C.Name(BOAR))
      cache[BOAR] = "Mottled Boar"   -- the game's answer arrives
      now = now + 59
      assert.is_nil(C.Name(BOAR))
      now = now + 1
      assert.equal("Mottled Boar", C.Name(BOAR))
      assert.equal(2, #links)
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
