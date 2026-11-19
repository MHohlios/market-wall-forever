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

  -- The lines as "left|right" strings
  local function Texts(lines)
    local texts = {}
    for i, line in ipairs(lines) do texts[i] = line[1] .. "|" .. line[2] end
    return texts
  end

  local GOLD, ORANGE = "|cfff5c518", "|cffffb057"

  describe("lines", function()
    local Lines
    before_each(function() Lines = ns.TooltipLines.Mob end)

    local function Worth()
      return GOLD .. "Worth per kill|r|" .. ns.Money(95) .. " " .. GREY .. "typical|r · " .. ns.Money(320) .. " " .. GREY .. "avg|r"
    end
    -- All grey, the amounts without their coin colours
    local function Outlets(skin)
      return GREY .. "Vendor 45c · Market 62c" .. (skin or "") .. "|r"
    end

    it("shows Optimal worth per kill, each outlet's median beside the kills, and the top drop", function()
      assert.same({
        Worth(),
        Outlets(" · Skin 30c") .. "|" .. GREY .. "140 kills|r",
        GREY .. "Top drop|r|Raptor Hide " .. GREY .. "4%|r",
      }, Texts(Lines(FullStats(), true, 10)))
    end)

    it("leaves out skinning when it is not included", function()
      assert.equal(Outlets() .. "|" .. GREY .. "140 kills|r", Texts(Lines(FullStats(), false, 10))[2])
    end)

    it("rounds the top drop's share to a whole percent", function()
      local stats = FullStats()
      stats.top.share = 0.675
      assert.equal(GREY .. "Top drop|r|Raptor Hide " .. GREY .. "68%|r", Texts(Lines(stats, false, 10))[3])
    end)

    it("leaves out the top drop when nothing dropped", function()
      local stats = FullStats()
      stats.top = nil
      assert.equal(2, #Lines(stats, false, 10))
    end)

    it("shows values from one kill, flagging fewer than the reliable kills in orange", function()
      local stats = FullStats()
      stats.seen = 1
      local texts = Texts(Lines(stats, false, 10))
      assert.equal(Worth(), texts[1])
      assert.equal(Outlets() .. "|" .. ORANGE .. "< 10 kills|r", texts[2])
    end)

    it("shows the kill count in grey from exactly the reliable kills", function()
      local stats = FullStats()
      stats.seen = 10
      assert.equal(Outlets() .. "|" .. GREY .. "10 kills|r", Texts(Lines(stats, false, 10))[2])
    end)

    it("shows nothing for a mob with no record or no seen kill", function()
      assert.same({}, Lines(nil, true, 10))
      assert.same({}, Lines({ name = "Jungle Stalker", kills = 3, lifetime = 3, seen = 0 }, true, 10))
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
      for t = 1, 2 do
        ns.Recording.Emit({ t = t, kind = "kill", npc = RAPTOR, guid = "Creature-0-1-0-1-" .. RAPTOR .. "-" .. t,
          name = "Raptor", outcome = ns.Kills.LOOTED, coin = 50, drops = { [FLESH] = 1 } })
      end
    end)

    after_each(function()
      _G.Enum, _G.TooltipDataProcessor, _G.UnitGUID, _G.GameTooltip = nil, nil, nil, nil
    end)

    local function KillCount()
      return (tooltip.lines[3]:match("|([^|]*|c%x+[^|]*|r)$"))
    end

    it("reads the creature from the mouseover GUID", function()
      guid = "Creature-0-1-0-1-" .. RAPTOR .. "-99"
      unitHook(tooltip)
      assert.equal(" ", tooltip.lines[1])
      local worth = "|cfff5c518Worth per kill|r|"
      assert.equal(worth, tooltip.lines[2]:sub(1, #worth))
      assert.equal(4, #tooltip.lines)
    end)

    it("moves the orange flag with the reliable kills setting, hiding nothing", function()
      guid = "Creature-0-1-0-1-" .. RAPTOR .. "-99"
      unitHook(tooltip)
      assert.equal("|cffffb057< 10 kills|r", KillCount())
      tooltip.lines = {}
      MarketWallDB.cfg.mobMinKills = 2
      unitHook(tooltip)
      assert.equal(4, #tooltip.lines)
      assert.equal(GREY .. "2 kills|r", KillCount())
    end)

    it("adds nothing for a mob whose kills were all looted by someone else", function()
      ns.Recording.Emit({ t = 3, kind = "kill", npc = 999, guid = "Creature-0-1-0-1-999-3", outcome = ns.Kills.UNSEEN })
      guid = "Creature-0-1-0-1-999-3"
      unitHook(tooltip)
      assert.same({}, tooltip.lines)
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
