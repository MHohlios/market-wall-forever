local addon = require("spec.helpers.addon")

local TURTLE, SNAPPER, BANDIT = 1001, 1002, 2001
local SCALE, FISH, ORE = 10, 20, 30
local T0 = 1000000

-- SCALE sells to vendors for 10 and on the market for 100; FISH has no market; ORE no thin market
local PRICES = {
  vendor = function(id) return ({ [SCALE] = 10, [FISH] = 5, [ORE] = 20 })[id] end,
  wall = function(id)
    if id == SCALE then return 100, true end
    if id == ORE then return 300, false end
  end,
  disenchant = function() return nil end,
}

describe("Sessions", function()
  local ns, S, lenses

  before_each(function()
    ns = addon.Load()
    S = ns.Sessions
    lenses = ns.Mobs.Lenses(PRICES, { cut = 0.05, disenchant = false }, {})
  end)

  local function Loot(t, npc, coin, drops)
    return { t = t, kind = "loot", source = "npc:" .. npc, npc = npc, coin = coin, drops = drops or { [FISH] = 1 } }
  end

  describe("timing", function()
    it("counts running time and leaves paused time out", function()
      local s = S.New("Tanaris turtles", "Farmer-Forever", T0)
      assert.equal(600, S.Duration(s, T0 + 600))
      assert.is_true(S.PauseAt(s, T0 + 600))
      assert.is_false(S.PauseAt(s, T0 + 700))
      assert.equal(600, S.Duration(s, T0 + 5000))
      assert.is_true(S.ResumeAt(s, T0 + 1000))
      assert.equal(800, S.Duration(s, T0 + 1200))
      assert.is_true(S.StopAt(s, T0 + 1300))
      assert.equal(900, S.Duration(s, T0 + 9999))
    end)

    it("ends a session stopped while paused at the pause", function()
      local s = S.New("x", "c", T0)
      S.PauseAt(s, T0 + 300)
      S.StopAt(s, T0 + 4000)
      assert.equal(300, S.Duration(s, T0 + 9999))
    end)

    it("records nothing while paused or after stopping", function()
      local s = S.New("x", "c", T0)
      S.PauseAt(s, T0 + 10)
      assert.is_false(S.Add(s, Loot(T0 + 20, TURTLE, 50)))
      S.ResumeAt(s, T0 + 30)
      assert.is_true(S.Add(s, Loot(T0 + 40, TURTLE, 50)))
      S.StopAt(s, T0 + 50)
      assert.is_false(S.Add(s, Loot(T0 + 60, TURTLE, 50)))
      assert.same({ [FISH] = 1 }, s.activities["npc:" .. TURTLE].drops)
    end)

    it("flags stretches over ten running minutes with nothing gained, without pausing", function()
      local s = S.New("x", "c", T0)
      S.Add(s, Loot(T0 + 300, TURTLE, 5))
      S.Add(s, Loot(T0 + 300 + 840, TURTLE, 5))      -- 14 minutes later
      S.PauseAt(s, T0 + 1200)
      S.ResumeAt(s, T0 + 5000)                        -- a long pause is not a gap
      S.Add(s, Loot(T0 + 5100, TURTLE, 5))
      S.Add(s, { t = T0 + 5300, kind = "loot", npc = TURTLE, coin = 0, drops = {} })   -- an empty corpse gains nothing
      S.StopAt(s, T0 + 5400)
      assert.same({ { T0 + 1140, 840 } }, s.gaps)
    end)

    it("flags a quiet stretch at the end of a session", function()
      local s = S.New("x", "c", T0)
      S.Add(s, Loot(T0 + 60, TURTLE, 5))
      S.StopAt(s, T0 + 60 + 700)
      assert.same({ { T0 + 760, 700 } }, s.gaps)
    end)
  end)

  describe("activities", function()
    it("tags each kind of gain", function()
      assert.equal("npc:" .. TURTLE, S.ActivityOf(Loot(T0, TURTLE, 1)))
      assert.equal("chests", S.ActivityOf({ kind = "loot", source = "object:3714" }))
      assert.equal("chests", S.ActivityOf({ kind = "loot", source = "item" }))
      assert.equal("mining", S.ActivityOf({ kind = "gather", skill = "mining" }))
      assert.equal("herbalism", S.ActivityOf({ kind = "gather", skill = "herbalism" }))
      assert.equal("skinning", S.ActivityOf({ kind = "gather", skill = "skinning" }))
      assert.equal("fishing", S.ActivityOf({ kind = "fish" }))
      assert.equal("quests", S.ActivityOf({ kind = "quest" }))
      assert.is_nil(S.ActivityOf({ kind = "kill" }))
    end)

    it("leaves vendor and auction-house sales out of value earned", function()
      local s = S.New("x", "c", T0)
      assert.is_false(S.Add(s, { t = T0 + 1, kind = "money", source = "vendor_sale", delta = 5000, coin = 5000 }))
      assert.is_false(S.Add(s, { t = T0 + 2, kind = "money", source = "auction_sale", delta = 9000, coin = 9000 }))
      assert.equal(0, S.Value(s, lenses.optimal))
    end)

    it("names beasts by creature family, other mobs by name", function()
      local creatures = { [TURTLE] = { name = "Snapping Turtle", family = "Turtle" }, [BANDIT] = { name = "Defias Bandit" } }
      assert.equal("Turtle", S.ActivityName("npc:" .. TURTLE, creatures))
      assert.equal("Defias Bandit", S.ActivityName("npc:" .. BANDIT, creatures))
      assert.equal("Mob 9", S.ActivityName("npc:9", creatures))
      assert.equal("Chests and containers", S.ActivityName("chests", creatures))
    end)

    it("renames and merges groups, and moves what was merged into a renamed group", function()
      local groups = {}
      S.Rename(groups, "Snapping Turtle", "Turtles")
      S.Rename(groups, "Giant Turtle", "Turtles")
      assert.equal("Turtles", S.GroupOf(groups, "Giant Turtle"))
      S.Rename(groups, "Turtles", "Shells")
      assert.same({ "Shells", "Shells", "Shells" },
        { S.GroupOf(groups, "Snapping Turtle"), S.GroupOf(groups, "Giant Turtle"), S.GroupOf(groups, "Turtles") })
      S.Rename(groups, "Owl", "Snapping Turtle")   -- merging into a merged name joins its group
      assert.equal("Shells", S.GroupOf(groups, "Owl"))
    end)

    it("unmerges one member of a group back to its own name, leaving the rest merged", function()
      local groups = {}
      S.Rename(groups, "Snapping Turtle", "Turtles")
      S.Rename(groups, "Giant Turtle", "Turtles")
      S.Rename(groups, "Turtles", "Shells")
      assert.same({ "Giant Turtle", "Snapping Turtle", "Turtles" }, S.Members(groups, "Shells"))
      S.Unmerge(groups, "Giant Turtle")
      assert.equal("Giant Turtle", S.GroupOf(groups, "Giant Turtle"))
      assert.same({ "Snapping Turtle", "Turtles" }, S.Members(groups, "Shells"))
      assert.same({}, S.Members(groups, "Giant Turtle"))
      S.Rename(groups, "Giant Turtle", "Shells")   -- and can merge again
      assert.equal("Shells", S.GroupOf(groups, "Giant Turtle"))
    end)
  end)

  describe("value", function()
    local function Farm()
      local s = S.New("Tanaris turtles", "c", T0)
      S.Add(s, Loot(T0 + 60, TURTLE, 100, { [SCALE] = 2 }))
      S.AddLootCoin(s, { ["npc:" .. TURTLE] = 100 }, 100, T0 + 61)
      S.Add(s, Loot(T0 + 120, SNAPPER, 50, { [SCALE] = 1 }))
      S.AddLootCoin(s, { ["npc:" .. SNAPPER] = 50 }, 50, T0 + 121)
      S.Add(s, { t = T0 + 180, kind = "fish", coin = 0, drops = { [FISH] = 10 } })
      S.Add(s, { t = T0 + 240, kind = "gather", skill = "mining", drops = { [ORE] = 1 } })
      S.Add(s, { t = T0 + 300, kind = "quest", coin = 400, drops = {} })
      S.StopAt(s, T0 + 1800)
      return s
    end

    it("prices the same gains under each lens", function()
      local s = Farm()
      -- coin 550; vendor 3 x 10 + 10 x 5 + 20; market 3 x 95 + 0 + 20 (thin); optimal 3 x 95 + 10 x 5 + 20
      assert.same({ vendor = 650, market = 855, optimal = 905 }, S.Values(s, lenses))
    end)

    it("breaks a session into groups with share, gold per hour and top items", function()
      local s = Farm()
      local creatures = { [TURTLE] = { family = "Turtle" }, [SNAPPER] = { family = "Turtle" } }
      local report = S.Report(s, lenses.optimal, function(key) return S.ActivityName(key, creatures) end, T0 + 9999)
      assert.same({ 1800, 905, 550, 1810 }, { report.duration, report.value, report.coin, report.perHour })
      local turtles = report.groups[1]
      assert.same({ "Turtle", 435, 870 }, { turtles.name, turtles.value, turtles.perHour })
      assert.near(435 / 905, turtles.share, 1e-9)
      assert.same({ { id = SCALE, qty = 3, value = 285 } }, turtles.top)
      local names = {}
      for i, group in ipairs(report.groups) do names[i] = group.name end
      assert.same({ "Turtle", "Quests", "Fishing", "Mining" }, names)
    end)

    it("keeps its value at the moment it ended beside the value at current prices", function()
      local s = Farm()
      s.ended = S.Values(s, lenses)
      local cheaper = ns.Mobs.Lenses({ vendor = PRICES.vendor, wall = function() return nil end,
        disenchant = PRICES.disenchant }, { cut = 0.05 }, {})
      local report = S.Report(s, cheaper.optimal, tostring, T0 + 9999)
      assert.equal(650, report.value)
      assert.equal(905, report.ended.optimal)
    end)
  end)

  describe("history", function()
    local function Run(label, start, hours, value)
      local s = S.New(label, "c", start)
      S.StopAt(s, start + hours * 3600)
      s.ended = { optimal = value }
      return s
    end

    it("lists runs newest first, filtered by label, with gold per hour", function()
      local list = { Run("Turtles", T0, 1, 3000), Run("Herbs", T0 + 1e4, 2, 2000), Run("Turtles", T0 + 2e4, 0.5, 2000) }
      local rows = S.History(list, "Turtles", function(s) return s.ended.optimal end, T0 + 1e5)
      assert.same({ 4000, 3000 }, { rows[1].perHour, rows[2].perHour })
      assert.equal(3, #S.History(list, nil, function() return 0 end, T0 + 1e5))
      assert.same({ "Herbs", "Turtles" }, S.Labels(list))
    end)

    it("gives the best and median gold per hour of a farm's runs", function()
      local rows = { { perHour = 30 }, { perHour = 10 }, { perHour = 20 }, { perHour = 40 } }
      assert.same({ best = 40, median = 25 }, S.Compare(rows))
      assert.same({ best = 30, median = 20 }, S.Compare({ rows[1], rows[2], rows[3] }))
      assert.is_nil(S.Compare({}))
    end)
  end)

  describe("in game", function()
    local fire, now
    local realPrint = print
    local spawn = 0

    -- Opens a loot window through the kill tracker, one fresh corpse per { npc, coin, drops }
    local function LootWindow(t, ...)
      local slots = {}
      for _, corpse in ipairs({ ... }) do
        spawn = spawn + 1
        local guid = "Creature-0-5250-0-12-" .. corpse[1] .. "-" .. spawn
        slots[#slots + 1] = { type = 2, text = corpse[2] .. " Copper", sources = { n = 2, guid, corpse[2] } }
        for id, qty in pairs(corpse[3] or {}) do
          slots[#slots + 1] = { type = 1, link = "|Hitem:" .. id .. "::::|h[x]|h", quantity = qty, sources = { n = 2, guid, qty } }
        end
      end
      ns.Kills.tracker:Loot(slots, false, t)
    end

    -- Coin reaching your bags that the ledger credits to loot
    local function Received(t, copper)
      ns.Recording.Emit({ t = t, kind = "money", source = "loot", delta = copper })
    end

    before_each(function()
      ns, fire = addon.Load()
      S = ns.Sessions
      now = T0
      _G.time = function() return now end
      _G.print = function() end
      _G.UnitName = function() return "Farmer" end
      _G.GetNormalizedRealmName = function() return "Forever" end
      fire("ADDON_LOADED", addon.ADDON)
      S.GameLenses = function() return lenses end
    end)

    after_each(function()
      _G.time, _G.print, _G.UnitName, _G.GetNormalizedRealmName = os.time, realPrint, nil, nil
    end)

    it("keeps running through a UI reload, leaving the reload's time out", function()
      local s = S.Start("Tanaris turtles")
      now = T0 + 600
      fire("PLAYER_LOGOUT")
      now = T0 + 630
      fire("PLAYER_ENTERING_WORLD", false, true)
      assert.is_nil(s.pausedAt)
      now = T0 + 700
      assert.equal(670, S.Duration(s, now))
    end)

    it("stays paused after a real logout and login", function()
      local s = S.Start("Tanaris turtles")
      now = T0 + 600
      fire("PLAYER_LOGOUT")
      now = T0 + 630
      fire("PLAYER_ENTERING_WORLD", true, false)
      assert.equal(T0 + 600, s.pausedAt)
    end)

    it("judges a reload by a short gap when the game does not say", function()
      local s = S.Start("x")
      S.PauseAt(s, T0 + 100, true)
      assert.is_false(S.AfterLogin(s, T0 + 100 + S.RELOAD_GAP, nil))
      assert.is_true(S.AfterLogin(s, T0 + 150, nil))
      S.PauseAt(s, T0 + 200)   -- paused by hand: a reload keeps it paused
      assert.is_false(S.AfterLogin(s, T0 + 210, true))
    end)

    it("splits received coin only across the loot window that showed it, even in the same second", function()
      local s = S.Start("Tanaris turtles")
      LootWindow(T0 + 10, { TURTLE, 100 })
      Received(T0 + 10, 100)
      LootWindow(T0 + 10, { SNAPPER, 50 })
      Received(T0 + 10, 50)
      assert.same({ 100, 50 }, { s.activities["npc:" .. TURTLE].coin, s.activities["npc:" .. SNAPPER].coin })
    end)

    it("leaves out loot coin from a window that recorded nothing, such as Pick Pocket", function()
      local s = S.Start("Tanaris turtles")
      local tracker, living = ns.Kills.tracker, "Creature-0-5250-0-12-" .. BANDIT .. "-9"
      LootWindow(T0 + 10, { TURTLE, 50 })
      Received(T0 + 10, 50)
      tracker:Closed(true, T0 + 11)
      tracker:Cast(921, T0 + 20)
      tracker:Loot({ { type = 2, text = "30 Copper", sources = { n = 2, living, 30 } } }, false, T0 + 21)
      Received(T0 + 21, 30)
      assert.equal(50, s.activities["npc:" .. TURTLE].coin)
      assert.is_nil(s.activities["npc:" .. BANDIT])
    end)

    it("leaves out loot coin that arrives long after your last loot window closed", function()
      local s = S.Start("Tanaris turtles")
      LootWindow(T0 + 10, { TURTLE, 50 })
      ns.Kills.tracker:Closed(true, T0 + 11)
      Received(T0 + 30, 20)   -- a party member's share, with no window of yours
      assert.same({}, s.activities)
    end)

    it("does not count an item bought from a vendor just after a quest frame closed as a reward", function()
      local s = S.Start("Tanaris turtles")
      _G.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
      fire("QUEST_COMPLETE")
      fire("QUEST_FINISHED")
      fire("MERCHANT_SHOW")
      fire("CHAT_MSG_LOOT", "You receive item: |cffffffff|Hitem:4306::::::::|h[Silk Cloth]|h|r.")
      _G.LOOT_ITEM_PUSHED_SELF = nil
      assert.same({}, s.activities)
    end)

    it("pauses the running session on logout", function()
      local s = S.Start("Tanaris turtles")
      now = T0 + 600
      fire("PLAYER_LOGOUT")
      now = T0 + 9000
      assert.equal(600, S.Duration(s, now))
      S.Resume()
      now = T0 + 9060
      assert.equal(660, S.Duration(s, now))
    end)

    it("records core events into the running session and keeps its value when it stops", function()
      S.Start("Tanaris turtles")
      LootWindow(T0 + 10, { TURTLE, 100, { [SCALE] = 1 } })
      Received(T0 + 11, 100)
      now = T0 + 3600
      local s = S.Stop()
      assert.same({ vendor = 110, market = 195, optimal = 195 }, s.ended)
      assert.is_nil(S.Current())
    end)

    it("counts only the share of a corpse's coin you received, split across the window's corpses", function()
      local s = S.Start("Tanaris turtles")
      LootWindow(T0 + 10, { TURTLE, 100 }, { SNAPPER, 50 })
      Received(T0 + 11, 31)
      ns.Recording.Emit({ t = T0 + 12, kind = "money", source = "vendor_sale", delta = 500 })
      assert.same({ 21, 10 }, { s.activities["npc:" .. TURTLE].coin, s.activities["npc:" .. SNAPPER].coin })
    end)

    it("keeps a merged group for later sessions", function()
      MarketWallDB.creatures[TURTLE] = { name = "Snapping Turtle" }
      S.RenameGroup("Snapping Turtle", "Turtles")
      local s = S.Start("Tanaris turtles")
      ns.Recording.Emit(Loot(T0 + 10, TURTLE, 100))
      assert.equal("Turtles", S.ReportFor(s, "optimal").groups[1].name)
      assert.same({ ["Snapping Turtle"] = "Turtles" }, MarketWallDB.sessionGroups)
    end)
  end)
end)

describe("Quests", function()
  it("reads the item and quantity from a received-item message", function()
    local Q = addon.Load().Quests
    local single, multiple = "You receive item: %s.", "You receive item: %sx%d."
    local link = "|cffffffff|Hitem:4306::::::::|h[Silk Cloth]|h|r"
    assert.same({ 4306, 1 }, { Q.ParseReceived("You receive item: " .. link .. ".", single, multiple) })
    assert.same({ 4306, 5 }, { Q.ParseReceived("You receive item: " .. link .. "x5.", single, multiple) })
    assert.is_nil(Q.ParseReceived("You receive loot: " .. link .. ".", single, multiple))
  end)

  it("takes items as rewards only with the reward window open or just after a turn-in, never at a shop", function()
    local Q = addon.Load().Quests
    assert.is_true(Q.IsReward({ reward = true, shops = {} }, 100))
    assert.is_true(Q.IsReward({ turnedIn = 98, shops = {} }, 100))
    assert.is_false(Q.IsReward({ turnedIn = 97, shops = {} }, 100))
    assert.is_false(Q.IsReward({ shops = {} }, 100))
    assert.is_false(Q.IsReward({ reward = true, shops = { merchant = true } }, 100))
  end)
end)
