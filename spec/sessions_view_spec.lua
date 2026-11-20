local addon = require("spec.helpers.addon")

local T0 = 1000000
local SCALE, FEATHER, FISH = 10, 20, 30

describe("Sessions view", function()
  local ns, V, S

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {} }
    _G.C_Item = {}
    ns.R().names = { [SCALE] = "Turtle Scale", [FEATHER] = "Feather", [FISH] = "Yellowtail" }
    V, S = ns.SessionsView, ns.Sessions
  end)

  local PRICE = { [SCALE] = 50, [FEATHER] = 10, [FISH] = 20 }
  local function Price(id) return PRICE[id] end

  -- Turtles (npc 1) worth 150, owls (npc 2) 100 with their coin, fishing 250: 500 in all
  local function Farm()
    local s = S.New("Tanaris turtles", "Farmer-Forever", T0)
    s.activities = {
      ["npc:1"] = { coin = 0, drops = { [SCALE] = 3 } },
      ["npc:2"] = { coin = 50, drops = { [FEATHER] = 5 } },
      fishing = { coin = 0, drops = { [FISH] = 10, [SCALE] = 1 } },
    }
    return s
  end
  local NAMES = { ["npc:1"] = "Turtles", ["npc:2"] = "Owls", fishing = "Fishing" }
  local function Name(key) return NAMES[key] end

  describe("tracker", function()
    it("shows elapsed time, value earned and gold per hour while running", function()
      local s = Farm()
      local text = V.TrackerText(s, S.Report(s, Price, Name, T0 + 1800))
      assert.equal("Tanaris turtles  |cff4fc36brunning|r", text.title)
      assert.equal("0:30:00", text.elapsed)
      assert.equal(ns.Money(500), text.value)
      assert.equal(ns.Money(1000), text.perHour)
    end)

    it("stops the clock while paused and says so", function()
      local s = Farm()
      S.PauseAt(s, T0 + 3600)
      local text = V.TrackerText(s, S.Report(s, Price, Name, T0 + 7200))
      assert.equal("Tanaris turtles  |cffffb057paused|r", text.title)
      assert.equal("1:00:00", text.elapsed)
      assert.equal(ns.Money(500), text.perHour)
    end)
  end)

  describe("activities", function()
    local function Report() return S.Report(Farm(), Price, Name, T0 + 3600) end

    it("lists groups largest first with their share, value, gold per hour and top items", function()
      local entries = V.ActivityEntries(Report())
      local names = {}
      for i, entry in ipairs(entries) do names[i] = entry.group end
      assert.same({ "Fishing", "Turtles", "Owls" }, names)
      assert.same({ 0.5, 0.3, 0.2 }, { entries[1].bar, entries[2].bar, entries[3].bar })   -- share bars
      assert.same({ "Fishing", "50%", 250, 250, "Yellowtail x10, Turtle Scale x1" }, entries[1].cells)
      assert.same({ "Owls", "20%", 100, 100, "Feather x5" }, entries[3].cells)
    end)

    it("sorts by a header column, and says when a group gained only coins", function()
      local entries = V.ActivityEntries(Report())
      ns.MobsView.Sort(entries, { col = 1 })
      assert.same({ "Fishing", "Owls", "Turtles" }, { entries[1].group, entries[2].group, entries[3].group })
      local coins = S.New("x", "c", T0)
      coins.activities.quests = { coin = 500, drops = {} }
      local only = V.ActivityEntries(S.Report(coins, Price, tostring, T0 + 60))[1]
      assert.equal("100%", only.cells[2])
      assert.equal("|cffa3acaccoins only|r", only.cells[5])
    end)

    it("shows the value at session end only once it stopped", function()
      local s = Farm()
      assert.equal("|cffa3acacstill open|r", V.Stats(S.Report(s, Price, Name, T0 + 60), "optimal")[2][2])
      S.StopAt(s, T0 + 3600)
      s.ended = { optimal = 777, market = 0, vendor = 0 }
      s.gaps = { { T0, 700 }, { T0, 900 } }
      local stats = V.Stats(S.Report(s, Price, Name, T0 + 9999), "optimal")
      assert.equal(ns.Money(777), stats[2][2])
      assert.equal(ns.Money(50), stats[4][2])
      assert.equal("2 (26 min)", stats[5][2])
    end)
  end)

  describe("history", function()
    local function Run(label, start, hours, value)
      local s = S.New(label, "c", start)
      S.StopAt(s, start + hours * 3600)
      s.value = value
      return s
    end
    local list = {
      Run("Tanaris turtles", T0, 1, 3000),
      Run("Felwood herbs", T0 + 1e4, 2, 5000),
      Run("Tanaris turtles", T0 + 2e4, 2, 5000),
      Run("Tanaris turtles", T0 + 3e4, 1, 1000),
    }
    local function Value(s) return s.value end

    it("filters by label, newest first", function()
      local entries = V.HistoryEntries(list, "Tanaris turtles", Value, T0 + 1e5)
      assert.equal(3, #entries)
      assert.equal(list[4], entries[1].session)
      assert.equal(list[1], entries[3].session)
      assert.same({ "Tanaris turtles", "1 h", 1000, 1000 },
        { entries[1].cells[1], entries[1].cells[3], entries[1].cells[4], entries[1].cells[5] })
      assert.equal(4, #V.HistoryEntries(list, nil, Value, T0 + 1e5))
    end)

    it("compares one label's runs by their best and median gold per hour", function()
      local _, rows = V.HistoryEntries(list, "Tanaris turtles", Value, T0 + 1e5)
      assert.equal("3 runs.  Best " .. ns.Money(3000) .. " / hour.  Median " .. ns.Money(2500) .. " / hour.",
        V.CompareText("Tanaris turtles", rows))
      local _, all = V.HistoryEntries(list, nil, Value, T0 + 1e5)
      assert.is_nil(V.CompareText(nil, all))
    end)

    it("offers the most recently used labels first, each once", function()
      assert.same({ "Tanaris turtles", "Felwood herbs" }, V.RecentLabels(list, 5))
      assert.same({ "Tanaris turtles" }, V.RecentLabels(list, 1))
    end)

    it("lists every label with its number of runs for the dropdown", function()
      assert.same({ { label = "Felwood herbs", runs = 1 }, { label = "Tanaris turtles", runs = 3 } }, V.LabelChoices(list))
      assert.equal(" · 1 run", addon.Plain(V.RunsText(1)))
      assert.equal(" · 3 runs", addon.Plain(V.RunsText(3)))
    end)
  end)

  describe("session menu", function()
    local function Kinds(choices)
      local kinds = {}
      for i, choice in ipairs(choices) do kinds[i] = choice.kind end
      return kinds
    end

    local function Stopped(label, start, seconds)
      local s = ns.Sessions.New(label, "c", start)
      ns.Sessions.StopAt(s, start + seconds)
      return s
    end

    it("offers relabelling, merging, a new duration and deleting for a stopped session", function()
      local older, newer = Stopped("Farm Turt", T0, 32 * 60), Stopped("Farm Turtle v2", T0 + 1e4, 44 * 60)
      local choices = V.MenuChoices({ older, newer }, older)
      assert.same({ "label", "merge", "duration", "delete" }, Kinds(choices))
      assert.equal(newer, choices[2].target)
      assert.matches("^Merge into Farm Turtle v2 · ", addon.Plain(choices[2].text))
    end)

    it("offers pause or resume and stop instead of delete while a session is open", function()
      local open = ns.Sessions.New("Farm", "c", T0)
      assert.same({ "label", "pause", "stop" }, Kinds(V.MenuChoices({ open }, open)))
      ns.Sessions.PauseAt(open, T0 + 60)
      assert.same({ "label", "resume", "stop" }, Kinds(V.MenuChoices({ open }, open)))
    end)

    it("says what a delete removes and what it keeps", function()
      local s = Stopped("Farm Turt", T0, 32 * 60)
      local question, detail = V.DeleteText(s, 44200)
      assert.equal("Delete the session \"Farm Turt\" from " .. date("%b %d, %H:%M", T0) .. "?", question)
      assert.equal("Its 32 min and 4g 42s of loot leave Sessions. The Ledger and Mobs keep their records.", addon.Plain(detail))
    end)

    it("reads a typed duration as minutes or hours:minutes", function()
      assert.same({ 2640, 4320, 4320 }, { V.ParseDuration("44"), V.ParseDuration("1:12"), V.ParseDuration("72") })
      assert.is_nil(V.ParseDuration("0"))
      assert.is_nil(V.ParseDuration("an hour"))
      assert.is_nil(V.ParseDuration("1:5"))
    end)
  end)
end)
