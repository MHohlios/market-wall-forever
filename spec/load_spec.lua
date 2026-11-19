local addon = require("spec.helpers.addon")

describe("loading the addon", function()
  it("lists only files that exist", function()
    local files = addon.TocFiles()
    assert.is_true(#files > 0)
    for _, file in ipairs(files) do
      local handle = io.open(file)
      assert.is_truthy(handle, file .. " is in the TOC but missing")
      handle:close()
    end
  end)

  it("loads every TOC file in order without error", function()
    local ns = addon.Load()
    assert.is_table(ns.Wall)
    assert.is_function(ns.BuildSellPage)    -- from Sell.lua
    assert.is_function(ns.BaitPress)        -- from BaitUI.lua, called by Bindings.xml
    assert.is_table(ns.PriceView)           -- from PriceView.lua, before Sell.lua uses it
    assert.is_function(ns.ToggleSearch)     -- from Search.lua
    assert.is_function(ns.InitMinimapButton) -- from Minimap.lua
    assert.is_function(ns.Recording.Emit)   -- the recording core, Record.lua
    assert.is_table(ns.Kills.tracker)       -- Kills.lua
    assert.is_function(ns.Containers.OpenedValue) -- Containers.lua
    assert.is_function(ns.Mobs.For)         -- Mobs.lua
    assert.is_table(ns.DisenchantLog.tracker) -- DisenchantLog.lua
    assert.is_function(ns.MobsView.Build)   -- MobsView.lua, before Search.lua builds it
    assert.is_function(ns.LedgerView.Build) -- LedgerView.lua, the same
    assert.is_function(ns.SessionsView.Build) -- SessionsView.lua, the same
    assert.is_function(ns.OpenSessions)     -- from Search.lua, for the minimap menu
    assert.is_function(ns.UpdateSessionTracker) -- SessionTracker.lua
    assert.is_function(ns.InitTooltip)      -- from Tooltip.lua, the last TOC file
  end)

  it("creates its SavedVariables on ADDON_LOADED", function()
    local _, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    assert.same({ version = 1, cfg = {}, realms = {}, mobs = {}, disenchants = {}, containers = {}, ledger = {}, sessions = {},
      sessionGroups = {}, creatures = {}, depositRate = {} }, MarketWallDB)
  end)
end)
