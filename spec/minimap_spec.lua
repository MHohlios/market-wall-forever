local addon = require("spec.helpers.addon")

describe("minimap button position", function()
  local M
  before_each(function() M = addon.Load().MinimapButton end)

  local function Near(expected, actual)
    assert.is_true(math.abs(expected - actual) < 1e-9, "expected " .. expected .. ", got " .. actual)
  end

  it("places the button on a circle round the minimap's centre", function()
    local x, y = M.Offset(0, 80)
    Near(80, x) Near(0, y)
    x, y = M.Offset(90, 80)
    Near(0, x) Near(80, y)
    x, y = M.Offset(225, 10)
    Near(-10 / math.sqrt(2), x) Near(-10 / math.sqrt(2), y)
  end)

  it("reads the angle of a cursor offset from 0 up to 360", function()
    Near(0, M.Angle(5, 0))
    Near(90, M.Angle(0, 5))
    Near(180, M.Angle(-5, 0))
    Near(225, M.Angle(-3, -3))
    Near(270, M.Angle(0, -5))
  end)

  it("puts the button back at the angle it was dragged to", function()
    for _, angle in ipairs({ 0, 45, 135, 200, 315 }) do
      Near(angle, M.Angle(M.Offset(angle, 75)))
    end
  end)
end)
