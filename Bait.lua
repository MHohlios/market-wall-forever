-- MarketWall: pure bait logic. No game API in this file so it can be tested outside the game.
--
-- Baiting: a seller posts a unit or two far under the market so others copy that price,
-- then buys the copies and relists them. The newest listing at a price sells first.
local _, ns = ...
local B = {}
ns.Bait = B

local SCANS_TO_FLAG = 2
-- Keeps exact edges inside their limits: 1000 * 0.03 and 1 - 80/100 both land just under in floating point
local EDGE = 1e-9
B.STALE_PURCHASE = 10   -- seconds a quote or purchase may stay unanswered before a press resets it

local function UnitsAt(ladder, price)
  for i = 1, #ladder do
    if ladder[i].p == price then return ladder[i].q end
    if ladder[i].p > price then break end
  end
  return 0
end

-- The range the "minimum % under the wall" setting is held to
B.MIN_UNDER, B.MAX_UNDER = 0.10, 0.95

function B.MinUnder(setting)
  return math.min(B.MAX_UNDER, math.max(B.MIN_UNDER, setting))
end

-- The cheapest level when it sits at least minUnder under the wall (0.5 is half the wall's
-- price) and below the item's normal range. Ordinary undercutting stays close to the wall.
-- stats come from ns.StatsFor, which falls back to today's wall on an item's first day.
local function Candidate(ladder, wall, stats, minUnder)
  local cheapest = ladder and ladder[1]
  if not cheapest or not wall or 1 - cheapest.p / wall + EDGE < minUnder then return nil end
  if not stats or stats.n == 0 or cheapest.p >= stats.p25 then return nil end
  return cheapest
end

-- One scan of an item: returns the new bait record, or nil when its cheapest level is not bait.
-- record: { p = bait price, u = units first seen, q = units now, w = wall, first =, last =, seen = scans }
function B.Update(record, ladder, wall, stats, minUnder, now)
  local level = Candidate(ladder, wall, stats, minUnder)
  if not level then return nil end
  if not record or record.p ~= level.p then
    return { p = level.p, u = level.q, q = level.q, w = wall, first = now, last = now, seen = 1 }
  end
  record.q = level.q
  record.u = math.min(record.u, level.q)   -- the original bait was partly bought
  record.w = wall
  record.last = now
  record.seen = math.min(record.seen + 1, SCANS_TO_FLAG)
  return record
end

-- Confirmed: a second full scan or a live search saw the same bait level. Only a confirmed
-- record plans a buy; one seen once is shown, dimmed, until then.
function B.Flagged(record)
  return record ~= nil and record.seen >= SCANS_TO_FLAG
end

-- Units posted at the bait price since it first appeared
function B.Copies(record)
  return math.max(0, record.q - record.u)
end

-- Under the wall as a fraction: 0.7 is 70% under
function B.Under(record)
  return 1 - record.p / record.w
end

-- The bait level's note, after the page's own word for it: "(1) + 14 copies"
function B.LevelNote(record)
  return string.format("(%d) + %d copies", record.u, B.Copies(record))
end

-- A warning when posting at price would match the bait: at its price or within band of it.
-- Returns nil when there is no bait record or the price is away from it. A record seen once
-- warns too: a needless warning costs nothing, a missed one costs gold.
function B.PostWarning(record, price, band)
  if not record or math.abs(price - record.p) > record.p * band + EDGE then return nil end
  return string.format("%d unit%s at %s sits %d%% under the %s wall. Likely bait; don't match it.",
    record.u, record.u == 1 and "" or "s", ns.Money(record.p), ns.Round(B.Under(record) * 100), ns.Money(record.w))
end

-- Confirmed items first, then piling-up items, then the furthest under the wall
function B.Before(a, b)
  local ca, cb = B.Flagged(a), B.Flagged(b)
  if ca ~= cb then return ca end
  local pa, pb = B.Copies(a) > 0, B.Copies(b) > 0
  if pa ~= pb then return pa end
  return B.Under(a) > B.Under(b)
end

-- A live search's ladder with the bait as that search saw it. The saved record changes with
-- every later scan, and a plan built from it could lose the bait it must leave.
-- bait is nil unless the record is confirmed: only confirmed bait is bought against.
function B.Snapshot(ladder, record)
  return { ladder = ladder, bait = B.Flagged(record) and { p = record.p, u = record.u } or nil }
end

-- What one buy would take. A commodity purchase always takes the cheapest units, so leaving
-- the bait means stopping at the bait level: higher levels cannot be reached without it.
-- Returns { qty, cost, leaving, blocked, leaveAt } where blocked counts units at or below the
-- threshold that sit above the bait and were left out to keep it, and leaveAt is the bait price
-- when the bait is left: no unit of the purchase may cost more than that.
function B.Plan(ladder, threshold, record, leaveBait)
  local plan = { qty = 0, cost = 0, leaving = 0, blocked = 0 }
  if not threshold then return plan end
  local leave = 0
  if leaveBait and record and record.p <= threshold then
    leave = math.min(record.u, UnitsAt(ladder, record.p))
  end
  local stopped = false
  for i = 1, #ladder do
    local level = ladder[i]
    if level.p > threshold then break end
    if stopped then
      plan.blocked = plan.blocked + level.q
    else
      local take = level.q
      if leave > 0 and level.p == record.p then
        take = level.q - leave
        plan.leaving, plan.leaveAt = leave, record.p
        stopped = true
      end
      plan.qty = plan.qty + take
      plan.cost = plan.cost + take * level.p
    end
  end
  return plan
end

-- The game quotes the final price before a commodity purchase completes. Accept it only when
-- no unit is over the threshold. unitPrice is the game's quoted unit price.
-- leaveAt: the bait price when leaving the bait. Every unit bought must then be a copy at
-- exactly that price; any other total means the supply changed since the search and the
-- cheapest-first purchase could take the bait.
function B.QuoteOK(unitPrice, totalPrice, qty, threshold, leaveAt)
  if not totalPrice or qty <= 0 then return false, "No price quoted" end
  if totalPrice / qty > threshold or (unitPrice and unitPrice > threshold) then
    return false, "Price rose over " .. ns.Money(threshold)
  end
  if leaveAt and totalPrice ~= qty * leaveAt then return false, "Supply changed" end
  return true
end

-------------------------------------------------------------------------------
-- The action button. Each press does exactly one thing; nothing is ever queued.
-- Phases: search, searching, deal, nothing, quote, confirm, buying.
-------------------------------------------------------------------------------
function B.NewButton()
  return { phase = "search" }
end

-- What a press would do now: "search", "buy", "confirm", "reset", "busy" or "wait" (with seconds).
-- gap: minimum seconds between searches. ready: the game's search throttle is open.
-- lastSearch: when the previous search went out, for any item, so switching items keeps the gap.
function B.NextAction(s, now, gap, ready, lastSearch)
  local phase = s.phase
  if phase == "deal" then return "buy" end
  if phase == "confirm" then return "confirm" end
  if phase == "searching" then return "busy" end
  if phase == "quote" or phase == "buying" then
    if now - s.since > B.STALE_PURCHASE then return "reset" end
    return "busy"
  end
  local left = gap - (now - (lastSearch or -math.huge))
  if left > 0 then return "wait", math.ceil(left) end
  if not ready then return "wait", 1 end
  return "search"
end

function B.Searched(s)
  s.phase, s.note, s.plan = "searching", nil, nil
end

-- The search was stopped or got no answer: nothing is known, so the next press searches again
function B.Unanswered(s)
  s.phase, s.note, s.plan = "search", nil, nil
end

-- Returns true when the search found a deal (play the sound)
function B.Found(s, plan, threshold)
  s.plan, s.threshold = plan, threshold
  s.phase = plan.qty > 0 and "deal" or "nothing"
  return plan.qty > 0
end

function B.Started(s, now)
  s.phase, s.since = "quote", now
end

-- ok: the quote is within the threshold. needPress: the confirm must be its own press.
function B.Quoted(s, total, ok, reason, needPress, now)
  if not ok then
    s.phase, s.note = "search", reason
  elseif needPress then
    s.phase, s.quoted = "confirm", total
  else
    s.phase, s.quoted, s.since = "buying", total, now
  end
end

function B.Confirmed(s, now)
  s.phase, s.since = "buying", now
end

-- The purchase finished or was cancelled; the next press searches again
function B.Finished(s, note)
  s.phase, s.note = "search", note
end

-- The threshold or the leave/buy choice changed after a search: recompute what to buy
-- Returns true when a purchase waiting on its quote or its confirm press must be cancelled,
-- because it was checked against the old values. Once confirmed it can no longer change.
function B.Replan(s, plan, threshold)
  if s.phase == "deal" or s.phase == "nothing" then B.Found(s, plan, threshold) end
  return s.phase == "quote" or s.phase == "confirm"
end

function B.Label(s, name, action, wait)
  if action == "wait" then return string.format("Waiting %ds", wait) end
  if action == "reset" then return "No answer from the game · Press to reset" end
  local phase, plan = s.phase, s.plan
  if phase == "searching" then return "Searching " .. name .. "..." end
  if phase == "quote" then return "Getting the price..." end
  if phase == "buying" then return "Buying..." end
  if phase == "deal" then
    local text = string.format("Buy %d %s at up to %s (%s)", plan.qty, name, ns.Money(s.threshold), ns.Money(plan.cost))
    if plan.leaving > 0 then text = text .. ", leaving " .. plan.leaving end
    return text
  end
  if phase == "confirm" then
    return string.format("Confirm %d %s for %s", plan.qty, name, ns.Money(s.quoted))
  end
  if phase == "nothing" then
    return string.format("Nothing at or below %s · Search again", ns.Money(s.threshold))
  end
  if s.note then return s.note .. " · Search " .. name end
  return "Search " .. name
end
