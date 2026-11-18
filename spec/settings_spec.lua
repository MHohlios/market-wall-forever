local addon = require("spec.helpers.addon")

describe("Reset to defaults", function()
  it("clears every setting but the Salvager ones, which were imported once from Disenchantry", function()
    local ns = addon.Load()
    local cfg = { ahCut = 0.1, mobMinKills = 3, minimapButton = false, salvagerMode = "on", salvagerBonus = 15 }
    ns.ResetSettings(cfg)
    assert.same({ salvagerMode = "on", salvagerBonus = 15 }, cfg)
  end)
end)
