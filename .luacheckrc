-- MarketWall runs in WoW's Lua 5.1 sandbox
std = "lua51"
-- Long single-line UI layouts and data rows are the house style
max_line_length = false
exclude_files = { ".direnv/", "result/" }

-- Globals the addon defines or writes into
globals = {
  "MarketWall",
  "MarketWallDB",           -- SavedVariables
  "SLASH_MARKETWALL1",
  "SLASH_MARKETWALL2",
  "SlashCmdList",
  "StaticPopupDialogs",
  "AuctionHouseFrame",      -- the Market tab clears its displayMode and adds MarketWallFrame
  "BINDING_HEADER_MARKETWALL",            -- Key Bindings labels for Bindings.xml
  "BINDING_NAME_MARKETWALL_BAIT_ACTION",
}

-- WoW API the addon reads
read_globals = {
  -- Lua extensions WoW exposes as globals
  "date", "time", "strtrim",
  -- Namespaces and enums
  "C_AuctionHouse", "C_Container", "C_Item", "C_Timer", "C_UnitAuras",
  "Enum", "ItemLocation", "SOUNDKIT", "TooltipDataProcessor", "ChatFrameUtil",
  -- Functions
  "CreateFrame", "GetBindingKey", "GetBuildInfo", "GetItemInfo", "GetMoney", "GetNormalizedRealmName", "GetRealmName",
  "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo", "GetSpellInfo",
  "GetCursorPosition", "GetItemCount", "GetTime", "PlaySound", "UnitGUID", "UnitName", "UnitCreatureFamily", "CanLootUnit", "IsFishingLoot",
  "GetNumLootItems", "GetLootSlotInfo", "GetLootSlotLink", "GetLootSlotType", "GetLootSourceInfo",
  "StaticPopup_Show", "hooksecurefunc", "ChatEdit_InsertLink",
  "GetTradeSkillLine", "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillItemLink", "GetTradeSkillNumMade",
  "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
  "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "GetTrainerServiceSkillReq",
  "GetTrainerServiceItemLink",
  "PanelTemplates_DeselectTab", "PanelTemplates_SelectTab", "PanelTemplates_TabResize",
  -- Frames and constants
  "LibStub",                -- only to find Auctionator's tabs, when it is installed
  "UIParent", "UISpecialFrames", "Minimap", "GameTooltip", "ItemRefTooltip", "ITEM_QUALITY_COLORS", "NUM_BAG_SLOTS", "NUM_REAGENTBAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "YES", "NO", "OKAY", "CANCEL",
  -- Disenchantry's SavedVariables, imported at login (DisenchantLog.lua)
  "DisenchantryDB",
}

files["spec/"] = { std = "+busted" }
