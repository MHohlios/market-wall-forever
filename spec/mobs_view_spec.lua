local addon = require("spec.helpers.addon")

local GREY, ORANGE = "|cffa3acac", "|cffffb057"

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
      { npc = 2, name = "Jungle Stalker", lifetime = 7, seen = 0 },   -- every kill looted by someone else
      market(Valued(3, "Stranglethorn Raptor", 95, 142), {}),
      { npc = 4, lifetime = 12, seen = 0 },   -- never targeted, so no name
      market(Valued(5, "Young Panther", 400, 11), {}),
    }
  end

  local function Names(rows)
    local names = {}
    for i, row in ipairs(rows) do names[i] = row.name end
    return names
  end

  it("sorts by median per kill, with mobs that have no seen kill last", function()
    local rows = V.Rows(All(), "optimal", "")
    assert.same({ "Young Panther", "Stranglethorn Raptor", "Lashtail Raptor", "Jungle Stalker", "NPC 4" }, Names(rows))
    assert.equal(0, rows[5].kills)   -- the seen kills, not all 12
  end)

  describe("header sort", function()
    local function Entries()
      local entries = {}
      for i, row in ipairs(V.Rows(All(), "optimal", "")) do entries[i] = { name = row.name, sort = V.MobSortValues(row) } end
      return entries
    end

    it("keeps the median order until a header is clicked", function()
      local entries = Entries()
      V.Sort(entries, nil)
      assert.same({ "Young Panther", "Stranglethorn Raptor", "Lashtail Raptor", "Jungle Stalker", "NPC 4" }, Names(entries))
    end)

    it("sorts by a column either way, with mobs that have no value last", function()
      local entries = Entries()
      V.Sort(entries, { col = 2, desc = true })
      assert.same({ "Stranglethorn Raptor", "Lashtail Raptor", "Young Panther", "Jungle Stalker", "NPC 4" }, Names(entries))
      V.Sort(entries, { col = 3, desc = false })
      assert.same({ "Lashtail Raptor", "Stranglethorn Raptor", "Young Panther" }, { entries[1].name, entries[2].name, entries[3].name })
      assert.same({ "Jungle Stalker", "NPC 4" }, { entries[4].name, entries[5].name })
    end)

    it("sorts the drop table by name or by any lens value", function()
      ns.R().names[1], ns.R().names[2] = "Raptor Flesh", "Raptor Hide"
      local function Drop(id, share, optimal)
        local drop = { id = id, share = share, quantity = 1, vendor = 1, market = 1, optimal = optimal }
        return { name = id, sort = V.DropSortValues(drop) }
      end
      local entries = { Drop(2, 0.1, 50), Drop(1, 0.5, 10) }
      V.Sort(entries, { col = 1, desc = false })
      assert.same({ 1, 2 }, Names(entries))
      V.Sort(entries, { col = 6, desc = true })
      assert.same({ 2, 1 }, Names(entries))
    end)
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

  it("counts unpriced drops and shows no values for a mob with no seen kill", function()
    local rows = V.Rows(All(), "optimal", "")
    local lashtail = V.MobCells(rows[3], 10)
    assert.same({ "Lashtail Raptor", "58", ns.Money(80), ns.Money(160), ns.Money(120), "item:7 31%", ORANGE .. "1|r" }, lashtail)
    assert.same({ "Jungle Stalker", ORANGE .. "0|r", GREY .. "-|r", GREY .. "-|r", GREY .. "-|r", GREY .. "-|r", "" },
      V.MobCells(rows[4], 10))
  end)

  describe("under the kills before values are reliable", function()
    local panther   -- 11 seen kills
    before_each(function() panther = V.Rows(All(), "optimal", "Panther")[1] end)

    it("shows the values with the kill count in orange and a hover saying they are rough", function()
      local cells = V.MobCells(panther, 12)
      assert.same({ ORANGE .. "11|r", ns.Money(400) }, { cells[2], cells[3] })
      assert.equal("Fewer than 12 kills; values are rough", V.MobTip(panther, 12))
    end)

    it("shows a plain kill count and no hover from the threshold on", function()
      assert.equal("11", V.MobCells(panther, 11)[2])
      assert.is_nil(V.MobTip(panther, 11))
    end)
  end)
end)
