-- MarketWall: Classic tailoring recipes, data only. Every other profession is one more table like
-- this in ns.RecipeTables, keyed by its English name. See Crafting.lua for a recipe's fields.
--
-- Source: wow-classic-items by Nakroma (github.com/nexus-devs/wow-classic-items), MIT, see
-- LICENSES/wow-classic-items.txt. Recipes come from its Classic release 0.8.2 (commit e848aab):
-- every item it lists as made by Tailoring at skill 1 to 300, by required skill. Its later
-- releases are TBC and WotLK data with changed recipes (Bolt of Runecloth takes 4 cloth there, 5
-- in Classic); a pattern's source comes from them only where 0.8.2 has none. Each product and
-- pattern is wowhead.com/classic/item=<id>.
--
-- Not in the source, so left out: skill-up thresholds (skillUp), trainer costs, and whether a
-- vendor's pattern is limited supply. A pattern with no source listed has source nil. Vendor
-- pattern costs are as the source saw them, a few with a reputation discount.
local _, ns = ...

local TRAINER, DROP, QUEST = { kind = "trainer" }, { kind = "drop" }, { kind = "quest" }

local function Vendor(cost)
  return { kind = "vendor", cost = cost }
end

-- Learned from a pattern item, and where that pattern comes from
local function Taught(pattern, source)
  return { pattern = pattern, source = source }
end

local function R(product, name, skill, made, reagents, learn)
  if learn == TRAINER then learn = { source = TRAINER } end
  return { product = product, name = name, skill = skill, made = made, reagents = reagents,
    pattern = learn.pattern, source = learn.source }
end

ns.RecipeTables = ns.RecipeTables or {}
ns.RecipeTables.Tailoring = {
  skillLine = 197, spell = 3908,   -- for ns.ProfessionSkill

  -- Reagents a trade-goods vendor sells, at their list price. The source's vendorPrice has these
  -- a few percent low, as seen with a reputation discount.
  vendor = {
    [2320] = 10,     -- Coarse Thread
    [2321] = 100,    -- Fine Thread
    [4291] = 500,    -- Silken Thread
    [8343] = 2000,   -- Heavy Silken Thread
    [14341] = 5000,  -- Rune Thread
    [2324] = 25,     -- Bleach
    [2604] = 50,     -- Red Dye
    [6260] = 50,     -- Blue Dye
    [2605] = 100,    -- Green Dye
    [4340] = 350,    -- Gray Dye
    [4341] = 500,    -- Yellow Dye
    [2325] = 1000,   -- Black Dye
    [6261] = 1000,   -- Orange Dye
    [4342] = 2500,   -- Purple Dye
    [10290] = 2500,  -- Pink Dye
  },

  -- R(product, name, required skill, made, reagents { { item, count } }, how it is learned)
  recipes = {
  R(2996, "Bolt of Linen Cloth", 1, 1, { { 2589, 2 } }, TRAINER),
  R(4344, "Brown Linen Shirt", 1, 1, { { 2996, 1 }, { 2320, 1 } }, TRAINER),
  R(2570, "Linen Cloak", 1, 1, { { 2996, 1 }, { 2320, 1 } }, TRAINER),
  R(10045, "Simple Linen Pants", 1, 1, { { 2996, 1 }, { 2320, 1 } }, TRAINER),
  R(2576, "White Linen Shirt", 1, 1, { { 2996, 1 }, { 2320, 1 }, { 2324, 1 } }, TRAINER),
  R(2568, "Brown Linen Vest", 10, 1, { { 2996, 1 }, { 2320, 1 } }, TRAINER),
  R(7026, "Linen Belt", 15, 1, { { 2996, 1 }, { 2320, 1 } }, TRAINER),
  R(10046, "Simple Linen Boots", 20, 1, { { 2996, 2 }, { 2318, 1 }, { 2320, 1 } }, TRAINER),
  R(4343, "Brown Linen Pants", 30, 1, { { 2996, 2 }, { 2320, 1 } }, TRAINER),
  R(6238, "Brown Linen Robe", 30, 1, { { 2996, 3 }, { 2320, 1 } }, TRAINER),
  R(6241, "White Linen Robe", 30, 1, { { 2996, 3 }, { 2320, 1 }, { 2324, 1 } }, TRAINER),
  R(4307, "Heavy Linen Gloves", 35, 1, { { 2996, 2 }, { 2320, 1 } }, TRAINER),
  R(2577, "Blue Linen Shirt", 40, 1, { { 2996, 2 }, { 2320, 1 }, { 6260, 1 } }, TRAINER),
  R(2572, "Red Linen Robe", 40, 1, { { 2996, 3 }, { 2320, 2 }, { 2604, 2 } }, Taught(2598, DROP)),
  R(2575, "Red Linen Shirt", 40, 1, { { 2996, 2 }, { 2320, 1 }, { 2604, 1 } }, TRAINER),
  R(6786, "Simple Dress", 40, 1, { { 2996, 2 }, { 2320, 1 }, { 6260, 1 }, { 2324, 1 } }, TRAINER),
  R(4238, "Linen Bag", 45, 1, { { 2996, 3 }, { 2320, 3 } }, TRAINER),
  R(6240, "Blue Linen Vest", 55, 1, { { 2996, 3 }, { 2320, 1 }, { 6260, 1 } }, Taught(6270, nil)),
  R(6239, "Red Linen Vest", 55, 1, { { 2996, 3 }, { 2320, 1 }, { 2604, 1 } }, Taught(6271, DROP)),
  R(4308, "Green Linen Bracers", 60, 1, { { 2996, 3 }, { 2320, 2 }, { 2605, 1 } }, TRAINER),
  R(2580, "Reinforced Linen Cape", 60, 1, { { 2996, 2 }, { 2320, 3 } }, TRAINER),
  R(2569, "Linen Boots", 65, 1, { { 2996, 3 }, { 2320, 1 }, { 2318, 1 } }, TRAINER),
  R(2578, "Barbaric Linen Vest", 70, 1, { { 2996, 4 }, { 2318, 1 }, { 2321, 1 } }, TRAINER),
  R(6242, "Blue Linen Robe", 70, 1, { { 2996, 4 }, { 2320, 2 }, { 6260, 2 } }, Taught(6272, nil)),
  R(2579, "Green Linen Shirt", 70, 1, { { 2996, 3 }, { 2321, 1 }, { 2605, 1 } }, TRAINER),
  R(4309, "Handstitched Linen Britches", 70, 1, { { 2996, 4 }, { 2321, 2 } }, TRAINER),
  R(5762, "Red Linen Bag", 70, 1, { { 2996, 4 }, { 2321, 1 }, { 2604, 1 } }, Taught(5771, DROP)),
  R(2997, "Bolt of Woolen Cloth", 75, 1, { { 2592, 3 } }, TRAINER),
  R(10047, "Simple Kilt", 75, 1, { { 2996, 4 }, { 2321, 1 } }, TRAINER),
  R(2584, "Woolen Cape", 75, 1, { { 2997, 1 }, { 2321, 1 } }, TRAINER),
  R(4312, "Soft-soled Linen Boots", 80, 1, { { 2996, 5 }, { 2318, 2 }, { 2321, 1 } }, TRAINER),
  R(4240, "Woolen Bag", 80, 1, { { 2997, 3 }, { 2321, 1 } }, TRAINER),
  R(2582, "Green Woolen Vest", 85, 1, { { 2997, 2 }, { 2321, 2 }, { 2605, 1 } }, TRAINER),
  R(4310, "Heavy Woolen Gloves", 85, 1, { { 2997, 3 }, { 2321, 1 } }, TRAINER),
  R(5542, "Pearl-clasped Cloak", 90, 1, { { 2997, 3 }, { 2321, 2 }, { 5498, 1 } }, TRAINER),
  R(4241, "Green Woolen Bag", 95, 1, { { 2997, 4 }, { 2605, 1 }, { 2321, 1 } }, Taught(4292, DROP)),
  R(4313, "Red Woolen Boots", 95, 1, { { 2997, 4 }, { 2318, 2 }, { 2321, 1 }, { 2604, 2 } }, Taught(4345, DROP)),
  R(2583, "Woolen Boots", 95, 1, { { 2997, 4 }, { 2321, 2 }, { 2318, 2 } }, TRAINER),
  R(6263, "Blue Overalls", 100, 1, { { 2997, 4 }, { 2321, 2 }, { 6260, 2 } }, Taught(6274, nil)),
  R(2587, "Gray Woolen Shirt", 100, 1, { { 2997, 2 }, { 2321, 1 }, { 4340, 1 } }, TRAINER),
  R(4311, "Heavy Woolen Cloak", 100, 1, { { 2997, 3 }, { 2321, 2 }, { 5498, 2 } }, Taught(4346, DROP)),
  R(2585, "Gray Woolen Robe", 105, 1, { { 2997, 4 }, { 2321, 3 }, { 4340, 1 } }, Taught(2601, DROP)),
  R(4314, "Double-stitched Woolen Shoulders", 110, 1, { { 2997, 3 }, { 2321, 2 } }, TRAINER),
  R(4316, "Heavy Woolen Pants", 110, 1, { { 2997, 5 }, { 2321, 4 } }, TRAINER),
  R(4330, "Stylish Red Shirt", 110, 1, { { 2997, 3 }, { 2604, 2 }, { 2321, 1 } }, TRAINER),
  R(6787, "White Woolen Dress", 110, 1, { { 2997, 3 }, { 2324, 4 }, { 2321, 1 } }, TRAINER),
  R(6264, "Greater Adept's Robe", 115, 1, { { 2997, 5 }, { 2321, 3 }, { 2604, 3 } }, Taught(6275, nil)),
  R(5763, "Red Woolen Bag", 115, 1, { { 2997, 4 }, { 2604, 1 }, { 2321, 1 } }, Taught(5772, DROP)),
  R(10048, "Colorful Kilt", 120, 1, { { 2997, 5 }, { 2604, 3 }, { 2321, 1 } }, Taught(10316, DROP)),
  R(4315, "Reinforced Woolen Shoulders", 120, 1, { { 2997, 6 }, { 2319, 2 }, { 2321, 2 } }, Taught(4347, DROP)),
  R(6384, "Stylish Blue Shirt", 120, 1, { { 2997, 4 }, { 6260, 2 }, { 4340, 1 }, { 2321, 1 } }, Taught(6390, DROP)),
  R(6385, "Stylish Green Shirt", 120, 1, { { 2997, 4 }, { 2605, 2 }, { 4340, 1 }, { 2321, 1 } }, Taught(6391, DROP)),
  R(4305, "Bolt of Silk Cloth", 125, 1, { { 4306, 4 } }, TRAINER),
  R(4331, "Phoenix Gloves", 125, 1, { { 2997, 4 }, { 5500, 1 }, { 2321, 4 }, { 2324, 2 } }, Taught(4348, DROP)),
  R(4317, "Phoenix Pants", 125, 1, { { 2997, 6 }, { 5500, 1 }, { 2321, 3 } }, Taught(4349, DROP)),
  R(4320, "Spidersilk Boots", 125, 1, { { 4305, 2 }, { 2319, 4 }, { 3182, 4 }, { 5500, 2 } }, TRAINER),
  R(4318, "Gloves of Meditation", 130, 1, { { 2997, 4 }, { 2321, 3 }, { 3383, 1 } }, TRAINER),
  R(4332, "Bright Yellow Shirt", 135, 1, { { 4305, 1 }, { 4341, 1 }, { 2321, 1 } }, Taught(14627, Vendor(720))),
  R(5766, "Lesser Wizard's Robe", 135, 1, { { 4305, 2 }, { 2321, 2 }, { 3182, 2 } }, TRAINER),
  R(7046, "Azure Silk Pants", 140, 1, { { 4305, 4 }, { 6260, 2 }, { 2321, 3 } }, TRAINER),
  R(4321, "Spider Silk Slippers", 140, 1, { { 4305, 3 }, { 3182, 1 }, { 2321, 2 } }, Taught(4350, DROP)),
  R(4319, "Azure Silk Gloves", 145, 1, { { 4305, 3 }, { 4234, 2 }, { 6260, 2 }, { 2321, 2 } }, Taught(7114, nil)),
  R(7048, "Azure Silk Hood", 145, 1, { { 4305, 2 }, { 6260, 2 }, { 2321, 1 } }, TRAINER),
  R(7047, "Hands of Darkness", 145, 1, { { 4305, 3 }, { 4234, 2 }, { 6048, 2 }, { 2321, 2 } }, Taught(7092, DROP)),
  R(4324, "Azure Silk Vest", 150, 1, { { 4305, 5 }, { 6260, 4 } }, TRAINER),
  R(5770, "Robes of Arcana", 150, 1, { { 4305, 4 }, { 2321, 2 }, { 3182, 2 } }, Taught(5773, DROP)),
  R(4245, "Small Silk Pack", 150, 1, { { 4305, 3 }, { 4234, 2 }, { 2321, 3 } }, TRAINER),
  R(7049, "Truefaith Gloves", 150, 1, { { 4305, 3 }, { 4234, 2 }, { 929, 4 }, { 2321, 1 } }, Taught(7091, DROP)),
  R(4333, "Dark Silk Shirt", 155, 1, { { 4305, 2 }, { 4340, 2 }, { 2321, 1 } }, Taught(6401, nil)),
  R(7050, "Silk Headband", 160, 1, { { 4305, 3 }, { 2321, 2 } }, TRAINER),
  R(6795, "White Swashbuckler's Shirt", 160, 1, { { 4305, 3 }, { 2324, 2 }, { 4291, 1 } }, TRAINER),
  R(4322, "Enchanter's Cowl", 165, 1, { { 4305, 3 }, { 2321, 2 }, { 4337, 2 } }, Taught(14630, Vendor(1000))),
  R(7065, "Green Silk Armor", 165, 1, { { 4305, 5 }, { 2605, 2 }, { 4291, 1 } }, Taught(7090, DROP)),
  R(7051, "Earthen Vest", 170, 1, { { 4305, 3 }, { 7067, 1 }, { 2321, 2 } }, TRAINER),
  R(4334, "Formal White Shirt", 170, 1, { { 4305, 3 }, { 2324, 2 }, { 2321, 1 } }, TRAINER),
  R(4323, "Shadow Hood", 170, 1, { { 4305, 4 }, { 4291, 1 }, { 3824, 1 } }, Taught(4351, DROP)),
  R(7052, "Azure Silk Belt", 175, 1, { { 4305, 4 }, { 7070, 1 }, { 6260, 2 }, { 2321, 2 }, { 7071, 1 } }, TRAINER),
  R(7053, "Azure Silk Cloak", 175, 1, { { 4305, 3 }, { 6260, 2 }, { 2321, 2 } }, Taught(7089, nil)),
  R(4339, "Bolt of Mageweave", 175, 1, { { 4338, 5 } }, TRAINER),
  R(4325, "Boots of the Enchanter", 175, 1, { { 4305, 4 }, { 4291, 1 }, { 4337, 2 } }, Taught(4352, DROP)),
  R(7055, "Crimson Silk Belt", 175, 1, { { 4305, 4 }, { 7071, 1 }, { 2604, 2 }, { 4291, 1 } }, TRAINER),
  R(5764, "Green Silk Pack", 175, 1, { { 4305, 4 }, { 4234, 3 }, { 2321, 3 }, { 2605, 1 } }, Taught(5774, DROP)),
  R(6796, "Red Swashbuckler's Shirt", 175, 1, { { 4305, 3 }, { 2604, 2 }, { 4291, 1 } }, TRAINER),
  R(7056, "Crimson Silk Cloak", 180, 1, { { 4305, 5 }, { 2604, 2 }, { 6371, 2 }, { 4291, 1 } }, Taught(7087, Vendor(1200))),
  R(7057, "Green Silken Shoulders", 180, 1, { { 4305, 5 }, { 4291, 2 } }, TRAINER),
  R(4328, "Spider Belt", 180, 1, { { 4305, 4 }, { 4337, 2 }, { 7071, 1 } }, Taught(4353, DROP)),
  R(5765, "Black Silk Pack", 185, 1, { { 4305, 5 }, { 2325, 1 }, { 2321, 4 } }, Taught(5775, DROP)),
  R(7058, "Crimson Silk Vest", 185, 1, { { 4305, 4 }, { 2604, 2 }, { 2321, 2 } }, TRAINER),
  R(4326, "Long Silken Cloak", 185, 1, { { 4305, 4 }, { 3827, 1 }, { 4291, 1 } }, TRAINER),
  R(4335, "Rich Purple Silk Shirt", 185, 1, { { 4305, 4 }, { 4342, 1 }, { 4291, 1 } }, Taught(4354, DROP)),
  R(7060, "Azure Shoulders", 190, 1, { { 4305, 6 }, { 7072, 2 }, { 6260, 2 }, { 4291, 2 } }, Taught(7085, DROP)),
  R(7059, "Crimson Silk Shoulders", 190, 1, { { 4305, 5 }, { 6371, 2 }, { 2604, 2 }, { 4291, 2 } }, Taught(7084, DROP)),
  R(17723, "Green Holiday Shirt", 190, 1, { { 4305, 5 }, { 2605, 4 }, { 4291, 1 } }, Taught(17724, nil)),
  R(7054, "Robe of Power", 190, 1, { { 4339, 2 }, { 7067, 2 }, { 7070, 2 }, { 7068, 2 }, { 7069, 2 }, { 4291, 2 } }, TRAINER),
  R(7062, "Crimson Silk Pantaloons", 195, 1, { { 4305, 4 }, { 2604, 2 }, { 4291, 2 } }, TRAINER),
  R(7061, "Earthen Silk Belt", 195, 1, { { 4305, 5 }, { 7067, 4 }, { 4234, 4 }, { 7071, 1 }, { 4291, 2 } }, Taught(7086, DROP)),
  R(4336, "Black Swashbuckler's Shirt", 200, 1, { { 4305, 5 }, { 2325, 1 }, { 4291, 1 } }, Taught(10728, Vendor(1500))),
  R(4327, "Icy Cloak", 200, 1, { { 4339, 3 }, { 4291, 2 }, { 3829, 1 }, { 4337, 2 } }, Taught(4355, nil)),
  R(4329, "Star Belt", 200, 1, { { 4339, 4 }, { 4234, 4 }, { 3864, 1 }, { 7071, 1 }, { 4291, 1 } }, Taught(4356, DROP)),
  R(9999, "Black Mageweave Leggings", 205, 1, { { 4339, 2 }, { 4291, 3 } }, TRAINER),
  R(9998, "Black Mageweave Vest", 205, 1, { { 4339, 2 }, { 4291, 3 } }, TRAINER),
  R(7063, "Crimson Silk Robe", 205, 1, { { 4305, 8 }, { 7068, 4 }, { 3827, 2 }, { 2604, 4 }, { 4291, 1 } }, Taught(7088, Vendor(5000))),
  R(10001, "Black Mageweave Robe", 210, 1, { { 4339, 3 }, { 8343, 1 } }, TRAINER),
  R(7064, "Crimson Silk Gloves", 210, 1, { { 4305, 6 }, { 7068, 2 }, { 6371, 2 }, { 4304, 2 }, { 2604, 4 }, { 4291, 2 } }, TRAINER),
  R(10002, "Shadoweave Pants", 210, 1, { { 4339, 3 }, { 10285, 2 }, { 8343, 1 } }, TRAINER),
  R(10003, "Black Mageweave Gloves", 215, 1, { { 4339, 2 }, { 8343, 2 } }, TRAINER),
  R(10056, "Orange Mageweave Shirt", 215, 1, { { 4339, 1 }, { 6261, 1 }, { 8343, 1 } }, TRAINER),
  R(10009, "Red Mageweave Pants", 215, 1, { { 4339, 3 }, { 2604, 2 }, { 8343, 1 } }, Taught(10302, DROP)),
  R(10007, "Red Mageweave Vest", 215, 1, { { 4339, 3 }, { 2604, 2 }, { 8343, 1 } }, Taught(10300, DROP)),
  R(10004, "Shadoweave Robe", 215, 1, { { 4339, 3 }, { 10285, 2 }, { 8343, 1 } }, TRAINER),
  R(10008, "White Bandit Mask", 215, 1, { { 4339, 1 }, { 2324, 1 }, { 8343, 1 } }, Taught(10301, DROP)),
  R(10052, "Orange Martial Shirt", 220, 1, { { 4339, 2 }, { 6261, 2 }, { 8343, 1 } }, Taught(10311, nil)),
  R(10042, "Cindercloth Robe", 225, 1, { { 4339, 5 }, { 7077, 2 }, { 8343, 2 } }, TRAINER),
  R(10019, "Dreamweave Gloves", 225, 1, { { 4339, 4 }, { 8153, 4 }, { 10286, 2 }, { 8343, 2 } }, TRAINER),
  R(10021, "Dreamweave Vest", 225, 1, { { 4339, 6 }, { 8153, 6 }, { 10286, 2 }, { 8343, 2 } }, TRAINER),
  R(22246, "Enchanted Mageweave Pouch", 225, 1, { { 4339, 4 }, { 11137, 4 }, { 8343, 2 } }, Taught(22307, nil)),
  R(10050, "Mageweave Bag", 225, 1, { { 4339, 4 }, { 4291, 2 } }, TRAINER),
  R(10018, "Red Mageweave Gloves", 225, 1, { { 4339, 3 }, { 2604, 2 }, { 8343, 2 } }, Taught(10312, DROP)),
  R(10023, "Shadoweave Gloves", 225, 1, { { 4339, 5 }, { 10285, 5 }, { 8343, 2 } }, TRAINER),
  R(10026, "Black Mageweave Boots", 230, 1, { { 4339, 3 }, { 8343, 2 }, { 4304, 2 } }, TRAINER),
  R(10024, "Black Mageweave Headband", 230, 1, { { 4339, 3 }, { 8343, 2 } }, TRAINER),
  R(10027, "Black Mageweave Shoulders", 230, 1, { { 4339, 3 }, { 8343, 2 } }, TRAINER),
  R(10054, "Lavender Mageweave Shirt", 230, 1, { { 4339, 2 }, { 4342, 2 }, { 8343, 2 } }, Taught(10314, nil)),
  R(10055, "Pink Mageweave Shirt", 235, 1, { { 4339, 3 }, { 10290, 1 }, { 8343, 1 } }, Taught(10317, nil)),
  R(10051, "Red Mageweave Bag", 235, 1, { { 4339, 4 }, { 2604, 2 }, { 8343, 2 } }, TRAINER),
  R(10029, "Red Mageweave Shoulders", 235, 1, { { 4339, 4 }, { 2604, 2 }, { 8343, 3 } }, Taught(10315, DROP)),
  R(10028, "Shadoweave Shoulders", 235, 1, { { 4339, 5 }, { 10285, 4 }, { 8343, 2 } }, TRAINER),
  R(10053, "Simple Black Dress", 235, 1, { { 4339, 3 }, { 2325, 1 }, { 8343, 1 }, { 2324, 1 } }, TRAINER),
  R(10030, "Admiral's Hat", 240, 1, { { 4339, 3 }, { 4589, 6 }, { 8343, 2 } }, Taught(10318, Vendor(7000))),
  R(10033, "Red Mageweave Headband", 240, 1, { { 4339, 4 }, { 2604, 2 }, { 8343, 2 } }, Taught(10320, DROP)),
  R(10031, "Shadoweave Boots", 240, 1, { { 4339, 6 }, { 10285, 6 }, { 8343, 3 }, { 4304, 2 } }, TRAINER),
  R(10034, "Tuxedo Shirt", 240, 1, { { 4339, 4 }, { 8343, 2 } }, Taught(10321, nil)),
  R(10044, "Cindercloth Boots", 245, 1, { { 4339, 5 }, { 7077, 1 }, { 8343, 3 }, { 4304, 2 } }, TRAINER),
  R(10025, "Shadoweave Mask", 245, 1, { { 4339, 2 }, { 10285, 8 }, { 8343, 2 } }, Taught(10463, QUEST)),
  R(10035, "Tuxedo Pants", 245, 1, { { 4339, 4 }, { 8343, 3 } }, Taught(10323, nil)),
  R(14048, "Bolt of Runecloth", 250, 1, { { 14047, 5 } }, TRAINER),
  R(10041, "Dreamweave Circlet", 250, 1, { { 4339, 8 }, { 8153, 4 }, { 10286, 2 }, { 8343, 3 }, { 6037, 1 }, { 1529, 1 } }, TRAINER),
  R(21154, "Festival Dress", 250, 1, { { 14048, 4 }, { 4625, 2 }, { 2604, 2 }, { 14341, 1 } }, Taught(21722, QUEST)),
  R(21542, "Festival Suit", 250, 1, { { 14048, 4 }, { 4625, 2 }, { 2604, 2 }, { 14341, 1 } }, Taught(21723, QUEST)),
  R(14342, "Mooncloth", 250, 1, { { 14256, 2 } }, Taught(14526, Vendor(20000))),
  R(10036, "Tuxedo Jacket", 250, 1, { { 4339, 5 }, { 8343, 3 } }, Taught(10326, nil)),
  R(10040, "White Wedding Dress", 250, 1, { { 4339, 5 }, { 8343, 3 }, { 2324, 1 } }, Taught(10325, nil)),
  R(13868, "Frostweave Robe", 255, 1, { { 14048, 5 }, { 7079, 2 }, { 14341, 1 } }, Taught(14467, DROP)),
  R(13869, "Frostweave Tunic", 255, 1, { { 14048, 5 }, { 7079, 2 }, { 14341, 1 } }, Taught(14466, DROP)),
  R(13856, "Runecloth Belt", 255, 1, { { 14048, 3 }, { 14341, 1 } }, TRAINER),
  R(14042, "Cindercloth Vest", 260, 1, { { 14048, 5 }, { 7077, 3 }, { 14341, 1 } }, Taught(14471, DROP)),
  R(14046, "Runecloth Bag", 260, 1, { { 14048, 5 }, { 8170, 2 }, { 14341, 1 } }, Taught(14468, Vendor(12000))),
  R(13858, "Runecloth Robe", 260, 1, { { 14048, 5 }, { 14227, 1 }, { 14341, 1 } }, Taught(14469, Vendor(12000))),
  R(13857, "Runecloth Tunic", 260, 1, { { 14048, 5 }, { 14227, 1 }, { 14341, 1 } }, Taught(14470, DROP)),
  R(21340, "Soul Pouch", 260, 1, { { 14048, 6 }, { 8170, 4 }, { 7972, 2 }, { 14341, 1 } }, Taught(21358, Vendor(12000))),
  R(13870, "Frostweave Gloves", 265, 1, { { 14048, 3 }, { 7080, 1 }, { 14341, 1 } }, Taught(14474, DROP)),
  R(14143, "Ghostweave Belt", 265, 1, { { 14048, 3 }, { 9210, 2 }, { 14227, 1 }, { 14341, 1 } }, Taught(14473, DROP)),
  R(13860, "Runecloth Cloak", 265, 1, { { 14048, 4 }, { 14227, 1 }, { 14341, 1 } }, Taught(14472, Vendor(12000))),
  R(14101, "Brightcloth Gloves", 270, 1, { { 14048, 4 }, { 3577, 2 }, { 14341, 1 } }, Taught(14479, DROP)),
  R(14100, "Brightcloth Robe", 270, 1, { { 14048, 5 }, { 3577, 2 }, { 14341, 1 } }, Taught(14478, DROP)),
  R(14043, "Cindercloth Gloves", 270, 1, { { 14048, 4 }, { 7077, 3 }, { 14341, 1 } }, Taught(14476, DROP)),
  R(14142, "Ghostweave Gloves", 270, 1, { { 14048, 4 }, { 9210, 2 }, { 14227, 1 }, { 14341, 1 } }, Taught(14477, DROP)),
  R(14103, "Brightcloth Cloak", 275, 1, { { 14048, 4 }, { 3577, 2 }, { 14341, 1 } }, Taught(14484, DROP)),
  R(22251, "Cenarion Herb Bag", 275, 1, { { 14048, 5 }, { 8831, 10 }, { 11040, 8 }, { 14341, 2 } }, Taught(22310, Vendor(22500))),
  R(14044, "Cindercloth Cloak", 275, 1, { { 14048, 5 }, { 7078, 1 }, { 14341, 1 } }, Taught(14482, DROP)),
  R(14134, "Cloak of Fire", 275, 1, { { 14048, 6 }, { 7078, 4 }, { 7077, 4 }, { 7068, 4 }, { 14341, 1 } }, Taught(14486, nil)),
  R(22248, "Enchanted Runecloth Bag", 275, 1, { { 14048, 5 }, { 16203, 2 }, { 14341, 2 } }, Taught(22308, Vendor(22500))),
  R(14107, "Felcloth Pants", 275, 1, { { 14048, 5 }, { 14256, 4 }, { 14341, 1 } }, Taught(14483, Vendor(16842))),
  R(14141, "Ghostweave Vest", 275, 1, { { 14048, 6 }, { 9210, 4 }, { 14227, 1 }, { 14341, 1 } }, Taught(14480, DROP)),
  R(13863, "Runecloth Gloves", 275, 1, { { 14048, 4 }, { 8170, 4 }, { 14341, 1 } }, Taught(14481, Vendor(14400))),
  R(14132, "Wizardweave Leggings", 275, 1, { { 14048, 6 }, { 11176, 1 }, { 14341, 1 } }, Taught(14485, DROP)),
  R(14045, "Cindercloth Pants", 280, 1, { { 14048, 6 }, { 7078, 1 }, { 14341, 1 } }, Taught(14490, DROP)),
  R(13871, "Frostweave Pants", 280, 1, { { 14048, 6 }, { 7080, 1 }, { 14341, 1 } }, Taught(14489, DROP)),
  R(13864, "Runecloth Boots", 280, 1, { { 14048, 4 }, { 14227, 2 }, { 8170, 4 }, { 14341, 1 } }, Taught(14488, Vendor(18000))),
  R(21341, "Felcloth Bag", 285, 1, { { 14256, 12 }, { 12810, 6 }, { 20520, 2 }, { 14227, 4 } }, Taught(21369, nil)),
  R(14108, "Felcloth Boots", 285, 1, { { 14048, 6 }, { 14256, 4 }, { 8170, 4 }, { 14341, 1 } }, Taught(14492, DROP)),
  R(18258, "Gordok Ogre Suit", 285, 1, { { 14048, 2 }, { 8170, 4 }, { 18240, 1 }, { 14341, 1 } }, TRAINER),
  R(14136, "Robe of Winter Night", 285, 1, { { 14048, 10 }, { 14256, 12 }, { 12808, 4 }, { 7080, 4 }, { 14341, 1 } }, Taught(14493, DROP)),
  R(13865, "Runecloth Pants", 285, 1, { { 14048, 6 }, { 14227, 2 }, { 14341, 1 } }, Taught(14491, DROP)),
  R(19056, "Argent Boots", 290, 1, { { 14048, 6 }, { 12810, 4 }, { 13926, 2 }, { 12809, 2 }, { 14227, 2 } }, Taught(19216, nil)),
  R(14104, "Brightcloth Pants", 290, 1, { { 14048, 6 }, { 3577, 4 }, { 14227, 1 }, { 14341, 1 } }, Taught(14494, DROP)),
  R(14111, "Felcloth Hood", 290, 1, { { 14048, 5 }, { 14256, 4 }, { 14341, 1 } }, Taught(14496, DROP)),
  R(14144, "Ghostweave Pants", 290, 1, { { 14048, 6 }, { 9210, 4 }, { 14341, 1 } }, Taught(14495, DROP)),
  R(15802, "Mooncloth Boots", 290, 1, { { 14048, 6 }, { 14342, 4 }, { 7971, 2 }, { 14341, 1 } }, TRAINER),
  R(14137, "Mooncloth Leggings", 290, 1, { { 14048, 6 }, { 14342, 4 }, { 14341, 1 } }, Taught(14497, DROP)),
  R(19047, "Wisdom of the Timbermaw", 290, 1, { { 14048, 8 }, { 7076, 3 }, { 12803, 3 }, { 14227, 2 } }, Taught(19215, Vendor(23157))),
  R(13866, "Runecloth Headband", 295, 1, { { 14048, 4 }, { 14227, 2 }, { 14341, 1 } }, Taught(14498, DROP)),
  R(19059, "Argent Shoulders", 300, 1, { { 14342, 5 }, { 12809, 2 }, { 14227, 2 } }, Taught(19217, nil)),
  R(18405, "Belt of the Archmage", 300, 1, { { 14048, 16 }, { 9210, 10 }, { 14342, 10 }, { 7080, 12 }, { 7078, 12 }, { 14344, 6 }, { 14341, 6 } }, Taught(18414, nil)),
  R(22249, "Big Bag of Enchantment", 300, 1, { { 14048, 6 }, { 14344, 4 }, { 12810, 4 }, { 14227, 4 } }, Taught(22309, DROP)),
  R(19684, "Bloodvine Boots", 300, 1, { { 14342, 3 }, { 19726, 3 }, { 12810, 4 }, { 14048, 4 }, { 14227, 4 } }, Taught(19766, Vendor(56250))),
  R(19683, "Bloodvine Leggings", 300, 1, { { 14342, 4 }, { 19726, 4 }, { 12804, 4 }, { 14048, 4 }, { 14227, 2 } }, Taught(19765, Vendor(56250))),
  R(19682, "Bloodvine Vest", 300, 1, { { 14342, 3 }, { 19726, 5 }, { 12804, 4 }, { 14048, 4 }, { 14227, 2 } }, Taught(19764, Vendor(56250))),
  R(14156, "Bottomless Bag", 300, 1, { { 14048, 8 }, { 14342, 12 }, { 14344, 2 }, { 17012, 2 }, { 14341, 2 } }, Taught(14510, DROP)),
  R(18413, "Cloak of Warding", 300, 1, { { 14048, 12 }, { 12809, 4 }, { 12360, 1 }, { 14341, 2 } }, Taught(18418, nil)),
  R(21342, "Core Felcloth Bag", 300, 1, { { 14256, 20 }, { 17012, 16 }, { 19726, 8 }, { 7078, 4 }, { 14227, 4 } }, Taught(21371, DROP)),
  R(18407, "Felcloth Gloves", 300, 1, { { 14048, 12 }, { 14256, 20 }, { 12662, 6 }, { 12808, 8 }, { 14341, 2 } }, Taught(18415, nil)),
  R(14106, "Felcloth Robe", 300, 1, { { 14048, 8 }, { 14256, 8 }, { 12662, 4 }, { 14341, 2 } }, Taught(14506, DROP)),
  R(14112, "Felcloth Shoulders", 300, 1, { { 14048, 7 }, { 14256, 6 }, { 12662, 4 }, { 8170, 4 }, { 14341, 2 } }, Taught(14508, DROP)),
  R(16979, "Flarecore Gloves", 300, 1, { { 14048, 8 }, { 17010, 6 }, { 7078, 4 }, { 12810, 2 }, { 14341, 2 } }, Taught(17018, Vendor(84210))),
  R(19165, "Flarecore Leggings", 300, 1, { { 14342, 8 }, { 17010, 5 }, { 17011, 3 }, { 7078, 10 }, { 14227, 4 } }, Taught(19220, Vendor(95294))),
  R(16980, "Flarecore Mantle", 300, 1, { { 14048, 12 }, { 17010, 4 }, { 17011, 4 }, { 12810, 6 }, { 14341, 2 } }, Taught(17017, Vendor(180000))),
  R(19156, "Flarecore Robe", 300, 1, { { 14342, 10 }, { 17010, 2 }, { 17011, 3 }, { 7078, 6 }, { 14227, 4 } }, Taught(19219, Vendor(60000))),
  R(18263, "Flarecore Wraps", 300, 1, { { 14342, 6 }, { 17010, 8 }, { 7078, 2 }, { 12810, 6 }, { 14341, 4 } }, Taught(18265, DROP)),
  R(22660, "Gaea's Embrace", 300, 1, { { 19726, 1 }, { 14342, 2 }, { 12803, 4 }, { 14227, 4 } }, Taught(22683, Vendor(90000))),
  R(22658, "Glacial Cloak", 300, 1, { { 22682, 5 }, { 14048, 4 }, { 7080, 2 }, { 14227, 4 } }, Taught(22685, nil)),
  R(22654, "Glacial Gloves", 300, 1, { { 22682, 5 }, { 14048, 4 }, { 7080, 4 }, { 14227, 4 } }, Taught(22684, nil)),
  R(22652, "Glacial Vest", 300, 1, { { 22682, 7 }, { 14048, 8 }, { 7080, 6 }, { 14227, 8 } }, Taught(22686, nil)),
  R(22655, "Glacial Wrists", 300, 1, { { 22682, 4 }, { 14048, 2 }, { 7080, 2 }, { 14227, 4 } }, Taught(22687, nil)),
  R(14146, "Gloves of Spell Mastery", 300, 1, { { 14048, 10 }, { 14342, 10 }, { 9210, 10 }, { 13926, 6 }, { 12364, 6 }, { 12810, 8 }, { 14341, 2 } }, Taught(14511, DROP)),
  R(18408, "Inferno Gloves", 300, 1, { { 14048, 12 }, { 7078, 10 }, { 7910, 2 }, { 14341, 2 } }, Taught(18416, nil)),
  R(19050, "Mantle of the Timbermaw", 300, 1, { { 14342, 5 }, { 7076, 5 }, { 12803, 5 }, { 14227, 2 } }, Taught(19218, Vendor(42105))),
  R(14155, "Mooncloth Bag", 300, 1, { { 14048, 4 }, { 14342, 1 }, { 14341, 1 } }, Taught(14499, DROP)),
  R(14140, "Mooncloth Circlet", 300, 1, { { 14048, 4 }, { 14342, 6 }, { 12800, 1 }, { 12810, 2 }, { 14341, 2 } }, Taught(14509, DROP)),
  R(18409, "Mooncloth Gloves", 300, 1, { { 14048, 12 }, { 14342, 6 }, { 13926, 2 }, { 14341, 2 } }, Taught(18417, nil)),
  R(18486, "Mooncloth Robe", 300, 1, { { 14048, 6 }, { 14342, 4 }, { 13926, 2 }, { 14341, 2 } }, Taught(18487, Vendor(40000))),
  R(14139, "Mooncloth Shoulders", 300, 1, { { 14048, 5 }, { 14342, 5 }, { 14341, 1 } }, Taught(14507, DROP)),
  R(14138, "Mooncloth Vest", 300, 1, { { 14048, 6 }, { 14342, 4 }, { 14341, 1 } }, Taught(14501, DROP)),
  R(14152, "Robe of the Archmage", 300, 1, { { 14048, 12 }, { 7078, 10 }, { 7082, 10 }, { 7076, 10 }, { 7080, 10 }, { 14341, 2 } }, Taught(14513, DROP)),
  R(14153, "Robe of the Void", 300, 1, { { 14048, 12 }, { 12662, 20 }, { 14256, 40 }, { 7078, 12 }, { 12808, 12 }, { 14341, 2 } }, Taught(14514, DROP)),
  R(13867, "Runecloth Shoulders", 300, 1, { { 14048, 7 }, { 14227, 2 }, { 8170, 4 }, { 14341, 1 } }, Taught(14504, DROP)),
  R(20539, "Runed Stygian Belt", 300, 1, { { 14048, 2 }, { 20520, 6 }, { 14256, 2 }, { 12810, 2 }, { 14227, 2 } }, Taught(20548, nil)),
  R(20537, "Runed Stygian Boots", 300, 1, { { 14048, 4 }, { 20520, 6 }, { 14256, 4 }, { 12810, 2 }, { 14227, 2 } }, Taught(20547, nil)),
  R(20538, "Runed Stygian Leggings", 300, 1, { { 14048, 6 }, { 20520, 8 }, { 14256, 6 }, { 14227, 2 } }, Taught(20546, nil)),
  R(22252, "Satchel of Cenarius", 300, 1, { { 14048, 6 }, { 14342, 2 }, { 13468, 1 }, { 14227, 4 } }, Taught(22312, Vendor(56250))),
  R(22757, "Sylvan Crown", 300, 1, { { 14048, 4 }, { 14342, 2 }, { 12803, 2 }, { 14227, 2 } }, Taught(22773, Vendor(50000))),
  R(22758, "Sylvan Shoulders", 300, 1, { { 14048, 2 }, { 12803, 4 }, { 14227, 2 } }, Taught(22772, Vendor(50000))),
  R(22756, "Sylvan Vest", 300, 1, { { 14048, 4 }, { 19726, 2 }, { 12803, 2 }, { 14227, 2 } }, Taught(22774, Vendor(50000))),
  R(14154, "Truefaith Vestments", 300, 1, { { 14048, 12 }, { 14342, 10 }, { 12811, 4 }, { 13926, 4 }, { 9210, 10 }, { 14341, 2 } }, Taught(14512, DROP)),
  R(14128, "Wizardweave Robe", 300, 1, { { 14048, 8 }, { 11176, 2 }, { 14341, 1 } }, Taught(14500, DROP)),
  R(14130, "Wizardweave Turban", 300, 1, { { 14048, 6 }, { 11176, 4 }, { 7910, 1 }, { 14341, 1 } }, Taught(14505, DROP)),
  },
}
