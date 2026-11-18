local addon = require("spec.helpers.addon")

local WOLF = 1234
local LINEN, FANG, RING, LEATHER, DUSTLESS = 2589, 3300, 7001, 2318, 4444

describe("Mobs", function()
  local ns, M, K

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    M, K = ns.Mobs, ns.Kills
  end)

  local function KillEvent(t, outcome, coin, drops, gather)
    return { t = t, kind = "kill", npc = WOLF, guid = "Creature-0-1-0-1-" .. WOLF .. "-" .. t, name = "Wolf",
      outcome = outcome, coin = coin, drops = drops, gather = gather }
  end

  describe("storage", function()
    it("keeps the last 1,000 kills and lifetime totals for all of them", function()
      local mobs = {}
      for t = 1, 1005 do M.Add(mobs, KillEvent(t, K.LOOTED, 10, { [LINEN] = 1 })) end
      local mob = mobs[WOLF]
      assert.equal(1000, #mob.kills)
      assert.equal(6, mob.kills[1][1])            -- the oldest five were dropped
      assert.same({ kills = 1005, looted = 1005, empty = 0, unseen = 0, coin = 10050,
        drops = { [LINEN] = 1005 }, gathered = 0, gather = {} }, mob.life)
    end)

    it("stores compact arrays with values only where the outcome has them", function()
      local mobs = {}
      M.Add(mobs, KillEvent(1, K.LOOTED, 5, { [LINEN] = 2 }))
      M.Add(mobs, KillEvent(2, K.EMPTY))
      M.Add(mobs, KillEvent(3, K.UNSEEN, nil, nil, { [LEATHER] = 1 }))
      assert.same({ { 1, K.LOOTED, 5, { [LINEN] = 2 } }, { 2, K.EMPTY }, { 3, K.UNSEEN, nil, nil, { [LEATHER] = 1 } } },
        mobs[WOLF].kills)
      assert.equal("Wolf", mobs[WOLF].name)
    end)

    it("attaches a gather that arrives after its kill settled", function()
      local kill = KillEvent(1, K.LOOTED, 5, { [LINEN] = 1 })
      ns.Recording.Emit(kill)
      ns.Recording.Emit({ kind = "gather", guid = kill.guid, npc = WOLF, drops = { [LEATHER] = 2 } })
      local mob = MarketWallDB.mobs[WOLF]
      assert.same({ [LEATHER] = 2 }, mob.kills[1][5])
      assert.same({ 1, { [LEATHER] = 2 } }, { mob.life.gathered, mob.life.gather })
    end)

    it("ignores gathers for corpses it never stored", function()
      ns.Recording.Emit({ kind = "gather", guid = "GameObject-0-1-0-1-1617-1", drops = { [765] = 1 } })
      assert.same({}, MarketWallDB.mobs)
    end)
  end)

  -- the saved supply set is written by full scans (disenchant_deals_spec) and live searches (bait_spec)
  describe("real supply", function()
    local t = 1700000000

    it("prices at the wall while the latest scan or search had plenty", function()
      ns.R().supplied = { [LINEN] = true }
      ns.Record(LINEN, { { p = 100, q = 30 } }, 30, t)
      assert.same({ 100, true }, { M.GamePrices().wall(LINEN) })
    end)

    it("falls back once the latest scan or search no longer had plenty", function()
      ns.R().supplied = {}
      ns.Record(LINEN, { { p = 100, q = 30 } }, 30, t)
      assert.same({ 100, false }, { M.GamePrices().wall(LINEN) })
    end)
  end)

  describe("Stats", function()
    local vendor, walls, de, opts

    local function Prices()
      return {
        vendor = function(id) return vendor[id] end,
        wall = function(id) local w = walls[id] if w then return w[1], w[2] end end,
        disenchant = function(id) return de[id] end,
      }
    end

    local function Mob(kills)
      local mobs = {}
      for i, k in ipairs(kills) do M.Add(mobs, KillEvent(i, k[1], k[2], k[3], k[4])) end
      return mobs[WOLF]
    end

    before_each(function()
      vendor = { [LINEN] = 10, [FANG] = 50, [RING] = 100, [LEATHER] = 20, [DUSTLESS] = 7 }
      walls = { [LINEN] = { 100, true }, [FANG] = { 200, false }, [RING] = { 1000, true }, [LEATHER] = { 40, true } }
      de = { [RING] = 5000 }
      opts = { cut = 0.05, disenchant = false, skinning = false, rareShare = 0.02, minKills = 3 }
    end)

    it("shows only counts below the minimum kills", function()
      local stats = M.Stats(Mob({ { K.LOOTED, 0, { [LINEN] = 1 } }, { K.UNSEEN }, { K.UNSEEN } }), Prices(), opts)
      assert.same({ name = "Wolf", kills = 3, lifetime = 3, seen = 1 }, stats)
    end)

    it("needs at least one seen kill even with minimum kills set to 0", function()
      opts.minKills = 0
      local stats = M.Stats(Mob({ { K.UNSEEN } }), Prices(), opts)
      assert.same({ name = "Wolf", kills = 1, lifetime = 1, seen = 0 }, stats)
    end)

    it("gives median and average per lens, counting 0c kills and leaving out unseen ones", function()
      local stats = M.Stats(Mob({
        { K.LOOTED, 10, { [LINEN] = 1 } },   -- vendor 20, market 105
        { K.LOOTED, 0, { [LINEN] = 3 } },    -- vendor 30, market 285
        { K.EMPTY },                         -- 0
        { K.UNSEEN },
      }), Prices(), opts)
      assert.same({ 4, 3 }, { stats.kills, stats.seen })
      assert.same({ 20, 50 / 3 }, { stats.vendor.median, stats.vendor.average })
      assert.same({ 105, 130 }, { stats.market.median, stats.market.average })
    end)

    it("prices a thin market at vendor and flags items with no market price", function()
      local stats = M.Stats(Mob({
        { K.LOOTED, 0, { [FANG] = 1 } }, { K.LOOTED, 0, { [FANG] = 1 } }, { K.LOOTED, 0, { [DUSTLESS] = 1 } },
      }), Prices(), opts)
      assert.equal(50, stats.market.median)            -- FANG has thin supply
      assert.same({ [DUSTLESS] = true }, stats.market.unpriced)
      assert.near(100 / 3, stats.market.average, 1e-9)  -- DUSTLESS counts 0c
    end)

    it("uses disenchanting in Optimal only when it is on", function()
      local mob = Mob({ { K.LOOTED, 0, { [RING] = 1 } }, { K.LOOTED, 0, {} }, { K.LOOTED, 0, { [RING] = 1 } } })
      local off = M.Stats(mob, Prices(), opts)
      assert.same({ 950, "Optimal" }, { off.optimal.median, off.optimal.label })
      opts.disenchant = true
      local on = M.Stats(mob, Prices(), opts)
      assert.same({ 4750, "Optimal (incl. DE)" }, { on.optimal.median, on.optimal.label })
    end)

    it("adds skinning to Optimal when it is on, and has its own lens from gathered kills", function()
      local mob = Mob({
        { K.LOOTED, 0, {}, { [LEATHER] = 2 } }, { K.EMPTY, nil, nil, { [LEATHER] = 1 } }, { K.LOOTED, 0, {} },
      })
      local stats = M.Stats(mob, Prices(), opts)
      assert.same({ 2, 57, 0 }, { stats.skinning.n, stats.skinning.median, stats.optimal.average })
      opts.skinning, opts.disenchant = true, true
      stats = M.Stats(mob, Prices(), opts)
      assert.same({ 38, "Optimal (incl. skinning, DE)" }, { stats.optimal.average, stats.optimal.label })
    end)

    it("leaves rare drops out of Optimal without rare drops", function()
      local kills = {}
      for i = 1, 99 do kills[i] = { K.LOOTED, 0, { [LINEN] = 1 } } end
      kills[100] = { K.LOOTED, 0, { [LINEN] = 1, [RING] = 1 } }   -- 1% of kills
      local stats = M.Stats(Mob(kills), Prices(), opts)
      assert.near(95 + 9.5, stats.optimal.average, 1e-9)
      assert.near(95, stats.optimalNoRare.average, 1e-9)
    end)

    it("names the drop that carries the most value and how often it drops", function()
      local stats = M.Stats(Mob({
        { K.LOOTED, 0, { [LINEN] = 1 } }, { K.LOOTED, 0, { [LINEN] = 1 } },
        { K.LOOTED, 0, { [LINEN] = 1, [RING] = 1 } }, { K.EMPTY },
      }), Prices(), opts)
      assert.same({ id = RING, share = 0.25 }, stats.top)
    end)

    it("leaves rare drops out of every lens's without-rare values", function()
      local kills = {}
      for i = 1, 99 do kills[i] = { K.LOOTED, 0, { [LINEN] = 1 } } end
      kills[100] = { K.LOOTED, 0, { [LINEN] = 1, [RING] = 1 } }
      local stats = M.Stats(Mob(kills), Prices(), opts)
      assert.same({ 10, 95 }, { stats.vendorNoRare.average, stats.marketNoRare.average })
      assert.near(10 + 1, stats.vendor.average, 1e-9)
    end)
  end)

  describe("DropTable", function()
    local opts
    local prices = {
      vendor = function(id) return ({ [LINEN] = 10, [RING] = 100 })[id] end,
      wall = function(id) return ({ [LINEN] = 100, [RING] = 1000 })[id], true end,
      disenchant = function(id) return id == RING and 5000 or nil end,
    }

    local function Mob()
      local mobs = {}
      M.Add(mobs, KillEvent(1, K.LOOTED, 0, { [LINEN] = 1 }))
      M.Add(mobs, KillEvent(2, K.LOOTED, 0, { [LINEN] = 3, [RING] = 1 }))
      M.Add(mobs, KillEvent(3, K.EMPTY))
      M.Add(mobs, KillEvent(4, K.UNSEEN))
      return mobs[WOLF]
    end

    before_each(function()
      opts = { cut = 0.05, disenchant = false, skinning = false, rareShare = 0.02, minKills = 3 }
    end)

    it("gives each drop's share of seen kills, its quantity when it drops and one unit's value per lens", function()
      local rows = M.DropTable(Mob(), prices, opts)
      assert.equal(2, #rows)
      assert.same({ id = RING, share = 1 / 3, quantity = 1, vendor = 100, market = 950, optimal = 950 }, rows[1])
      assert.same({ id = LINEN, share = 2 / 3, quantity = 2, vendor = 10, market = 95, optimal = 95 }, rows[2])
    end)

    it("prices Optimal at disenchanting when it is included and worth more", function()
      opts.disenchant = true
      assert.equal(4750, M.DropTable(Mob(), prices, opts)[1].optimal)
    end)

    it("is empty for a mob whose kills dropped nothing", function()
      local mobs = {}
      M.Add(mobs, KillEvent(1, K.EMPTY))
      assert.same({}, M.DropTable(mobs[WOLF], prices, opts))
    end)
  end)
end)
