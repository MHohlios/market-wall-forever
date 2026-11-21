local addon = require("spec.helpers.addon")

local ID = 7
local HEADING, HINT = "|cff2fa39d", "|cff5d6464"
local BRIGHT, WHITE, FADED, DIM = "|cff3fe6d6", "|cffffffff", "|cff868d8d", "|cff6f7676"
local FADED_NA = FADED .. "n/a (first scan)|r"

describe("item tooltip lines", function()
  local ns, Fire, tooltip, shift

  -- A tooltip that records its lines as "left|right" strings, and its double lines' sides apart
  local function NewTooltip(owner)
    local lines, doubles = {}, {}
    return {
      lines = lines,
      doubles = doubles,
      GetOwner = function() return owner end,
      AddLine = function(_, text) lines[#lines + 1] = text end,
      AddDoubleLine = function(_, left, right)
        lines[#lines + 1] = left .. "|" .. right
        doubles[#doubles + 1] = { left = left, right = right }
      end,
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

  -- Index of the first line containing the text, nil without one
  local function Find(text)
    for i, line in ipairs(tooltip.lines) do
      if line:find(text, 1, true) then return i end
    end
  end

  -- The labels of the bright rows: the best outlet's, or none
  local function BrightRows()
    local labels = {}
    for _, line in ipairs(tooltip.lines) do
      local label = line:match("^  " .. BRIGHT .. "(.-)|r")
      if label then labels[#labels + 1] = label end
    end
    return labels
  end

  before_each(function()
    ns, Fire = addon.Load()
    _G.MarketWallDB = { version = 1, cfg = {}, realms = {}, depositRate = {}, containers = {} }
    _G.C_Item = {}
    shift = false
    _G.IsShiftKeyDown = function() return shift end
    tooltip = NewTooltip()
  end)

  after_each(function()
    _G.MarketWallDB, _G.C_Item, _G.C_Container, _G.IsShiftKeyDown = nil, nil, nil, nil
  end)

  describe("7-day trend, with Shift held", function()
    before_each(function() shift = true end)

    it("shows nothing for a never-scanned item", function()
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({}, tooltip.lines)
    end)

    it("reads n/a on an item's first scan", function()
      SeedWalls(1000)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Market|r"))
      assert.is_true(Has("7-day trend|r|" .. FADED_NA))
    end)

    it("reads a plain n/a when the only other price is older than 7 days", function()
      ns.R().days[ID] = { [ns.Today() - 10] = { 900 }, [ns.Today()] = { 1000 } }
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("7-day trend|r|" .. FADED .. "n/a|r"))
      assert.is_false(Has("first scan"))
    end)

    it("reads a plain n/a for both when the last scan is older than the baseline window", function()
      ns.R().days[ID] = { [ns.Today() - 20] = { 1000 } }
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("Against median (last scan)|r|" .. FADED .. "n/a|r"))
      assert.is_true(Has("7-day trend|r|" .. FADED .. "n/a|r"))
    end)

    it("names a rise past 3% up and a fall past 3% down", function()
      SeedWalls(1000, 1060)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("7-day trend|r|"))
      assert.is_true(Has(ns.PriceView.UP .. " 6%"))

      tooltip = NewTooltip()
      SeedWalls(1000, 940)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has(ns.PriceView.DOWN .. " 6%"))
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
      assert.is_true(Has(ns.PriceView.UP .. " 3%"))

      tooltip = NewTooltip()
      SeedWalls(1000, 969)
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has(ns.PriceView.DOWN .. " 3%"))
    end)
  end)

  describe("stack total", function()
    local function BagSlot(info)
      _G.C_Container = { GetContainerItemInfo = function() return info end }
      return { GetSlotAndBagID = function() return 4, 0 end }
    end

    before_each(function()
      SeedWalls(1000)
      ns.R().supplied[ID] = true
    end)

    it("multiplies the best outlet's net by the stack size, as a faded row", function()
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Has("  " .. FADED .. "Stack of 20|r|" .. FADED .. ns.MoneyFaded(950 * 20)))   -- the wall after the 5% cut
    end)

    it("shows nothing without a best outlet, such as a thin market and no vendor price", function()
      ns.R().supplied[ID] = nil
      tooltip = NewTooltip(BagSlot({ itemID = ID, stackCount = 20 }))
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_false(Has("Stack of"))
      assert.same({}, BrightRows())
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
      assert.is_false(Has("Stack of"))
    end)
  end)

  describe("outlets and disenchant materials", function()
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
      Item(ESSENCE, "Essence", { quality = UNCOMMON, classID = 7 })
      Item(SHARD, "Shard", { classID = 7 })
      -- disenchant value 75% × 2.5 × 100 + 20% × 1.5 × 1000 + 5% × 2000 = 587.5, 558 after the cut
      Wall(DUST, 100)
      Wall(ESSENCE, 1000)
      Wall(SHARD, 2000)
    end)

    -- Asserts each text is in its line, in order, and that there are no more lines
    local function AssertLines(order)
      for i, text in ipairs(order) do
        assert.truthy(tooltip.lines[i] and tooltip.lines[i]:find(text, 1, true), text)
      end
      assert.equal(#order, #tooltip.lines)
    end

    it("lists the heading, the low-data flag and Market, Vendor and Disenchant", function()
      SeedWalls(500, 500, 500, 500)
      ns.R().supplied[ID] = true
      ns.R().watch[ID] = { buy = 400 }
      ns.TooltipLines.Add(tooltip, ID)
      AssertLines({ " ", HEADING .. "MarketWall|r|" .. HINT .. "Shift: details|r", "Only 4 days of data",
        "  " .. FADED .. "Market|r", "Vendor|r", "Disenchant|r" })
    end)

    it("adds the materials under Disenchant and the market context at the end while Shift is held", function()
      SeedWalls(500, 500, 500, 500)
      ns.R().supplied[ID] = true
      ns.R().watch[ID] = { buy = 400 }
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      AssertLines({ " ", HEADING .. "MarketWall|r|", "Only 4 days of data", "Market|r", "Vendor|r", "Disenchant|r",
        "75%  2–3  Dust", "20%  1–2  Essence", "5%  1  Shard", "Classic table · range",
        "Against median|r", "7-day trend|r", "Your buy / sell|r" })
    end)

    it("hints at Shift only when it would add detail, and not while it is held", function()
      ns.TooltipLines.Add(tooltip, ID)   -- never scanned, but it can be disenchanted
      assert.equal(HEADING .. "MarketWall|r|" .. HINT .. "Shift: details|r", tooltip.lines[2])

      shift = true
      tooltip = NewTooltip()
      ns.TooltipLines.Add(tooltip, ID)
      assert.equal(HEADING .. "MarketWall|r|", tooltip.lines[2])

      shift = false
      Item(ID, "Potion", { quality = UNCOMMON, level = 18, classID = CONSUMABLE, vendor = 100 })
      tooltip = NewTooltip()
      ns.TooltipLines.Add(tooltip, ID)   -- no wall, no materials, no conversion
      assert.equal(HEADING .. "MarketWall|r|", tooltip.lines[2])
    end)

    it("hides the materials and market context without Shift", function()
      SeedWalls(500, 500, 500, 500)
      ns.R().watch[ID] = { buy = 400 }
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_nil(Find("Dust"))
      assert.is_nil(Find("Against median"))
      assert.is_nil(Find("7-day trend"))
      assert.is_nil(Find("Your buy"))
    end)

    it("shows one net price per outlet: no (net) labels, no total in mats, no odds footer and no best tag", function()
      SeedWalls(500, 500, 500, 500)
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      for _, gone in ipairs({ "(net)", "in mats", "odds", "best" }) do assert.is_nil(Find(gone), gone) end
    end)

    it("brightens the vendor over a lower disenchant when there is no wall, as for a soulbound item", function()
      items[ID].vendor = 600
      ns.TooltipLines.Add(tooltip, ID)
      AssertLines({ " ", "MarketWall", "  " .. FADED .. "Market|r|" .. FADED .. "no price|r",
        "  " .. BRIGHT .. "Vendor|r|" .. WHITE .. ns.Money(600) .. "|r",
        "  " .. FADED .. "Disenchant|r|" .. FADED .. ns.MoneyFaded(558.125) .. "|r" })
    end)

    it("brightens disenchanting without a wall when it pays more, unless the setting leaves it out", function()
      ns.TooltipLines.Add(tooltip, ID)   -- 558 from disenchanting, against a 100c vendor price
      assert.same({ "Disenchant" }, BrightRows())

      MarketWallDB.cfg.mobDisenchant = "never"
      tooltip = NewTooltip()
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({ "Vendor" }, BrightRows())
      assert.truthy(Find("Disenchant|r|" .. FADED .. ns.MoneyFaded(558.125)))   -- still shown
    end)

    it("adds no block for an item with nothing to price: no wall, vendor price, disenchant or conversion", function()
      Item(ID, "Hearthstone", { quality = 1, level = 1, classID = CONSUMABLE })
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({}, tooltip.lines)
    end)

    it("shows the block with Market at no price when only a container value prices the item", function()
      local CLAM = 5523
      Item(CLAM, "Clam", { classID = 15 })
      MarketWallDB.containers[CLAM] = { opens = 2, coin = 30, drops = { [DUST] = 4 } }
      ns.TooltipLines.Add(tooltip, CLAM)
      assert.truthy(Find("Market|r|" .. FADED .. "no price|r"))
      assert.truthy(Find("Opens to"))
    end)

    it("notes a thin market on the Market row when a vendor is best beside a higher wall", function()
      items[ID].vendor = 400
      Wall(ID, 500)
      ns.R().supplied[ID] = nil   -- no real supply behind the wall
      MarketWallDB.cfg.mobDisenchant = "never"
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Market|r " .. FADED .. "(thin market)|r|"))
      assert.same({ "Vendor" }, BrightRows())

      tooltip = NewTooltip()
      ns.R().supplied[ID] = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_nil(Find("thin market"))
    end)

    it("puts the stack line after the outlets, at the best outlet's net", function()
      Wall(ID, 500)   -- 445 net on the market, against 558.125 from disenchanting
      _G.C_Container = { GetContainerItemInfo = function() return { itemID = ID, stackCount = 5 } end }
      tooltip = NewTooltip({ GetSlotAndBagID = function() return 4, 0 end })
      ns.TooltipLines.Add(tooltip, ID)
      assert.equal(Find("Disenchant|r") + 1, Find("Stack of 5|r|" .. FADED .. ns.MoneyFaded(558.125 * 5)))
    end)

    it("brightens disenchanting when its materials after the cut pay most", function()
      Wall(ID, 500)   -- 445 net, against 558 from disenchanting
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({ "Disenchant" }, BrightRows())
    end)

    it("brightens the market, in white money, when the wall after the cut pays most, and fades the rest", function()
      Wall(ID, 1000)   -- 950 after the cut, less 30% of the 100c vendor price
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({ "Market" }, BrightRows())
      assert.truthy(Find("Market|r|" .. WHITE .. ns.Money(920) .. "|r"))
      assert.truthy(Find("Vendor|r|" .. FADED .. ns.MoneyFaded(100) .. "|r"))
      assert.truthy(Find("Disenchant|r|" .. FADED .. ns.MoneyFaded(558.125) .. "|r"))
    end)

    it("brightens the vendor when it pays most", function()
      items[ID].vendor = 700
      Wall(ID, 500)
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({ "Vendor" }, BrightRows())
    end)

    it("takes each material's deposit off the disenchant net, and materials keep their wall", function()
      items[DUST].vendor, items[ESSENCE].vendor, items[SHARD].vendor = 10, 100, 200
      -- 75% × 2.5 × 3 + 20% × 1.5 × 30 + 5% × 60 = 17.625 in deposits at 30%
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Disenchant|r|" .. WHITE .. ns.Money(558.125 - 17.625)))
      assert.truthy(Find("  Dust|r|" .. DIM .. ns.MoneyFaded(100)))
    end)

    it("moves the bright row to the vendor once the deposits count", function()
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
      assert.same({ "Market" }, BrightRows())
      assert.truthy(Find("Market|r|" .. WHITE .. ns.Money(2090)))

      -- at the standard 30% for 24h both drop below the vendor
      MarketWallDB.depositRate[2] = nil
      tooltip = NewTooltip()
      ns.TooltipLines.Add(tooltip, ID)
      assert.same({ "Vendor" }, BrightRows())
      assert.truthy(Find("Market|r|" .. FADED .. ns.MoneyFaded(2090 - 615.6)))
      assert.truthy(Find("Disenchant|r|" .. FADED .. ns.MoneyFaded(2071 - 107.25)))
    end)

    it("shows what a container you have opened gives on average, after the outlets", function()
      local CLAM = 5523
      Item(CLAM, "Clam", { classID = 15, vendor = 5 })
      -- dust lists at 100, 95 after the cut: (30 + 4 × 95) / 2
      MarketWallDB.containers[CLAM] = { opens = 2, coin = 30, drops = { [DUST] = 4 } }
      ns.TooltipLines.Add(tooltip, CLAM)
      assert.equal(Find("Vendor|r") + 1, Find("  " .. FADED .. "Opens to avg (2 opened)|r|" .. FADED .. ns.MoneyFaded(205)))

      tooltip = NewTooltip()
      ns.TooltipLines.Add(tooltip, ID)   -- never opened
      assert.is_nil(Find("Opens to"))
    end)

    it("leaves out the vendor row without a vendor price and the disenchant rows for an item that can't be", function()
      Item(ID, "Potion", { quality = UNCOMMON, level = 18, classID = CONSUMABLE })
      Wall(ID, 500)
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Market|r"))
      assert.is_nil(Find("Vendor"))
      assert.is_nil(Find("Disenchant"))
    end)

    it("keeps the materials when one has no price yet", function()
      ns.R().days[SHARD] = nil
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Disenchant|r|" .. FADED .. "materials not scanned|r"))
      assert.truthy(Find("5%  1  Shard|r|" .. DIM .. "-|r"))
    end)

    it("shows each material's chance, how many, plain name and wall each", function()
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      local each = "|r" .. DIM .. " each|r"
      assert.truthy(Find("      " .. DIM .. "75%  2–3  Dust|r|" .. DIM .. ns.MoneyFaded(100) .. each))
      assert.truthy(Find("      " .. DIM .. "20%  1–2  Essence|r|" .. DIM .. ns.MoneyFaded(1000) .. each))
      assert.truthy(Find("      " .. DIM .. "5%  1  Shard|r|" .. DIM .. ns.MoneyFaded(2000) .. each))
      assert.is_nil(Find("×"))
    end)

    it("ends with where the odds come from and one disenchant's range after the cut and deposit", function()
      items[DUST].vendor, items[ESSENCE].vendor = 10, 100
      local depositOf = ns.Mobs.GamePrices().deposit
      local function Net(count, wall, id) return count * (wall * 0.95 - depositOf(id)) end
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      -- the fewest dust (2) up to the one shard, which beats the most essence (2) after their deposits
      assert.is_true(Net(1, 2000, SHARD) > Net(2, 1000, ESSENCE))
      local range = ns.MoneyFaded(Net(2, 100, DUST)) .. " to " .. ns.MoneyFaded(Net(1, 2000, SHARD))
      assert.equal(Find("5%  1  Shard") + 1, Find("      " .. DIM .. "Classic table · range " .. range .. "|r|"))
    end)

    it("shows an estimate's average quantity, as it has no range", function()
      local NEW_RARE, BRILLIANT = 200001, 14344
      Item(NEW_RARE, "Rare", { quality = 3, level = 60, classID = ARMOR })
      Item(BRILLIANT, "Brilliant", { classID = 7 })
      Wall(BRILLIANT, 3000)
      shift = true
      ns.TooltipLines.Add(tooltip, NEW_RARE)
      assert.truthy(Find(DIM .. "99.5%  ~1  Brilliant|r|"))
      local each = ns.MoneyFaded(3000 * 0.95 - ns.Mobs.GamePrices().deposit(BRILLIANT))
      assert.truthy(Find(DIM .. "Forever estimate · range " .. each .. " to " .. each .. "|r|"))
    end)

    it("sorts materials by chance, most likely first", function()
      ns.DisenchantOutcomes = function()
        return { { id = SHARD, chance = 0.05, quantity = 1 }, { id = DUST, chance = 0.75, quantity = 2.5 },
          { id = ESSENCE, chance = 0.2, quantity = 1.5 } }, "Classic table"
      end
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.is_true(Find(" Dust|") < Find(" Essence|"))
      assert.is_true(Find(" Essence|") < Find(" Shard|"))
    end)

    it("skips materials under 1%", function()
      -- Forever's new level 60 rare: 99.5% Large Brilliant Shard, 0.5% Nexus Crystal
      local NEW_RARE, BRILLIANT, NEXUS = 200001, 14344, 20725
      Item(NEW_RARE, "Rare", { quality = 3, level = 60, classID = ARMOR })
      Item(BRILLIANT, "Brilliant", { classID = 7 })
      Item(NEXUS, "Nexus", { classID = 7 })
      Wall(BRILLIANT, 3000)
      Wall(NEXUS, 9000)
      shift = true
      ns.TooltipLines.Add(tooltip, NEW_RARE)
      assert.truthy(Find("99.5%  ~1  Brilliant"))
      assert.is_nil(Find("Nexus"))
    end)

    it("blends your own disenchants into the chances and the ranges, and names them", function()
      local key = ns.DisenchantLog.SampleKey(ID, UNCOMMON, 18, ARMOR, false)
      MarketWallDB.disenchants = { samples = { [key] = { count = 25,
        materials = { [DUST] = { hits = 25, total = 50, min = 1, max = 3 } } } } }
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("83.3%  1–3  Dust"))   -- (50 × 75% + 25) / (50 + 25)
      assert.truthy(Find(DIM .. "Classic table + your 25 disenchants · range "))
    end)

    it("shows no normal range or cheapest / dearest time", function()
      SeedWalls(400, 500, 600, 500, 450, 550, 500)
      shift = true
      ns.TooltipLines.Add(tooltip, ID)
      assert.truthy(Find("Against median"))
      assert.is_nil(Find("Normal range"))
      assert.is_nil(Find("Cheapest"))
    end)

    describe("conversions", function()
      local IRON_ORE, IRON_BAR = 2772, 3575

      local function InStack(count)
        _G.C_Container = { GetContainerItemInfo = function() return { itemID = IRON_ORE, stackCount = count } end }
        tooltip = NewTooltip({ GetSlotAndBagID = function() return 4, 0 end })
      end

      before_each(function()
        Item(IRON_ORE, "Iron Ore", { classID = 7, vendor = 50 })
        Item(IRON_BAR, "Iron Bar", { classID = 7, vendor = 100 })
        Wall(IRON_ORE, 400)   -- 380 after the cut, less a 15c deposit: 365
      end)

      it("lists Make after the outlets, bright when it pays most, then the stack at its net as bars", function()
        Wall(IRON_BAR, 600)   -- 570 after the cut, less a 30c deposit: 540 per ore
        InStack(20)
        ns.TooltipLines.Add(tooltip, IRON_ORE)
        AssertLines({ " ", "MarketWall|r|" .. HINT .. "Shift: details", "Only 1 day", "Market|r", "Vendor|r",
          "  " .. BRIGHT .. "Make Iron Bar|r|" .. WHITE .. ns.Money(540) .. "|r",
          "Stack of 20 (as bars)|r|" .. FADED .. ns.MoneyFaded(540 * 20) })
        assert.same({ "Make Iron Bar" }, BrightRows())
      end)

      it("shows the recipe under the Make row only while Shift is held", function()
        ns.TooltipLines.Add(tooltip, IRON_ORE)
        assert.is_nil(Find("ore → "))

        shift = true
        tooltip = NewTooltip()
        ns.TooltipLines.Add(tooltip, IRON_ORE)
        assert.equal(Find("Make Iron Bar|r") + 1, Find("      " .. DIM .. "1 ore → 1 bar|r|"))
      end)

      it("leaves the market bright and the stack on it when bars net less", function()
        Wall(IRON_BAR, 300)   -- 255 per ore
        InStack(20)
        ns.TooltipLines.Add(tooltip, IRON_ORE)
        assert.same({ "Market" }, BrightRows())
        assert.truthy(Find("Make Iron Bar|r|" .. FADED .. ns.MoneyFaded(255)))
        assert.truthy(Find("Stack of 20|r|" .. FADED .. ns.MoneyFaded(365 * 20)))
        assert.is_nil(Find("as bars"))
      end)

      it("notes a thin product market and keeps it from the bright row and the stack", function()
        Wall(IRON_BAR, 600)   -- 540 per ore, above the ore's 365, but no real supply behind it
        ns.R().supplied[IRON_BAR] = nil
        InStack(20)
        ns.TooltipLines.Add(tooltip, IRON_ORE)
        assert.truthy(Find("Make Iron Bar|r " .. FADED .. "(thin market)|r|" .. FADED .. ns.MoneyFaded(540)))
        assert.same({ "Market" }, BrightRows())
        assert.truthy(Find("Stack of 20|r|" .. FADED .. ns.MoneyFaded(365 * 20)))
      end)

      it("splits the product's net across the cloth it takes", function()
        local LINEN, BOLT = 2589, 2996
        Item(LINEN, "Linen Cloth", { classID = 7 })
        Item(BOLT, "Bolt of Linen Cloth", { classID = 7 })
        Wall(LINEN, 10)
        Wall(BOLT, 100)   -- 95 after the cut, for 2 cloth
        shift = true
        ns.TooltipLines.Add(tooltip, LINEN)
        assert.truthy(Find("  " .. BRIGHT .. "Make Bolt of Linen Cloth|r|" .. WHITE .. ns.Money(47.5)))
        assert.truthy(Find("2 cloth → 1 bolt"))
      end)

      it("takes 8 Dark Iron Ore for a bar", function()
        local DARK_ORE, DARK_BAR = 11370, 11371
        Item(DARK_ORE, "Dark Iron Ore", { classID = 7 })
        Item(DARK_BAR, "Dark Iron Bar", { classID = 7 })
        Wall(DARK_ORE, 900)
        Wall(DARK_BAR, 8000)   -- 7600 after the cut, for 8 ore
        shift = true
        ns.TooltipLines.Add(tooltip, DARK_ORE)
        assert.truthy(Find("  " .. BRIGHT .. "Make Dark Iron Bar|r|" .. WHITE .. ns.Money(950)))
        assert.truthy(Find("8 ore → 1 bar"))
      end)

      it("keeps only a price in the right column of every row, notes going on the left", function()
        local function AssertMoneyOnly()
          local checked = 0
          for _, line in ipairs(tooltip.doubles) do
            if line.left:find("^  " .. BRIGHT) or line.left:find("^  " .. FADED) then
              local leftover = line.right:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                :gsub("%-?%d+|T[^|]+|t", ""):gsub(" ", "")
              assert.equal("", leftover, line.left)
              checked = checked + 1
            end
          end
          return checked
        end

        Wall(IRON_BAR, 600)
        InStack(20)
        ns.TooltipLines.Add(tooltip, IRON_ORE)   -- Market, Vendor, Make Iron Bar, Stack
        assert.equal(4, AssertMoneyOnly())

        Wall(ID, 500)
        ns.R().supplied[ID] = nil   -- thin market
        _G.C_Container = { GetContainerItemInfo = function() return { itemID = ID, stackCount = 5 } end }
        tooltip = NewTooltip({ GetSlotAndBagID = function() return 4, 0 end })
        ns.TooltipLines.Add(tooltip, ID)   -- Market, Vendor, Disenchant, Stack
        assert.equal(4, AssertMoneyOnly())

        local CLAM = 5523
        Item(CLAM, "Clam", { classID = 15, vendor = 5 })
        Wall(CLAM, 50)
        MarketWallDB.containers[CLAM] = { opens = 2, coin = 30, drops = { [DUST] = 4 } }
        tooltip = NewTooltip()
        ns.TooltipLines.Add(tooltip, CLAM)   -- Market, Vendor, Opens to
        assert.equal(3, AssertMoneyOnly())
      end)

      it("says the product is not scanned without a wall for it, and leaves the market bright", function()
        ns.TooltipLines.Add(tooltip, IRON_ORE)
        assert.truthy(Find("Make Iron Bar|r|" .. FADED .. "Iron Bar not scanned|r"))
        assert.same({ "Market" }, BrightRows())
      end)
    end)
  end)

  describe("Shift redraw", function()
    local refreshes

    before_each(function()
      refreshes = 0
      _G.TooltipDataProcessor = { AddTooltipPostCall = function() end }
      _G.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
      _G.GameTooltip = {
        IsShown = function() return true end,
        GetItem = function() return "Vest", "link" end,
        RefreshData = function() refreshes = refreshes + 1 end,
      }
      _G.ItemRefTooltip = { IsShown = function() return false end }
      ns.InitTooltip()
    end)

    after_each(function()
      _G.TooltipDataProcessor, _G.Enum, _G.GameTooltip, _G.ItemRefTooltip = nil, nil, nil, nil
    end)

    it("redraws a shown item tooltip when either Shift goes down or up, and not for other keys", function()
      Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
      Fire("MODIFIER_STATE_CHANGED", "RSHIFT", 0)
      Fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
      assert.equal(2, refreshes)
    end)

    it("leaves a tooltip that shows no item alone", function()
      _G.GameTooltip.GetItem = function() return nil end
      Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
      assert.equal(0, refreshes)
    end)
  end)
end)
