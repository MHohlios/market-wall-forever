local addon = require("spec.helpers.addon")

local MIN_UNDER = 0.5

local Plain = addon.Plain

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
      local record = B.Update(nil, Baited(), 100, History(), MIN_UNDER,1000)
      assert.is_false(B.Flagged(record))
      record = B.Update(record, Baited(), 100, History(), MIN_UNDER,2000)
      assert.is_true(B.Flagged(record))
      assert.same({ 30, 1, 1000, 2000 }, { record.p, record.u, record.first, record.last })
    end)

    it("flags from an item's first day, against today's wall, but still only after two scans", function()
      local firstScan = W.Stats({}, 100)
      local record = B.Update(nil, Baited(), 100, firstScan, MIN_UNDER, 1)
      assert.is_false(B.Flagged(record))
      assert.is_true(B.Flagged(B.Update(record, Baited(), 100, firstScan, MIN_UNDER, 2)))
    end)

    it("does not flag an item with no normal price at all", function()
      assert.is_nil(B.Update(nil, Baited(), 100, W.Stats({}), MIN_UNDER, 1))
    end)

    -- Silk Cloth as the owner saw it: 110 units at 1s 98c under a 2s 5c wall
    local function Undercut()
      return (W.SortLadder({ [198] = 110, [205] = 400, [210] = 900 }))
    end
    local function NearWall()
      return W.Stats({ 205, 210, 210, 215 })
    end

    it("does not flag ordinary undercutting a few percent under the wall", function()
      local record = B.Update(nil, Undercut(), 205, NearWall(), MIN_UNDER, 1)
      assert.is_nil(B.Update(record, Undercut(), 205, NearWall(), MIN_UNDER, 2))
    end)

    it("flags a level far under the wall after two scans", function()
      local ladder = W.SortLadder({ [20] = 2, [200] = 400, [205] = 900 })
      local stats = W.Stats({ 195, 200, 200, 205 })
      local record = B.Update(nil, ladder, 200, stats, MIN_UNDER, 1)
      assert.is_false(B.Flagged(record))
      assert.is_true(B.Flagged(B.Update(record, ladder, 200, stats, MIN_UNDER, 2)))
    end)

    it("moves the boundary with the minimum under the wall", function()
      local half = W.SortLadder({ [50] = 1, [100] = 200 })
      assert.is_table(B.Update(nil, half, 100, History(), 0.5, 1))
      assert.is_nil(B.Update(nil, half, 100, History(), 0.75, 1))
      local quarter = W.SortLadder({ [25] = 1, [100] = 200 })
      assert.is_table(B.Update(nil, quarter, 100, History(), 0.75, 1))
    end)

    it("keeps a level exactly at the minimum under the wall", function()
      local ninety = W.SortLadder({ [90] = 1, [100] = 200 })
      local eighty = W.SortLadder({ [80] = 1, [100] = 200 })
      assert.is_table(B.Update(nil, ninety, 100, History(), 0.10, 1))
      assert.is_table(B.Update(nil, eighty, 100, History(), 0.20, 1))
      assert.is_nil(B.Update(nil, W.SortLadder({ [81] = 1, [100] = 200 }), 100, History(), 0.20, 1))
    end)

    it("holds the setting to 10% to 95%", function()
      assert.same({ 0.10, 0.5, 0.95 }, { B.MinUnder(0), B.MinUnder(0.5), B.MinUnder(1) })
    end)

    it("does not flag a cheapest level at the wall", function()
      local ladder = W.SortLadder({ [100] = 200, [110] = 600 })
      assert.is_nil(B.Update(nil, ladder, 100, History(), MIN_UNDER,1))
    end)

    it("does not flag a cheap level that is within the normal range", function()
      local wide = W.Stats({ 20, 60, 100, 140 })   -- normal range starts at 50
      local ladder = W.SortLadder({ [55] = 1, [100] = 200 })
      assert.is_nil(B.Update(nil, ladder, 100, wide, MIN_UNDER,1))
    end)

    it("starts over when the cheapest price changes", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_UNDER,1)
      record = B.Update(record, Baited(), 100, History(), MIN_UNDER,2)
      local undercut = W.SortLadder({ [25] = 1, [30] = 1, [100] = 200 })
      record = B.Update(record, undercut, 100, History(), MIN_UNDER,3)
      assert.equal(25, record.p)
      assert.is_false(B.Flagged(record))
    end)

    it("counts copies posted at the bait price since it appeared", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_UNDER,1)
      record = B.Update(record, Baited(14), 100, History(), MIN_UNDER,2)
      assert.equal(14, B.Copies(record))
      assert.equal(1, record.u)
    end)

    it("clears the record when the bait level is gone", function()
      local record = B.Update(nil, Baited(), 100, History(), MIN_UNDER,1)
      local clean = W.SortLadder({ [100] = 200, [110] = 600 })
      assert.is_nil(B.Update(record, clean, 100, History(), MIN_UNDER,2))
      assert.is_nil(B.Update(record, {}, nil, History(), MIN_UNDER,2))
    end)

    it("lists piling-up items first, then the furthest under the wall", function()
      local piling = { p = 50, u = 1, q = 5, w = 100, seen = 2 }
      local deep = { p = 10, u = 1, q = 1, w = 100, seen = 2 }
      local shallow = { p = 40, u = 1, q = 1, w = 100, seen = 2 }
      local items = { shallow, deep, piling }
      table.sort(items, B.Before)
      assert.same({ piling, deep, shallow }, items)
    end)

    it("lists confirmed items before items seen once", function()
      local confirmed = { p = 40, u = 1, q = 1, w = 100, seen = 2 }
      local deepOnce = { p = 10, u = 1, q = 1, w = 100, seen = 1 }
      local items = { deepOnce, confirmed }
      table.sort(items, B.Before)
      assert.same({ confirmed, deepOnce }, items)
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

    it("clears a saved flag whose level no longer qualifies", function()
      local stale = { p = 198, u = 110, q = 160, w = 205, first = 1, last = 1, seen = 2 }
      ns.R().bait[7] = stale
      local ladder = W.SortLadder({ [198] = 160, [205] = 400 })
      ns.UpdateBait(7, ladder, 205, W.Stats({ 205, 210, 210, 215 }), 3, true)
      assert.is_nil(ns.R().bait[7])
    end)

    it("reads the minimum under the wall from the settings", function()
      local ladder, stats = W.SortLadder({ [40] = 1, [100] = 200 }), History()
      ns.UpdateBait(7, ladder, 100, stats, 1, true)
      assert.is_table(ns.R().bait[7])
      MarketWallDB.cfg.baitMinUnder = 0.7
      ns.UpdateBait(7, ladder, 100, stats, 2, true)
      assert.is_nil(ns.R().bait[7])
    end)

    it("leaves the record untouched while the item's commodity status is unknown", function()
      local record = { p = 30, u = 1, q = 3, w = 100, first = 1, last = 1, seen = 2 }
      ns.R().bait[9] = record
      ns.UpdateBait(9, W.SortLadder({ [100] = 200 }), 100, History(), 5)   -- no item info loaded
      assert.equal(record, ns.R().bait[9])
      assert.same({ p = 30, u = 1, q = 3, w = 100, first = 1, last = 1, seen = 2 }, record)
    end)

    -- a live search updates the record the same way, with the commodity known
    it("confirms a record seen once when a live search still finds the bait level", function()
      ns.UpdateBait(7, Baited(), 100, History(), 1, true)
      assert.is_false(B.Flagged(ns.R().bait[7]))
      ns.UpdateBait(7, Baited(), 100, History(), 2, true)
      assert.is_true(B.Flagged(ns.R().bait[7]))
    end)

    it("drops a record seen once when a live search no longer finds the bait level", function()
      ns.UpdateBait(7, Baited(), 100, History(), 1, true)
      ns.UpdateBait(7, W.SortLadder({ [100] = 200 }), 100, History(), 2, true)
      assert.is_nil(ns.R().bait[7])
    end)

    it("drops every record the latest full scan did not refresh", function()
      local function Record(last) return { p = 30, u = 1, q = 1, w = 100, first = 1, last = last, seen = 2 } end
      ns.R().bait[7], ns.R().bait[8], ns.R().bait[9] = Record(5), Record(10), Record(12)
      ns.ClearStaleBait(10)
      assert.is_nil(ns.R().bait[7])
      assert.is_table(ns.R().bait[8])
      assert.is_table(ns.R().bait[9])   -- a live search after the scan started
    end)

    it("logs each purchase with item, units, unit price, total and time", function()
      ns.AddPosition(7, 14, 420)
      local entry = ns.R().buys[1]
      assert.same({ id = 7, qty = 14, unit = 30, total = 420 }, { id = entry.id, qty = entry.qty, unit = entry.unit, total = entry.total })
      assert.is_number(entry.t)
    end)
  end)

  describe("searching on a press", function()
    local fire, sent, keyInfo, ready, hasResults, answers
    before_each(function()
      ns, fire = addon.Load()
      fire("ADDON_LOADED", addon.ADDON)
      ns.ahOpen = true
      sent, keyInfo, ready, hasResults, answers = 0, nil, true, false, {}
      _G.GetTime = function() return 0 end
      _G.C_AuctionHouse = {
        MakeItemKey = function(id) return { itemID = id } end,
        GetItemKeyInfo = function() return keyInfo end,
        IsThrottledMessageSystemReady = function() return ready end,
        SendSearchQuery = function() sent = sent + 1 end,
        HasSearchResults = function() return hasResults end,
        HasFullCommoditySearchResults = function() return true end,
        GetCommoditySearchResultsQuantity = function() return 3 end,
        GetNumCommoditySearchResults = function() return 1 end,
        GetCommoditySearchResultInfo = function() return { unitPrice = 30, quantity = 3 } end,
      }
    end)
    after_each(function() _G.C_AuctionHouse, _G.GetTime = nil, nil end)

    local function Search()
      return ns.SearchNow(1, function(answered) answers[#answers + 1] = answered end)
    end

    it("sends the search during the press", function()
      keyInfo = {}
      assert.is_true(Search())
      assert.equal(1, sent)
    end)

    it("sends nothing, now or later, while the item's info is loading or searches are throttled", function()
      assert.is_false(Search())
      keyInfo, ready = {}, false
      assert.is_false(Search())
      assert.is_falsy(ns.scanState.running)   -- no scan left waiting to send later
      assert.equal(0, sent)
    end)

    it("reports an answered search", function()
      keyInfo, hasResults = {}, true
      Search()
      fire("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
      assert.same({ true }, answers)
      assert.equal(30, ns.ladders[1].ladder[1].p)
    end)

    -- saved, so a reload keeps what the latest search saw (mob values read it)
    it("saves whether the search saw real supply, replacing the full scan's verdict", function()
      ns.R().supplied[1] = true
      keyInfo, hasResults = {}, true
      Search()
      fire("COMMODITY_SEARCH_RESULTS_UPDATED", 1)   -- 3 units, under minSupply
      assert.is_nil(MarketWallDB.realms[ns.Realm()].supplied[1])
      MarketWallDB.cfg.minSupply = 3
      Search()
      fire("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
      assert.is_true(MarketWallDB.realms[ns.Realm()].supplied[1])
    end)

    it("records nothing when the search gets no answer", function()
      local record = { p = 30, u = 1, q = 3, w = 100, first = 1, last = 1, seen = 2 }
      local cur = { t = 1, w = 100, q = 50 }
      ns.R().bait[1], ns.R().watch[1] = record, { cur = cur }
      keyInfo = {}
      Search()
      fire("COMMODITY_SEARCH_RESULTS_UPDATED", 1)   -- an empty response
      assert.same({ false }, answers)
      assert.equal(record, ns.R().bait[1])
      assert.equal(cur, ns.R().watch[1].cur)
      assert.is_nil(ns.ladders[1])
      assert.equal(1, sent)   -- and it did not retry
    end)

    it("reports a search stopped by closing the auction house as unanswered", function()
      keyInfo = {}
      Search()
      ns.OnAuctionHouseClosed()
      assert.same({ false }, answers)
    end)
  end)

  describe("commodity purchase", function()
    local fire, confirmed, ended
    before_each(function()
      ns, fire = addon.Load()
      fire("ADDON_LOADED", addon.ADDON)
      confirmed, ended = {}, {}
      _G.C_AuctionHouse = {
        StartCommoditiesPurchase = function() end,
        CancelCommoditiesPurchase = function() end,
        ConfirmCommoditiesPurchase = function(id, qty) confirmed[#confirmed + 1] = { id, qty } end,
      }
    end)
    after_each(function() _G.C_AuctionHouse = nil end)

    local function Start(id, qty)
      return ns.StartCommodityPurchase(id, qty, qty * 30, function() end,
        function(bought, note) ended[#ended + 1] = { id, bought, note } end)
    end

    it("tells the purchase's owner when it is cancelled", function()
      Start(1, 2)
      ns.CancelPurchase("Auction house closed")
      assert.same({ { 1, false, "Auction house closed" } }, ended)
    end)

    it("confirms only the purchase it was given", function()
      local stale = Start(1, 2)
      fire("COMMODITY_PRICE_UPDATED", 30, 60)
      ns.CancelPurchase()
      local current = Start(2, 5)
      fire("COMMODITY_PRICE_UPDATED", 30, 150)
      assert.is_false(ns.ConfirmPurchase(stale))
      assert.same({}, confirmed)
      assert.is_true(ns.ConfirmPurchase(current))
      assert.same({ { 2, 5 } }, confirmed)
    end)

    it("does not confirm before the game has quoted a price", function()
      local purchase = Start(1, 2)
      assert.is_false(ns.ConfirmPurchase(purchase))
    end)
  end)

  describe("buy plan", function()
    -- bait (1) + 14 copies at 30, 4 units at 35, the wall at 100
    local ladder, record
    before_each(function()
      ladder = W.SortLadder({ [30] = 15, [35] = 4, [100] = 200 })
      record = { p = 30, u = 1, q = 15, w = 100, seen = 2 }
    end)

    it("leaves the bait's units and stops at the bait level", function()
      local plan = B.Plan(ladder, 35, record, true)
      assert.same({ qty = 14, cost = 14 * 30, leaving = 1, blocked = 4, leaveAt = 30 }, plan)
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
      assert.same({ qty = 0, cost = 0, leaving = 1, blocked = 0, leaveAt = 30 }, B.Plan(partly, 30, record, true))
    end)

    it("buys nothing under the bait price", function()
      assert.same({ qty = 0, cost = 0, leaving = 0, blocked = 0 }, B.Plan(ladder, 29, record, true))
    end)

    it("keeps the bait a search saw after a later scan changes or clears the record", function()
      local seen = B.Snapshot(ladder, record)
      record.p, record.u = 25, 3                  -- a scan found a new cheapest level
      assert.is_nil(B.Update(record, W.SortLadder({ [100] = 200 }), 100, History(), MIN_UNDER,2))
      local plan = B.Plan(seen.ladder, 35, seen.bait, true)
      assert.same({ 1, 30 }, { plan.leaving, plan.leaveAt })
    end)

    it("keeps no bait from a search that saw it only once", function()
      record.seen = 1
      assert.is_nil(B.Snapshot(ladder, record).bait)
    end)
  end)

  describe("Leave bait after a full scan", function()
    local ID = 7
    local pending, purchases, page

    -- Frames whose Create* methods return frames, so the Bait Detect page can be built
    local function PageFrames()
      local plainFrame = CreateFrame
      local function NewPageFrame(...)
        local frame = plainFrame(...)
        frame.CreateTexture = function() return NewPageFrame() end
        frame.CreateFontString = function() return NewPageFrame() end
        frame.IsVisible = function() return true end
        return frame
      end
      _G.CreateFrame = NewPageFrame
    end

    before_each(function()
      local fire
      ns, fire = addon.Load()
      fire("ADDON_LOADED", addon.ADDON)
      B, W = ns.Bait, ns.Wall
      PageFrames()
      page = ns.BuildBaitPage(CreateFrame("Frame"))
      ns.ahOpen = true
      pending, purchases = nil, {}
      _G.GetTime = function() return 100 end
      _G.GetMoney = function() return 1e9 end
      _G.C_AuctionHouse = { IsThrottledMessageSystemReady = function() return true end }
      ns.SearchNow = function(_, onDone) pending = onDone return true end
      ns.StartCommodityPurchase = function(id, qty) purchases[#purchases + 1] = { id, qty } return {} end
      ns.R().bait[ID] = { p = 30, u = 1, q = 15, w = 100, first = 1, last = 1, seen = 2 }
    end)
    after_each(function() _G.C_AuctionHouse, _G.GetTime, _G.GetMoney = nil, nil, nil end)

    it("still leaves the bait the live search saw when a re-plan follows a full scan", function()
      page.list.onClick({ id = ID })              -- selecting searches; the bait price is the limit
      local ladder, total = W.SortLadder({ [30] = 15, [100] = 200 })
      ns.ladders[ID] = { ladder = ladder, total = total, t = os.time(), kind = "commodity" }
      pending(true)

      ns.R().bait[ID] = nil                       -- a full scan cleared the record
      page.take.scripts.OnClick()                 -- Buy bait, then back to Leave bait: re-plans
      page.leave.scripts.OnClick()

      ns.BaitPress()
      assert.same({ { ID, 14 } }, purchases)
    end)

    local function SearchSeenOnce(confirmedByIt)
      ns.R().bait[ID].seen = 1
      page.list.onClick({ id = ID })
      local ladder, total = W.SortLadder({ [30] = 15, [100] = 200 })
      ns.ladders[ID] = { ladder = ladder, total = total, t = os.time(), kind = "commodity" }
      if confirmedByIt then ns.R().bait[ID].seen = 2 end   -- as the search's own ns.UpdateBait does
      pending(true)
      _G.GetTime = function() return 200 end   -- past the search gap
    end

    it("offers no buy for bait the live search did not confirm", function()
      local label
      page.action.SetText = function(_, text) label = text end
      SearchSeenOnce(false)
      ns.RefreshBait()
      assert.equal("Not confirmed as bait · Search " .. ns.Name(ID), Plain(label))
      ns.BaitPress()                              -- searches again; never buys
      assert.same({}, purchases)
    end)

    it("buys once the live search confirms a row seen once", function()
      SearchSeenOnce(true)
      ns.BaitPress()
      assert.same({ { ID, 14 } }, purchases)
    end)

    it("lists rows seen once dimmed, after confirmed rows, and counts both in the status line", function()
      ns.R().bait[8] = { p = 10, u = 1, q = 1, w = 100, first = 1, last = 1, seen = 1 }
      ns.R().bait[9] = { p = 20, u = 1, q = 1, w = 100, first = 1, last = 1, seen = 1 }
      local rows = ns.BaitListData()
      assert.same({ ID, false }, { rows[1].id, rows[1].dim })
      assert.same({ true, "seen once" }, { rows[2].dim, rows[2].cells[6] })
      ns.RefreshBait()
      assert.equal("1 possibly baited · 2 seen once", ns.ui.statusNote)
      ns.R().bait[ID] = nil
      ns.RefreshBait()
      assert.equal("2 seen once", ns.ui.statusNote)
    end)
  end)

  describe("price quote", function()
    describe("when leaving the bait", function()
      -- planned: 14 copies at 30, threshold 35
      it("accepts only every unit at the bait price", function()
        assert.is_true(B.QuoteOK(30, 14 * 30, 14, 35, 30))
      end)

      it("cancels when copies were bought since the search", function()
        -- 14 units are now 5 at 30 (the bait included) and 9 at 35
        local ok, reason = B.QuoteOK(35, 5 * 30 + 9 * 35, 14, 35, 30)
        assert.is_false(ok)
        assert.equal("Supply changed", reason)
      end)

      it("cancels when cheaper units appeared and copies were bought", function()
        -- 14 units are now 13 at 25 and the bait at 30: cheaper on average, bait included
        assert.same({ false, "Supply changed" }, { B.QuoteOK(30, 13 * 25 + 30, 14, 35, 30) })
      end)
    end)

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
      B.Searched(s)
      assert.equal("busy", B.NextAction(s, 0.5, GAP, true, 0))

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
      B.Searched(s)
      assert.is_false(B.Found(s, { qty = 0, cost = 0, leaving = 0, blocked = 0 }, 35))
      assert.equal("Nothing at or below 35c · Search again", Label("search"))
      assert.equal("search", B.NextAction(s, 5, GAP, true, 0))
    end)

    it("keeps the minimum gap when switching to another item", function()
      -- the last search, for the previous item, went out at 10
      local other = B.NewButton()
      assert.equal("wait", (B.NextAction(other, 10.5, GAP, true, 10)))
      assert.equal("search", (B.NextAction(other, 11, GAP, true, 10)))
    end)

    it("waits out the minimum gap and the game's throttle without doing anything", function()
      B.Searched(s)
      B.Found(s, { qty = 0, cost = 0, leaving = 0, blocked = 0 }, 35)
      local action, wait = B.NextAction(s, 10.2, GAP, true, 10)
      assert.same({ "wait", 1 }, { action, wait })
      assert.equal("Waiting 1s", Label(action, wait))
      assert.same({ "wait", 3 }, { B.NextAction(s, 10.2, 3, true, 10) })
      assert.equal("wait", (B.NextAction(s, 20, GAP, false, 10)))
      assert.equal("nothing", s.phase)   -- waiting changed nothing
    end)

    it("goes back to Search after a search that was stopped or got no answer", function()
      B.Searched(s)
      B.Unanswered(s)
      assert.equal("search", B.NextAction(s, 5, GAP, true, 0))
      assert.equal("Search Thorium Bar", Label("search"))
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

    it("asks to cancel a quoted purchase when the limit or the bait choice changes", function()
      local none = { qty = 0, cost = 0, leaving = 0, blocked = 0 }
      B.Found(s, { qty = 2, cost = 60, leaving = 0, blocked = 0 }, 30)
      assert.is_false(B.Replan(s, none, 20))
      B.Found(s, { qty = 2, cost = 60, leaving = 0, blocked = 0 }, 30)
      B.Started(s, 0)
      assert.is_true(B.Replan(s, none, 20))
      B.Quoted(s, 60, true, nil, true, 1)
      assert.is_true(B.Replan(s, none, 20))
      B.Confirmed(s, 2)
      assert.is_false(B.Replan(s, none, 20))   -- already confirmed: nothing left to cancel
    end)
  end)
end)
