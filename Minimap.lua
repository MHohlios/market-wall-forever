-- MarketWall: the MW button on the minimap's edge. Click opens the search window, right-click
-- the farm session menu; drag moves it.
local _, ns = ...

local M = {}
ns.MinimapButton = M

M.DEFAULT_ANGLE = 225   -- degrees counter-clockwise from the right: bottom left
local EDGE = 5          -- how far past the minimap's edge the button's centre sits

-- Offset from the minimap's centre for a button at this angle and distance
function M.Offset(angle, radius)
  local rad = math.rad(angle)
  return math.cos(rad) * radius, math.sin(rad) * radius
end

-- The angle, from 0 up to 360, of a point offset from the minimap's centre
function M.Angle(dx, dy)
  return math.deg(math.atan2(dy, dx)) % 360
end

local button

local function Place()
  local x, y = M.Offset(MarketWallDB.minimapAngle or M.DEFAULT_ANGLE, Minimap:GetWidth() / 2 + EDGE)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function FollowCursor()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  MarketWallDB.minimapAngle = M.Angle(cx / scale - mx, cy / scale - my)
  Place()
end

-- Right-click: start, pause or resume, stop and open farm sessions
local function SessionMenu()
  local S = ns.Sessions
  local s = S.Current()
  local items = {
    { text = "Farm session" },
    { text = "Start session...", disabled = s ~= nil, onClick = function()
      local recent = ns.SessionsView.RecentLabels(MarketWallDB.sessions, 1)
      ns.widgets.Prompt("Label for the new session:", recent[1], S.Start)
    end },
  }
  if not s then
    for _, label in ipairs(ns.SessionsView.RecentLabels(MarketWallDB.sessions, ns.SessionsView.RECENT_LABELS)) do
      items[#items + 1] = { text = "    Start \"" .. label .. "\"", onClick = function() S.Start(label) end }
    end
  end
  items[#items + 1] = { text = s and s.pausedAt and "Resume" or "Pause", disabled = s == nil,
    onClick = function() if s.pausedAt then S.Resume() else S.Pause() end end }
  items[#items + 1] = { text = "Stop", disabled = s == nil, onClick = S.Stop }
  items[#items + 1] = { text = "Open sessions", onClick = ns.OpenSessions }
  ns.widgets.ShowMenu(items)
end

function ns.UpdateMinimapButton()
  if button then button:SetShown(ns.Cfg("minimapButton")) end
end

function ns.InitMinimapButton()
  if button or not Minimap then return end
  button = CreateFrame("Button", "MarketWallMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetSize(20, 20)
  background:SetPoint("TOPLEFT", 7, -5)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  local label = button:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  label:SetPoint("CENTER", background, "CENTER", 0, 0)
  label:SetText("MW")

  button:SetScript("OnClick", function(_, mouse)
    GameTooltip:Hide()
    if mouse == "RightButton" then SessionMenu() else ns.ToggleSearch() end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("MarketWall: click to search prices, right-click for farm sessions")
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  button:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", FollowCursor)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

  Place()
  ns.UpdateMinimapButton()
end
