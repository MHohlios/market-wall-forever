local addon = require("spec.helpers.addon")

describe("money", function()
  local ns
  before_each(function() ns = addon.Load() end)

  local Plain = addon.Plain

  describe("Money", function()
    it("shows a dash for no price", function()
      assert.equal("-", ns.Money(nil))
    end)

    it("shows copper-only prices without empty gold or silver", function()
      assert.equal("5c", Plain(ns.Money(5)))
      assert.equal("0c", Plain(ns.Money(0)))
    end)

    it("keeps zero silver and copper once there is gold", function()
      assert.equal("2g 0s 0c", Plain(ns.Money(20000)))
    end)

    it("rounds fractional copper and carries into silver", function()
      assert.equal("1s 0c", Plain(ns.Money(99.6)))
    end)

    it("puts the sign in front of negative amounts", function()
      assert.equal("-1s 5c", Plain(ns.Money(-105)))
    end)

    it("shows each amount with its coin icon after the number", function()
      assert.equal("1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:0|t 41|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:0:0|t "
        .. "23|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:0:0|t", ns.Money(14123))
    end)

    it("leaves the colour to the surrounding text", function()
      assert.is_nil(ns.Money(14123):find("|c", 1, true))
    end)
  end)

  describe("MoneyShort", function()
    it("leaves copper out from 1g up, rounding to the nearest silver", function()
      assert.equal("1g 41s", Plain(ns.MoneyShort(14123)))
      assert.equal("2g 0s", Plain(ns.MoneyShort(19999)))
      assert.equal("-12g 35s", Plain(ns.MoneyShort(-123456)))
    end)

    it("keeps copper below 1g, where there is room", function()
      assert.equal("99s 99c", Plain(ns.MoneyShort(9999)))
      assert.equal("5c", Plain(ns.MoneyShort(5)))
    end)
  end)

  describe("MoneyText", function()
    it("writes the plain letter form", function()
      assert.equal("1g 41s 23c", ns.MoneyText(14123))
      assert.equal("5c", ns.MoneyText(5))
      assert.equal("2g 0s 0c", ns.MoneyText(20000))
      assert.equal("-1s 5c", ns.MoneyText(-105))
      assert.equal("-", ns.MoneyText(nil))
    end)
  end)

  describe("ParseMoney", function()
    it("reads each unit and mixed amounts", function()
      assert.equal(80, ns.ParseMoney("80c"))
      assert.equal(120, ns.ParseMoney("1s 20c"))
      assert.equal(20000, ns.ParseMoney("2g"))
      assert.equal(10500, ns.ParseMoney("1g5s"))
      assert.equal(10000, ns.ParseMoney("1G"))
    end)

    it("reads a plain copper number, dropping fractions", function()
      assert.equal(123, ns.ParseMoney("123"))
      assert.equal(12, ns.ParseMoney("12.7"))
    end)

    it("reads its own formatted output back", function()
      for _, copper in ipairs({ 7, 105, 20000, 123456 }) do
        assert.equal(copper, ns.ParseMoney(ns.MoneyText(copper)))
      end
    end)

    it("rejects malformed text", function()
      assert.is_nil(ns.ParseMoney(nil))
      assert.is_nil(ns.ParseMoney(""))
      assert.is_nil(ns.ParseMoney("abc"))
      assert.is_nil(ns.ParseMoney("5x"))
      assert.is_nil(ns.ParseMoney("g"))
      assert.is_nil(ns.ParseMoney("1g x"))
      assert.is_nil(ns.ParseMoney("1.5.5g"))
    end)

    it("reads decimals with a unit", function()
      assert.equal(15000, ns.ParseMoney("1.5g"))
      assert.equal(150, ns.ParseMoney("1.5s"))
      assert.equal(10250, ns.ParseMoney("1g 2.5s"))
      assert.equal(1, ns.ParseMoney("1.9c"))
    end)

    it("rejects negative amounts", function()
      assert.is_nil(ns.ParseMoney("-5"))
      assert.is_nil(ns.ParseMoney("-5g"))
      assert.is_nil(ns.ParseMoney("1g -5s"))
    end)
  end)
end)
