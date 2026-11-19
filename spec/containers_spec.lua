local addon = require("spec.helpers.addon")

local CLAM, MEAT, PEARL = 5523, 5503, 5498

describe("Containers", function()
  local ns, C

  before_each(function()
    local fire
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    C = ns.Containers
  end)

  local function Opened(coin, drops, fields)
    local event = { kind = "loot", source = "item", container = CLAM, coin = coin, drops = drops }
    for k, v in pairs(fields or {}) do event[k] = v end
    ns.Recording.Emit(event)
  end

  it("keeps each container's openings, coin and raw contents", function()
    Opened(10, { [MEAT] = 1 })
    Opened(0, { [MEAT] = 2, [PEARL] = 1 })
    assert.same({ [CLAM] = { opens = 2, coin = 10, drops = { [MEAT] = 3, [PEARL] = 1 } } }, MarketWallDB.containers)
  end)

  it("keeps nothing for a container it can't name, or for a corpse's loot", function()
    Opened(10, { [MEAT] = 1 }, { container = false })
    ns.Recording.Emit({ kind = "loot", source = "npc:1", npc = 1, coin = 5, drops = { [MEAT] = 1 } })
    assert.same({}, MarketWallDB.containers)
  end)

  describe("OpenedValue", function()
    -- MEAT sells to vendors for 6; PEARL lists at 1000 with real supply, 950 after the cut
    local prices = {
      vendor = function(id) return ({ [MEAT] = 6 })[id] end,
      wall = function(id) if id == PEARL then return 1000, true end end,
      deposit = function() return 0 end,
      disenchant = function() return nil end,
    }
    local opts = { cut = 0.05, disenchant = false }

    it("averages one opening's coin and contents at each content's best outlet", function()
      local history = { opens = 4, coin = 40, drops = { [MEAT] = 6, [PEARL] = 1 } }
      assert.equal((40 + 6 * 6 + 950) / 4, C.OpenedValue(history, prices, opts))
    end)

    it("is nil for a container never opened", function()
      assert.is_nil(C.OpenedValue(nil, prices, opts))
    end)
  end)
end)
