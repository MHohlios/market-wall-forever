-- MarketWall: recipes in game. Reads the open profession window into MarketWallDB.crafting, merges
-- it with the bundled recipe tables (Recipes/*.lua) and prices recipes with Crafting.lua.
--
-- Saved in MarketWallDB.crafting, per character by its GUID (Recording.CharacterKey):
--   [guid] = { [profession] = { rank, maxRank, t, recipes = { [product] = recipe } } }
-- where a recipe holds name, made, reagents and colour (see Crafting.lua). Recipes are only ever
-- added or updated, as a collapsed header or a filter hides some from a read.
--
-- API for the crafting guide, trainer rows and pattern tooltips:
--   Professions.Names()                    professions with a table or saved recipes, sorted
--   Professions.Known(profession)          this character's saved read, or nil
--   Professions.Rank(profession)           this character's skill, or nil when unknown
--   Professions.Recipes(profession)        every recipe, known and bundled, merged (Crafting.Merge)
--   Professions.ByPattern(itemID)          the recipe a pattern teaches and its profession, or nil
--   Professions.ByName(profession, name)   a recipe by its name, for trainer rows without a product
--   Professions.Context(profession)        game prices and rank, read once for a whole list
--   Professions.Evaluate(recipe, context)  Crafting.Evaluate at those prices
--   Professions.Guide(profession)          every recipe evaluated and ranked (Crafting.Rank)
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

-- Every profession window call the reader makes
local TRADE_SKILL_API = {
  "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumMade",
  "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
}

local function HasTradeSkillAPI()
  for _, name in ipairs(TRADE_SKILL_API) do
    if type(_G[name]) ~= "function" then return false end
  end
  return true
end

-- One recipe row of the open window: its product and recipe, nil while the product, the reagent
-- count or a reagent is not readable yet
local function ReadRecipe(index, name, difficulty)
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

-- The open profession window: its name, rank, maximum rank and { [product] = recipe } for the
-- rows readable now. Nil when no profession is open or the client lacks the API.
function Professions.ReadWindow()
  if not HasTradeSkillAPI() then return nil end
  local name, rank, maxRank = GetTradeSkillLine()
  if type(name) ~= "string" or name == "" or name == "UNKNOWN" then return nil end
  local recipes = {}
  for index = 1, GetNumTradeSkills() or 0 do
    local recipeName, kind = GetTradeSkillInfo(index)
    if kind and kind ~= "header" and kind ~= "subheader" then
      local product, recipe = ReadRecipe(index, recipeName, kind)
      if product then recipes[product] = recipe end
    end
  end
  return name, rank, maxRank, recipes
end

-- This character's saved professions, nil before its first read
local function CharacterBook()
  local key = ns.Recording.CharacterKey()
  return key and MarketWallDB.crafting[key]
end

-- Saves the open window into this character's book
function Professions.Read()
  local name, rank, maxRank, recipes = Professions.ReadWindow()
  local key = name and ns.Recording.CharacterKey()
  if not key then return end
  local book = MarketWallDB.crafting[key] or {}
  MarketWallDB.crafting[key] = book
  local saved = book[name] or { recipes = {} }
  saved.rank, saved.maxRank, saved.t = rank, maxRank, time()
  for product, recipe in pairs(recipes) do saved.recipes[product] = recipe end
  book[name] = saved
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
  return Crafting.Merge(known and known.recipes, bundled and bundled.recipes)
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

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", Professions.Read)
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_UPDATE" }) do
  pcall(frame.RegisterEvent, frame, event)   -- a client without the Classic profession window lacks them
end
