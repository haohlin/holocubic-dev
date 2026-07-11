package.path = "apps/holo-flight-deck/package/?.lua;" .. package.path
local flight = require("flight_math")

local function equal(actual, expected, message)
  assert(actual == expected, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function near(actual, expected, epsilon, message)
  assert(math.abs(actual - expected) <= epsilon, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

equal(flight.normalize(11.5, 10, 1.5, 45), 0, "dead zone includes its boundary")
near(flight.normalize(11.6, 10, 1.5, 45), 1.6, 0.0001, "positive value survives dead zone")
equal(flight.normalize(-100, 0, 1.5, 45), -45, "negative tilt clamps")
near(flight.smooth(0, 10, 0.28), 2.8, 0.0001, "smoothing uses alpha")

local physical_roll, physical_pitch = flight.device_attitude(14, -20, 10, -15, 1.5, 45)
equal(physical_roll, -5, "device pitch controls the visual roll axis")
equal(physical_pitch, 4, "device roll controls the visual pitch axis")

local x1, y1, x2, y2 = flight.horizon(320, 240, 45, 0)
equal(x1, 25, "level horizon starts at left extent")
equal(x2, 295, "level horizon ends at right extent")
equal(y1, 195, "full pitch offsets horizon down")
equal(y2, 195, "level horizon is horizontal")

local _, up_y1, _, up_y2 = flight.horizon(320, 240, 0, 35)
assert(up_y1 < up_y2, "positive roll rises from left to right")

print("flight_math tests passed")
