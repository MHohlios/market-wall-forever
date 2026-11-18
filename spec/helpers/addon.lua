-- Loads MarketWall outside the game: just enough WoW API for every TOC file to load.
local M = {}

M.ADDON = "MarketWall"

local function noop() end

-- A frame that accepts any method call and remembers its events and scripts
local function NewFrame(frames)
  local frame = { scripts = {}, events = {} }
  function frame:SetScript(name, fn) self.scripts[name] = fn end
  function frame:RegisterEvent(event) self.events[event] = true end
  frame.RegisterUnitEvent = frame.RegisterEvent
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
  _G.CreateFrame = function() return NewFrame(frames) end
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

  return ns, Fire
end

return M
