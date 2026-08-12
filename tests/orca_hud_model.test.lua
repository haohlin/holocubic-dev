package.path = "apps/holo-orca-hud/package/?.lua;" .. package.path
local hud = require("hud_model")

local function equal(actual, expected, message)
  assert(actual == expected, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

equal(hud.axis_delta(5, 5), 0, "the measured five-degree backward rest pose is the vertical middle")
equal(hud.axis_delta(-31, 5), -36, "forward tilt is negative relative to the corrected vertical middle")

local pulse, previous_roll, rest_roll, vertical_latched = hud.vertical_motion_pulse(10, nil, nil, false, 10, 3, 3)
equal(pulse, 0, "the first IMU sample calibrates the actual resting angle without navigating")
equal(previous_roll, 10, "the gesture remembers the first raw roll sample")
equal(rest_roll, 10, "the gesture compensates from the device's current resting angle")
assert(not vertical_latched, "calibration leaves vertical motion armed")

pulse, previous_roll, rest_roll, vertical_latched = hud.vertical_motion_pulse(0, previous_roll, rest_roll, vertical_latched, 10, 3, 3)
equal(pulse, 1, "a sharp ten-degree forward tilt emits one downward navigation pulse")
assert(vertical_latched, "a fired gesture locks until the cube returns to rest")

pulse, previous_roll, rest_roll, vertical_latched = hud.vertical_motion_pulse(10, previous_roll, rest_roll, vertical_latched, 10, 3, 3)
equal(pulse, 0, "the fast return to rest does not emit an opposite navigation pulse")
assert(not vertical_latched, "returning within the calibrated rest band rearms the gesture")

pulse, previous_roll, rest_roll, vertical_latched = hud.vertical_motion_pulse(20, previous_roll, rest_roll, vertical_latched, 10, 3, 3)
equal(pulse, -1, "a sharp ten-degree backward tilt emits one upward navigation pulse")
assert(vertical_latched, "the opposite gesture also requires a return to rest")

local accepted_pulse, next_action_at = hud.rate_limit_pulse(1, 1000, 0, 1000)
equal(accepted_pulse, 1, "the first vertical snap is accepted immediately")
equal(next_action_at, 2000, "an accepted snap blocks another action for one full second")

accepted_pulse, next_action_at = hud.rate_limit_pulse(-1, 1500, next_action_at, 1000)
equal(accepted_pulse, 0, "an opposite snap inside the one-second lockout is ignored")
equal(next_action_at, 2000, "the ignored snap does not extend the lockout")

accepted_pulse, next_action_at = hud.rate_limit_pulse(-1, 2000, next_action_at, 1000)
equal(accepted_pulse, -1, "the next snap becomes active exactly one second later")
equal(next_action_at, 3000, "each accepted action starts a fresh one-second lockout")

local slow_pulse, slow_previous, slow_rest, slow_latched = hud.vertical_motion_pulse(10, nil, nil, false, 10, 3, 3)
for _, roll in ipairs({ 12, 14, 16, 18, 20 }) do
  slow_pulse, slow_previous, slow_rest, slow_latched = hud.vertical_motion_pulse(
    roll, slow_previous, slow_rest, slow_latched, 10, 3, 3
  )
  equal(slow_pulse, 0, "a gradual lean is not mistaken for a sudden vertical command")
end

local pulse_selection, pulse_changed = hud.move_selection_pulse(2, 4, 1)
equal(pulse_selection, 3, "a downward vertical pulse advances the session selection once")
assert(pulse_changed, "a non-zero vertical pulse reports the selection change")

local pulse_scroll, pulse_scroll_changed = hud.move_scroll_pulse(2, 6, -1)
equal(pulse_scroll, 3, "an upward vertical pulse reveals one older transcript row")
assert(pulse_scroll_changed, "a vertical transcript pulse reports the scroll change")

local terminal_rows = hud.terminal_lines({
  lines = { "    terminal indentation", "Error: this is visibly important" },
}, 4, 18)
equal(terminal_rows[1], "    terminal", "terminal rows preserve leading indentation")
equal(terminal_rows[2], "    indentation", "wrapped continuation retains the terminal indent")
equal(hud.transcript_tone("Error: this is visibly important"), "red", "terminal errors retain a distinct error tone")
equal(hud.transcript_tone("$ status"), "blue", "terminal prompts retain an accent tone")
equal(hud.transcript_tone("    nested output"), "dim", "indented terminal output uses the quieter code tone")

local wide_index, wide_latched, wide_changed = hud.move_selection(2, 4, 35, false, 36, 18)
equal(wide_index, 2, "35 degrees remains inside the widened directional deadzone")
equal(wide_latched, false, "the wider deadzone does not latch")
assert(not wide_changed, "the wider deadzone does not navigate")

wide_index, wide_latched, wide_changed = hud.move_selection(2, 4, 36, false, 36, 18)
equal(wide_index, 3, "36 degrees deliberately engages navigation")
equal(wide_latched, true, "a widened threshold still latches after one action")
assert(wide_changed, "a threshold crossing still changes selection")

local index, latched, changed = hud.move_selection(2, 4, 18, false, 24, 12)
equal(index, 2, "motion inside the 24 degree directional deadzone does not select")
equal(latched, false, "deadzone motion does not latch the direction")
assert(not changed, "deadzone motion does not change selection")

index, latched, changed = hud.move_selection(2, 4, 25, false, 24, 12)
equal(index, 3, "a deliberate tilt advances the selected session")
equal(latched, true, "selection latches until returned to neutral")
assert(changed, "a threshold crossing changes selection")

index, latched, changed = hud.move_selection(index, 4, 30, latched, 24, 12)
equal(index, 3, "a held tilt changes selection only once")
equal(latched, true, "held tilt remains latched")
assert(not changed, "held tilt does not repeat")

index, latched, changed = hud.move_selection(index, 4, 12, latched, 24, 12)
equal(index, 3, "release-band tilt keeps the selection")
equal(latched, false, "returning inside the 12 degree release zone unlatches selection")
assert(not changed, "release motion is not a selection event")

index, latched, changed = hud.move_selection(1, 4, -25, false, 24, 12)
equal(index, 1, "left tilt clamps at the first session")
equal(latched, true, "edge tilt still latches")
assert(not changed, "edge tilt does not report a movement")

local page, page_latched, page_changed = hud.move_page(1, 25, false, 24, 12)
equal(page, 2, "right tilt enters the session navigator")
equal(page_latched, true, "horizontal page navigation latches until neutral")
assert(page_changed, "right tilt reports the hierarchy change")

page, page_latched, page_changed = hud.move_page(page, -25, false, 24, 12)
equal(page, 1, "left tilt backs out of the session navigator")
equal(page_latched, true, "back navigation latches until neutral")
assert(page_changed, "left tilt reports the hierarchy change")

page, page_latched, page_changed = hud.move_page(2, 25, false, 24, 12)
equal(page, 3, "forward tilt opens the transcript viewer")
equal(page_latched, true, "chat navigation latches until neutral")
assert(page_changed, "right tilt enters the chat viewer")

local tone, label = hud.session_indicator({ focused = true, agentState = "working", canActivate = true })
equal(tone, "amber", "a working session receives the Orca working indicator")
equal(label, "WORKING", "working status remains legible without relying on color")

tone, label = hud.session_indicator({ agentState = "done", canActivate = true })
equal(tone, "green", "a completed session receives the done indicator")
equal(label, "DONE", "completed sessions are explicitly labeled done")

tone, label = hud.session_indicator({ agentState = "blocked", canActivate = false })
equal(tone, "red", "a blocked session takes precedence over disconnected state")
equal(label, "ATTENTION", "blocked status is explicit")

tone, label = hud.session_indicator({ agentState = "idle", canActivate = false })
equal(tone, "muted", "a session without a connected terminal has an offline tone")
equal(label, "OFFLINE", "a session without a connected terminal is explicitly offline")

local compact_tone, compact_meta = hud.compact_session_meta({ agentState = "done", canActivate = true, terminalCount = 3 })
equal(compact_tone, "green", "compact metadata retains the semantic status tone")
equal(compact_meta, "DONE / 3T", "compact metadata fits on one small status line")

local transcript = hud.transcript_lines({ lines = { "stale", "  executing CLI  ", "last" } }, 2, 10)
equal(#transcript, 2, "the transcript keeps only the display-safe tail")
equal(transcript[1], "executing.", "the transcript compacts long lines to the canvas width")
equal(transcript[2], "last", "the transcript retains the latest line")

local plain_transcript = hud.transcript_lines({
  lines = { "old", "  one plain terminal row that is intentionally longer than the display width  ", "new" },
}, 8, 42)
equal(#plain_transcript, 3, "the restored transcript keeps one compact display row per terminal row")
equal(plain_transcript[2], "one plain terminal row that is intentiona.", "the plain transcript truncates instead of reflowing a terminal row")

local window, scroll, max_scroll = hud.transcript_window({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }, 0, 3)
equal(scroll, 0, "chat opens at the newest retained tail")
equal(max_scroll, 7, "chat scroll range retains every available line")
equal(table.concat(window, ","), "8,9,10", "chat window initially shows newest lines")

scroll, latched, changed = hud.move_scroll(scroll, max_scroll, -25, false, 24, 12)
equal(scroll, 1, "vertical up motion scrolls toward older chat lines")
equal(latched, true, "chat scrolling shares the directional latch")
assert(changed, "a deliberate chat tilt changes scroll position")
window, scroll, max_scroll = hud.transcript_window({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }, scroll, 3)
equal(table.concat(window, ","), "7,8,9", "older chat lines become visible after scrolling")

local repeat_scroll, repeat_at, repeat_changed = hud.move_scroll_repeat(0, 6, -36, 1000, 0, 36, 18, 200)
equal(repeat_scroll, 1, "an upward held tilt starts by moving one older line")
equal(repeat_at, 1200, "held chat scrolling schedules the next line at five ticks per second")
assert(repeat_changed, "the initial held tilt updates the transcript window")

repeat_scroll, repeat_at, repeat_changed = hud.move_scroll_repeat(repeat_scroll, 6, -36, 1100, repeat_at, 36, 18, 200)
equal(repeat_scroll, 1, "held scrolling waits for the five-Hz repeat interval")
assert(not repeat_changed, "a repeat does not fire early")

repeat_scroll, repeat_at, repeat_changed = hud.move_scroll_repeat(repeat_scroll, 6, -36, 1200, repeat_at, 36, 18, 200)
equal(repeat_scroll, 2, "an upward held tilt continues one transcript line at a time")
assert(repeat_changed, "the due repeat advances the transcript")

repeat_scroll, repeat_at, repeat_changed = hud.move_scroll_repeat(repeat_scroll, 6, 36, 1400, 0, 36, 18, 200)
equal(repeat_scroll, 1, "a downward held tilt returns one transcript line at a time")
assert(repeat_changed, "the opposite held direction also scrolls")

repeat_scroll, repeat_at, repeat_changed = hud.move_scroll_repeat(repeat_scroll, 6, 0, 1450, repeat_at, 36, 18, 200)
equal(repeat_at, 0, "returning to the deadzone cancels held scroll repeats")
assert(not repeat_changed, "neutral tilt does not change the transcript")

local layout = hud.row_layout(57)
equal(layout.title_y, 60, "row title begins with a consistent top inset")
equal(layout.meta_y, 76, "row metadata has a separate non-overlapping baseline")
equal(layout.title_font, 12, "row titles use the readable compact font")
equal(layout.meta_font, 10, "row metadata uses the smaller supporting font")

assert(hud.render_due(1000, 900, true, 200), "state changes render immediately")
assert(not hud.render_due(1050, 1000, false, 200), "steady state does not redraw on every input tick")
assert(not hud.render_due(1200, 1000, false, 200), "steady state never reapplies LVGL styles without a state change")

assert(hud.request_allowed(false, false), "an idle HTTP transport accepts a request")
assert(not hud.request_allowed(true, false), "a status request blocks a second concurrent request")
assert(not hud.request_allowed(false, true), "a weather request blocks a second concurrent request")
assert(not hud.request_allowed(false, false, true), "a transcript request blocks a second concurrent request")

equal(hud.transport_error_label("status", -1), "BRIDGE OFFLINE", "a native transport failure is named for the reachable component, not exposed as HTTP -1")
equal(hud.transport_error_label("transcript", 502), "ORCA DESKTOP OFFLINE", "a bridge-side Orca failure is distinct from a cube-to-bridge failure")
equal(hud.transport_error_label("transcript", 500), "TRANSCRIPT UNAVAILABLE", "other transcript failures remain scoped to the transcript view")

equal(hud.next_poll("chat", 5000, 1000, 0, 5000, 5000), "transcript", "the chat refresh wins when both background status and transcript polls are due")
equal(hud.next_poll("chat", 4000, 0, 1000, 5000, 5000), nil, "the scheduler does not create a premature second request")
equal(hud.next_poll("sessions", 5000, 0, 0, 5000, 5000), "status", "non-chat pages retain context polling")

local chat = hud.transcript_layout()
equal(chat.visible_lines, 8, "the restored viewport renders the original eight compact transcript rows")
equal(chat.section_label_y, 39, "the transcript heading returns to the original smoked-gray baseline")
equal(chat.session_y, 48, "the session summary returns to the original transcript placement")
equal(chat.panel_y, 87, "the history pane returns to the original transcript placement")
equal(chat.text_y, 104, "the first history row returns below the original RECENT OUTPUT label")
equal(chat.font_size, 10, "the history rows return to the original readable text size")
assert(chat.line_step >= chat.font_line_h + 3, "transcript baselines leave a clear visual gap instead of colliding")
assert(chat.text_y + (chat.visible_lines - 1) * chat.line_step + chat.font_line_h <= chat.panel_y + chat.panel_h - chat.bottom_padding,
  "every visible transcript row stays inside the terminal pane")

local canvas = hud.canvas_layout()
equal(canvas.width, 320, "canvas matches the physical display width")
equal(canvas.height, 240, "canvas matches the physical display height")
equal(canvas.sessions.first_row_y, 55, "session rows start below the compact header")
equal(canvas.sessions.row_step, 36, "four session rows leave a clear footer rail")
equal(canvas.home.system_row_h, 27, "System is intentionally a single-line row")

print("orca_hud_model tests passed")
