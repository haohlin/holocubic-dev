package.path = "apps/holo-orca-hud/package/?.lua;" .. package.path
local hud = require("hud_model")

local function equal(actual, expected, message)
  assert(actual == expected, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local index, latched, changed = hud.move_selection(2, 4, 16, false, 12)
equal(index, 3, "right tilt advances the selected session")
equal(latched, true, "selection latches until returned to neutral")
assert(changed, "a threshold crossing changes selection")

index, latched, changed = hud.move_selection(index, 4, 16, latched, 12)
equal(index, 3, "a held tilt changes selection only once")
equal(latched, true, "held tilt remains latched")
assert(not changed, "held tilt does not repeat")

index, latched, changed = hud.move_selection(index, 4, 0, latched, 12)
equal(index, 3, "neutral tilt keeps the selection")
equal(latched, false, "neutral tilt unlatches selection")
assert(not changed, "neutral tilt is not a selection event")

index, latched, changed = hud.move_selection(1, 4, -18, false, 12)
equal(index, 1, "left tilt clamps at the first session")
equal(latched, true, "edge tilt still latches")
assert(not changed, "edge tilt does not report a movement")

local page, page_latched, page_changed = hud.move_page(1, 2, 18, false, 12)
equal(page, 2, "forward tilt opens the session navigator")
equal(page_latched, true, "page navigation latches until neutral")
assert(page_changed, "page navigation reports the mode change")

page, page_latched, page_changed = hud.move_page(page, 2, 0, page_latched, 12)
equal(page, 2, "neutral tilt keeps the current mode")
equal(page_latched, false, "neutral tilt unlatches mode navigation")
assert(not page_changed, "neutral mode tilt does not change page")

print("orca_hud_model tests passed")
