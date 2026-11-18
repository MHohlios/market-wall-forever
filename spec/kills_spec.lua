local addon = require("spec.helpers.addon")

local MONEY, ITEM = 2, 1
local WOLF, BOAR = 1234, 5678
local LINEN, FANG, LEATHER = 2589, 3300, 2318

local function Guid(npc, spawn)
  return "Creature-0-5250-0-12-" .. npc .. "-" .. spawn
end

local function Slot(itemID, quantity, ...)
  return { type = ITEM, link = "|Hitem:" .. itemID .. "::::|h[x]|h", quantity = quantity, sources = { n = select("#", ...), ... } }
end

local function Coin(text, ...)
  return { type = MONEY, text = text, quantity = 0, sources = { n = select("#", ...), ... } }
end

describe("Kills", function()
  local K, events, answers, tracker

  before_each(function()
    local ns = addon.Load()
    K = ns.Kills
    events, answers = {}, {}
    tracker = K.NewTracker(function(e) events[#events + 1] = e end, function(guid) return answers[guid] end)
  end)

  local function Of(kind)
    local out = {}
    for _, e in ipairs(events) do
      if e.kind == kind then out[#out + 1] = e end
    end
    return out
  end

  describe("ParseCoin", function()
    it("reads gold, silver and copper as the loot window writes them", function()
      assert.equal(12, K.ParseCoin("12 Copper"))
      assert.equal(105, K.ParseCoin("1 Silver\n5 Copper"))
      assert.equal(20304, K.ParseCoin("2 Gold\n3 Silver\n4 Copper"))
      assert.equal(10500, K.ParseCoin("1g 5s"))
      assert.equal(1234 * 10000, K.ParseCoin("1,234 Gold"))
    end)

    it("reads coin icons", function()
      local text = "3|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t 7|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
      assert.equal(307, K.ParseCoin(text))
    end)

    it("falls back to the quantity field when the text has no amount", function()
      assert.equal(250, K.ParseCoin("", 250))
      assert.equal(250, K.ParseCoin(nil, 250))
      assert.equal(0, K.ParseCoin("Coins", 0))
    end)
  end)

  it("counts each victim once", function()
    local wolf = Guid(WOLF, 1)
    assert.is_table(tracker:Kill(wolf, 100))
    assert.is_nil(tracker:Kill(wolf, 101))
    tracker:Loot({ Slot(LINEN, 1, wolf, 1) }, false, 102)
    tracker:Tick(1000)
    assert.equal(1, #Of("kill"))
  end)

  it("ignores players and objects as kills", function()
    assert.is_nil(tracker:Kill("Player-5250-0ABC", 100))
    assert.is_nil(tracker:Kill("GameObject-0-5250-0-12-777-1", 100))
  end)

  it("credits each slot of an area loot to its own corpse", function()
    local wolf, boar = Guid(WOLF, 1), Guid(BOAR, 2)
    tracker:Kill(wolf, 100)
    tracker:Kill(boar, 100)
    tracker:Loot({
      Slot(LINEN, 5, wolf, 2, boar, 3),       -- one stack merged from both corpses
      Slot(FANG, 1, wolf, 1),
      Coin("1 Silver\n20 Copper", wolf, 70, boar, 50),
    }, false, 105)
    local kills = Of("kill")
    assert.equal(2, #kills)
    local byGuid = {}
    for _, e in ipairs(kills) do byGuid[e.guid] = e end
    assert.same({ [LINEN] = 2, [FANG] = 1 }, byGuid[wolf].drops)
    assert.equal(70, byGuid[wolf].coin)
    assert.same({ [LINEN] = 3 }, byGuid[boar].drops)
    assert.equal(50, byGuid[boar].coin)
    assert.equal(K.LOOTED, byGuid[boar].outcome)
    assert.equal("loot", byGuid[boar].via)
    assert.equal(2, #Of("loot"))
  end)

  it("records the whole coin slot for a single corpse, before any party split", function()
    local wolf = Guid(WOLF, 1)
    tracker:Kill(wolf, 100)
    tracker:Loot({ Coin("1 Gold\n2 Silver", wolf, 0) }, false, 101)
    assert.equal(10200, Of("kill")[1].coin)
  end)

  it("splits a coin slot evenly when several corpses give no amounts", function()
    local wolf, boar = Guid(WOLF, 1), Guid(BOAR, 2)
    tracker:Loot({ Coin("5 Copper", wolf, nil, boar, nil) }, false, 101)
    local coin = {}
    for _, e in ipairs(Of("kill")) do coin[e.guid] = e.coin end
    assert.same({ [wolf] = 3, [boar] = 2 }, coin)
  end)

  it("uses the coin slot's quantity when a single source gives 0", function()
    local wolf = Guid(WOLF, 1)
    local coin = Coin("", wolf, 0)
    coin.quantity = 250
    assert.equal(250, K.SplitLoot({ coin })[wolf].coin)
  end)

  it("skips a slot with no readable source and keeps the rest of the window", function()
    local wolf = Guid(WOLF, 1)
    local byGuid = K.SplitLoot({ Slot(FANG, 1), Slot(LINEN, 1, wolf, 1) })
    assert.same({ [wolf] = { coin = 0, drops = { [LINEN] = 1 } } }, byGuid)
  end)

  it("counts a corpse looted without a PARTY_KILL as a kill", function()
    tracker:Loot({ Slot(LINEN, 1, Guid(WOLF, 9), 1) }, false, 100)
    assert.equal(1, #Of("kill"))
  end)

  it("is 0c at once when you open its loot and it is empty", function()
    local wolf = Guid(WOLF, 1)
    tracker:Kill(wolf, 100)
    tracker:Loot({}, false, 101, wolf)
    local kill = Of("kill")[1]
    assert.same({ K.EMPTY, "loot" }, { kill.outcome, kill.via })
  end)

  it("leaves a kill pending when its window has slots but no readable sources", function()
    local wolf = Guid(WOLF, 1)
    tracker:Kill(wolf, 100)
    tracker:Loot({ Slot(LINEN, 1) }, false, 101, wolf)
    tracker:Closed(true)
    assert.equal(0, #Of("kill"))
    tracker:Tick(190)
    assert.same({ K.UNSEEN, "window" }, { Of("kill")[1].outcome, Of("kill")[1].via })
    assert.is_nil(tracker.corpses[wolf].loot)
  end)

  it("records an empty corpse opened right after a Pick Pocket on a mob that then died as 0c", function()
    local wolf = Guid(WOLF, 1)
    tracker:Cast(921, 100)
    tracker:Kill(wolf, 101)
    tracker:Loot({}, false, 102, wolf)
    assert.same({ K.EMPTY, "loot" }, { Of("kill")[1].outcome, Of("kill")[1].via })
  end)

  it("records corpse loot opened right after a Pick Pocket on a mob that then died", function()
    local wolf = Guid(WOLF, 1)
    tracker:Cast(921, 100)
    tracker:Kill(wolf, 101)
    tracker:Loot({ Slot(LINEN, 2, wolf, 2) }, false, 102)
    assert.same({ K.LOOTED, { [LINEN] = 2 } }, { Of("kill")[1].outcome, Of("kill")[1].drops })
  end)

  it("ignores Pick Pocket windows, so the later corpse loot is the kill's drops", function()
    local wolf = Guid(WOLF, 1)
    tracker:Cast(921, 100)
    tracker:Loot({ Slot(5000, 1, wolf, 1) }, false, 101)
    tracker:Closed(true)
    tracker:Kill(wolf, 120)
    tracker:Loot({ Slot(LINEN, 2, wolf, 2) }, false, 125)
    assert.same({ 1, 0 }, { #Of("kill"), #Of("gather") })
    assert.same({ [LINEN] = 2 }, Of("kill")[1].drops)
  end)

  describe("a kill you did not loot", function()
    it("is 0c when CanLootUnit says it had no loot", function()
      local wolf = Guid(WOLF, 1)
      answers[wolf] = "empty"
      tracker:Kill(wolf, 100)
      tracker:Tick(101)
      assert.equal(0, #Of("kill"))     -- still lootable until the window passes
      tracker:Tick(190)
      local kill = Of("kill")[1]
      assert.same({ K.EMPTY, "canloot" }, { kill.outcome, kill.via })
      assert.is_nil(kill.coin)
    end)

    it("is unseen when CanLootUnit says someone else has it", function()
      local wolf = Guid(WOLF, 1)
      answers[wolf] = "theirs"
      tracker:Kill(wolf, 100)
      tracker:Tick(101)
      answers[wolf] = "empty"          -- later answers are ignored: they looted it meanwhile
      tracker:Tick(190)
      assert.same({ K.UNSEEN, "canloot" }, { Of("kill")[1].outcome, Of("kill")[1].via })
    end)

    it("is unseen when CanLootUnit gives no answer, by the window rule", function()
      tracker:Kill(Guid(WOLF, 1), 100)
      tracker:Tick(101)
      tracker:Tick(190)
      assert.same({ K.UNSEEN, "window" }, { Of("kill")[1].outcome, Of("kill")[1].via })
      assert.same({ loot = 0, canloot = 0, window = 1 }, tracker.paths)
    end)

    it("is still credited when looted inside the window", function()
      local wolf = Guid(WOLF, 1)
      answers[wolf] = "mine"
      tracker:Kill(wolf, 100)
      tracker:Tick(101)
      tracker:Loot({ Slot(LINEN, 2, wolf, 2) }, false, 150)
      assert.same({ K.LOOTED, { [LINEN] = 2 } }, { Of("kill")[1].outcome, Of("kill")[1].drops })
    end)

    it("settles at once on logout", function()
      tracker:Kill(Guid(WOLF, 1), 100)
      tracker:Tick(101, true)
      assert.equal(1, #Of("kill"))
    end)
  end)

  describe("Classify", function()
    it("waits out the window unless looted", function()
      assert.is_nil(K.Classify({ t = 0, check = "empty" }, 10, 90))
      assert.equal(K.LOOTED, K.Classify({ t = 0, looted = true }, 10, 90))
      assert.equal(K.EMPTY, K.Classify({ t = 0, check = "empty" }, 90, 90))
      assert.equal(K.UNSEEN, K.Classify({ t = 0, check = "mine" }, 90, 90))
      assert.equal(K.UNSEEN, K.Classify({ t = 0, check = false }, 90, 90))
    end)
  end)

  describe("gathering", function()
    it("records a second window on an emptied corpse as a gather", function()
      local wolf = Guid(WOLF, 1)
      tracker:Kill(wolf, 100)
      tracker:Loot({ Slot(LINEN, 1, wolf, 1) }, false, 101)
      tracker:Closed(true)
      tracker:Loot({ Slot(LEATHER, 2, wolf, 2) }, false, 105)
      assert.equal(1, #Of("kill"))
      local gather = Of("gather")[1]
      assert.same({ WOLF, { [LEATHER] = 2 } }, { gather.npc, gather.drops })
      assert.equal(1, #Of("loot"))
    end)

    it("ignores reopening a corpse with items left in it", function()
      local wolf = Guid(WOLF, 1)
      tracker:Loot({ Slot(LINEN, 1, wolf, 1), Slot(FANG, 1, wolf, 1) }, false, 101)
      tracker:Closed(false)
      tracker:Loot({ Slot(FANG, 1, wolf, 1) }, false, 110)
      assert.same({ 1, 1, 0 }, { #Of("kill"), #Of("loot"), #Of("gather") })
    end)

    it("records a window right after a skinning cast as a gather and keeps it on the kill", function()
      local wolf = Guid(WOLF, 1)
      answers[wolf] = "empty"
      tracker:Kill(wolf, 100)
      tracker:Cast(8613, 102)
      tracker:Loot({ Slot(LEATHER, 1, wolf, 1) }, false, 103)
      tracker:Tick(200)
      local kill = Of("kill")[1]
      assert.same({ K.EMPTY, { [LEATHER] = 1 } }, { kill.outcome, kill.gather })
    end)

    it("records a corpse's gather once even when its window is reopened", function()
      local wolf = Guid(WOLF, 1)
      tracker:Loot({ Slot(LINEN, 1, wolf, 1) }, false, 101)
      tracker:Closed(true)
      tracker:Cast(8613, 102)
      tracker:Loot({ Slot(LEATHER, 1, wolf, 1) }, false, 103)
      tracker:Closed(false)
      tracker:Loot({ Slot(LEATHER, 1, wolf, 1) }, false, 110)
      tracker:Closed(true)
      assert.equal(1, #Of("gather"))
    end)

    it("counts a cast only for the first window after it, so a fresh corpse looted next is a drop", function()
      local a, b = Guid(WOLF, 1), Guid(WOLF, 2)
      tracker:Kill(a, 90)
      tracker:Kill(b, 90)
      tracker:Loot({ Slot(LINEN, 1, a, 1) }, false, 95)
      tracker:Closed(true)
      tracker:Cast(8613, 100)
      tracker:Loot({ Slot(LEATHER, 1, a, 1) }, false, 100)
      tracker:Closed(true)
      tracker:Loot({ Slot(FANG, 1, b, 1) }, false, 102)
      local kills = Of("kill")
      assert.same({ 1, 2 }, { #Of("gather"), #kills })
      assert.same({ b, K.LOOTED, { [FANG] = 1 } }, { kills[2].guid, kills[2].outcome, kills[2].drops })
    end)

    it("records every mining cast on the same vein, each once", function()
      local vein = "GameObject-0-5250-0-12-1731-1"
      local ORE = 2770
      tracker:Cast(2575, 100)
      tracker:Loot({ Slot(ORE, 2, vein, 2) }, false, 101)
      tracker:Closed(true)
      tracker:Cast(2575, 105)
      tracker:Loot({ Slot(ORE, 1, vein, 1) }, false, 106)
      tracker:Closed(false)
      tracker:Loot({ Slot(ORE, 1, vein, 1) }, false, 110)   -- reopened without a new cast
      local gathers = Of("gather")
      assert.equal(2, #gathers)
      assert.same({ "mining", { [ORE] = 2 } }, { gathers[1].skill, gathers[1].drops })
      assert.same({ "mining", { [ORE] = 1 } }, { gathers[2].skill, gathers[2].drops })
    end)

    it("tags a gather with the skill of its cast", function()
      local wolf = Guid(WOLF, 1)
      tracker:Cast(8613, 100)
      tracker:Loot({ Slot(LEATHER, 1, wolf, 1) }, false, 101)
      tracker:Cast(2366, 110)
      tracker:Loot({ Slot(765, 1, "GameObject-0-5250-0-12-1617-1", 1) }, false, 111)
      assert.same({ "skinning", "herbalism" }, { Of("gather")[1].skill, Of("gather")[2].skill })
    end)

    it("treats a window long after the cast as loot", function()
      local wolf = Guid(WOLF, 1)
      tracker:Cast(8613, 100)
      tracker:Loot({ Slot(LINEN, 1, wolf, 1) }, false, 110)
      assert.same({ 1, 0 }, { #Of("kill"), #Of("gather") })
    end)
  end)

  it("records a container opened from your bags as loot from an item", function()
    tracker:Loot({ Slot(LINEN, 2, "Item-5250-0-40000000ABCDEF", 2) }, false, 100)
    local loot = Of("loot")[1]
    assert.same({ "item", { [LINEN] = 2 } }, { loot.source, loot.drops })
    assert.equal(0, #Of("kill"))
  end)

  it("records no container loot for disenchanting results, which DisenchantLog.lua owns, even reopened", function()
    local item = "Item-5250-0-40000000ABCDEF"
    tracker:Loot({ Slot(10940, 2, item, 2) }, false, 101, nil, true)
    tracker:Closed(false)
    tracker:Loot({ Slot(10940, 1, item, 1) }, false, 102)
    assert.equal(0, #Of("loot"))
  end)

  it("records a container reopened with loot left once, and the next one from its stack again", function()
    local item = "Item-5250-0-40000000ABCDEF"
    tracker:Loot({ Slot(LINEN, 2, item, 2) }, false, 100)
    tracker:Closed(false)
    tracker:Loot({ Slot(LINEN, 2, item, 2) }, false, 105)
    tracker:Closed(true)
    tracker:Loot({ Slot(LINEN, 1, item, 1) }, false, 110)
    local loots = Of("loot")
    assert.same({ 2, { [LINEN] = 2 }, { [LINEN] = 1 } }, { #loots, loots[1].drops, loots[2].drops })
  end)

  it("numbers each loot window on its loot and fish events", function()
    tracker:Loot({ Slot(LINEN, 1, Guid(WOLF, 1), 1) }, false, 100)
    tracker:Closed(true)
    tracker:Loot({ Slot(LINEN, 1, Guid(WOLF, 2), 1) }, false, 100)
    tracker:Closed(true)
    tracker:Loot({ Coin("3 Copper") }, true, 100)
    assert.same({ 1, 2, 3 }, { Of("loot")[1].window, Of("loot")[2].window, Of("fish")[1].window })
  end)

  it("names a looted mob from a unit seen earlier", function()
    local wolf = Guid(WOLF, 1)
    tracker:SawUnit(wolf, "Timber Wolf")
    tracker:Loot({ Slot(LINEN, 1, wolf, 1) }, false, 100)
    assert.equal("Timber Wolf", Of("loot")[1].name)
  end)

  it("keeps fishing out of mob records", function()
    tracker:Loot({ Slot(6291, 1, "GameObject-0-5250-0-12-35591-1", 1), Coin("3 Copper") }, true, 100)
    local fish = Of("fish")[1]
    assert.same({ "fishing", 3, { [6291] = 1 } }, { fish.source, fish.coin, fish.drops })
    assert.same({ 0, 0 }, { #Of("kill"), #Of("loot") })
  end)
end)
