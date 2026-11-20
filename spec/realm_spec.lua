local addon = require("spec.helpers.addon")

local ALLIANCE_GUID, HORDE_GUID = "Player-6796-002683B6", "Player-6796-0099AAAA"
local BEARDO = "Creature-0-6796-0-12-8661-00002A1B3C"   -- Gadgetzan's auctioneer
local STORMWIND_AUCTIONEER = "Creature-0-6796-0-12-8719-00002A1B3C"

-- Records each call to a widget so a test can ask what it was last told
local function Recorder()
  local calls = {}
  return setmetatable({ calls = calls }, { __index = function(_, method)
    return function(_, ...) calls[method] = { ... } end
  end })
end

describe("realm and faction history", function()
  local ns, fire, guid, npcGUID, faction, printed

  local function Load(saved)
    ns, fire = addon.Load()
    _G.MarketWallDB = saved
    fire("ADDON_LOADED", addon.ADDON)
    ns.OnAuctionHouseShow = function() end   -- the Market tab is not under test
  end

  local realPrint = print
  before_each(function()
    guid, npcGUID, faction, printed = ALLIANCE_GUID, nil, "Alliance", {}
    _G.UnitGUID = function(unit)
      if unit == "player" then return guid end
      if unit == "npc" then return npcGUID end
    end
    _G.UnitFactionGroup = function() return faction end
    _G.UnitName = function() return "Fikus" end
    _G.GetMoney = function() return 1e9 end
    _G.GetNormalizedRealmName = function() return "CAMWOWUS2Realm1PvE" end
    -- only the move's own chat line; other modules greet the login too
    _G.print = function(...)
      local line = table.concat({ ... }, " ")
      if line:find("auction house history", 1, true) then printed[#printed + 1] = line end
    end
    Load()
  end)

  after_each(function()
    _G.UnitGUID, _G.UnitFactionGroup, _G.UnitName, _G.GetMoney, _G.GetNormalizedRealmName = nil, nil, nil, nil, nil
    _G.print = realPrint
  end)

  describe("the realm key", function()
    it("is the GUID's server ID and the faction", function()
      assert.equal("6796-Alliance", ns.RealmKey())
      faction = "Horde"
      assert.equal("6796-Horde", ns.RealmKey())
    end)

    it("falls back to the realm name while the GUID is unreadable", function()
      guid = nil
      assert.equal("CAMWOWUS2Realm1PvE-Alliance", ns.RealmKey())
      guid = "secret"
      _G.issecretvalue = function(v) return v == "secret" end
      assert.equal("CAMWOWUS2Realm1PvE-Alliance", ns.RealmKey())
      _G.issecretvalue = nil
    end)

    it("calls an unknown faction Neutral", function()
      faction = nil
      assert.equal("6796-Neutral", ns.RealmKey())
    end)
  end)

  it("gives Horde and Alliance characters separate buckets", function()
    fire("PLAYER_LOGIN")
    ns.R().watch[7] = { buy = 10 }
    guid, faction = HORDE_GUID, "Horde"
    fire("PLAYER_LOGIN")
    assert.is_nil(ns.R().watch[7])
    assert.is_table(MarketWallDB.realms["6796-Alliance"].watch[7])
    assert.is_table(MarketWallDB.realms["6796-Horde"])
  end)

  describe("moving the realm-name history", function()
    local old
    before_each(function()
      old = { watch = { [7] = { buy = 10 } }, lastFull = 1 }
      Load({ realms = { CAMWOWUS2Realm1PvE = old } })
    end)

    it("moves it to the first character's faction and says so once", function()
      fire("PLAYER_LOGIN")
      assert.equal(old, MarketWallDB.realms["6796-Alliance"])
      assert.is_nil(MarketWallDB.realms.CAMWOWUS2Realm1PvE)
      assert.equal(1, #printed)
      assert.truthy(printed[1]:find("belongs to Alliance", 1, true))
      guid, faction = HORDE_GUID, "Horde"
      fire("PLAYER_LOGIN")
      assert.equal(1, #printed)
      assert.is_nil(ns.R().watch[7])
    end)

    it("never overwrites history already under the new key", function()
      local current = { watch = { [9] = { buy = 5 } } }
      MarketWallDB.realms["6796-Alliance"] = current
      fire("PLAYER_LOGIN")
      assert.equal(current, MarketWallDB.realms["6796-Alliance"])
      assert.equal(old, MarketWallDB.realms.CAMWOWUS2Realm1PvE)
      assert.equal(0, #printed)
    end)

    it("waits while the faction is unknown", function()
      faction = nil
      fire("PLAYER_LOGIN")
      assert.equal(old, MarketWallDB.realms.CAMWOWUS2Realm1PvE)
      assert.equal(0, #printed)
    end)
  end)

  describe("the neutral auction house", function()
    it("is known by its auctioneer", function()
      assert.equal(8661, ns.NpcID(BEARDO))
      assert.is_true(ns.IsNeutralAuctioneer(BEARDO))
      assert.is_false(ns.IsNeutralAuctioneer(STORMWIND_AUCTIONEER))
      assert.is_false(ns.IsNeutralAuctioneer(nil))   -- unreadable: your faction's
      assert.is_false(ns.IsNeutralAuctioneer(ALLIANCE_GUID))
    end)

    it("is detected as the auction house opens, and forgotten as it closes", function()
      npcGUID = BEARDO
      fire("AUCTION_HOUSE_SHOW")
      assert.is_true(ns.neutralAH)
      assert.is_false(ns.CanTrade())
      fire("AUCTION_HOUSE_CLOSED")
      npcGUID = STORMWIND_AUCTIONEER
      fire("AUCTION_HOUSE_SHOW")
      assert.is_false(ns.neutralAH)
      assert.is_true(ns.CanTrade())
    end)

    describe("once open", function()
      local sent
      before_each(function()
        fire("PLAYER_LOGIN")
        npcGUID = BEARDO
        fire("AUCTION_HOUSE_SHOW")
        sent = {}
        _G.C_AuctionHouse = setmetatable({}, { __index = function(_, name)
          return function() sent[#sent + 1] = name return true end
        end })
      end)
      after_each(function() _G.C_AuctionHouse = nil end)

      it("sends no scan, search or purchase and records nothing", function()
        ns.ladders[7] = { ladder = { { p = 5, q = 3 } }, total = 3, t = time(), kind = "commodity" }
        ns.StartFullScan()
        ns.StartWatchScan({ 7 })
        assert.is_false(ns.SearchNow(7))
        ns.BuyUnder(7, 100)
        MarketWallDB.cfg.autoScan = true
        ns.MaybeAutoScan()
        assert.same({}, sent)
        assert.is_falsy(ns.fullScanRunning or ns.scanState.running)
        assert.is_nil(MarketWallDB.lastReplicate)
        assert.same({}, ns.R().buys)
        assert.same({}, ns.R().days)
      end)

      it("greys out the scan buttons and shows the note under the faction's status line", function()
        local ui = ns.ui
        ui.frame, ui.status, ui.bar, ui.neutralNote = Recorder(), Recorder(), Recorder(), Recorder()
        ui.scanButton, ui.fullButton = Recorder(), Recorder()
        ns.UpdateStatus()
        assert.same({ false }, ui.scanButton.calls.SetEnabled)
        assert.is_table(ui.fullButton.calls.Disable)
        assert.is_nil(ui.fullButton.calls.Enable)
        assert.equal("Neutral auction house: MarketWall doesn't scan, buy or post here. Your Alliance history is shown as it was.",
          addon.Plain(ui.neutralNote.calls.SetText[1]))
        assert.same({ true }, ui.neutralNote.calls.SetShown)
      end)
    end)
  end)

  it("starts the status line with the faction", function()
    local ui = ns.ui
    ui.frame, ui.status, ui.bar, ui.neutralNote = Recorder(), Recorder(), Recorder(), Recorder()
    ui.scanButton, ui.fullButton = Recorder(), Recorder()
    fire("PLAYER_LOGIN")
    ns.UpdateStatus()
    assert.truthy(addon.Plain(ui.status.calls.SetText[1]):find("^Alliance · Full scan never"))
    assert.same({ true }, ui.scanButton.calls.SetEnabled)
    faction = "Horde"
    assert.equal("Horde · Scan complete", addon.Plain(ui.WithFaction("Scan complete")))
  end)
end)
