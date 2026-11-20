local addon = require("spec.helpers.addon")

-- Runecloth Belt: trainer-taught, 3 Bolt of Runecloth and 1 Rune Thread (vendor, 50s)
local BELT, BOLT = 13856, 14048

local function Link(id) return "|cffffffff|Hitem:" .. id .. "::::::::::0|h[Item]|h|r" end

describe("trainer", function()
  local ns, fire, services, globals

  local function Stub(name, value)
    globals[#globals + 1] = name
    _G[name] = value
  end

  -- A trainer over services: { name, type, profession, rank, hasSkill, product, cost }, whose
  -- GetTrainerServiceInfo returns Forever's tuple, or Classic's when classic is set
  local function OpenTrainer(classic)
    Stub("GetNumTrainerServices", function() return #services end)
    Stub("GetTrainerServiceInfo", function(i)
      local s = services[i]
      if not s then return nil end
      if classic then return s.name, "", s.type or "available", false end
      return s.name, s.type or "available", 12345, 1, "", nil
    end)
    Stub("GetTrainerServiceSkillReq", function(i)
      local s = services[i]
      if s then return s.profession, s.rank, s.hasSkill ~= false end
    end)
    Stub("GetTrainerServiceItemLink", function(i)
      local s = services[i]
      return s and s.product and Link(s.product) or nil
    end)
    Stub("GetTrainerServiceCost", function(i) return services[i] and services[i].cost end)
  end

  local function Wall(id, wall)
    ns.R().days[id] = { [ns.Today()] = { wall, wall, wall, 50, wall } }
    ns.R().supplied[id] = true
  end

  before_each(function()
    ns, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    globals = {}
    Stub("C_Item", {})
    services = {
      { name = "Tailoring", type = "header" },
      { name = "Bolt of Runecloth (old name)", profession = "Tailoring", rank = 250, product = BOLT, cost = 10000 },
      { name = "runecloth belt", profession = "Tailoring", rank = 255, cost = 15000 },
      { name = "Artisan Tailoring", profession = "Tailoring", rank = 200, cost = 500000 },
      { name = "Frostbolt", rank = 0, cost = 2000 },   -- a class trainer's spell: no profession
    }
    OpenTrainer()
  end)

  after_each(function()
    for _, name in ipairs(globals) do _G[name] = nil end
  end)

  describe("matching a service to its recipe", function()
    it("matches by the product in its item link", function()
      local recipe, profession = ns.Trainer.Recipe(2)
      assert.same({ BOLT, "Tailoring" }, { recipe.product, profession })
    end)

    it("falls back to the name within the trainer's profession", function()
      assert.equal(BELT, ns.Trainer.Recipe(3).product)
    end)

    it("matches nothing for headers, other services and class trainers", function()
      assert.is_nil(ns.Trainer.Recipe(1))
      assert.is_nil(ns.Trainer.Recipe(4))
      assert.is_nil(ns.Trainer.Recipe(5))
    end)
  end)

  describe("training costs", function()
    it("saves each recipe's cost by profession and product, and it reaches the guide's payback", function()
      fire("TRAINER_SHOW")
      assert.same({ Tailoring = { [BOLT] = 10000, [BELT] = 15000 } }, MarketWallDB.crafting.trainer)

      Wall(BOLT, 1000)
      Wall(BELT, 10000)
      for _, e in ipairs(ns.Professions.Guide("Tailoring")) do
        if e.recipe.product == BELT then
          assert.same({ 15000, "trainer" }, { e.learnCost, e.learnSource })
          assert.equal(math.ceil(15000 / e.profit), e.payback)
          return
        end
      end
      error("Runecloth Belt not in the guide")
    end)

    it("saves again on TRAINER_UPDATE, keeping the latest cost", function()
      fire("TRAINER_SHOW")
      services[3].cost = 12000
      fire("TRAINER_UPDATE")
      assert.equal(12000, MarketWallDB.crafting.trainer.Tailoring[BELT])
    end)
  end)

  describe("row text and hover breakdown", function()
    before_each(function()
      Wall(BOLT, 1000)
      Wall(BELT, 10000)
    end)

    it("shows the training cost, profit and payback", function()
      local text = addon.Plain(ns.Trainer.RowText(3))
      assert.truthy(text:find("^1g 50s 0c · %+%d+s %d+c · %d+ crafts$"), text)
    end)

    it("shows the skill a recipe still needs instead of its cost", function()
      services[3].hasSkill = false
      assert.truthy(addon.Plain(ns.Trainer.RowText(3)):find("^needs 255 · "))
    end)

    it("shows known and profit for a learned recipe", function()
      services[3].type = "used"
      assert.truthy(addon.Plain(ns.Trainer.RowText(3)):find("^known · %+"))
    end)

    it("leaves unmatched rows alone", function()
      assert.is_nil(ns.Trainer.RowText(1))
      assert.is_nil(ns.Trainer.Breakdown(4))
    end)

    it("breaks a row down into mats, sale, profit, market and payback", function()
      local lines = ns.Trainer.Breakdown(3)
      local left = {}
      for i, line in ipairs(lines) do left[i] = addon.Plain(line[1]) end
      assert.equal("Mats: 3 item:" .. BOLT .. ", 1 item:14341", left[1])
      assert.same({ "Sells for (net)", "Profit per craft", "Market" }, { left[2], left[3], left[4] })
      assert.equal("80s 0c", addon.Plain(lines[1][2]))   -- 3 × 10s wall + 50s vendor thread
      assert.truthy(left[5]:find("^Training pays back in %d+ crafts$"))
    end)
  end)

  describe("the trainer window", function()
    local hooks, button

    before_each(function()
      hooks = {}
      Stub("hooksecurefunc", function(name, fn) hooks[name] = fn end)
      local text = {}
      button = {
        id = 3, scripts = {},
        GetID = function(self) return self.id end,
        HookScript = function(self, name, fn) self.scripts[name] = fn end,
        CreateFontString = function()
          return { SetPoint = function() end, SetJustifyH = function() end,
            SetText = function(_, value) text.value = value end }
        end,
      }
      button.text = text
      Stub("ClassTrainerFrame_Update", function() end)
      Wall(BOLT, 1000)
      Wall(BELT, 10000)
    end)

    it("annotates each of Forever's pooled rows as the scroll box sets it up", function()
      Stub("ClassTrainerFrame_InitServiceButton", function() end)
      fire("ADDON_LOADED", "Blizzard_TrainerUI")
      hooks.ClassTrainerFrame_InitServiceButton(button, {})
      assert.truthy(addon.Plain(button.text.value):find("^1g 50s 0c · "))
      assert.is_function(button.scripts.OnEnter)

      button.id = 4   -- the pooled button reused for a service that teaches no recipe
      hooks.ClassTrainerFrame_InitServiceButton(button, {})
      assert.equal("", button.text.value)
    end)

    it("annotates Classic's fixed rows on each update", function()
      OpenTrainer(true)
      services[3].type = "used"
      Stub("ClassTrainerSkill1", button)
      fire("ADDON_LOADED", "Blizzard_TrainerUI")
      hooks.ClassTrainerFrame_Update()
      assert.truthy(addon.Plain(button.text.value):find("^known · %+"))
    end)

    it("does nothing when the client lacks a trainer call", function()
      Stub("ClassTrainerFrame_InitServiceButton", function() end)
      Stub("GetTrainerServiceItemLink", nil)
      fire("ADDON_LOADED", "Blizzard_TrainerUI")
      fire("TRAINER_SHOW")
      assert.same({}, hooks)
      assert.is_nil(MarketWallDB.crafting.trainer)
    end)
  end)
end)
