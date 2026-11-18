local addon = require("spec.helpers.addon")

local MIN_DAYS = 5

local function Plain(text)
  return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

describe("Bait", function()
  local ns, B, W
  before_each(function()
    ns = addon.Load()
    B, W = ns.Bait, ns.Wall
  end)

  -- Four past days with the wall at 100, so the normal range is 100 to 100
  local function History()
    return W.Stats({ 95, 100, 100, 105 })
  end

  -- 1 bait unit at 30 under a wall of 100
  local function Baited(extra)
    local map = { [30] = 1 + (extra or 0), [100] = 200, [110] = 600 }
    return (W.SortLadder(map))
  end

  describe("detection", function()
    it("flags a thin level under the wall and the normal range once it persists", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_DAYS, 1000)
      assert.is_false(B.Flagged(record))
      record = B.Update(record, Baited(), 100, History(), MIN_DAYS, 2000)
      assert.is_true(B.Flagged(record))
      assert.same({ 30, 1, 1000, 2000 }, { record.p, record.u, record.first, record.last })
    end)

    it("does not flag without enough history", function()
      local short = W.Stats({ 100, 100 })
      local record = B.Update(nil, Baited(), 100, short, MIN_DAYS, 1)
      assert.is_nil(B.Update(record, Baited(), 100, short, MIN_DAYS, 2))
      assert.is_nil(B.Update(nil, Baited(), 100, W.Stats({}), MIN_DAYS, 1))
    end)

    it("does not flag a cheapest level at the wall", function()
      local ladder = W.SortLadder({ [100] = 200, [110] = 600 })
      assert.is_nil(B.Update(nil, ladder, 100, History(), MIN_DAYS, 1))
    end)

    it("does not flag a cheap level that is within the normal range", function()
      local wide = W.Stats({ 20, 60, 100, 140 })   -- normal range starts at 50
      local ladder = W.SortLadder({ [55] = 1, [100] = 200 })
      assert.is_nil(B.Update(nil, ladder, 100, wide, MIN_DAYS, 1))
    end)

    it("starts over when the cheapest price changes", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_DAYS, 1)
      record = B.Update(record, Baited(), 100, History(), MIN_DAYS, 2)
      local undercut = W.SortLadder({ [25] = 1, [30] = 1, [100] = 200 })
      record = B.Update(record, undercut, 100, History(), MIN_DAYS, 3)
      assert.equal(25, record.p)
      assert.is_false(B.Flagged(record))
    end)

    it("counts copies posted at the bait price since it appeared", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_DAYS, 1)
      record = B.Update(record, Baited(14), 100, History(), MIN_DAYS, 2)
      assert.equal(14, B.Copies(record))
      assert.equal(1, record.u)
    end)

    it("clears the record when the bait level is gone", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_DAYS, 1)
      local clean = W.SortLadder({ [100] = 200, [110] = 600 })
      assert.is_nil(B.Update(record, clean, 100, History(), MIN_DAYS, 2))
      assert.is_nil(B.Update(record, {}, nil, History(), MIN_DAYS, 2))
    end)

    it("lists piling-up items first, then the furthest under the wall", function()
      local piling = { p = 50, u = 1, q = 5, w = 100 }
      local deep = { p = 10, u = 1, q = 1, w = 100 }
      local shallow = { p = 40, u = 1, q = 1, w = 100 }
      local items = { shallow, deep, piling }
      table.sort(items, B.Before)
      assert.same({ piling, deep, shallow }, items)
    end)
  end)

  describe("saved records", function()
    local fire
    before_each(function()
      ns, fire = addon.Load()
      fire("ADDON_LOADED", addon.ADDON)
      B, W = ns.Bait, ns.Wall
    end)

    it("keeps commodities only", function()
      ns.UpdateBait(7, Baited(), 100, History(), 1, true)
      assert.is_table(ns.R().bait[7])
      _G.C_Item = { GetItemMaxStackSizeByID = function() return 1 end }
      ns.UpdateBait(8, Baited(), 100, History(), 1)
      _G.C_Item = nil
      assert.is_nil(ns.R().bait[8])
    end)
  end)

  describe("buy plan", function()
    -- bait (1) + 14 copies at 30, 4 units at 35, the wall at 100
    local ladder, record
    before_each(function()
      ladder = W.SortLadder({ [30] = 15, [35] = 4, [100] = 200 })
      record = { p = 30, u = 1, q = 15, w = 100 }
    end)

    it("leaves the bait's units and stops at the bait level", function()
      local plan = B.Plan(ladder, 35, record, true)
      assert.same({ qty = 14, cost = 14 * 30, leaving = 1, blocked = 4 }, plan)
    end)

    it("buys the bait and every level at or below the threshold", function()
      local plan = B.Plan(ladder, 35, record, false)
      assert.same({ qty = 19, cost = 15 * 30 + 4 * 35, leaving = 0, blocked = 0 }, plan)
    end)

    it("includes a level exactly at the threshold and not one just above", function()
      assert.equal(19, B.Plan(ladder, 35, record, false).qty)
      assert.equal(15, B.Plan(ladder, 34, record, false).qty)
    end)

    it("buys several cheap levels when there is no bait to leave", function()
      local plan = B.Plan(ladder, 35, nil, true)
      assert.same({ qty = 19, cost = 15 * 30 + 4 * 35, leaving = 0, blocked = 0 }, plan)
    end)

    it("leaves only the bait units still listed", function()
      local partly = W.SortLadder({ [30] = 1, [100] = 200 })
      record.u = 2
      assert.same({ qty = 0, cost = 0, leaving = 1, blocked = 0 }, B.Plan(partly, 30, record, true))
    end)

    it("buys nothing under the bait price", function()
      assert.same({ qty = 0, cost = 0, leaving = 0, blocked = 0 }, B.Plan(ladder, 29, record, true))
    end)
  end)

  describe("price quote", function()
    it("accepts a quote with every unit within the threshold", function()
      assert.is_true(B.QuoteOK(35, 14 * 30, 14, 35))
    end)

    it("rejects a quote over the threshold and says why", function()
      local ok, reason = B.QuoteOK(36, 14 * 30, 14, 35)
      assert.is_false(ok)
      assert.equal("Price rose over 35c", Plain(reason))
      assert.is_false(B.QuoteOK(nil, 14 * 36, 14, 35))
      assert.is_false(B.QuoteOK(nil, nil, 14, 35))
    end)
  end)

  describe("action button", function()
    local GAP = 1
    local s
    before_each(function() s = B.NewButton() end)

    local function Label(action, wait)
      return Plain(B.Label(s, "Thorium Bar", action, wait))
    end

    it("searches, finds a deal, buys, confirms with a press and searches again", function()
      assert.equal("search", B.NextAction(s, 0, GAP, true))
      assert.equal("Search Thorium Bar", Label("search"))
      B.Searched(s, 0)
      assert.equal("busy", B.NextAction(s, 0.5, GAP, true))

      local found = B.Found(s, { qty = 18, cost = 560, leaving = 1, blocked = 0 }, 35)
      assert.is_true(found)
      assert.equal("buy", B.NextAction(s, 2, GAP, true))
      assert.equal("Buy 18 Thorium Bar at up to 35c (5s 60c), leaving 1", Label("buy"))

      B.Started(s, 2)
      assert.equal("busy", B.NextAction(s, 3, GAP, true))
      B.Quoted(s, 560, true, nil, true, 3)
      assert.equal("confirm", B.NextAction(s, 4, GAP, true))
      assert.equal("Confirm 18 Thorium Bar for 5s 60c", Label("confirm"))

      B.Confirmed(s, 4)
      assert.equal("busy", B.NextAction(s, 5, GAP, true))
      B.Finished(s, "Bought 18 for 5s 60c")
      assert.equal("search", B.NextAction(s, 6, GAP, true))
    end)

    it("confirms without a press when the setting allows it", function()
      B.Found(s, { qty = 1, cost = 30, leaving = 0, blocked = 0 }, 30)
      B.Started(s, 0)
      B.Quoted(s, 30, true, nil, false, 1)
      assert.equal("buying", s.phase)
    end)

    it("says when nothing is at or below the threshold", function()
      B.Searched(s, 0)
      assert.is_false(B.Found(s, { qty = 0, cost = 0, leaving = 0, blocked = 0 }, 35))
      assert.equal("Nothing at or below 35c · Search again", Label("search"))
      assert.equal("search", B.NextAction(s, 5, GAP, true))
    end)

    it("waits out the minimum gap and the game's throttle without doing anything", function()
      B.Searched(s, 10)
      B.Found(s, { qty = 0, cost = 0, leaving = 0, blocked = 0 }, 35)
      local action, wait = B.NextAction(s, 10.2, GAP, true)
      assert.same({ "wait", 1 }, { action, wait })
      assert.equal("Waiting 1s", Label(action, wait))
      assert.same({ "wait", 3 }, { B.NextAction(s, 10.2, 3, true) })
      assert.equal("wait", (B.NextAction(s, 20, GAP, false)))
      assert.equal("nothing", s.phase)   -- waiting changed nothing
    end)

    it("cancels a quote over the threshold and shows the reason", function()
      B.Found(s, { qty = 18, cost = 560, leaving = 1, blocked = 0 }, 35)
      B.Started(s, 0)
      B.Quoted(s, 900, false, "Price rose over 35c", true, 1)
      assert.equal("search", B.NextAction(s, 2, GAP, true))
      assert.equal("Price rose over 35c · Search Thorium Bar", Label("search"))
    end)

    it("lets a press reset a purchase the game never answered", function()
      B.Found(s, { qty = 1, cost = 30, leaving = 0, blocked = 0 }, 30)
      B.Started(s, 0)
      assert.equal("busy", B.NextAction(s, B.STALE_PURCHASE, GAP, true))
      assert.equal("reset", B.NextAction(s, B.STALE_PURCHASE + 1, GAP, true))
    end)

    it("recomputes the deal when the threshold changes after a search", function()
      B.Found(s, { qty = 0, cost = 0, leaving = 0, blocked = 0 }, 29)
      B.Replan(s, { qty = 14, cost = 420, leaving = 1, blocked = 0 }, 30)
      assert.equal("buy", B.NextAction(s, 5, GAP, true))
      B.Started(s, 5)
      B.Replan(s, { qty = 0, cost = 0, leaving = 0, blocked = 0 }, 1)
      assert.equal("quote", s.phase)   -- never changes a purchase in flight
    end)
  end)
end)
