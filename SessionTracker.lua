-- MarketWall: the running-session tracker. A small movable frame, shown only while a farm
-- session is open, with its time, value earned and gold per hour under a lens, and Pause or
-- Resume and Stop. Its place and lens are saved in MarketWallDB.trackerPos and trackerLens.
local _, ns = ...
local Sessions = ns.Sessions

local LENSES = ns.MobsView.LENSES
local TICK = 1   -- seconds between refreshes

local tracker

local function Lens()
  return MarketWallDB.trackerLens or LENSES[1].key
end

local function LensLabel(key)
  for _, lens in ipairs(LENSES) do
    if lens.key == key then return lens.label end
  end
end

local function NextLens(key)
  for i, lens in ipairs(LENSES) do
    if lens.key == key then return LENSES[i % #LENSES + 1].key end
  end
  return LENSES[1].key
end

local function Line(f, y, label)
  local w = ns.widgets
  local name = w.MakeText(f, "GameFontDisableSmall")
  name:SetPoint("TOPLEFT", 10, y)
  name:SetText(label)
  local value = w.MakeText(f, "GameFontHighlightSmall", "RIGHT")
  value:SetPoint("TOPRIGHT", -10, y)
  return value
end

local function SavePosition(f)
  local point, _, relativePoint, x, y = f:GetPoint()
  MarketWallDB.trackerPos = { point, relativePoint, x, y }
end

local function Build()
  local w = ns.widgets
  local f = CreateFrame("Frame", "MarketWallSessionTracker", UIParent)
  f:SetSize(220, 100)
  local pos = MarketWallDB.trackerPos
  if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("TOPRIGHT", -220, -220) end
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition(self)
  end)
  local edge = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  edge:SetAllPoints()
  edge:SetColorTexture(0.35, 0.29, 0.16, 1)
  local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetPoint("TOPLEFT", 1, -1)
  bg:SetPoint("BOTTOMRIGHT", -1, 1)
  bg:SetColorTexture(0.05, 0.07, 0.07, 0.92)

  f.title = w.MakeText(f, "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -8)
  f.title:SetPoint("RIGHT", -10, 0)
  f.title:SetWordWrap(false)
  f.elapsed = Line(f, -28, "Elapsed")
  f.value = Line(f, -42, "Value earned")
  f.perHour = Line(f, -56, "Gold / hour")

  f.pause = w.MakeButton(f, "Pause", 64)
  f.pause:SetPoint("BOTTOMLEFT", 8, 8)
  f.pause:SetScript("OnClick", function()
    local s = Sessions.Current()
    if s and s.pausedAt then Sessions.Resume() else Sessions.Pause() end
    ns.UpdateSessionTracker()
  end)
  f.stop = w.MakeButton(f, "Stop", 56)
  f.stop:SetPoint("LEFT", f.pause, "RIGHT", 4, 0)
  f.stop:SetScript("OnClick", function()
    Sessions.Stop()
    ns.UpdateSessionTracker()
  end)
  f.lens = w.MakeButton(f, "", 76)
  f.lens:SetPoint("LEFT", f.stop, "RIGHT", 4, 0)
  f.lens:SetScript("OnClick", function()
    MarketWallDB.trackerLens = NextLens(Lens())
    ns.UpdateSessionTracker()
  end)
  f.lens:SetScript("OnEnter", function(self)
    w.ShowTip(self, "Lens", "Values items at Optimal, Market or Vendor prices. Click for the next.")
  end)
  f.lens:SetScript("OnLeave", w.HideTip)
  tracker = f
end

local shownState   -- "running", "paused" or "none", as last shown

-- Shows the open session, or hides the tracker when none is. Starting, pausing, resuming or
-- stopping, from any of its controls, redraws the search window too.
function ns.UpdateSessionTracker()
  local s = Sessions.Current()
  local state = s and (s.pausedAt and "paused" or "running") or "none"
  if state ~= shownState then
    shownState = state
    ns.SearchChanged()
  end
  if not s then
    if tracker then tracker:Hide() end
    return
  end
  if not tracker then Build() end
  local lens = Lens()
  local text = ns.SessionsView.TrackerText(s, Sessions.ReportFor(s, lens))
  tracker.title:SetText(text.title)
  tracker.elapsed:SetText(text.elapsed)
  tracker.value:SetText(text.value)
  tracker.perHour:SetText(text.perHour)
  tracker.pause:SetText(s.pausedAt and "Resume" or "Pause")
  tracker.lens:SetText(LensLabel(lens))
  tracker:Show()
end

-- Ticks from login, when the sessions and prices are ready
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent", function(self)
  local elapsed = TICK
  self:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= TICK then
      elapsed = 0
      ns.UpdateSessionTracker()
    end
  end)
end)
