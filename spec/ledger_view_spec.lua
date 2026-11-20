local addon = require("spec.helpers.addon")

local DAY = 86400

describe("Ledger view", function()
  local ns, L, Ledger
  -- Wednesday 18 November 2026, midday local time; the week before is in the same month
  local NOW = os.time({ year = 2026, month = 11, day = 18, hour = 12 })
  local LAST_WEEK = NOW - 7 * DAY
  local OCTOBER = os.time({ year = 2026, month = 10, day = 20, hour = 12 })

  before_each(function()
    ns = addon.Load()
    L, Ledger = ns.LedgerView, ns.Ledger
  end)

  -- Opened in October with 1000; 500 of loot in October, last week 300 sold to vendors, this
  -- week 200 more loot, 50 of repairs and 20 lost while offline
  local function Main()
    local book = Ledger.NewBook(1000, OCTOBER - DAY)
    Ledger.Record(book, 1500, OCTOBER, "loot")
    Ledger.Record(book, 1800, LAST_WEEK, "vendor_sale")
    Ledger.Record(book, 2000, NOW - 60, "loot")
    Ledger.Record(book, 1950, NOW - 50, "repair")
    Ledger.Record(book, 1930, NOW - 40, "offline")
    return book
  end
  -- Opened last week with 400; this week 100 of quest gold
  local function Alt()
    local book = Ledger.NewBook(400, LAST_WEEK)
    Ledger.Record(book, 500, NOW - 30, "quest")
    return book
  end
  local function Ledgers() return { ["Main-Forever"] = Main(), ["Alt-Forever"] = Alt() } end

  it("shows this character's book or every character's", function()
    local ledger = Ledgers()
    assert.same({ ledger["Main-Forever"] }, L.Books(ledger, "Main-Forever", false))
    assert.equal(2, #L.Books(ledger, "Main-Forever", true))
    assert.same({}, L.Books(ledger, "New-Forever", false))
  end)

  it("shows only this character's book when another character has the same name", function()
    local fikus, namesake = Main(), Alt()
    local ledger = { ["Player-1-0000AAAA"] = fikus, ["Player-2-0000BBBB"] = namesake }
    assert.same({ fikus }, L.Books(ledger, "Player-1-0000AAAA", false))
    assert.same({ namesake }, L.Books(ledger, "Player-2-0000BBBB", false))
  end)

  it("rolls up the chosen week or month for one character or all", function()
    local week, month = L.PeriodOf("week", NOW), L.PeriodOf("month", NOW)
    local main = L.Books(Ledgers(), "Main-Forever", false)
    assert.same({ income = { loot = 200 }, spending = { repair = 50, offline = 20 } }, L.Roll(main, "week", week))
    assert.same({ income = { loot = 200, vendor_sale = 300 }, spending = { repair = 50, offline = 20 } },
      L.Roll(main, "month", month))
    assert.same({ income = { loot = 500 }, spending = {} }, L.Roll(main, "month", L.Step("month", month, -1)))
    local all = L.Books(Ledgers(), "Main-Forever", true)
    assert.same({ income = { loot = 200, quest = 100 }, spending = { repair = 50, offline = 20 } }, L.Roll(all, "week", week))
  end)

  it("steps weeks by seven days and months across the year", function()
    assert.equal(L.PeriodOf("week", LAST_WEEK), L.Step("week", L.PeriodOf("week", NOW), -1))
    assert.equal(202512, L.Step("month", 202601, -1))
    assert.equal(202701, L.Step("month", 202612, 1))
    assert.equal(202611, L.Step("month", 202610, 1))
    assert.equal("This week", L.PeriodText("week", L.PeriodOf("week", NOW), NOW))
    assert.equal("October 2026", L.PeriodText("month", 202610, NOW))
  end)

  it("lists each side largest first, then Other and Unrecorded, then the total, leaving out empty sources", function()
    local function Labels(rows)
      local out = {}
      for i, row in ipairs(rows) do out[i] = row.label .. " " .. row.copper end
      return out
    end
    assert.same({ "Vendor sales 300", "Loot coins 200", "Total 500" },
      Labels(L.Rows({ loot = 200, vendor_sale = 300, other = 0 })))
    assert.same({ "Repairs 50", "Other 5", "Unrecorded 20", "Total 75" },
      Labels(L.Rows({ repair = 50, offline = 20, other = 5 })))
    assert.same({ "Total 0" }, Labels(L.Rows({})))
  end)

  it("sums up income, spending and net, and says how much spending is unrecorded", function()
    local main = L.Books(Ledgers(), "Main-Forever", false)
    local summary = L.Summary(L.Roll(main, "week", L.PeriodOf("week", NOW)))
    assert.same({ income = 200, spending = 70, net = 130, unrecorded = 20 }, summary)
    assert.equal("20c of spending is unrecorded: gold that changed while MarketWall wasn't running.",
      addon.Plain(L.UnrecordedText(summary)))
    assert.is_nil(L.UnrecordedText(L.Summary({ income = { loot = 5 }, spending = { repair = 5 } })))
  end)

  it("gives each day of the week its net gold, today's included when it is the only one", function()
    local week = L.PeriodOf("week", NOW)
    local days = L.Days(L.Books(Ledgers(), "Main-Forever", true), "week", week)
    assert.equal(7, #days)
    assert.equal(week, days[1].day)
    local nets = {}
    for i, day in ipairs(days) do nets[i] = day.net end
    assert.same({ 0, 0, 200 - 50 - 20 + 100, 0, 0, 0, 0 }, nets)   -- all on Wednesday
    assert.equal(ns.DayOf(NOW), days[3].day)
    assert.same({ "Mon", "Wed" }, { L.DayLabel("week", days[1].day), L.DayLabel("week", days[3].day) })
  end)

  it("gives a month a bar per calendar day, labelling the first and every fifth", function()
    local days = L.Days({ Main() }, "month", 202611)
    assert.equal(30, #days)
    assert.same({ "1", "", "5" }, { L.DayLabel("month", days[1].day), L.DayLabel("month", days[2].day), L.DayLabel("month", days[5].day) })
    assert.equal(300, days[11].net)   -- Nov 11, a week before NOW: the vendor sale
    assert.equal(31, #L.Days({ Main() }, "month", 202610))
  end)
end)
