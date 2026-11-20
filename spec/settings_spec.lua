local addon = require("spec.helpers.addon")

describe("Reset to defaults", function()
  it("clears every setting but the Salvager ones, which were imported once from Disenchantry", function()
    local ns = addon.Load()
    local cfg = { ahCut = 0.1, mobMinKills = 3, minimapButton = false, salvagerMode = "on", salvagerBonus = 15 }
    ns.ResetSettings(cfg)
    assert.same({ salvagerMode = "on", salvagerBonus = 15 }, cfg)
  end)
end)

describe("the Settings page", function()
  local SETTING_KEYS = {
    "ahCut", "wallShare", "minHistoryDays", "minSupply", "minSnipeProfit", "minSnipeDiscount", "dipPct",
    "minDisenchantProfit", "minDisenchantPct", "salvagerMode", "salvagerBonus", "autoScan", "sound", "staleMinutes",
    "baitSearchGap", "baitMinUnder", "baitConfirmPress", "mobDisenchant", "mobSkinning", "mobRareShare", "mobMinKills",
    "minimapButton",
  }

  local ns
  before_each(function() ns = addon.Load() end)

  local function Defs()
    local defs = {}
    for _, group in ipairs(ns.ui.settingGroups) do
      for _, def in ipairs(group.settings) do defs[#defs + 1] = def end
    end
    return defs
  end

  local function Def(key)
    for _, def in ipairs(Defs()) do
      if def.key == key then return def end
    end
  end

  it("lists every setting in exactly one group", function()
    local seen = {}
    for _, def in ipairs(Defs()) do
      assert.is_nil(seen[def.key], def.key .. " is in two groups")
      seen[def.key] = true
    end
    local expected = {}
    for _, key in ipairs(SETTING_KEYS) do expected[key] = true end
    assert.same(expected, seen)
  end)

  it("keeps each shortened label on the key it stores", function()
    local renamed = {
      minDisenchantProfit = "Minimum profit", minDisenchantPct = "Minimum profit %", salvagerMode = "Salvager",
      salvagerBonus = "Salvager bonus", staleMinutes = "Grey out watchlist after", baitSearchGap = "Search gap",
      baitMinUnder = "Minimum under the wall", baitConfirmPress = "Confirm each purchase",
      mobDisenchant = "Disenchanting", mobSkinning = "Skinning", mobMinKills = "Kills before reliable",
    }
    for key, label in pairs(renamed) do assert.equal(label, Def(key).label) end
  end)

  it("offers each three-way mode's stored values as Auto, On and Off", function()
    local function Switch(key)
      local shown = {}
      for _, mode in ipairs(Def(key).modes) do shown[#shown + 1] = mode.key .. "=" .. mode.label end
      return table.concat(shown, " ")
    end
    assert.equal("auto=Auto always=On never=Off", Switch("mobDisenchant"))
    assert.equal("auto=Auto always=On never=Off", Switch("mobSkinning"))
    assert.equal("auto=Auto on=On off=Off", Switch("salvagerMode"))
  end)

  it("reads a typed value with or without the unit it is shown with", function()
    assert.equal(45, ns.ui.ParseSetting(Def("staleMinutes"), "45 min"))
    assert.equal(45, ns.ui.ParseSetting(Def("staleMinutes"), "45"))
    assert.equal(2, ns.ui.ParseSetting(Def("baitSearchGap"), "2 s"))
    assert.is_nil(ns.ui.ParseSetting(Def("baitSearchGap"), "0.5 s"))
  end)

  it("saves a switch click as the stored mode", function()
    local saved
    local switch = ns.widgets.MakeSwitch(CreateFrame("Frame"), Def("mobSkinning").modes, function(key) saved = key end)
    switch.buttons[2].scripts.OnClick(switch.buttons[2])
    assert.equal("always", saved)
  end)
end)
