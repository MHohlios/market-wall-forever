-- Loads MarketWall outside the game: just enough WoW API for every TOC file to load.
local M = {}

M.ADDON = "MarketWall"

local function noop() end

-- A frame that accepts any method call and remembers its parent, events, scripts, size and
-- anchors: points[i] = { point, x, y } for anchors given as offsets from the parent
local function NewFrame(frames, parent)
  local frame = { scripts = {}, events = {}, points = {}, parent = parent }
  function frame:SetSize(width, height) self.width, self.height = width, height end
  function frame:SetWidth(width) self.width = width end
  function frame:SetHeight(height) self.height = height end
  function frame:SetPoint(point, x, y)
    if type(x) ~= "table" then self.points[#self.points + 1] = { point, x or 0, y or 0 } end
  end
  function frame:SetScript(name, fn) self.scripts[name] = fn end
  function frame:RegisterEvent(event) self.events[event] = true end
  frame.RegisterUnitEvent = frame.RegisterEvent
  function frame.CreateTexture() return NewFrame(frames) end
  frame.CreateFontString = frame.CreateTexture
  frames[#frames + 1] = frame
  return setmetatable(frame, { __index = function() return noop end })
end

-- Files listed in the TOC, in load order
function M.TocFiles()
  local files = {}
  for line in io.lines(M.ADDON .. ".toc") do
    line = line:gsub("%s+$", "")
    if line ~= "" and not line:find("^#") then files[#files + 1] = line end
  end
  return files
end

-- Fresh globals and a fresh addon namespace on every call, so tests do not share state
function M.Load()
  local frames = {}
  _G.CreateFrame = function(_, _, parent) return NewFrame(frames, parent) end
  _G.date, _G.time = os.date, os.time
  _G.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  _G.SlashCmdList = {}
  _G.StaticPopupDialogs = {}
  _G.MarketWallDB = nil   -- SavedVariables arrive empty on a first login

  local ns = {}
  for _, file in ipairs(M.TocFiles()) do
    local chunk = assert(loadfile(file))
    chunk(M.ADDON, ns)
  end

  local function Fire(event, ...)
    for _, frame in ipairs(frames) do
      if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
  end

  return ns, Fire, frames
end

return M
