local addon = require("spec.helpers.addon")

local RAPTOR, HIDE, FLESH = 1020, 4304, 12184
local GREY = "|cffa3acac"

describe("mob tooltip", function()
  local ns, fire

  before_each(function()
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    _G.C_Item = {}
    ns.R().names[HIDE] = "Raptor Hide"
  end)

  local function Summary(median, average) return { median = median, average = average } end

  local function FullStats()
    return {
      name = "Stranglethorn Raptor", kills = 142, lifetime = 142, seen = 140,
      vendor = Summary(45, 112), market = Summary(62, 280), skinning = Summary(30, 34),
      optimal = { median = 95, average = 320, label = "Optimal (incl. skinning, DE)" },
      optimalNoRare = Summary(90, 105),
      top = { id = HIDE, share = 0.042 },
    }
  end

  -- The lines as "left|right" strings, or the text of a single line
  local function Texts(lines)
    local texts = {}
    for i, line in ipairs(lines) do texts[i] = line[2] and (line[1] .. "|" .. line[2]) or line[1] end
    return texts
  end

  local GOLD = "|cfff5c518"

  describe("lines", function()
    local Lines
    before_each(function() Lines = ns.TooltipLines.Mob end)

    it("shows seen kills, a median and an average block, without-rare and the top drop", function()
      assert.same({
        "Stranglethorn Raptor|" .. GREY .. "140 kills (2 unseen)|r",
        GOLD .. "Median per kill|r",
        GREY .. "  Vendor|r|" .. ns.Money(45),
        GREY .. "  Market|r|" .. ns.Money(62),
        GREY .. "  Skinning|r|" .. ns.Money(30),
        "  Optimal " .. GREY .. "(incl. skinning, DE)|r|" .. ns.Money(95),
        GOLD .. "Average per kill|r",
        GREY .. "  Vendor|r|" .. ns.Money(112),
        GREY .. "  Market|r|" .. ns.Money(280),
        GREY .. "  Skinning|r|" .. ns.Money(34),
        "  Optimal " .. GREY .. "(incl. skinning, DE)|r|" .. ns.Money(320),
        GREY .. "  Optimal, without rare drops|r|" .. ns.Money(105),
        GREY .. "Top drop:|r Raptor Hide 4.2%" .. GREY .. " of kills|r",
      }, Texts(Lines(FullStats(), true, 10)))
    end)

    it("leaves out skinning when it is not included", function()
      local texts = Texts(Lines(FullStats(), false, 10))
      assert.equal(11, #texts)
      assert.equal(GREY .. "  Market|r|" .. ns.Money(62), texts[4])
      assert.equal(GOLD .. "Average per kill|r", texts[6])
    end)

    it("shows a bare Optimal label when it includes neither skinning nor disenchanting", function()
      local stats = FullStats()
      stats.optimal.label = "Optimal"
      assert.equal("  Optimal|" .. ns.Money(95), Texts(Lines(stats, false, 10))[5])
    end)

    it("shows only the seen kill count, which the minimum counts, below the minimum kills", function()
      local stats = { name = "Jungle Stalker", kills = 12, lifetime = 12, seen = 7 }
      assert.same({ "Jungle Stalker|" .. GREY .. "7 kills (5 unseen)|r", GREY .. "Values show from 10 kills.|r" },
        Texts(Lines(stats, true, 10)))
    end)

    it("shows nothing for a mob with no record", function()
      assert.same({}, Lines(nil, true, 10))
    end)
  end)

  describe("on hover", function()
    local unitHook, guid, tooltip

    before_each(function()
      _G.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
      _G.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 2 then unitHook = fn end end }
      _G.UnitGUID = function(unit) return unit == "mouseover" and guid or nil end
      tooltip = { lines = {} }
      function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
      function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. "|" .. right end
      _G.GameTooltip = tooltip
      ns.InitTooltip()
      MarketWallDB.cfg.mobMinKills = 1
      for t = 1, 2 do
        ns.Recording.Emit({ t = t, kind = "kill", npc = RAPTOR, guid = "Creature-0-1-0-1-" .. RAPTOR .. "-" .. t,
          name = "Raptor", outcome = ns.Kills.LOOTED, coin = 50, drops = { [FLESH] = 1 } })
      end
    end)

    after_each(function()
      _G.Enum, _G.TooltipDataProcessor, _G.UnitGUID, _G.GameTooltip = nil, nil, nil, nil
    end)

    it("reads the creature from the mouseover GUID", function()
      guid = "Creature-0-1-0-1-" .. RAPTOR .. "-99"
      unitHook(tooltip)
      assert.equal("Raptor|" .. GREY .. "2 kills|r", tooltip.lines[2])
    end)

    it("adds nothing for players, pets or creatures with no record", function()
      for _, g in ipairs({ "Player-1-0ABC", "Pet-0-1-0-1-" .. RAPTOR .. "-1", "Creature-0-1-0-1-999-1" }) do
        guid = g
        unitHook(tooltip)
      end
      assert.same({}, tooltip.lines)
    end)

    it("keeps the cached values until the mob gets a new kill", function()
      local first = ns.Mobs.For(RAPTOR)
      assert.equal(first, ns.Mobs.For(RAPTOR))
      ns.Recording.Emit({ t = 3, kind = "kill", npc = RAPTOR, guid = "Creature-0-1-0-1-" .. RAPTOR .. "-3",
        outcome = ns.Kills.EMPTY })
      local second = ns.Mobs.For(RAPTOR)
      assert.are_not.equal(first, second)
      assert.equal(3, second.lifetime)
      ns.Mobs.Invalidate()   -- a finished scan or a settings change
      assert.are_not.equal(second, ns.Mobs.For(RAPTOR))
    end)

    it("reprices once item info that was still loading arrives", function()
      assert.equal(50, ns.Mobs.For(RAPTOR).vendor.median)   -- the flesh has no vendor price yet
      _G.C_Item = { GetItemInfo = function() return "Raptor Flesh", nil, nil, nil, nil, nil, nil, nil, nil, nil, 25 end }
      fire("GET_ITEM_INFO_RECEIVED", FLESH, true)
      assert.equal(75, ns.Mobs.For(RAPTOR).vendor.median)
    end)

    it("asks the open search window to redraw when a kill is recorded", function()
      local changed = 0
      ns.SearchChanged = function() changed = changed + 1 end
      ns.Recording.Emit({ t = 3, kind = "kill", npc = RAPTOR, guid = "Creature-0-1-0-1-" .. RAPTOR .. "-3",
        outcome = ns.Kills.EMPTY })
      assert.equal(1, changed)
    end)

    it("reprices and redraws when a disenchant is recorded", function()
      local changed = 0
      ns.SearchChanged = function() changed = changed + 1 end
      local first = ns.Mobs.For(RAPTOR)
      ns.Recording.Emit({ t = 3, kind = "disenchant", item = 1001, quality = 2, level = 28, classID = 4,
        salvager = false, materials = { [11083] = 1 } })
      assert.are_not.equal(first, ns.Mobs.For(RAPTOR))
      assert.equal(1, changed)
    end)
  end)
end)
