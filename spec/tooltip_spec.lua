local addon = require("spec.helpers.addon")

local ID = 7
local GREY = "|cffa3acac"
local GREY_NA = GREY .. "n/a (first scan)|r"

describe("item tooltip lines", function()
  local ns, tooltip

  -- A tooltip that records its lines as "left|right" strings
  local function NewTooltip(owner)
    local lines = {}
    return {
      lines = lines,
      GetOwner = function() return owner end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. "|" .. right end,
    }
  end

  -- Gives the item one wall per entry, oldest first, ending today
  local function SeedWalls(...)
    local walls = { ... }
    local days = {}
    for i, wall in ipairs(walls) do days[ns.Today() - (#walls - i)] = { wall } end
    ns.R().days[ID] = days
  end

  local function Has(text)
    for _, line in ipairs(tooltip.lines) do
      if line:find(text, 1, true) then return true end
    end
    return false
  end

  before_each(function()
    ns = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, depositRate = {} }
    _G.C_Item = {}
    tooltip = NewTooltip()
  end)

  after_each(function()
    _G.MarketWallDB, _G.C_Item, _G.C_Container = nil, nil, nil
  end)

  describe("7-day trend", function()
    it("shows nothing for a never-scanned item", function()
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({}, tooltip.lines)
    end)

    it("reads n/a on an item's first scan", function()
      SeedWalls(1000)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Net market|r"))
      assert.is_true(Has("7-day trend|r|" .. GREY_NA))
    end)

    it("reads a plain n/a when the only other price is older than 7 days", function()
      ns.R().days[ID] = { [ns.Today() - 10] = { 900 }, [ns.Today()] = { 1000 } }
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("7-day trend|r|" .. GREY .. "n/a|r"))
      assert.is_false(Has("first scan"))
    end)

    it("reads a plain n/a for both when the last scan is older than the baseline window", function()
      ns.R().days[ID] = { [ns.Today() - 20] = { 1000 } }
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Against median (last scan)|r|" .. GREY .. "n/a|r"))
      assert.is_true(Has("7-day trend|r|" .. GREY .. "n/a|r"))
    end)

    it("names a rise past 3% up and a fall past 3% down", function()
      SeedWalls(1000, 1060)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("7-day trend|r|"))
      assert.is_true(Has("up 6%"))

      tooltip = NewTooltip()
      SeedWalls(1000, 940)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("down 6%"))
    end)

    it("calls moves of 3% or less flat, exactly 3% included, and anything past it a trend", function()
      SeedWalls(1000, 1030)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("flat"))

      tooltip = NewTooltip()
      SeedWalls(1000, 970)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("flat"))

      tooltip = NewTooltip()
      SeedWalls(1000, 1031)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("up 3%"))

      tooltip = NewTooltip()
      SeedWalls(1000, 969)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("down 3%"))
    end)
  end)

  describe("stack total", function()
    local function BagSlot(info)
      _G.C_Container = { GetContainerItemInfo = function() return info end }
      return { GetSlotAndBagID = function() return 4, 0 end }
    end

    before_each(function() SeedWalls(1000) end)

    it("multiplies the wall by the stack size", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Stack of 20|r|" .. ns.Money(20000)))
    end)

    it("shows nothing for a stack of 1", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 1 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
    end)

    it("shows nothing when the count cannot be found", function()
      ns.TooltipLines.Add(tooltip, ID)   -- no owner
      assert.is_false(Has("Stack of"))

      tooltip = NewTooltip(BagSlot(nil))   -- empty slot
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))

      tooltip = NewTooltip(BagSlot({ itemID = ID }))   -- no stackCount
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
    end)

    it("ignores a slot that holds a different item", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID + 1, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
    end)

    it("reads the slot from the owner's id and its parent's id when it has no slot method", function()
      _G.C_Container = {
        GetContainerItemInfo = function(bag, slot)
          return bag == 2 and slot == 5 and { itemID = ID, stackCount = 3 } or nil
        end,
      }
      local owner = { GetID = function() return 5 end, GetParent = function() return { GetID = function() return 2 end } end }
      assert.equal(3, ns.TooltipLines.StackCount(NewTooltip(owner), ID))
    end)

    it("adds no stack line to a never-scanned item", function()
      ns.R().days[ID] = nil
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({}, tooltip.lines)
    end)
  end)

  describe("outlets and disenchant breakdown", function()
    local ARMOR, CONSUMABLE, UNCOMMON = 4, 0, 2
    -- Level 18 green armor: 75% for 2.5 dust, 20% for 1.5 essence, 5% for 1 shard
    local DUST, ESSENCE, SHARD = 10940, 10939, 10978
    local items

    local function Item(id, name, fields)
      items[id] = { name = name, quality = fields.quality, level = fields.level,
        vendor = fields.vendor or 0, classID = fields.classID }
    end

    local function Wall(id, price)
      ns.R().days[id] = { [ns.Today()] = { price } }
      ns.R().supplied[id] = true
    end

    -- Index of the first line containing the text, nil without one
    local function Find(text)
      for i, line in ipairs(tooltip.lines) do
        if line:find(text, 1, true) then return i end
      end
    end

    local BEST = "best|r"

    before_each(function()
      items = {}
      _G.C_Item = {
        GetItemInfo = function(id)
          local item = items[id]
          if not item then return nil end
          return item.name, "link", item.quality, item.level, 1, "", "", 1, "", 0, item.vendor, item.classID
        end,
      }
      MarketWallDB.cfg.mobDisenchant = "always"
      Item(ID, "Vest", { quality = UNCOMMON, level = 18, classID = ARMOR, vendor = 100 })
      Item(DUST, "Dust", { classID = 7 })
      Item(ESSENCE, "Essence", { classID = 7 })
      Item(SHARD, "Shard", { classID = 7 })
      -- disenchant value 75% × 2.5 × 100 + 20% × 1.5 × 1000 + 5% × 2000 = 587.5, 558 after the cut
      Wall(DUST, 100)
      Wall(ESSENCE, 1000)
      Wall(SHARD, 2000)
    end)

    it("lists Net market, Vendor and Net disenchant, then the materials, then market context", function()
      SeedWalls(500, 500, 500, 500)
      ns.R().supplied[ID] = true
      ns.R().watch[ID] = { buy = 400 }
      ns.TooltipLines.Add(tooltip, ID)
      local order = { " ", "Net market|r", "Vendor|r", "Net disenchant", "Dust", "Essence", "Shard", "odds: classic table",
        " ", "Only 4 days of data", "Against median|r", "7-day trend|r", "Your buy / sell|r" }
      for i, text in ipairs(order) do
        if text == " " then
          assert.equal(" ", tooltip.lines[i])
        else
          assert.truthy(tooltip.lines[i]:find(text, 1, true), text)
        end
      end
      assert.equal(#order, #tooltip.lines)
    end)

    it("leaves no gap after the breakdown when there is no market context", function()
      ns.TooltipLines.Add(tooltip, ID)   -- never scanned, so no wall to compare
      assert.equal(Find("odds:"), #tooltip.lines)
    end)

    it("notes a thin market on the Net market row when a vendor is best beside a higher wall", function()
      items[ID].vendor = 400
      Wall(ID, 500)
      ns.R().supplied[ID] = nil   -- no real supply behind the wall
      MarketWallDB.cfg.mobDisenchant = "never"
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(tooltip.lines[Find("Net market")]:find("(today) (thin market)|r", 1, true))
      assert.truthy(tooltip.lines[Find("Vendor")]:find(BEST, 1, true))

      tooltip = NewTooltip()
      ns.R().supplied[ID] = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_nil(Find("thin market"))
    end)

    it("puts the stack line right after Net market", function()
      Wall(ID, 500)
      _G.C_Container = { GetContainerItemInfo = function() return { itemID = ID, stackCount = 5 } end }
      tooltip = NewTooltip({ GetSlotAndBagID = function() return 4, 0 end })
      ns.TooltipLines.Add(tooltip, ID)
      assert.equal(Find("Net market|r") + 1, Find("Stack of 5"))
      assert.equal(Find("Stack of 5") + 1, Find("Vendor|r"))
    end)

    it("marks disenchanting best when its materials after the cut pay most", function()
      Wall(ID, 500)   -- 475 after the cut, against 558 from disenchanting
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(tooltip.lines[Find("Net disenchant")]:find(BEST, 1, true))
      assert.is_nil(tooltip.lines[Find("Net market|r")]:find(BEST, 1, true))
      assert.is_nil(tooltip.lines[Find("Vendor|r")]:find(BEST, 1, true))
    end)

    it("marks the market best when the wall after the cut pays most", function()
      Wall(ID, 1000)
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(tooltip.lines[Find("Net market")]:find(BEST, 1, true))
      assert.is_nil(tooltip.lines[Find("Net disenchant")]:find(BEST, 1, true))
    end)

    it("marks the vendor best when it pays most", function()
      items[ID].vendor = 700
      Wall(ID, 500)
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(tooltip.lines[Find("Vendor")]:find(BEST, 1, true))
      assert.is_nil(tooltip.lines[Find("Net disenchant")]:find(BEST, 1, true))
    end)

    it("shows the market's net after the cut and a 24h deposit, with the listed price in grey", function()
      Wall(ID, 1000)   -- 950 after the cut, less 30% of the 100c vendor price
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("|" .. ns.Money(920) .. " " .. GREY .. "· " .. ns.Money(1000) .. " listed (today)|r"))
    end)

    it("marks nothing without a wall, as the Sell page groups it with no market data", function()
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_nil(Find(BEST))
      assert.is_nil(Find("Net market"))
      assert.truthy(Find("Vendor|r|" .. ns.Money(100)))
      assert.truthy(Find("Net disenchant|r|" .. ns.Money(558.125) .. " " .. GREY .. "· " .. ns.Money(588) .. " in mats|r"))
    end)

    it("takes each material's deposit off the disenchant net and says so under the breakdown", function()
      items[DUST].vendor, items[ESSENCE].vendor, items[SHARD].vendor = 10, 100, 200
      -- 75% × 2.5 × 3 + 20% × 1.5 × 30 + 5% × 60 = 17.625 in deposits at 30%
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Net disenchant|r|" .. ns.Money(558.125 - 17.625) .. " "))
      assert.truthy(Find("odds: classic table · net after the cut and each material's deposit|r"))
      assert.truthy(Find("  Dust|" .. GREY .. "2.5× · 75%|r " .. ns.Money(100)))   -- materials keep their wall
    end)

    it("moves the best tag to the vendor once the deposits count", function()
      -- a vest the vendor buys for 20s 52c, listed at 22s, whose materials list at 21s 80c
      items[ID].vendor = 2052
      Wall(ID, 2200)
      Wall(DUST, 400)
      Wall(ESSENCE, 3000)
      Wall(SHARD, 10600)
      items[DUST].vendor, items[ESSENCE].vendor, items[SHARD].vendor = 100, 400, 1000

      -- without deposits the market pays most: 20s 90c, against 20s 71c from disenchanting
      MarketWallDB.depositRate[2] = 0
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(tooltip.lines[Find("Net market")]:find(BEST, 1, true))
      assert.truthy(Find("|" .. ns.Money(2090) .. " " .. GREY .. "· " .. ns.Money(2200) .. " listed"))

      -- at the standard 30% for 24h both drop below the vendor
      MarketWallDB.depositRate[2] = nil
      tooltip = NewTooltip()
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(tooltip.lines[Find("Vendor")]:find(BEST, 1, true))
      assert.truthy(Find("|" .. ns.Money(2090 - 615.6) .. " " .. GREY .. "· " .. ns.Money(2200) .. " listed"))
      assert.truthy(Find("|" .. ns.Money(2071 - 107.25) .. " " .. GREY .. "· " .. ns.Money(2180) .. " in mats"))
    end)

    it("leaves out the vendor row without a vendor price and the disenchant rows for an item that can't be", function()
      Item(ID, "Potion", { quality = UNCOMMON, level = 18, classID = CONSUMABLE })
      Wall(ID, 500)
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Net market"))
      assert.is_nil(Find("Vendor"))
      assert.is_nil(Find("Net disenchant"))
      assert.is_nil(Find("odds:"))
    end)

    it("keeps the breakdown when a material has no price yet", function()
      ns.R().days[SHARD] = nil
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("materials not scanned"))
      assert.truthy(Find("Shard"))
    end)

    it("shows each material's quantity, chance and wall", function()
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("  Dust|" .. "|cffa3acac2.5× · 75%|r " .. ns.Money(100)))
      assert.truthy(Find("  Essence|" .. "|cffa3acac1.5× · 20%|r " .. ns.Money(1000)))
      assert.truthy(Find("  Shard|" .. "|cffa3acac1× · 5%|r " .. ns.Money(2000)))
    end)

    it("sorts materials by chance, most likely first", function()
      ns.DisenchantOutcomes = function()
        return { { id = SHARD, chance = 0.05, quantity = 1 }, { id = DUST, chance = 0.75, quantity = 2.5 },
          { id = ESSENCE, chance = 0.2, quantity = 1.5 } }, "classic table"
      end
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Find("  Dust|") < Find("  Essence|"))
      assert.is_true(Find("  Essence|") < Find("  Shard|"))
    end)

    it("skips materials under 1% and names Forever's estimate", function()
      -- Forever's new level 60 rare: 99.5% Large Brilliant Shard, 0.5% Nexus Crystal
      local NEW_RARE, BRILLIANT, NEXUS = 200001, 14344, 20725
      Item(NEW_RARE, "Rare", { quality = 3, level = 60, classID = ARMOR })
      Item(BRILLIANT, "Brilliant", { classID = 7 })
      Item(NEXUS, "Nexus", { classID = 7 })
      Wall(BRILLIANT, 3000)
      Wall(NEXUS, 9000)
      ns.TooltipLines.Add(tooltip, NEW_RARE)
      assert.truthy(Find("1× · 99.5%"))
      assert.is_nil(Find("Nexus"))
      assert.truthy(Find("odds: Forever estimate"))
    end)

    it("names your own disenchants as the source once there are enough", function()
      local key = ns.DisenchantLog.SampleKey(ID, UNCOMMON, 18, ARMOR, false)
      MarketWallDB.disenchants = { samples = { [key] = { count = 25, materials = { [DUST] = { hits = 25, total = 50 } } } } }
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("odds: your 25 disenchants"))
      assert.truthy(Find("2× · 100%"))
    end)

    it("shows no normal range or cheapest / dearest time", function()
      SeedWalls(400, 500, 600, 500, 450, 550, 500)
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Against median"))
      assert.is_nil(Find("Normal range"))
      assert.is_nil(Find("Cheapest"))
    end)
  end)
end)
