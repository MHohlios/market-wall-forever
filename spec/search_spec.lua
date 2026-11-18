local addon = require("spec.helpers.addon")

describe("item search", function()
  local S
  before_each(function() S = addon.Load().ItemSearch end)

  describe("name matching", function()
    local names = { [1] = "Thorium Bar", [2] = "Thorium Ore", [3] = "Dense Thorium Shield", [4] = "Thorium", [5] = "Arcane Crystal", [6] = "Enchanted Thorium Bar" }

    it("matches any part of a name, ignoring case and outer spaces", function()
      assert.same({ 3 }, S.Match(names, "  THORIUM s ", 10))
      assert.same({ 5 }, S.Match(names, "crys", 10))
    end)

    it("ranks the exact name first, then names that start with the text, then the rest", function()
      assert.same({ 4, 1, 2, 3, 6 }, S.Match(names, "thorium", 10))
    end)

    it("returns at most the limit", function()
      assert.same({ 4, 1 }, S.Match(names, "Thorium", 2))
    end)

    it("matches nothing for empty text or an unseen name", function()
      assert.same({}, S.Match(names, "   ", 10))
      assert.same({}, S.Match(names, "mithril", 10))
    end)

    it("treats the text literally, not as a pattern", function()
      assert.same({}, S.Match(names, "thor.um", 10))
    end)
  end)

  describe("recent list", function()
    it("puts the newest search first", function()
      local list = { 1, 2 }
      S.Remember(list, 3, 10)
      assert.same({ 3, 1, 2 }, list)
    end)

    it("moves a repeated search to the front instead of listing it twice", function()
      local list = { 1, 2, 3 }
      S.Remember(list, 2, 10)
      assert.same({ 2, 1, 3 }, list)
    end)

    it("drops the oldest past the cap", function()
      local list = {}
      for id = 1, 12 do S.Remember(list, id, 10) end
      assert.same({ 12, 11, 10, 9, 8, 7, 6, 5, 4, 3 }, list)
    end)
  end)
end)
