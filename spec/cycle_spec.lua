local addon = require("spec.helpers.addon")

local ns = {}
assert(loadfile("Wall.lua"))("MarketWall", ns)
local W = ns.Wall

local DAY0 = 20000   -- a Sunday, so wday = (day - DAY0) % 7 + 1

-- One observation per part for each day; price(day, part) gives the wall
local function Observe(days, price, parts)
  local obs = {}
  for day = DAY0, DAY0 + days - 1 do
    for _, part in ipairs(parts or { 1, 2, 3, 4 }) do
      obs[#obs + 1] = { day = day, part = part, wday = (day - DAY0) % 7 + 1, w = price(day, part) }
    end
  end
  return obs
end

describe("Wall.Cycle", function()
  it("returns empty parts for no observations", function()
    local result = W.Cycle({})
    assert.same({}, result.parts)
    assert.is_nil(result.weekday)
    assert.is_nil(result.weekend)
  end)

  it("finds evenings 10% dearer every day", function()
    local result = W.Cycle(Observe(10, function(_, part) return part == 4 and 1100 or 1000 end))
    assert.near(1.10, result.parts[4].r, 0.001)
    for part = 1, 3 do assert.near(1.0, result.parts[part].r, 0.001) end
    assert.equal(10, result.parts[4].n)
  end)

  it("does not read a steady upward trend as a time pattern", function()
    local result = W.Cycle(Observe(10, function(day) return 1000 + (day - DAY0) * 50 end))
    for part = 1, 4 do assert.near(1.0, result.parts[part].r, 0.001) end
  end)

  it("counts every observation, including one scan a day and several scans on few days", function()
    local morning = W.Cycle(Observe(3, function() return 1000 end, { 2 }))
    assert.equal(3, morning.parts[2].n)
    assert.near(1.0, morning.parts[2].r, 0.001)

    -- Monday and Tuesday with all four parts: 8 weekday observations
    local twoDays = W.Cycle(Observe(3, function() return 1000 end))
    assert.equal(8, twoDays.weekday.n)
  end)

  it("splits weekdays from weekends", function()
    -- weekends 20% dearer, one scan a day
    local obs = Observe(28, function(day)
      local wday = (day - DAY0) % 7 + 1
      return (wday == 1 or wday == 7) and 1200 or 1000
    end, { 2 })
    local result = W.Cycle(obs)
    assert.is_true(result.weekend.r - result.weekday.r > 0.10)
    assert.equal(8, result.weekend.n)
    assert.equal(20, result.weekday.n)
  end)

  it("does not read a steady trend as a weekday pattern", function()
    local result = W.Cycle(Observe(28, function(day) return 1000 + (day - DAY0) * 20 end, { 2 }))
    assert.near(1.0, result.weekday.r, 0.02)
    assert.near(1.0, result.weekend.r, 0.02)
  end)
end)

describe("ns.Cycle", function()
  it("gives an item with no days empty parts instead of crashing", function()
    local loaded, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    local cycle = loaded.Cycle(12345)
    assert.same({}, cycle.parts)
  end)

  it("reads the stored days of an item", function()
    local loaded, fire = addon.Load()
    fire("ADDON_LOADED", addon.ADDON)
    -- a stored day is { wall, low, high, units, min, parts }, with parts = { [part] = wall }
    local today = loaded.Today()
    local days = {}
    for i = 0, 2 do days[today - i] = { 1000, 1000, 1000, 10, 1000, { [1] = 1000, [4] = 1100 } } end
    loaded.R().days[777] = days
    local cycle = loaded.Cycle(777)
    assert.equal(3, cycle.parts[4].n)
    assert.near(1100 / 1050, cycle.parts[4].r, 0.001)   -- against the day's median, 1050
  end)
end)
