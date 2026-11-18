local addon = require("spec.helpers.addon")

describe("Ledger", function()
  local ns, L

  before_each(function()
    ns = addon.Load()
    L = ns.Ledger
  end)

  describe("Attribute", function()
    local NOW = 1000

    local function Source(delta, contexts, buys)
      return L.Attribute(delta, contexts, NOW, buys)
    end

    it("credits each income source from the window open at the time", function()
      assert.equal("loot", Source(250, { loot = true }))
      assert.equal("vendor_sale", Source(250, { merchant = true }))
      assert.equal("auction_sale", Source(250, { mail = true, auction_mail = NOW }))
      assert.equal("quest", Source(250, { quest = NOW - 1 }))
      assert.equal("mail", Source(250, { mail = true }))
      assert.equal("trade", Source(250, { trade = true }))
    end)

    it("charges each spending source from the window open at the time", function()
      assert.equal("vendor_buy", Source(-250, { merchant = true }))
      assert.equal("repair", Source(-250, { merchant = true, repair = NOW }))
      assert.equal("auction_buy", Source(-250, { auction = true }))
      assert.equal("auction_deposit", Source(-250, { auction = true, auction_post = NOW }))
      assert.equal("training", Source(-250, { trainer = true }))
      assert.equal("flight", Source(-250, { taxi = NOW - 2 }))
      assert.equal("trade", Source(-250, { trade = true }))
    end)

    it("credits gold to a quest handed in just now, even with a loot window open", function()
      assert.equal("quest", Source(500, { loot = true, turned_in = NOW - 2 }))
      assert.equal("loot", Source(500, { loot = true, turned_in = NOW - 3 }))
    end)

    it("credits loot coins seen in a money message just after the loot window closed", function()
      assert.equal("loot", Source(57, { loot = NOW - 1 }))
    end)

    it("knows an auction-house purchase from MarketWall's own log, even with a post just made", function()
      local buys = { { t = NOW - 1, id = 2589, qty = 20, unit = 50, total = 1000 } }
      assert.equal("auction_buy", Source(-1000, { auction = true, auction_post = NOW }, buys))
      assert.equal("auction_deposit", Source(-60, { auction = true, auction_post = NOW }, buys))
    end)

    it("falls back to Other when nothing explains the change", function()
      assert.equal("other", Source(250, {}))
      assert.equal("other", Source(-250, {}))
      assert.equal("other", Source(250, { merchant = NOW - 3 }))   -- closed too long ago
      assert.equal("other", Source(250, { auction = true }))
    end)
  end)

  describe("a character's book", function()
    local DAY = 86400
    local T0 = os.time({ year = 2026, month = 11, day = 18, hour = 12 })

    it("opens with your gold the first time the ledger runs", function()
      local book = L.Login(nil, 12345, T0)
      assert.same({ T0, 12345 }, book.opening)
      assert.equal(12345, book.balance)
      assert.same({}, book.entries)
    end)

    it("records gold that moved while offline at login, and nothing when it did not", function()
      local book = L.Login(nil, 10000, T0)
      L.Record(book, 10500, T0 + 60, "loot")
      L.Login(book, 10500, T0 + DAY)
      assert.equal(1, #book.entries)
      L.Login(book, 9000, T0 + 2 * DAY)
      assert.same({ T0 + 2 * DAY, -1500, "offline" }, book.entries[2])
      assert.equal(9000, book.balance)
    end)

    it("records each change as the difference from the last balance, so its total is your gold", function()
      local book = L.NewBook(5000, T0)
      local money = 5000
      for i, step in ipairs({ { 300, "loot" }, { -120, "repair" }, { 7, "other" }, { -2000, "auction_buy" } }) do
        money = money + step[1]
        L.Record(book, money, T0 + i, step[2])
        assert.equal(money, L.Total(book))
      end
      assert.is_nil(L.Record(book, money, T0 + 10, "loot"))
      assert.equal(4, #book.entries)
    end)

    it("rolls every change up by week and month, income and spending apart", function()
      local book = L.NewBook(0, T0)
      L.Record(book, 500, T0, "loot")
      L.Record(book, 800, T0 + 60, "loot")
      L.Record(book, 700, T0 + 120, "repair")
      L.Record(book, 900, T0 + 14 * DAY, "vendor_sale")
      local week = book.weeks[L.WeekOf(T0)]
      assert.same({ income = { loot = 800 }, spending = { repair = 100 } }, week)
      assert.same({ vendor_sale = 200 }, book.weeks[L.WeekOf(T0 + 14 * DAY)].income)
      assert.same({ income = { loot = 800 }, spending = { repair = 100 } }, book.months[202611])
      assert.same({ income = { vendor_sale = 200 }, spending = {} }, book.months[202612])
    end)

    it("starts weeks on Monday", function()
      local monday = os.time({ year = 2026, month = 11, day = 16, hour = 12 })
      local sunday = os.time({ year = 2026, month = 11, day = 22, hour = 12 })
      assert.equal(L.WeekOf(monday), L.WeekOf(sunday))
      assert.equal(L.WeekOf(monday), ns.DayOf(monday))
      assert.equal(L.WeekOf(sunday) + 7, L.WeekOf(sunday + DAY))
    end)

    it("keeps raw entries for 90 days while the roll-ups keep the totals", function()
      local book = L.NewBook(0, T0)
      L.Record(book, 100, T0, "loot")
      L.Record(book, 300, T0 + 80 * DAY, "loot")
      L.Login(book, 300, T0 + 100 * DAY)
      assert.equal(1, #book.entries)
      assert.equal(T0 + 80 * DAY, book.entries[1][1])
      assert.equal(300, L.Total(book))
    end)
  end)

  describe("in game", function()
    local fire, money

    before_each(function()
      ns, fire = addon.Load()
      L = ns.Ledger
      money = 10000
      _G.GetMoney = function() return money end
      _G.UnitName = function() return "Farmer" end
      _G.GetNormalizedRealmName = function() return "Forever" end
      fire("ADDON_LOADED", addon.ADDON)
      fire("PLAYER_LOGIN")
    end)

    after_each(function()
      _G.GetMoney, _G.UnitName, _G.GetNormalizedRealmName = nil, nil, nil
    end)

    it("records an opening balance and attributes a sale at the merchant", function()
      local book = MarketWallDB.ledger["Farmer-Forever"]
      assert.equal(10000, book.opening[2])
      fire("MERCHANT_SHOW")
      money = 10450
      fire("PLAYER_MONEY")
      fire("MERCHANT_CLOSED")
      money = 10400
      fire("PLAYER_MONEY")
      assert.same({ "vendor_sale", "vendor_buy" }, { book.entries[1][3], book.entries[2][3] })
      assert.equal(10400, L.Total(book))
    end)

    it("records quest gold that arrives during a loot window as quest, and counts it once in a session", function()
      local s = ns.Sessions.Start("Tanaris turtles")
      local corpse = "Creature-0-5250-0-12-1001-1"
      ns.Kills.tracker:Loot({ { type = 2, text = "50 Copper", sources = { n = 2, corpse, 50 } } }, false, time())
      fire("CHAT_MSG_MONEY", "Your share of the loot is 50 Copper.")
      fire("QUEST_TURNED_IN", 123, 0, 500)
      money = 10500
      fire("PLAYER_MONEY")
      local book = MarketWallDB.ledger["Farmer-Forever"]
      assert.equal("quest", book.entries[1][3])
      assert.equal(500, s.activities.quests.coin)
      assert.is_nil(s.activities["npc:1001"])
    end)

    it("sends each gold change into the recording core", function()
      local seen
      ns.Recording.On("money", function(event) seen = event end)
      fire("CHAT_MSG_MONEY", "Your share of the loot is 57 Copper.")
      money = 10057
      fire("PLAYER_MONEY")
      assert.same({ "loot", 57 }, { seen.source, seen.delta })
    end)
  end)
end)
