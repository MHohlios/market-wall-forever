-- MarketWall: the crafting guide. Every recipe of a profession at saved wall prices (Professions.Guide),
-- most profit first, with a breakdown of the selected one. One panel, built in two places: the
-- search window's Crafting tab and the Market tab's Crafting tab. It only recommends: buying a
-- pattern is the item page's own manual flow.
local _, ns = ...
local Crafting, Outlet, PV = ns.Crafting, ns.Outlet, ns.PriceView

local V = {}
ns.CraftingView = V

V.MODES = { { key = "known", label = "Known" }, { key = "learnable", label = "Learnable" }, { key = "all", label = "All" } }

local LIST_ROWS = 10
local GREY, GAIN, LOSS, WARN, LABEL = ns.COLOR.GREY, ns.COLOR.GAIN, ns.COLOR.LOSS, ns.COLOR.WARN, ns.COLOR.LABEL
local PURPLE = "|cffc08cff"   -- the Forever tag, which the palette has no job for
local NO_DATA = GREY .. "no data|r"

-- The profession window's difficulty colours
local SKILL_COLOURS = {
  [Crafting.RED] = "|cffff2020", [Crafting.ORANGE] = "|cffff8040", [Crafting.YELLOW] = "|cffffff00",
  [Crafting.GREEN] = "|cff40bf40", [Crafting.GREY] = "|cff808080",
}
local MARKET_TEXT = {
  [Crafting.DEEP] = GAIN .. "Deep", [Crafting.STEADY] = "Steady", [Crafting.THIN] = WARN .. "Thin",
}
local MARKET_ORDER = { [Crafting.DEEP] = 3, [Crafting.STEADY] = 2, [Crafting.THIN] = 1 }
local LEARN_FROM = { trainer = "Trainer", vendor = "Vendor", drop = "Pattern drop", quest = "Quest" }

local RECIPE_TIP = "Click a recipe for its breakdown. The item's quality colour; Forever: an item only WoW Forever has."
local COMMON_COLUMNS = {
  { "Skill", 48, "RIGHT", "The skill the recipe needs, in its skill-up colour at your skill. Red: above your skill." },
  { "Mats cost", 74, "RIGHT", "One craft's reagents: each at its vendor price when a vendor sells it, otherwise its wall. No data when any reagent has no price.", money = true },
  { "Sells for", 80, "RIGHT", "What one craft sells for through its best outlet, after the cut and deposit, as the item tooltip shows it. DE: disenchanting pays most.", money = true },
  { "Profit", 74, "RIGHT", "Sells for minus mats cost, per craft.", cellTip = true },
}
local MARKET_COLUMN = { "Market", 100, nil, "How easy the product is to sell, from your scans: units listed on its latest day. Deep: 40 or more listed on 5 of the last 7 days. Thin: too little supply to trust its wall. The auction house reports no sales." }

local function Columns(...)
  local columns = {}
  for _, part in ipairs({ ... }) do
    for _, column in ipairs(part) do columns[#columns + 1] = column end
  end
  return columns
end

local KNOWN_COLUMNS = Columns(
  { { "Recipe", 230, nil, RECIPE_TIP } }, COMMON_COLUMNS,
  { { "Margin", 56, "RIGHT", "Profit as a share of the mats cost." }, MARKET_COLUMN, { "Learn", 74, nil, "Whether this character knows it." } })
-- Both column sets add up to 736 pixels, the search window's list width
local LEARNABLE_COLUMNS = Columns(
  { { "Recipe", 136, nil, RECIPE_TIP } }, COMMON_COLUMNS,
  { MARKET_COLUMN,
    { "Learn from", 100, nil, "Where the recipe is learned. On the AH: its pattern was listed in your scans." },
    { "Pattern cost", 68, "RIGHT", "The pattern's wall when it is listed, else its vendor or trainer price.", money = true },
    { "Pays back", 56, "RIGHT", "Crafts until the profit pays for the pattern, rounded up. Never: a craft makes no profit." } })

-------------------------------------------------------------------------------
-- Data
-------------------------------------------------------------------------------

local function RecipeName(recipe)
  return recipe.name or ns.Name(recipe.product)
end

-- The evaluations to list. show: mode (a V.MODES key), hideThin, hideLosses and filter, a part of
-- the name to match, ignoring case. A recipe with unknown profit is never a loss.
function V.Filter(evaluations, show)
  local want = string.lower(strtrim(show.filter or ""))
  local out = {}
  for _, evaluation in ipairs(evaluations) do
    local recipe = evaluation.recipe
    local listed = show.mode == "all" or (show.mode == "known") == recipe.known
    local thin = evaluation.market.level == Crafting.THIN
    local loss = evaluation.profit ~= nil and evaluation.profit < 0
    local named = want == "" or string.find(string.lower(RecipeName(recipe)), want, 1, true) ~= nil
    if listed and named and not (show.hideThin and thin) and not (show.hideLosses and loss) then
      out[#out + 1] = evaluation
    end
  end
  return out
end

function V.Columns(mode)
  return mode == "known" and KNOWN_COLUMNS or LEARNABLE_COLUMNS
end

-- Formatting --------------------------------------------------------------------------------

-- An exact amount, for the breakdown
function V.Money(copper)
  return copper and ns.Money(copper) or NO_DATA
end

-- A list's money cell: copper for the list to show compact, with the exact amount on hover
local function MoneyCell(copper)
  return copper or NO_DATA
end

-- Signed profit, green or red; compact unless exact, as a list cell is
function V.Profit(copper, exact)
  if not copper then return NO_DATA end
  local money = (exact and ns.Money or ns.MoneyShort)(copper)
  if copper < 0 then return LOSS .. money .. "|r" end
  return GAIN .. "+" .. money .. "|r"
end

function V.Margin(share)
  if not share then return NO_DATA end
  return (share < 0 and LOSS or GAIN) .. string.format("%d%%", ns.Round(share * 100)) .. "|r"
end

function V.Skill(skill, colour)
  if not skill then return NO_DATA end
  local code = SKILL_COLOURS[colour]
  return code and (code .. skill .. "|r") or tostring(skill)
end

function V.Market(market)
  if market.level == Crafting.NO_DATA then return GREY .. "No data|r" end
  return MARKET_TEXT[market.level] .. " · " .. market.units .. " listed|r"
end

function V.LearnFrom(evaluation)
  local recipe = evaluation.recipe
  if recipe.known then return "Known" end
  local source = recipe.source
  local text = source and LEARN_FROM[source.kind] or GREY .. "Unknown|r"
  if source and source.limited then text = text .. " (limited supply)" end
  if evaluation.learnSource == "wall" then return text .. " · on the AH" end
  if recipe.pattern and not (source and source.cost) then return text .. GREY .. " · not listed|r" end
  return text
end

function V.Payback(payback)
  if payback == Crafting.NEVER then return LOSS .. "never|r" end
  if not payback then return NO_DATA end
  return payback == 1 and "1 craft" or (payback .. " crafts")
end

-- The outlet that pays most. Outlet.Values says no data for a product never seen listed, yet
-- still prices its vendor and disenchant values, so the better of those two pays most then.
local function BestOutlet(outlet)
  if outlet.outlet ~= Outlet.NO_DATA then return outlet.outlet end
  if outlet.disenchant and outlet.disenchant > outlet.vendor then return Outlet.DISENCHANT end
  return Outlet.VENDOR
end


-- The product's name in its quality colour, or the recipe's name until the game has the item
local function RecipeCell(recipe)
  local coloured = ns.ColorName(recipe.product)
  if ns.R().names[recipe.product] or not recipe.name then return coloured end
  return recipe.name
end

-- Display cells for one recipe under a mode's columns
function V.Cells(evaluation, mode)
  local recipe = evaluation.recipe
  local cells = { RecipeCell(recipe), V.Skill(recipe.skill, evaluation.colour), MoneyCell(evaluation.cost),
    MoneyCell(evaluation.net), V.Profit(evaluation.profit) }
  if mode == "known" then
    cells[#cells + 1] = V.Margin(evaluation.margin)
    cells[#cells + 1] = V.Market(evaluation.market)
    cells[#cells + 1] = "Known"
  else
    cells[#cells + 1] = V.Market(evaluation.market)
    cells[#cells + 1] = V.LearnFrom(evaluation)
    cells[#cells + 1] = MoneyCell(evaluation.learnCost)
    cells[#cells + 1] = V.Payback(evaluation.payback)
  end
  return cells
end

-- Text after a cell, by column: the Forever tag after the name, and DE after Sells for when
-- disenchanting pays most
function V.Suffixes(evaluation)
  local suffixes = {}
  if evaluation.recipe.forever then suffixes[1] = " " .. PURPLE .. "Forever|r" end
  if evaluation.net and BestOutlet(evaluation.outlet) == Outlet.DISENCHANT then suffixes[4] = " " .. GREY .. "DE|r" end
  return suffixes
end

-- The Profit cell's hover: its exact amount when the cell rounds it
function V.CellTips(evaluation)
  local profit = evaluation.profit
  if profit and ns.Money(profit) ~= ns.MoneyShort(profit) then return { [5] = V.Profit(profit, true) } end
end

-- Raw values per column, for sorting by a header; unknown values are nil and sort last
function V.SortValues(evaluation, mode)
  local recipe, market = evaluation.recipe, evaluation.market
  local depth = MARKET_ORDER[market.level]
  local values = { string.lower(RecipeName(recipe)), recipe.skill, evaluation.cost, evaluation.net, evaluation.profit }
  if mode == "known" then
    values[6] = evaluation.margin
    values[7] = depth and depth * 1e6 + market.units
  else
    values[6] = depth and depth * 1e6 + market.units
    values[7] = recipe.known and "known" or (recipe.source and recipe.source.kind)
    values[8] = evaluation.learnCost
    values[9] = evaluation.payback == Crafting.NEVER and math.huge or evaluation.payback
  end
  return values
end

-- Status and breakdown ----------------------------------------------------------------------

local function Count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

-- The line over the list: the profession and its rank, the recipes read from the profession
-- window and when, and the age of the prices
function V.StatusText(profession, rank, known, lastFull)
  local head = profession
  if rank and rank > 0 then head = head .. " " .. rank .. (known and known.maxRank and ("/" .. known.maxRank) or "") end
  local recipes
  if known then
    local n = Count(known.recipes)
    recipes = string.format("%d %s known (read from your profession window %s)", n, n == 1 and "recipe" or "recipes", ns.Ago(known.t))
  else
    recipes = WARN .. "Open your profession window once to read your recipes.|r"
  end
  local prices = lastFull and ("prices from the full scan " .. ns.Ago(lastFull)) or (WARN .. "no full scan yet|r")
  return head .. " · " .. recipes .. " · " .. prices
end

-- The breakdown's three sections, each { title, rows = { { label, value }, ... } }.
-- info: name(id), bags(id) the count in your bags, trend the product's 7-day wall change or nil.
function V.Breakdown(evaluation, info)
  local made = evaluation.recipe.made

  local mats = { title = "Mats for one craft", rows = {} }
  for _, line in ipairs(evaluation.mats) do
    local detail = string.format("%s%s, %d in bags|r", GREY, line.source or "no price", info.bags(line.id))
    mats.rows[#mats.rows + 1] = { string.format("%d x %s  %s", line.count, info.name(line.id), detail), V.Money(line.cost) }
  end
  mats.rows[#mats.rows + 1] = { "Cost", V.Money(evaluation.cost) }

  local outlet = evaluation.outlet
  local best = BestOutlet(outlet)
  local function PerCraft(key, value)
    if not value then return NO_DATA end
    local text = ns.Money(value * made)
    if evaluation.net and key == best then text = LABEL .. "best|r  " .. text end
    return text
  end
  local product = {
    title = made == 1 and "Product, after the cut and deposit" or string.format("Product, %g per craft, after the cut and deposit", made),
    rows = {
      { "Vendor", PerCraft(Outlet.VENDOR, outlet.vendor > 0 and outlet.vendor or nil) },
      { outlet.thin and "Market (net), thin" or "Market (net)", PerCraft(Outlet.AUCTION, outlet.auction) },
      { "Disenchant (net)", PerCraft(Outlet.DISENCHANT, outlet.disenchant) },
      { "Profit per craft", V.Profit(evaluation.profit, true) },
    },
  }

  local market = evaluation.market
  local scanned = market.level ~= Crafting.NO_DATA
  local marketSection = {
    title = "Market",
    rows = {
      { "Listed, latest scan", scanned and tostring(market.units) or NO_DATA },
      { "Seen in scans, last 7 days", market.recent .. " of 7 days" },
      { "Wall, 7-day trend", info.trend and PV.TrendText(info.trend) or NO_DATA },
    },
  }
  return { mats, product, marketSection }
end

-- The guide for a profession, evaluated again only after a profession read or a price change
local cached = {}
local reads = 0   -- profession window events seen, each of which may read recipes or a new rank

local function Guide(profession)
  local stamp = table.concat({ profession, reads, ns.Mobs.pricesVersion }, ":")
  if cached.stamp ~= stamp then cached = { stamp = stamp, evaluations = ns.Professions.Guide(profession) } end
  return cached.evaluations
end

local function GameInfo(evaluation)
  local week = PV.Summary(PV.InRange(ns.Series(evaluation.recipe.product), 7, time()))
  local count = (C_Item and C_Item.GetItemCount) or GetItemCount   -- newer clients keep it only in C_Item
  return { name = ns.Name, bags = function(id) return count(id) or 0 end, trend = week and week.trend }
end

-------------------------------------------------------------------------------
-- Panel
-------------------------------------------------------------------------------

local LINE_H = 14

-- One breakdown section: a title over rows of a label and a right-aligned value
local function Section(parent, width)
  local w = ns.widgets
  local section = CreateFrame("Frame", nil, parent)
  section:SetSize(width, 120)
  section.title = w.MakeText(section, "GameFontNormalSmall")
  section.title:SetPoint("TOPLEFT")
  section.lines = {}

  local function Line(i)
    local line = section.lines[i]
    if line then return line end
    line = {
      label = w.MakeText(section, "GameFontHighlightSmall"),
      value = w.MakeText(section, "GameFontHighlightSmall", "RIGHT"),
    }
    line.label:SetPoint("TOPLEFT", 0, -i * LINE_H - 2)
    line.label:SetWidth(width - 90)
    line.label:SetWordWrap(false)
    line.value:SetPoint("TOPRIGHT", 0, -i * LINE_H - 2)
    line.value:SetWidth(90)
    section.lines[i] = line
    return line
  end

  function section:SetContent(content)
    self.title:SetText(content.title)
    for i, row in ipairs(content.rows) do
      local line = Line(i)
      line.label:SetText(row[1])
      line.value:SetText(row[2])
      line.label:Show()
      line.value:Show()
    end
    for i = #content.rows + 1, #self.lines do
      self.lines[i].label:Hide()
      self.lines[i].value:Hide()
    end
  end
  return section
end

local function CheckBox(parent, label, onClick)
  local box = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  box:SetSize(24, 24)
  box:SetScript("OnClick", onClick)
  box.label = ns.widgets.MakeText(parent, "GameFontNormalSmall")
  box.label:SetPoint("LEFT", box, "RIGHT", 0, 0)
  box.label:SetText(label)
  return box
end

-- The guide panel, filling parent from layout.top (the y offset under the parent's own heading).
-- layout.onPattern(itemID), when set, opens a pattern: clicking a recipe you don't know that has
-- one calls it, as well as selecting the recipe.
function V.Build(parent, layout)
  layout = layout or {}
  local top = layout.top or -34
  local w = ns.widgets
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetAllPoints()
  panel.mode = "known"
  panel.profession = nil   -- chosen on the first refresh
  panel.selected = nil     -- the selected recipe's product
  panel.sorts = {}         -- [known or learnable column set] = { col, desc } once a header is clicked

  local function Changed()
    panel.list.offset = 0
    panel:Refresh()
  end

  panel.status = w.MakeText(panel, "GameFontHighlightSmall")
  panel.status:SetPoint("TOPLEFT", 14, top - 2)
  panel.status:SetPoint("RIGHT", -14, 0)
  panel.status:SetWordWrap(false)

  local controlsY = top - 18
  panel.picker = w.MakeButton(panel, "", 100)
  panel.picker:SetPoint("TOPLEFT", 12, controlsY)
  panel.picker:SetScript("OnClick", function()
    local items = {}
    for i, name in ipairs(ns.Professions.Names()) do
      items[i] = { text = name, onClick = function()
        panel.profession, panel.selected = name, nil
        Changed()
      end }
    end
    w.ShowMenu(items)
  end)

  panel.modeButtons = {}
  local previous = panel.picker
  for i, mode in ipairs(V.MODES) do
    local button = w.MakeButton(panel, mode.label, 70)
    button:SetPoint("LEFT", previous, "RIGHT", i == 1 and 10 or 4, 0)
    button:SetScript("OnClick", function()
      panel.mode = mode.key
      Changed()
    end)
    panel.modeButtons[i] = button
    previous = button
  end
  panel.hideThin = CheckBox(panel, "Hide thin markets", Changed)
  panel.hideThin:SetPoint("LEFT", previous, "RIGHT", 10, 0)
  panel.hideLosses = CheckBox(panel, "Hide losses", Changed)
  panel.hideLosses:SetPoint("LEFT", panel.hideThin.label, "RIGHT", 8, 0)

  panel.filter = w.MakeEdit(panel, 120)
  panel.filter:SetPoint("TOPRIGHT", -16, controlsY - 1)
  panel.filter:SetScript("OnTextChanged", Changed)
  local filterLabel = w.MakeText(panel, "GameFontDisableSmall", "RIGHT")
  filterLabel:SetPoint("RIGHT", panel.filter, "LEFT", -10, 0)
  filterLabel:SetText("Filter")

  panel.list = w.CreateList(panel, LIST_ROWS)
  panel.list:SetPoint("TOPLEFT", 12, controlsY - 28)
  panel.list:SetPoint("RIGHT", -12, 0)
  panel.list:SetHeight(w.ListHeight(LIST_ROWS))
  panel.list.onClick = function(entry)
    local recipe = entry.evaluation.recipe
    panel.selected = recipe.product
    panel:Refresh()
    if layout.onPattern and not recipe.known and recipe.pattern then layout.onPattern(recipe.pattern) end
  end
  panel.list.onHeader = function(col)
    local key = panel.mode == "known" and "known" or "learnable"
    local sort = panel.sorts[key]
    if sort and sort.col == col then
      sort.desc = not sort.desc
    else
      panel.sorts[key] = { col = col, desc = col ~= 1 }   -- names A to Z, numbers biggest first
    end
    Changed()
  end
  panel.hint = w.MakeText(panel, "GameFontDisableSmall")
  panel.hint:SetPoint("TOPLEFT", panel.list, "BOTTOMLEFT", 8, -2)
  panel.hint:SetText("Sorted by profit per craft; thin markets are dimmed. " ..
    (layout.onPattern and "Click a recipe you don't know to load its pattern's listings." or "Click a recipe for its breakdown."))

  -- the breakdown: mats, product outlets, market
  panel.sections = {}
  local x = 0
  for i, width in ipairs({ 300, 220, 200 }) do
    local section = Section(panel, width)
    section:SetPoint("TOPLEFT", panel.list, "BOTTOMLEFT", x + 2, -20)
    panel.sections[i] = section
    x = x + width + 8
  end

  local function ChooseProfession()
    local names = ns.Professions.Names()
    for _, name in ipairs(names) do
      if name == panel.profession then return end
    end
    panel.profession = names[1]
    for _, name in ipairs(names) do
      if ns.Professions.Known(name) then
        panel.profession = name
        return
      end
    end
  end

  local function ShowBreakdown(evaluation)
    for _, section in ipairs(panel.sections) do section:SetShown(evaluation ~= nil) end
    if not evaluation then return end
    for i, content in ipairs(V.Breakdown(evaluation, GameInfo(evaluation))) do panel.sections[i]:SetContent(content) end
  end

  function panel:Refresh()
    ChooseProfession()
    local profession = self.profession
    local known = ns.Professions.Known(profession)
    self.picker:SetText(profession .. " v")
    self.status:SetText(V.StatusText(profession, ns.Professions.Rank(profession), known, ns.R().lastFull))
    for i, button in ipairs(self.modeButtons) do
      if V.MODES[i].key == self.mode then button:LockHighlight() else button:UnlockHighlight() end
    end

    local mode = self.mode
    local evaluations = V.Filter(Guide(profession), {
      mode = mode, hideThin = self.hideThin:GetChecked(), hideLosses = self.hideLosses:GetChecked(), filter = self.filter:GetText(),
    })
    local data, selected = {}, nil
    for i, evaluation in ipairs(evaluations) do
      local recipe = evaluation.recipe
      data[i] = {
        id = recipe.product, evaluation = evaluation, cells = V.Cells(evaluation, mode), sort = V.SortValues(evaluation, mode),
        suffixes = V.Suffixes(evaluation), cellTips = V.CellTips(evaluation),
        dim = evaluation.market.level == Crafting.THIN, highlight = recipe.product == self.selected,
      }
      if recipe.product == self.selected then selected = evaluation end
    end
    local sort = self.sorts[mode == "known" and "known" or "learnable"]
    ns.MobsView.Sort(data, sort)
    if not selected and data[1] then
      selected = data[1].evaluation
      self.selected = selected.recipe.product
      data[1].highlight = true
    end

    local empty = "No recipe matches."
    if mode == "known" and not known then empty = "Open your profession window once to read your recipes.\nLearnable lists the bundled recipes meanwhile." end
    self.list:SetColumns(V.Columns(mode), sort and sort.col, sort and sort.desc)
    self.list:SetData(data, empty)
    ShowBreakdown(selected)
  end

  return panel
end

-- A profession read changes the guide: evaluate it again and redraw whichever copy is on screen,
-- batched like item names, so after Professions.Read has handled the same event
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
  reads = reads + 1
  ns.SearchChanged()
  ns.ui.dirty = true
end)
for _, event in ipairs(ns.Professions.EVENTS) do
  pcall(events.RegisterEvent, events, event)   -- a client has only some of them
end
