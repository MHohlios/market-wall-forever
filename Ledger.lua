-- MarketWall: the cash ledger. Every gold change of each character, with where it came from.
-- Saved in MarketWallDB.ledger, per character by its GUID (Recording.CharacterKey): {
--   opening = { t, money },   your gold the first time the ledger ran on this character
--   balance =,                gold after the last recorded change
--   entries = { { t, delta, source }, ... },   raw changes from the last KEEP_DAYS, oldest first
--   weeks = { [first day of the week] = roll-up },   every change ever, by Monday-start week
--   months = { [yyyymm] = roll-up },                 and by calendar month
-- }
-- A roll-up is { income = { [source] = copper }, spending = { [source] = copper } }, both positive.
-- Roll-ups are added to as each change is recorded, so views never walk the raw entries, and raw
-- entries older than KEEP_DAYS are dropped at login. Each change is recorded as the difference from
-- the last balance, so opening money plus every roll-up always equals GetMoney().
local _, ns = ...

local Ledger = {}
ns.Ledger = Ledger

Ledger.KEEP_DAYS = 90
local RECENT = 2   -- seconds a closed window or a one-off event still explains a gold change

Ledger.LABELS = {
  loot = "Loot coins",
  vendor_sale = "Vendor sales",
  auction_sale = "Auction sales (from mail)",
  quest = "Quest rewards",
  mail = "Mail",
  trade = "Trades",
  vendor_buy = "Vendor purchases",
  repair = "Repairs",
  auction_buy = "Auction buys",
  auction_deposit = "Auction deposits",
  training = "Training",
  flight = "Flights",
  other = "Other",
  offline = "Unrecorded",   -- gold that changed while MarketWall wasn't running
}

-- contexts[name] is true while its window is open, or the time it closed or was last seen
local function Active(contexts, name, now)
  local v = contexts[name]
  return v == true or (type(v) == "number" and now - v <= RECENT)
end

-- One of your auction-house purchases (r.buys) that cost exactly this, made just now
local function MatchesBuy(buys, cost, now)
  for i = #buys, 1, -1 do
    local buy = buys[i]
    if now - buy.t > RECENT then return false end
    if buy.total == cost then return true end
  end
  return false
end

-- The ledger source of a gold change, from the windows open or seen within RECENT seconds.
-- Contexts: loot, quest (reward window), turned_in (a quest just handed in), trade, auction (house
-- open), auction_post, auction_mail (taking a sale's gold), mail, merchant, repair, trainer, taxi.
-- buys is the realm's purchase log.
function Ledger.Attribute(delta, contexts, now, buys)
  local function Is(name) return Active(contexts, name, now) end
  if delta > 0 then
    if Is("turned_in") then return "quest" end   -- its gold, even with a loot window open
    if Is("loot") then return "loot" end
    if Is("quest") then return "quest" end
    if Is("trade") then return "trade" end
    if Is("auction_mail") then return "auction_sale" end
    if Is("mail") then return "mail" end
    if Is("merchant") then return "vendor_sale" end
    return "other"
  end
  if MatchesBuy(buys or {}, -delta, now) then return "auction_buy" end
  if Is("trade") then return "trade" end
  if Is("auction_post") then return "auction_deposit" end
  if Is("auction") then return "auction_buy" end
  if Is("repair") then return "repair" end
  if Is("merchant") then return "vendor_buy" end
  if Is("trainer") then return "training" end
  if Is("taxi") then return "flight" end
  if Is("mail") then return "mail" end         -- postage and cash on delivery
  if Is("quest") then return "quest" end
  return "other"
end

function Ledger.WeekOf(t)
  local day = ns.DayOf(t)
  return day - (day + 3) % 7   -- day 0, 1 Jan 1970, was a Thursday
end

function Ledger.MonthOf(t)
  return tonumber(date("%Y%m", t))
end

local function AddTo(rolls, key, delta, source)
  local roll = rolls[key]
  if not roll then roll = { income = {}, spending = {} } rolls[key] = roll end
  local side = delta > 0 and roll.income or roll.spending
  side[source] = (side[source] or 0) + math.abs(delta)
end

function Ledger.NewBook(money, t)
  return { opening = { t, money }, balance = money, entries = {}, weeks = {}, months = {} }
end

-- Records the change from the last balance to money. Returns the entry, or nil when unchanged.
function Ledger.Record(book, money, t, source)
  local delta = money - book.balance
  if delta == 0 then return nil end
  local entry = { t, delta, source }
  book.entries[#book.entries + 1] = entry
  AddTo(book.weeks, Ledger.WeekOf(t), delta, source)
  AddTo(book.months, Ledger.MonthOf(t), delta, source)
  book.balance = money
  return entry
end

-- Drops raw entries older than KEEP_DAYS; the roll-ups already hold them
function Ledger.Prune(book, now)
  local cutoff, keep = now - Ledger.KEEP_DAYS * 86400, {}
  for _, entry in ipairs(book.entries) do
    if entry[1] >= cutoff then keep[#keep + 1] = entry end
  end
  book.entries = keep
end

-- A character's book at login: opened with today's gold the first time, otherwise any change
-- since the last recorded balance (gold moved while offline, or lost to a crash) as "offline"
function Ledger.Login(book, money, t)
  if not book then return Ledger.NewBook(money, t) end
  Ledger.Record(book, money, t, "offline")
  Ledger.Prune(book, t)
  return book
end

-- Books were once keyed "Name-Realm", which characters of the same name on different Forever
-- realms shared. The first character under key to log in with no book of its own adopts the book
-- under its legacy key; the others start fresh. Returns whether it adopted.
function Ledger.Adopt(ledger, key, legacy)
  if ledger[key] or not (legacy and ledger[legacy]) then return false end
  ledger[key], ledger[legacy] = ledger[legacy], nil
  return true
end

-- Opening money plus every recorded change; always equals the balance
function Ledger.Total(book)
  local total = book.opening[2]
  for _, roll in pairs(book.months) do
    for _, copper in pairs(roll.income) do total = total + copper end
    for _, copper in pairs(roll.spending) do total = total - copper end
  end
  return total
end

-- In game -----------------------------------------------------------------------------------

local contexts = {}
local book

local function Open(name) contexts[name] = true end
local function Seen(name) contexts[name] = time() end

local WINDOWS = {   -- [event] = { context, opens }
  LOOT_READY = { "loot", true }, LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot" },
  MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant" },
  AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction" },
  MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail" },
  TRADE_SHOW = { "trade", true }, TRADE_CLOSED = { "trade" },
  TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer" },
  TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi" },
  QUEST_COMPLETE = { "quest", true }, QUEST_FINISHED = { "quest" },
  CHAT_MSG_MONEY = { "loot" }, QUEST_TURNED_IN = { "turned_in" },   -- one-off: seen just now
}

local function OnMoney()
  if not book then return end
  if _G.InRepairMode and _G.InRepairMode() then Seen("repair") end
  local money, now = GetMoney(), time()
  local source = Ledger.Attribute(money - book.balance, contexts, now, ns.R().buys)
  local entry = Ledger.Record(book, money, now, source)
  if entry then ns.Recording.Emit({ t = now, kind = "money", source = source, delta = entry[2] }) end
end

-- At PLAYER_LOGIN, or the first PLAYER_ENTERING_WORLD when the GUID was not known yet
local function OnLogin()
  local key = ns.Recording.CharacterKey()
  if book or not key then return end
  local ledger = MarketWallDB.ledger
  Ledger.Adopt(ledger, key, ns.Recording.LegacyKey())
  book = Ledger.Login(ledger[key], GetMoney(), time())
  ledger[key] = book
end

local function Hook(owner, name, fn)
  if owner and type(owner[name]) == "function" and hooksecurefunc then
    if owner == _G then hooksecurefunc(name, fn) else hooksecurefunc(owner, name, fn) end
  end
end

-- Gold taken from an auction-house sale's mail, rather than mail from another player
local function TakingMail(index)
  if _G.GetInboxInvoiceInfo and _G.GetInboxInvoiceInfo(index) == "seller" then Seen("auction_mail") end
end

Hook(_G, "RepairAllItems", function() Seen("repair") end)
Hook(_G, "TakeInboxMoney", TakingMail)
Hook(_G, "AutoLootMailItem", TakingMail)
Hook(_G, "PostAuction", function() Seen("auction_post") end)
Hook(_G, "StartAuction", function() Seen("auction_post") end)
Hook(C_AuctionHouse, "PostItem", function() Seen("auction_post") end)
Hook(C_AuctionHouse, "PostCommodity", function() Seen("auction_post") end)

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then return OnLogin() end
  if event == "PLAYER_MONEY" then return OnMoney() end
  local window = WINDOWS[event]
  if window[2] then Open(window[1]) else Seen(window[1]) end
end)
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_MONEY")
for event in pairs(WINDOWS) do
  pcall(frame.RegisterEvent, frame, event)   -- some of these may not exist on every client
end

function Ledger.Book()
  return book
end
