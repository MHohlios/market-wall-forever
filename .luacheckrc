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
  "AuctionHouseFrame",      -- the Market tab clears its displayMode
}

-- WoW API the addon reads
read_globals = {
  -- Lua extensions WoW exposes as globals
  "date", "time", "strtrim",
  -- Namespaces and enums
  "C_AuctionHouse", "C_Container", "C_Item", "C_Timer", "C_UnitAuras",
  "Enum", "ItemLocation", "SOUNDKIT", "TooltipDataProcessor", "ChatFrameUtil",
  -- Functions
  "CreateFrame", "GetBuildInfo", "GetItemInfo", "GetMoney", "GetNormalizedRealmName", "GetRealmName",
  "GetTime", "PlaySound", "StaticPopup_Show", "hooksecurefunc", "ChatEdit_InsertLink",
  "PanelTemplates_DeselectTab", "PanelTemplates_SelectTab", "PanelTemplates_TabResize",
  -- Frames and constants
  "UIParent", "GameTooltip", "ItemRefTooltip", "ITEM_QUALITY_COLORS", "NUM_BAG_SLOTS", "YES", "NO",
  -- Disenchantry's SavedVariables, read for your own disenchant results
  "DisenchantryDB",
}

files["spec/"] = { std = "+busted" }
