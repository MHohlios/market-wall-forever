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

    it("never shows a zero coin", function()
      assert.equal("2g", Plain(ns.Money(20000)))
      assert.equal("88s", Plain(ns.Money(8800)))
      assert.equal("1g 5c", Plain(ns.Money(10005)))
    end)

    it("stays exact, keeping copper on gold amounts", function()
      assert.equal("9g 99s 88c", Plain(ns.Money(99988)))
    end)

    it("rounds fractional copper and carries into silver", function()
      assert.equal("1s", Plain(ns.Money(99.6)))
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

  describe("MoneyFaded", function()
    it("shows the same amount as Money, with each coin icon tinted darker", function()
      assert.equal("1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:0:0:64:64:0:64:0:64:128:128:128|t "
        .. "41|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:0:0:64:64:0:64:0:64:128:128:128|t "
        .. "23|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:0:0:64:64:0:64:0:64:128:128:128|t", ns.MoneyFaded(14123))
      assert.equal(Plain(ns.Money(-105)), Plain(ns.MoneyFaded(-105)))
    end)
  end)

  describe("MoneyShort", function()
    it("shows at most two coins, rounding gold amounts to the nearest silver", function()
      assert.equal("5g 5s", Plain(ns.MoneyShort(50473)))
      assert.equal("46g 5s", Plain(ns.MoneyShort(460496)))
      assert.equal("1g 41s", Plain(ns.MoneyShort(14123)))
    end)

    it("carries a rounded amount into the next coin and drops the zero left behind", function()
      assert.equal("10g", Plain(ns.MoneyShort(99988)))
      assert.equal("2g", Plain(ns.MoneyShort(19999)))
      assert.equal("1g", Plain(ns.MoneyShort(9999.6)))
    end)

    it("keeps amounts under 1g exact, since they already fit in two coins", function()
      assert.equal("77s 77c", Plain(ns.MoneyShort(7777)))
      assert.equal("5c", Plain(ns.MoneyShort(5)))
      assert.equal("0c", Plain(ns.MoneyShort(0)))
    end)

    it("rounds negative amounts the same way, with the sign in front", function()
      assert.equal("-12g 35s", Plain(ns.MoneyShort(-123456)))
      assert.equal("-10g", Plain(ns.MoneyShort(-99988)))
      assert.equal("-1s 5c", Plain(ns.MoneyShort(-105)))
    end)

    it("shows a dash for no price", function()
      assert.equal("-", ns.MoneyShort(nil))
    end)
  end)

  describe("MoneyText", function()
    it("writes the plain letter form", function()
      assert.equal("1g 41s 23c", ns.MoneyText(14123))
      assert.equal("5c", ns.MoneyText(5))
      assert.equal("2g", ns.MoneyText(20000))
      assert.equal("1g 5c", ns.MoneyText(10005))
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
      for _, copper in ipairs({ 0, 7, 105, 8800, 10005, 20000, 99988, 123456 }) do
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
