local addon = require("spec.helpers.addon")

local WEAPON, ARMOR, CONSUMABLE = 2, 4, 0
local COMMON, UNCOMMON = 1, 2
local STRANGE_DUST, LESSER_MAGIC_ESSENCE = 10940, 10938
local LOW_CRAFT_ID = 250620     -- one of Forever's crafted items with an estimate
local CUT = 0.05
local function NO_DEPOSITS() return 0 end

describe("FindDisenchantDeals", function()
  local ns, items, prices

  before_each(function()
    ns = addon.Load()
    prices = { [STRANGE_DUST] = 100, [LESSER_MAGIC_ESSENCE] = 1000 }
    ns.LatestWall = function(id) return prices[id] end
    items = {}
    _G.C_Item = {
      GetItemInfo = function(id)
        local item = items[id]
        if not item then return nil end
        return "item", "link", item.quality, item.level, 1, "", "", 1, "", 0, 0, item.classID
      end,
    }
    _G.GetBuildInfo = function() return "1.15.0", "12345" end
  end)

  after_each(function()
    _G.C_Item, _G.GetBuildInfo = nil, nil
  end)

  local function Item(id, quality, level, classID)
    items[id] = { quality = quality, level = level, classID = classID }
  end

  -- Green level-10 armor disenchants for 420 (80% of 1.5 dust at 100, 20% of 1.5 essence at
  -- 1000), so 399 after the 5% cut
  it("keeps gear listed under its value after the cut", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    local deals = ns.FindDisenchantDeals({ [1001] = 300 }, CUT, NO_DEPOSITS,0, 0)
    assert.equal(1, #deals)
    local d = deals[1]
    assert.equal(1001, d.id)
    assert.equal(300, d.price)
    assert.near(399, d.value, 1e-6)
    assert.near(99, d.profit, 1e-6)
    assert.near(0.33, d.pct, 1e-6)
    assert.equal("classic table", d.odds)
    assert.equal(1, d.skill)
  end)

  it("leaves out gear priced over its value after the cut, though under its value before it", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 410 }, CUT, NO_DEPOSITS,0, 0))
  end)

  it("leaves out gear that profits after the cut alone once the materials' deposits count", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    local deposits = { [STRANGE_DUST] = 30, [LESSER_MAGIC_ESSENCE] = 300 }
    -- 80% of 1.5 dust at 30 + 20% of 1.5 essence at 300 = 126 in deposits: 399 - 126 = 273 net
    assert.equal(1, #ns.FindDisenchantDeals({ [1001] = 380 }, CUT, NO_DEPOSITS, 0, 0))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 380 }, CUT, function(id) return deposits[id] end, 0, 0))
    local d = ns.FindDisenchantDeals({ [1001] = 200 }, CUT, function(id) return deposits[id] end, 0, 0)[1]
    assert.near(273, d.value, 1e-6)   -- as the item tooltip's Net disenchant shows it
    assert.near(73, d.profit, 1e-6)
  end)

  it("applies the minimum profit and % to the net", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    local function Deposit(id) return id == STRANGE_DUST and 10 or 0 end   -- 12 in deposits: 87 profit at 300
    assert.equal(1, #ns.FindDisenchantDeals({ [1001] = 300 }, CUT, Deposit, 86, 0.28))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 300 }, CUT, Deposit, 88, 0))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 300 }, CUT, Deposit, 0, 0.30))
  end)

  it("applies the minimum profit", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    assert.equal(1, #ns.FindDisenchantDeals({ [1001] = 300 }, CUT, NO_DEPOSITS,98, 0))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 300 }, CUT, NO_DEPOSITS,100, 0))
  end)

  it("applies the minimum profit %", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    assert.equal(1, #ns.FindDisenchantDeals({ [1001] = 300 }, CUT, NO_DEPOSITS,0, 0.32))
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 300 }, CUT, NO_DEPOSITS,0, 0.34))
  end)

  it("leaves out items whose likely materials have no price", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    prices[LESSER_MAGIC_ESSENCE] = nil
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 1 }, CUT, NO_DEPOSITS,0, 0))
  end)

  it("leaves out items below uncommon, non-gear and uncached items", function()
    Item(1001, COMMON, 10, ARMOR)
    Item(LOW_CRAFT_ID, UNCOMMON, 10, CONSUMABLE)   -- has an estimate, but is not gear
    assert.same({}, ns.FindDisenchantDeals({ [1001] = 1, [LOW_CRAFT_ID] = 1, [9999] = 1 }, CUT, NO_DEPOSITS,0, 0))
  end)

  it("names the source of the odds and the skill each item needs", function()
    Item(LOW_CRAFT_ID, UNCOMMON, 30, WEAPON)
    local d = ns.FindDisenchantDeals({ [LOW_CRAFT_ID] = 1 }, CUT, NO_DEPOSITS,0, 0)[1]
    assert.equal("Forever estimate", d.odds)
    assert.equal(50, d.skill)
  end)

  it("puts the most profit first", function()
    Item(1001, UNCOMMON, 10, ARMOR)
    Item(1002, UNCOMMON, 10, WEAPON)   -- weapons lean to essence: 1230, so 1168.5 after the cut
    Item(1003, UNCOMMON, 12, ARMOR)
    local deals = ns.FindDisenchantDeals({ [1001] = 300, [1002] = 300, [1003] = 200 }, CUT, NO_DEPOSITS,0, 0)
    assert.same({ 1002, 1003, 1001 }, { deals[1].id, deals[2].id, deals[3].id })
  end)
end)

describe("a full scan's Disenchant list", function()
  local ns, fire, loaded, tickers, vendor

  before_each(function()
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    MarketWallDB.cfg.minDisenchantProfit, MarketWallDB.cfg.minDisenchantPct = 0, 0
    local prices = { [STRANGE_DUST] = 100, [LESSER_MAGIC_ESSENCE] = 1000 }
    ns.LatestWall = function(id) return prices[id] end
    loaded, vendor = false, 0
    _G.C_Item = {
      GetItemInfoInstant = function() return 1001, "", "", "", 0, ARMOR end,
      GetItemInfo = function()
        if loaded then return "item", "link", UNCOMMON, 10, 1, "", "", 1, "", 0, vendor, ARMOR end
      end,
    }
    _G.C_AuctionHouse = {
      GetNumReplicateItems = function() return 1 end,
      GetReplicateItemInfo = function()   -- one auction of item 1001 at 300c
        return "item", nil, 1, nil, nil, nil, nil, nil, nil, 300, nil, nil, nil, nil, nil, nil, 1001
      end,
    }
    -- tickers run once the code that started them has stored them
    tickers = {}
    _G.C_Timer = { NewTicker = function(_, fn)
      local ticker = { Cancel = function(self) self.cancelled = true end }
      tickers[#tickers + 1] = { ticker = ticker, fn = fn }
      return ticker
    end }
    _G.GetTime, _G.GetBuildInfo = os.time, function() return "1.15.0", "12345" end
  end)

  after_each(function()
    _G.C_Item, _G.C_AuctionHouse, _G.C_Timer, _G.GetTime, _G.GetBuildInfo = nil, nil, nil, nil, nil
  end)

  local function RunTickers()
    local i = 1
    while tickers[i] do
      local t = tickers[i]
      while not t.ticker.cancelled do t.fn() end
      i = i + 1
    end
  end

  it("adds gear whose item data arrives after the scan ends", function()
    ns.fullScanRunning = true
    ns.OnReplicateReady()
    RunTickers()
    assert.same({}, ns.disenchants)

    loaded = true
    fire("GET_ITEM_INFO_RECEIVED", 1001, true)
    assert.equal(1, #ns.disenchants)
    assert.equal(300, ns.disenchants[1].price)
  end)

  describe("repricing when the deposits change", function()
    -- materials at a 200c vendor price, 1.5 expected per disenchant: 45 in deposits at 12h
    -- (354 net, 54 profit at 300c) and 180 at 48h (219 net, a loss)
    before_each(function()
      loaded, vendor = true, 200
      MarketWallDB.cfg.sellDuration = 1
      ns.fullScanRunning = true
      ns.OnReplicateReady()
      RunTickers()
    end)

    it("starts from the scan's deals at the Sell duration", function()
      assert.equal(1, #ns.DisenchantDeals())
      assert.near(354, ns.DisenchantDeals()[1].value, 1e-6)
    end)

    it("drops a deal that no longer pays at a longer Sell duration", function()
      MarketWallDB.cfg.sellDuration = 3
      ns.DisenchantDepositsChanged()
      assert.same({}, ns.DisenchantDeals())
    end)

    it("drops a deal that no longer pays once a higher deposit rate is learned", function()
      ns.Outlet.LearnDepositRate(1, 120, 200)   -- 60% at 12h
      assert.same({}, ns.DisenchantDeals())
    end)
  end)

  -- not a Disenchant list check, but this is where a full scan already runs end to end
  it("replaces the set of well-supplied items, for mob values", function()
    MarketWallDB.cfg.minSupply = 1
    ns.R().supplied = { [999] = true }
    ns.fullScanRunning = true
    ns.OnReplicateReady()
    RunTickers()
    assert.same({ [1001] = true }, ns.R().supplied)
  end)
end)

describe("DisenchantSkill", function()
  local ns = addon.Load()

  it("needs 1 skill up to item level 20", function()
    assert.equal(1, ns.DisenchantSkill(1))
    assert.equal(1, ns.DisenchantSkill(20))
  end)

  it("needs 25 more for every 5 levels after that", function()
    assert.equal(25, ns.DisenchantSkill(21))
    assert.equal(25, ns.DisenchantSkill(25))
    assert.equal(50, ns.DisenchantSkill(26))
    assert.equal(200, ns.DisenchantSkill(60))
  end)

  it("tops out at 225 from item level 61", function()
    assert.equal(225, ns.DisenchantSkill(61))
    assert.equal(225, ns.DisenchantSkill(88))
  end)
end)

describe("EnchantingSkill", function()
  local ns
  local lines

  before_each(function()
    ns = addon.Load()
    lines = {}
    _G.GetNumSkillLines = function() return #lines end
    _G.GetSkillLineInfo = function(i) return unpack(lines[i]) end
  end)

  after_each(function()
    _G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
    _G.GetProfessions, _G.GetProfessionInfo = nil, nil
  end)

  -- professions: list of { rank, skillLine }, reported by index like the game
  local function Professions(professions)
    _G.GetProfessions = function() return professions[1] and 1, professions[2] and 2 end
    _G.GetProfessionInfo = function(index)
      local p = professions[index]
      return "name", nil, p[1], 300, 0, 0, p[2]
    end
  end

  it("reads the rank from the profession API", function()
    Professions({ { 150, 197 }, { 260, 333 } })   -- Tailoring, Enchanting
    assert.equal(260, ns.EnchantingSkill())
  end)

  it("falls back to the skill list when the profession API lists nothing", function()
    Professions({})
    lines = { { "Professions", true, true }, { "Enchanting", false, nil, 120 } }
    assert.equal(120, ns.EnchantingSkill())
  end)

  it("is 0 when the profession API lists others and the skill list cannot say", function()
    Professions({ { 150, 197 } })
    lines = { { "Professions", true, false } }
    assert.equal(0, ns.EnchantingSkill())
  end)

  it("reads the rank from the skill list", function()
    lines = { { "Professions", true, true }, { "Tailoring", false, nil, 150 }, { "Enchanting", false, nil, 225 } }
    assert.equal(225, ns.EnchantingSkill())
  end)

  it("is 0 without Enchanting", function()
    lines = { { "Professions", true, true }, { "Tailoring", false, nil, 150 } }
    assert.equal(0, ns.EnchantingSkill())
  end)

  it("is unknown while a collapsed section could hide it", function()
    lines = { { "Professions", true, false } }
    assert.is_nil(ns.EnchantingSkill())
  end)

  it("is unknown when the game has no skill API", function()
    _G.GetNumSkillLines, _G.GetSkillLineInfo = nil, nil
    assert.is_nil(ns.EnchantingSkill())
  end)
end)
