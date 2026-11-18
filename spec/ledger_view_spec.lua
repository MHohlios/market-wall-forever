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

  it("lists each side largest first, then Other always and offline changes, then the total", function()
    local function Labels(rows)
      local out = {}
      for i, row in ipairs(rows) do out[i] = row.label .. " " .. row.copper end
      return out
    end
    assert.same({ "Vendor sales 300", "Loot coins 200", "Other 0", "Total 500" },
      Labels(L.Rows({ loot = 200, vendor_sale = 300 })))
    assert.same({ "Repairs 50", "Other 5", "Other (while offline or unrecorded) 20", "Total 75" },
      Labels(L.Rows({ repair = 50, offline = 20, other = 5 })))
    assert.same({ "Other 0", "Total 0" }, Labels(L.Rows({})))
  end)

  it("charts gold at the end of each period, counting each character from its opening", function()
    local ledger = Ledgers()
    local month = L.Balance(L.Books(ledger, "Main-Forever", false), "month", NOW)
    assert.same({ 1500, 1930 }, { month[1].w, month[2].w })
    assert.equal(os.time({ year = 2026, month = 11, day = 1, hour = 0 }), month[1].t)
    assert.equal(NOW, month[2].t)
    local weeks = L.Balance(L.Books(ledger, "Main-Forever", true), "week", NOW)
    local balances = {}
    for i, point in ipairs(weeks) do balances[i] = point.w end
    assert.same({ 1500, 1800 + 400, 1930 + 500 }, balances)
  end)

  it("charts the opening gold alone before any change", function()
    local book = Ledger.NewBook(700, NOW - 60)
    assert.same({ { t = NOW, w = 700 } }, L.Balance({ book }, "week", NOW))
  end)
end)
