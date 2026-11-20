-- MarketWall: crafting profit at a profession trainer. Each recipe row of the trainer window
-- (Forever's or Classic's) shows its training cost, profit per craft and payback; hovering one adds the breakdown to
-- the game's tooltip. Each recipe's training cost is saved for the crafting guide's payback.
--
-- Only reads: it never trains. It hooks Blizzard's trainer with hooksecurefunc and HookScript and
-- replaces nothing, so it cannot taint the window. A client lacking any trainer call it uses gets
-- nothing from this file.
local _, ns = ...
local Crafting, Professions = ns.Crafting, ns.Professions

local Trainer = {}
ns.Trainer = Trainer

local GREY, BRAND, LOSS = ns.COLOR.GREY, ns.COLOR.BRAND, ns.COLOR.LOSS
local TRAINER_UI = "Blizzard_TrainerUI"   -- load-on-demand, loaded on the first trainer visit

local TRAINER_API = {
  "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceSkillReq",
  "GetTrainerServiceItemLink",
}

function Trainer.HasAPI()
  for _, name in ipairs(TRAINER_API) do
    if type(_G[name]) ~= "function" then return false end
  end
  return true
end

local function ByProduct(profession, product)
  for _, recipe in ipairs(Professions.Recipes(profession)) do
    if recipe.product == product then return recipe end
  end
end

local SERVICE_TYPES = { available = true, unavailable = true, used = true, header = true }

-- A service's name and type ("available", "unavailable", "used" or "header"). Forever returns
-- name, type, texture, ...; Classic returns name, subText, type, isExpanded.
local function ServiceInfo(index)
  local name, second, third = GetTrainerServiceInfo(index)
  return name, SERVICE_TYPES[second] and second or third
end

-- The recipe a trainer service teaches and its profession, nil for anything else: by the product
-- its item link names, else by its name within the profession its skill requirement names.
function Trainer.Recipe(index)
  local name, serviceType = ServiceInfo(index)
  local profession = GetTrainerServiceSkillReq(index)
  if serviceType == "header" or type(profession) ~= "string" then return nil end
  local product = ns.ItemID(GetTrainerServiceItemLink(index))
  local recipe = product and ByProduct(profession, product) or Professions.ByName(profession, name)
  if recipe then return recipe, profession end
end

-- Saves the training cost of every recipe the open trainer lists
function Trainer.SaveCosts()
  if not Trainer.HasAPI() then return end
  for index = 1, GetNumTrainerServices() or 0 do
    local recipe, profession = Trainer.Recipe(index)
    local cost = recipe and GetTrainerServiceCost(index)
    if type(cost) == "number" then Professions.SaveTrainerCost(profession, recipe.product, cost) end
  end
end

-- A service's recipe evaluated at game prices and its training cost, nil when it teaches none
local function Evaluate(index)
  local recipe, profession = Trainer.Recipe(index)
  if not recipe then return nil end
  local cost = GetTrainerServiceCost(index)
  return Professions.Evaluate(recipe, Professions.Context(profession)), type(cost) == "number" and cost or nil
end

-- A recipe row's text: "known · profit" once learned, else the training cost, or the skill it
-- still needs, then profit and payback. Nil for a row that teaches no recipe MarketWall knows.
function Trainer.RowText(index)
  local evaluation, cost = Evaluate(index)
  if not evaluation then return nil end
  local profit = ns.CraftingText.Profit(evaluation.profit)
  local _, serviceType = ServiceInfo(index)
  if serviceType == "used" then return GREY .. "known|r · " .. profit end
  local _, skillRank, hasSkill = GetTrainerServiceSkillReq(index)
  local first = (not hasSkill and skillRank) and LOSS .. "needs " .. skillRank .. "|r" or ns.Money(cost)
  return first .. " · " .. profit .. " · " .. ns.CraftingText.Payback(Crafting.Payback(cost, evaluation.profit))
end

local function MatsText(mats)
  local parts = {}
  for i, mat in ipairs(mats) do parts[i] = mat.count .. " " .. ns.Name(mat.id) end
  return "Mats: " .. table.concat(parts, ", ")
end

local function TrainingPayback(payback)
  if payback == Crafting.NEVER then return "Training never pays back" end
  if not payback then return "Training payback: no data" end
  return "Training pays back in " .. ns.CraftingText.Payback(payback)
end

-- The hover breakdown as { left, right } pairs, nil for a row that teaches no known recipe
function Trainer.Breakdown(index)
  local evaluation, cost = Evaluate(index)
  if not evaluation then return nil end
  local noData = GREY .. "no data|r"
  return {
    { GREY .. MatsText(evaluation.mats) .. "|r", evaluation.cost and ns.Money(evaluation.cost) or noData },
    { GREY .. "Sells for (net)|r", evaluation.net and ns.Money(evaluation.net) or noData },
    { GREY .. "Profit per craft|r", ns.CraftingText.Profit(evaluation.profit) },
    { GREY .. "Market|r", ns.CraftingText.Market(evaluation.market) },
    { GREY .. TrainingPayback(Crafting.Payback(cost, evaluation.profit)) .. "|r", "" },
  }
end

-- Trainer window ----------------------------------------------------------------------------

local function ShowBreakdown(button)
  local lines = Trainer.Breakdown(button:GetID())
  if not lines then return end
  if not GameTooltip:IsOwned(button) then
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine((GetTrainerServiceInfo(button:GetID())))
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(BRAND .. "MarketWall|r")
  for _, line in ipairs(lines) do GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1) end
  GameTooltip:Show()
end

local function HideBreakdown(button)
  if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end

-- Writes a row button's text for the service its ID names, giving the button its text and hover
-- breakdown the first time
local function Annotate(button)
  if not button.marketWallText then
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    text:SetJustifyH("RIGHT")
    button.marketWallText = text
    button:HookScript("OnEnter", function(self) pcall(ShowBreakdown, self) end)
    button:HookScript("OnLeave", HideBreakdown)
  end
  button.marketWallText:SetText(Trainer.RowText(button:GetID()) or "")
end

-- Classic's fixed rows, ClassTrainerSkill1 onward
local function ClassicRows()
  local buttons, i = {}, 1
  while _G["ClassTrainerSkill" .. i] do
    buttons[i] = _G["ClassTrainerSkill" .. i]
    i = i + 1
  end
  return buttons
end

local hooked = false

-- Hooks the trainer window once it has loaded; nothing when the client lacks it or a trainer call.
-- Both windows set each row button's ID to the service index it shows.
function Trainer.HookWindow()
  if hooked or not Trainer.HasAPI() then return end
  if type(_G.ClassTrainerFrame_InitServiceButton) == "function" then
    -- Forever: a scroll box reuses row buttons, each set up here for the service it now shows
    hooked = true
    hooksecurefunc("ClassTrainerFrame_InitServiceButton", function(button) pcall(Annotate, button) end)
  elseif type(_G.ClassTrainerFrame_Update) == "function" and _G.ClassTrainerSkill1 then
    hooked = true
    local buttons = ClassicRows()
    hooksecurefunc("ClassTrainerFrame_Update", function()
      for _, button in ipairs(buttons) do pcall(Annotate, button) end
    end)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" then
    if name == TRAINER_UI then Trainer.HookWindow() end
    return
  end
  Trainer.HookWindow()   -- in case the trainer window loaded before MarketWall
  pcall(Trainer.SaveCosts)
end)
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE" }) do
  pcall(frame.RegisterEvent, frame, event)   -- a client without trainers lacks them
end
