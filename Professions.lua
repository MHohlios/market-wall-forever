-- MarketWall: recipes in game. Reads the open profession window into MarketWallDB.crafting, merges
-- it with the bundled recipe tables (Recipes/*.lua) and prices recipes with Crafting.lua.
--
-- Saved in MarketWallDB.crafting, per character by its GUID (Recording.CharacterKey):
--   [guid] = { [profession] = { rank, maxRank, t, recipes = { [product] = recipe } } }
-- where a recipe holds name, made, reagents and colour (see Crafting.lua). Recipes are only ever
-- added or updated, as a collapsed header or a filter hides some from a read. Trainer costs are
-- account-wide, as Trainer.lua last read them:
--   trainer = { [profession] = { [product] = copper } }
--
-- API for the crafting guide, trainer rows and pattern tooltips:
--   Professions.Names()                    professions with a table or saved recipes, sorted
--   Professions.Known(profession)          this character's saved read, or nil
--   Professions.Rank(profession)           this character's skill, or nil when unknown
--   Professions.Recipes(profession)        every recipe, known and bundled, merged (Crafting.Merge)
--   Professions.SaveTrainerCost(profession, product, cost)   a trainer's price, for payback
--   Professions.ByPattern(itemID)          the recipe a pattern teaches and its profession, or nil
--   Professions.ByName(profession, name)   a recipe by its name, for trainer rows without a product
--   Professions.Context(profession)        game prices and rank, read once for a whole list
--   Professions.Evaluate(recipe, context)  Crafting.Evaluate at those prices
--   Professions.Guide(profession)          every recipe evaluated and ranked (Crafting.Rank)
--   Professions.Diagnose()                 /mw professions: what reading the window finds on this client
local _, ns = ...
local Crafting = ns.Crafting

local Professions = {}
ns.Professions = Professions

ns.RecipeTables = ns.RecipeTables or {}   -- [profession] = { skillLine, spell, vendor, recipes }

-- The profession window's difficulty names as skill colours
local COLOURS = {
  difficult = Crafting.RED, optimal = Crafting.ORANGE, medium = Crafting.YELLOW,
  easy = Crafting.GREEN, trivial = Crafting.GREY,
}

-- Reading -----------------------------------------------------------------------------------
-- A client has one of two profession window APIs: the Classic GetTradeSkill* calls, or
-- C_TradeSkillUI, which clients with the modern API surface, Forever among them, have instead.

-- The window's events across both APIs. Each may bring recipes that were still loading.
Professions.EVENTS = { "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED" }

-- Every call each reader makes
local CLASSIC_API = {
  "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumMade",
  "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
}
local MODERN_API = { "GetBaseProfessionInfo", "GetAllRecipeIDs", "GetRecipeInfo", "GetRecipeSchematic" }

-- The names a table of calls lacks
local function Missing(calls, names)
  local missing = {}
  for _, name in ipairs(names) do
    if type(calls) ~= "table" or type(calls[name]) ~= "function" then missing[#missing + 1] = name end
  end
  return missing
end

local function Has(calls, names)
  return #Missing(calls, names) == 0
end

-- Classic: one recipe row of the open window, its product and recipe. Nil while the product, the
-- reagent count or a reagent is not readable yet.
local function ReadClassicRecipe(index, name, difficulty)
  local product = ns.ItemID(GetTradeSkillItemLink(index))
  local reagentCount = GetTradeSkillNumReagents(index)
  if not (product and reagentCount) then return nil end
  local reagents = {}
  for r = 1, reagentCount do
    local id = ns.ItemID(GetTradeSkillReagentItemLink(index, r))
    local count = select(3, GetTradeSkillReagentInfo(index, r))
    if not (id and count) then return nil end
    reagents[r] = { id, count }
  end
  local low, high = GetTradeSkillNumMade(index)
  low = low or 1
  return product, { name = name, made = (low + (high or low)) / 2, reagents = reagents, colour = COLOURS[difficulty] }
end

local function ReadClassicWindow()
  local name, rank, maxRank = GetTradeSkillLine()
  if type(name) ~= "string" or name == "" or name == "UNKNOWN" then return nil end
  local recipes = {}
  for index = 1, GetNumTradeSkills() or 0 do
    local recipeName, kind = GetTradeSkillInfo(index)
    if kind and kind ~= "header" and kind ~= "subheader" then
      local product, recipe = ReadClassicRecipe(index, recipeName, kind)
      if product then recipes[product] = recipe end
    end
  end
  return name, rank, maxRank, recipes
end

-- C_TradeSkillUI's relative difficulty (Enum.TradeskillRelativeDifficulty) as skill colours
local RELATIVE_COLOURS = { [0] = Crafting.ORANGE, [1] = Crafting.YELLOW, [2] = Crafting.GREEN, [3] = Crafting.GREY }

-- A schematic's required reagents as { id, count }, nil while one is not readable
local function ReadReagents(schematic)
  local reagents = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    if slot.required ~= false then
      local reagent = type(slot.reagents) == "table" and slot.reagents[1]
      local id, count = reagent and reagent.itemID, slot.quantityRequired
      if not (id and count) then return nil end
      reagents[#reagents + 1] = { id, count }
    end
  end
  return reagents
end

-- Modern: one learned recipe, its product and recipe. Nil for a recipe not learned or without an
-- item product, such as an enchant, and while its schematic is loading.
local function ReadModernRecipe(recipeID)
  local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
  if type(info) ~= "table" or not info.learned then return nil end
  local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
  local product = type(schematic) == "table" and schematic.outputItemID
  local reagents = product and ReadReagents(schematic)
  if not reagents then return nil end
  local low = schematic.quantityMin or 1
  return product, { name = info.name, made = (low + (schematic.quantityMax or low)) / 2, reagents = reagents,
    colour = RELATIVE_COLOURS[info.relativeDifficulty] }
end

-- False while the window shows another player's or an NPC's recipes, or is changing profession
local function ShowsOwnRecipes()
  for _, name in ipairs({ "IsTradeSkillLinked", "IsTradeSkillGuild", "IsNPCCrafting", "IsDataSourceChanging" }) do
    local check = C_TradeSkillUI[name]
    if type(check) == "function" and check() then return false end
  end
  return true
end

local function ReadModernWindow()
  if not ShowsOwnRecipes() then return nil end
  local profession = C_TradeSkillUI.GetBaseProfessionInfo()
  local name = type(profession) == "table" and profession.professionName
  if type(name) ~= "string" or name == "" then return nil end
  local recipes = {}
  for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
    local product, recipe = ReadModernRecipe(recipeID)
    if product then recipes[product] = recipe end
  end
  return name, profession.skillLevel, profession.maxSkillLevel, recipes
end

-- The open profession window: its name, rank, maximum rank and { [product] = recipe } for the
-- recipes readable now. Classic first; C_TradeSkillUI when the Classic calls read no recipe.
-- Nil when no profession is open or the client lacks both APIs.
function Professions.ReadWindow()
  if Has(_G, CLASSIC_API) then
    local name, rank, maxRank, recipes = ReadClassicWindow()
    if name and next(recipes) then return name, rank, maxRank, recipes end
  end
  if Has(C_TradeSkillUI, MODERN_API) then return ReadModernWindow() end
end

-- This character's saved professions, nil before its first read
local function CharacterBook()
  local key = ns.Recording.CharacterKey()
  return key and MarketWallDB.crafting[key]
end

-- Saves the open window into this character's book; true when it saved. A read with no recipe
-- readable yet, as while the window loads, saves nothing, and a later event reads again.
function Professions.Read()
  local name, rank, maxRank, recipes = Professions.ReadWindow()
  local key = name and next(recipes) and ns.Recording.CharacterKey()
  if not key then return false end
  local book = MarketWallDB.crafting[key] or {}
  MarketWallDB.crafting[key] = book
  local saved = book[name] or { recipes = {} }
  saved.rank, saved.maxRank, saved.t = rank, maxRank, time()
  for product, recipe in pairs(recipes) do saved.recipes[product] = recipe end
  book[name] = saved
  return true
end

-- Lookups -----------------------------------------------------------------------------------

function Professions.Names()
  local seen, names = {}, {}
  local book = CharacterBook() or {}
  for _, source in ipairs({ ns.RecipeTables, book }) do
    for name in pairs(source) do
      if not seen[name] then
        seen[name] = true
        names[#names + 1] = name
      end
    end
  end
  table.sort(names)
  return names
end

function Professions.Known(profession)
  local book = CharacterBook()
  return book and book[profession]
end

-- The live skill when the game reports it, else the rank the profession window last showed
function Professions.Rank(profession)
  local bundled = ns.RecipeTables[profession]
  local live = bundled and ns.ProfessionSkill(bundled.skillLine, bundled.spell, profession)
  if live then return live end
  local known = Professions.Known(profession)
  return known and known.rank
end

function Professions.Recipes(profession)
  local known = Professions.Known(profession)
  local bundled = ns.RecipeTables[profession]
  local trainer = MarketWallDB.crafting.trainer
  return Crafting.Merge(known and known.recipes, bundled and bundled.recipes, trainer and trainer[profession])
end

function Professions.SaveTrainerCost(profession, product, cost)
  local trainer = MarketWallDB.crafting.trainer or {}
  MarketWallDB.crafting.trainer = trainer
  trainer[profession] = trainer[profession] or {}
  trainer[profession][product] = cost
end

function Professions.ByPattern(patternID)
  for profession, bundled in pairs(ns.RecipeTables) do
    for _, recipe in ipairs(bundled.recipes) do
      if recipe.pattern == patternID then
        for _, merged in ipairs(Professions.Recipes(profession)) do
          if merged.product == recipe.product then return merged, profession end
        end
      end
    end
  end
end

function Professions.ByName(profession, name)
  local wanted = string.lower(name or "")
  for _, recipe in ipairs(Professions.Recipes(profession)) do
    if recipe.name and string.lower(recipe.name) == wanted then return recipe end
  end
end

-- Pricing -----------------------------------------------------------------------------------

-- The vendor's price for a reagent any recipe table lists as vendor-sold
local function VendorBuy(id)
  for _, bundled in pairs(ns.RecipeTables) do
    local price = bundled.vendor and bundled.vendor[id]
    if price then return price end
  end
end

function Professions.Context(profession)
  local prices = ns.Mobs.GamePrices()
  prices.buy = VendorBuy
  return {
    prices = prices, opts = ns.Mobs.GameOptions(),
    days = function(id) return ns.R().days[id] end, today = ns.Today(),
    rank = Professions.Rank(profession),
  }
end

function Professions.Evaluate(recipe, context)
  return Crafting.Evaluate(recipe, context)
end

function Professions.Guide(profession)
  local context, evaluations = Professions.Context(profession), {}
  for i, recipe in ipairs(Professions.Recipes(profession)) do
    evaluations[i] = Crafting.Evaluate(recipe, context)
  end
  return Crafting.Rank(evaluations)
end

-- Reading in game -----------------------------------------------------------------------------

local seen, unregistered = {}, {}   -- profession window events: [event] = count, and those the client lacks
local savedThisWindow, lastError, noted

-- Once a session, when a profession window closes without a read saving anything
local function NoteUnread()
  if noted then return end
  noted = true
  ns.Print("couldn't read recipes from that profession window. /mw professions shows why.")
end

local function OnEvent(_, event)
  seen[event] = (seen[event] or 0) + 1
  if event == "TRADE_SKILL_CLOSE" then
    if not savedThisWindow then NoteUnread() end
    savedThisWindow = false
    return
  end
  local ok, saved = pcall(Professions.Read)
  if not ok then lastError = tostring(saved) end
  savedThisWindow = savedThisWindow or (ok and saved)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", OnEvent)
for _, event in ipairs(Professions.EVENTS) do
  if not pcall(frame.RegisterEvent, frame, event) then unregistered[#unregistered + 1] = event end
end
pcall(frame.RegisterEvent, frame, "TRADE_SKILL_CLOSE")

local function Listed(names)
  return #names == 0 and "all present" or "missing " .. table.concat(names, ", ")
end

local function EventCounts()
  local counts = {}
  for _, event in ipairs(Professions.EVENTS) do counts[#counts + 1] = event .. " " .. (seen[event] or 0) end
  return table.concat(counts, ", ")
end

local function Count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- /mw professions: which profession window API and events this client has and what a read finds
-- now. Names nothing but the profession.
function Professions.Diagnose()
  ns.Print("reading the profession window on this client:")
  print("  Classic calls: " .. Listed(Missing(_G, CLASSIC_API)))
  print("  C_TradeSkillUI calls: " .. Listed(Missing(C_TradeSkillUI, MODERN_API)))
  print("  Events seen: " .. EventCounts())
  if #unregistered > 0 then print("  Events the client lacks: " .. table.concat(unregistered, ", ")) end
  if Has(C_TradeSkillUI, MODERN_API) then
    local ok, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    print("  C_TradeSkillUI lists " .. (ok and type(ids) == "table" and #ids or "no") .. " recipe IDs")
  end
  local ok, name, _, _, recipes = pcall(Professions.ReadWindow)
  if not ok then
    print("  Reading now failed: " .. tostring(name))
  elseif name then
    print("  Reading now: " .. name .. ", " .. Count(recipes) .. " recipes readable")
  else
    print("  Reading now: no profession window readable. Open one and type /mw professions again.")
  end
  print("  Character key: " .. (ns.Recording.CharacterKey() and "found" or "missing"))
  if lastError then print("  Last read error: " .. lastError) end
end
