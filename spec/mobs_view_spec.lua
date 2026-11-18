local addon = require("spec.helpers.addon")

local GREY = "|cffa3acac"

describe("Mobs view", function()
  local ns, V

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, mobs = {} }
    _G.C_Item = {}
    V = ns.MobsView
  end)

  local function Summary(median, average) return { median = median, average = average } end

  -- Stats as Mobs.All gives them: optimal median m, market median m / 2, vendor median m / 4
  local function Valued(npc, name, m, kills)
    return {
      npc = npc, name = name, lifetime = kills, seen = kills,
      optimal = Summary(m, m * 2), market = Summary(m / 2, m), vendor = Summary(m / 4, m / 2),
      optimalNoRare = Summary(m, m * 1.5), marketNoRare = Summary(m / 2, m * 0.75), vendorNoRare = Summary(m / 4, m / 2),
      top = { id = 7, share = 0.31 },
    }
  end
  local market = function(stats, unpriced) stats.market.unpriced = unpriced return stats end

  local function All()
    return {
      market(Valued(1, "Lashtail Raptor", 80, 58), { [5] = true }),
      { npc = 2, name = "Jungle Stalker", lifetime = 7, seen = 7 },
      market(Valued(3, "Stranglethorn Raptor", 95, 142), {}),
      { npc = 4, lifetime = 12, seen = 2 },   -- never targeted, so no name
      market(Valued(5, "Young Panther", 400, 11), {}),
    }
  end

  local function Names(rows)
    local names = {}
    for i, row in ipairs(rows) do names[i] = row.name end
    return names
  end

  it("sorts by median per kill, with mobs short of kills last, most kills first", function()
    assert.same({ "Young Panther", "Stranglethorn Raptor", "Lashtail Raptor", "NPC 4", "Jungle Stalker" },
      Names(V.Rows(All(), "optimal", "")))
  end)

  it("filters on any part of the name, ignoring case", function()
    assert.same({ "Stranglethorn Raptor", "Lashtail Raptor" }, Names(V.Rows(All(), "optimal", "  RAPTOR ")))
    assert.same({}, Names(V.Rows(All(), "optimal", "wolf")))
  end)

  it("shows the chosen lens's median, average and average without rare drops", function()
    local row = V.Rows(All(), "optimal", "Stranglethorn")[1]
    assert.same({ 95, 190, 142.5 }, { row.median, row.average, row.withoutRare })
    row = V.Rows(All(), "market", "Stranglethorn")[1]
    assert.same({ 47.5, 95, 71.25 }, { row.median, row.average, row.withoutRare })
    row = V.Rows(All(), "vendor", "Stranglethorn")[1]
    assert.same({ 23.75, 47.5, 47.5 }, { row.median, row.average, row.withoutRare })
  end)

  it("re-sorts when the lens changes", function()
    local all = All()
    all[3].vendor = Summary(1000, 1000)   -- vendors best, though not best under Optimal
    assert.equal("Stranglethorn Raptor", V.Rows(all, "vendor", "")[1].name)
    assert.equal("Young Panther", V.Rows(all, "optimal", "")[1].name)
  end)

  it("counts unpriced drops and says how many kills a mob still needs", function()
    local rows = V.Rows(All(), "optimal", "")
    local lashtail = V.MobCells(rows[3], 10)
    assert.same({ "Lashtail Raptor", "58", ns.Money(80), ns.Money(160), ns.Money(120), "item:7 31%", "|cffffb057" .. "1|r" }, lashtail)
    assert.same({ "Jungle Stalker", "7", GREY .. "-|r", GREY .. "-|r", GREY .. "-|r", GREY .. "needs 10 kills|r", "" },
      V.MobCells(rows[5], 10))
  end)
end)
