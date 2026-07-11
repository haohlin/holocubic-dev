# Holo Flight Deck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and install a transparent, tilt-controlled Holo Flight Deck app on the current Holocubic firmware.

**Architecture:** `flight_math.lua` owns the pure calibration, dead-zone, smoothing, and horizon geometry. `main.lua` loads that module, turns current-firmware IMU/key events into HUD state, and owns LVGL objects plus timer cleanup. The initial app has no network or Orca dependency.

**Tech Stack:** Holocubic Lua runtime, LVGL Lua bindings, Node.js built-in test runner, Fengari Lua CLI via `npx`, DevTools HTTP file API.

## Global Constraints

- Display target: 320 x 240 pixels.
- Base field: `0x000000`; cyan/white are primary HUD colours; no opaque UI panels.
- IMU: first valid sample is neutral; 1.5 degree dead zone; plus/minus 45 degree clamp; smoothing alpha `0.28`; 25 ms render period.
- Key handling: inspect all events; `HOME` short toggles scan; `HOME` long-start exits; never call power APIs.
- IMU callbacks only cache the latest sample; render, file, and network work do not run in callbacks.
- The first release has no network, firmware-setting, or Orca integration.

---

## File Structure

```text
apps/holo-flight-deck/
  package/
    app.info                 # launcher metadata
    flight_math.lua          # pure control law used on device and in host tests
    main.lua                 # LVGL HUD and firmware bindings
    info.html                # launcher description
tests/
  flight_math.test.lua       # host behavior tests through Fengari
  package-contract.test.mjs  # manifest and lifecycle binding contract
```

### Task 1: Test and implement the pure flight-control module

**Files:**
- Create: `tests/flight_math.test.lua`
- Create: `apps/holo-flight-deck/package/flight_math.lua`

**Interfaces:**
- Produces `flight_math.normalize(raw, neutral, dead_zone, limit) -> number`.
- Produces `flight_math.smooth(current, target, alpha) -> number`.
- Produces `flight_math.horizon(width, height, pitch, roll) -> x1, y1, x2, y2`.

- [ ] **Step 1: Write the failing Lua behavior test**

```lua
package.path = "apps/holo-flight-deck/package/?.lua;" .. package.path
local flight = require("flight_math")

local function equal(actual, expected, message)
  assert(actual == expected, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function near(actual, expected, epsilon, message)
  assert(math.abs(actual - expected) <= epsilon, (message or "values differ") .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

equal(flight.normalize(11.5, 10, 1.5, 45), 0, "dead zone includes its boundary")
equal(flight.normalize(11.6, 10, 1.5, 45), 1.6, "positive value survives dead zone")
equal(flight.normalize(-100, 0, 1.5, 45), -45, "negative tilt clamps")
near(flight.smooth(0, 10, 0.28), 2.8, 0.0001, "smoothing uses alpha")

local x1, y1, x2, y2 = flight.horizon(320, 240, 45, 0)
equal(x1, 25, "level horizon starts at left extent")
equal(x2, 295, "level horizon ends at right extent")
equal(y1, 195, "full pitch offsets horizon down")
equal(y2, 195, "level horizon is horizontal")

local _, up_y1, _, up_y2 = flight.horizon(320, 240, 0, 35)
assert(up_y1 < up_y2, "positive roll rises from left to right")

print("flight_math tests passed")
```

- [ ] **Step 2: Run the test and confirm the expected missing-module failure**

Run:

```bash
npx --yes --package=fengari-node-cli fengari tests/flight_math.test.lua
```

Expected: failure stating that module `flight_math` was not found.

- [ ] **Step 3: Implement the minimal pure control module**

```lua
local M = {}

local function clamp(value, lower, upper)
  if value < lower then return lower end
  if value > upper then return upper end
  return value
end

function M.normalize(raw, neutral, dead_zone, limit)
  local value = (tonumber(raw) or 0) - (tonumber(neutral) or 0)
  local threshold = math.abs(tonumber(dead_zone) or 0)
  local bound = math.abs(tonumber(limit) or 45)
  if math.abs(value) <= threshold then return 0 end
  return clamp(value, -bound, bound)
end

function M.smooth(current, target, alpha)
  local from = tonumber(current) or 0
  local to = tonumber(target) or 0
  local amount = clamp(tonumber(alpha) or 0, 0, 1)
  return from + (to - from) * amount
end

function M.horizon(width, height, pitch, roll)
  local screen_w = tonumber(width) or 320
  local screen_h = tonumber(height) or 240
  local center_x = screen_w / 2
  local center_y = screen_h / 2 + clamp(tonumber(pitch) or 0, -45, 45) / 45 * 75
  local radians = clamp(tonumber(roll) or 0, -35, 35) * math.pi / 180
  local half_length = 135
  local dx = math.cos(radians) * half_length
  local dy = math.sin(radians) * half_length
  return math.floor(center_x - dx + 0.5), math.floor(center_y - dy + 0.5),
         math.floor(center_x + dx + 0.5), math.floor(center_y + dy + 0.5)
end

return M
```

- [ ] **Step 4: Run the Lua behavior test and verify it passes**

Run:

```bash
npx --yes --package=fengari-node-cli fengari tests/flight_math.test.lua
```

Expected: `flight_math tests passed`.

- [ ] **Step 5: Commit the tested control law**

```bash
git add apps/holo-flight-deck/package/flight_math.lua tests/flight_math.test.lua
git commit -m "feat: add Flight Deck tilt control law"
```

### Task 2: Test and implement the packaged Flight Deck HUD

**Files:**
- Create: `tests/package-contract.test.mjs`
- Create: `apps/holo-flight-deck/package/app.info`
- Create: `apps/holo-flight-deck/package/main.lua`
- Create: `apps/holo-flight-deck/package/info.html`

**Interfaces:**
- Consumes `flight_math.normalize`, `flight_math.smooth`, and `flight_math.horizon` from Task 1.
- Produces a launcher-recognized app with id `holo-flight-deck` and entry `main.lua`.

- [ ] **Step 1: Write the failing package contract test**

```js
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const packageDir = new URL('../apps/holo-flight-deck/package/', import.meta.url);
const read = (name) => readFileSync(new URL(name, packageDir), 'utf8');

test('Flight Deck declares its launcher entry and safe firmware bindings', () => {
  assert.equal(existsSync(new URL('app.info', packageDir)), true);
  assert.equal(existsSync(new URL('main.lua', packageDir)), true);
  assert.match(read('app.info'), /^name = Holo Flight Deck$/m);
  assert.match(read('app.info'), /^entry = main.lua$/m);

  const source = read('main.lua');
  assert.match(source, /app_api\.on, "imu"/);
  assert.match(source, /app_api\.set_home_exit, false/);
  assert.match(source, /key_api\.on, function/);
  assert.match(source, /key_api\.off/);
  assert.match(source, /app_api\.on, "imu", nil/);
  assert.match(source, /tmr_api\.create/);
});
```

- [ ] **Step 2: Run the contract test and confirm the expected absent-package failure**

Run:

```bash
node --test tests/package-contract.test.mjs
```

Expected: failure reading `app.info` because the package does not yet exist.

- [ ] **Step 3: Create the manifest and launcher description**

Create `apps/holo-flight-deck/package/app.info`:

```ini
name = Holo Flight Deck
kind = app
entry = main.lua
description = Transparent tilt-controlled cockpit HUD and input probe
version = 0.1.0
```

Create `apps/holo-flight-deck/package/info.html`:

```html
<!doctype html>
<html lang="en"><meta charset="utf-8"><title>Holo Flight Deck</title>
<body style="background:#000;color:#8fe9ff;font:16px system-ui;padding:20px">
  <h1>Holo Flight Deck</h1>
  <p>Tilt-controlled transparent cockpit HUD.</p>
  <p>Short HOME toggles scan when the device exposes HOME. Long HOME exits.</p>
</body></html>
```

- [ ] **Step 4: Implement the firmware bindings and HUD**

Create `apps/holo-flight-deck/package/main.lua`:

```lua
local APP_KEY = "HOLO_FLIGHT_DECK_APP"
local previous = rawget(_G, APP_KEY)
if previous and previous.stop then pcall(function() previous.stop("reload") end) end

local app_api = rawget(_G, "app")
local key_api = rawget(_G, "key")
local tmr_api = rawget(_G, "tmr")
local flight = dofile("/sd/apps/holo-flight-deck/flight_math.lua")
local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local C = { black = 0x000000, cyan = 0x8FE9FF, faint = 0x36515A, white = 0xFFFFFF, amber = 0xFFC857 }

local APP = {
  width = 320, height = 240, dead_zone = 1.5, limit = 45, alpha = 0.28,
  neutral_roll = nil, neutral_pitch = nil, raw_roll = 0, raw_pitch = 0,
  roll = 0, pitch = 0, scan = false, sweep = 0, last_event = "IMU: waiting",
  imu_seen_at = 0, active = true, timer = nil, root = nil, ui = {},
}
_G[APP_KEY] = APP

local function call(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

local function clock_ms()
  if tmr_api and tmr_api.now then return math.floor((tonumber(tmr_api.now()) or 0) / 1000) end
  return 0
end

local function set_text(label, text)
  call(rawget(_G, "lv_label_set_text"), label, text)
end

local function make_label(text, x, y, color)
  local create = rawget(_G, "lv_label_create")
  local label = create and create(APP.root) or nil
  if not label then return nil end
  set_text(label, text)
  call(rawget(_G, "lv_obj_set_pos"), label, x, y)
  call(rawget(_G, "lv_obj_set_style_text_color"), label, color, MAIN)
  call(rawget(_G, "lv_obj_set_style_text_opa"), label, 255, MAIN)
  return label
end

local function make_line(color, width)
  local create = rawget(_G, "lv_line_create")
  local line = create and create(APP.root) or nil
  if not line then return nil end
  call(rawget(_G, "lv_line_set_points"), line, { 0, 0, 0, 0 }, 2)
  call(rawget(_G, "lv_obj_set_style_line_color"), line, color, MAIN)
  call(rawget(_G, "lv_obj_set_style_line_width"), line, width, MAIN)
  call(rawget(_G, "lv_obj_set_style_line_opa"), line, 255, MAIN)
  return line
end

local function set_line(line, x1, y1, x2, y2)
  if line then call(rawget(_G, "lv_line_set_points"), line, { x1, y1, x2, y2 }, 2) end
end

local function build_ui()
  local screen = rawget(_G, "lv_scr_act")
  APP.root = screen and screen() or nil
  if not APP.root then
    APP.last_event = "LVGL: no root screen"
    return false
  end
  call(rawget(_G, "lv_obj_clean"), APP.root)
  call(rawget(_G, "lv_obj_set_style_bg_color"), APP.root, C.black, MAIN)
  call(rawget(_G, "lv_obj_set_style_bg_opa"), APP.root, 255, MAIN)
  APP.ui.title = make_label("FLIGHT DECK", 12, 10, C.cyan)
  APP.ui.mode = make_label("SCAN OFF", 238, 10, C.faint)
  APP.ui.attitude = make_label("R +00.0  P +00.0", 96, 30, C.white)
  APP.ui.telemetry = make_label(APP.last_event, 12, 218, C.faint)
  APP.ui.horizon = make_line(C.cyan, 2)
  APP.ui.reticle_h = make_line(C.white, 1)
  APP.ui.reticle_v = make_line(C.white, 1)
  APP.ui.scan = make_line(C.faint, 1)
  set_line(APP.ui.reticle_h, 148, 120, 172, 120)
  set_line(APP.ui.reticle_v, 160, 108, 160, 132)
  return APP.ui.horizon ~= nil
end

local function render()
  if not APP.active then return end
  local target_roll, target_pitch = 0, 0
  if APP.neutral_roll ~= nil then
    target_roll = flight.normalize(APP.raw_roll, APP.neutral_roll, APP.dead_zone, APP.limit)
    target_pitch = flight.normalize(APP.raw_pitch, APP.neutral_pitch, APP.dead_zone, APP.limit)
  end
  APP.roll = flight.smooth(APP.roll, target_roll, APP.alpha)
  APP.pitch = flight.smooth(APP.pitch, target_pitch, APP.alpha)
  local x1, y1, x2, y2 = flight.horizon(APP.width, APP.height, APP.pitch, APP.roll)
  set_line(APP.ui.horizon, x1, y1, x2, y2)
  set_text(APP.ui.attitude, string.format("R %+.1f  P %+.1f", APP.roll, APP.pitch))
  if APP.scan then
    APP.sweep = (APP.sweep + 4) % 101
    set_line(APP.ui.scan, 204, 76, 204, 164)
    call(rawget(_G, "lv_obj_set_x"), APP.ui.scan, math.floor(APP.sweep - 50))
    set_text(APP.ui.mode, "SCAN ON")
    call(rawget(_G, "lv_obj_set_style_text_color"), APP.ui.mode, C.cyan, MAIN)
  else
    set_line(APP.ui.scan, 0, 0, 0, 0)
    set_text(APP.ui.mode, "SCAN OFF")
    call(rawget(_G, "lv_obj_set_style_text_color"), APP.ui.mode, C.faint, MAIN)
  end
  local age = APP.imu_seen_at == 0 and "no sample" or tostring(math.max(0, clock_ms() - APP.imu_seen_at)) .. "ms"
  set_text(APP.ui.telemetry, APP.last_event .. " | IMU " .. age)
end

function APP.stop(reason)
  if not APP.active then return end
  APP.active = false
  if APP.timer then
    call(function() APP.timer:stop() end)
    call(function() APP.timer:unregister() end)
    APP.timer = nil
  end
  if key_api and key_api.off then call(key_api.off) end
  if app_api and app_api.on then call(app_api.on, "imu", nil) end
  if APP.root then call(rawget(_G, "lv_obj_clean"), APP.root) end
  if rawget(_G, APP_KEY) == APP then _G[APP_KEY] = nil end
  print("[flight-deck] stopped", tostring(reason or ""))
end

if app_api and app_api.set_home_exit then call(app_api.set_home_exit, false) end
if app_api and app_api.on then
  call(app_api.on, "imu", function(_, roll, pitch)
    if not APP.active then return end
    if APP.neutral_roll == nil then
      APP.neutral_roll, APP.neutral_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
      APP.last_event = "IMU: neutral locked"
    end
    APP.raw_roll, APP.raw_pitch = tonumber(roll) or 0, tonumber(pitch) or 0
    APP.imu_seen_at = clock_ms()
  end)
else
  APP.last_event = "IMU: API unavailable"
end

if key_api and key_api.on then
  call(key_api.on, function(code, event_type)
    if not APP.active then return end
    APP.last_event = "KEY " .. tostring(code) .. " / " .. tostring(event_type)
    if code == key_api.HOME and event_type == key_api.SHORT then APP.scan = not APP.scan end
    if code == key_api.HOME and event_type == key_api.LONG_START then
      APP.stop("long HOME")
      if app_api and app_api.exit then call(app_api.exit) end
    end
  end)
else
  APP.last_event = "KEY: API unavailable"
end

if build_ui() and tmr_api and tmr_api.create then
  APP.timer = tmr_api.create()
  APP.timer:alarm(25, tmr_api.ALARM_AUTO, function()
    local ok, err = pcall(render)
    if not ok then APP.last_event = "render error: " .. tostring(err) end
  end)
  render()
else
  print("[flight-deck] UI or timer unavailable")
end
```

- [ ] **Step 5: Run syntax and contract checks**

Run:

```bash
npx --yes --package=fengari-node-cli fengari -e "assert(loadfile('apps/holo-flight-deck/package/main.lua'))"
node --test tests/package-contract.test.mjs
npx --yes --package=fengari-node-cli fengari tests/flight_math.test.lua
```

Expected: all three commands exit `0`; the contract test reports one passing test and the Lua test prints `flight_math tests passed`.

- [ ] **Step 6: Commit the testable app package**

```bash
git add apps/holo-flight-deck/package tests/package-contract.test.mjs
git commit -m "feat: add Holo Flight Deck app"
```

### Task 3: Install and validate on the current device

**Files:**
- Modify: no tracked source files unless device testing exposes a defect.

**Interfaces:**
- Consumes the `package/` directory from Task 2.
- Produces `/sd/apps/holo-flight-deck/` on the device; DevTools discovers it after a launcher refresh.

- [ ] **Step 1: Create the device app directory through DevTools**

Run:

```bash
curl --fail --silent --show-error -X POST \
  'http://clocteck-cubic.local/devtools/api/mkdir?path=/sd/apps/holo-flight-deck'
```

Expected: JSON containing `"ok":true` and the new directory path.

- [ ] **Step 2: Upload each deployable file without touching existing apps**

Run:

```bash
for name in app.info flight_math.lua main.lua info.html; do
  size=$(wc -c < "apps/holo-flight-deck/package/$name" | tr -d ' ')
  curl --fail --silent --show-error -X PUT \
    --data-binary "@apps/holo-flight-deck/package/$name" \
    "http://clocteck-cubic.local/devtools/api/upload?path=/sd/apps/holo-flight-deck/$name&offset=0&total=$size"
done
```

Expected: each JSON response contains `"ok":true` and `"done":true`.

- [ ] **Step 3: Verify exactly the uploaded files through the read-only DevTools list API**

Run:

```bash
curl --fail --silent --show-error \
  'http://clocteck-cubic.local/devtools/api/list?path=/sd/apps/holo-flight-deck'
```

Expected: entries for `app.info`, `flight_math.lua`, `main.lua`, and `info.html`; no existing app path is modified.

- [ ] **Step 4: Refresh the launcher and launch Holo Flight Deck from the device web control page**

Use the current web UI’s refresh/application-management control, then select
`Holo Flight Deck`. Confirm the screen presents black transparency, cyan
reticle, horizon, and telemetry before touching the device.

- [ ] **Step 5: Perform the physical acceptance test**

1. Hold the device neutral for one second; telemetry must show calibrated and
   the horizon must be level.
2. Tilt forward/backward; the horizon moves vertically.
3. Tilt left/right; the horizon rotates in the matching direction.
4. Tilt diagonally; both effects appear together with no app crash.
5. Short-press the physical button; record whether telemetry receives a key
   event and whether scan toggles.
6. Long-press only after step 5; confirm the app returns cleanly to launcher.

- [ ] **Step 6: Record results without committing device-specific telemetry**

Run:

```bash
git status --short
```

Expected: no source changes unless a test finding requires a new red-green-fix cycle.
