# Holo Orca Canvas Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unstable multi-object LVGL renderer with one stable canvas while preserving the established Holo Context HUD design and controls.

**Architecture:** `main.lua` keeps the existing bridge, session state, timer, gyro, and button logic. Its rendering layer becomes one retained `LV_IMG_CF_TRUE_COLOR` canvas which is repainted only when `render_dirty` is true. Canvas helper functions draw black, bordered rails, source PNG assets, text, semantic state squares, and the fixed footer directly into that canvas.

**Tech Stack:** HoloCubic Lua runtime, current firmware canvas APIs (`lv_canvas_create`, frame begin/end, draw rect/text/image), existing Node tests, Fengari model tests, hostname-only DevTools deployment.

## Global Constraints

- Use `clocteck-cubic.local` for every device request.
- Preserve the accepted Orca Mobile-derived visual hierarchy and packaged official assets.
- Keep true-black background, 12px titles, 10px metadata, and no overlapping System metadata.
- Keep existing bridge and physical controls unchanged.
- Do not create dynamic LVGL labels, images, panels, dots, or lines after startup.
- Do not commit without explicit user authorization.

---

### Task 1: Define canvas layout and package contract

**Files:**
- Modify: `apps/holo-orca-hud/package/hud_model.lua`
- Modify: `tests/orca_hud_model.test.lua`
- Modify: `tests/package-contract.test.mjs`

**Interfaces:**
- Produces `M.canvas_layout()` with immutable Home, Sessions, row, and rail coordinates.
- `main.lua` consumes `hud.canvas_layout()` rather than per-widget `row_layout()`.

- [ ] **Step 1: Write the failing model checks**

```lua
local layout = hud.canvas_layout()
equal(layout.width, 320, "canvas matches the physical display width")
equal(layout.height, 240, "canvas matches the physical display height")
equal(layout.sessions.first_row_y, 55, "session rows start below the compact header")
equal(layout.sessions.row_step, 36, "four session rows leave a clear footer rail")
equal(layout.home.system_row_h, 27, "System is intentionally a single-line row")
```

- [ ] **Step 2: Verify the checks fail**

Run: `npx --yes --package=fengari-node-cli fengari tests/orca_hud_model.test.lua`

Expected: failure because `canvas_layout` is not defined.

- [ ] **Step 3: Implement the immutable layout contract and static renderer checks**

```lua
function M.canvas_layout()
  return {
    width = 320, height = 240,
    sessions = { first_row_y = 55, row_step = 36, row_h = 35 },
    home = { system_row_y = 181, system_row_h = 27, rail_y = 214 },
  }
end
```

Add package assertions for `lv_canvas_create`, `lv_canvas_frame_begin` or
`lv_canvas_begin`, `lv_canvas_draw_text`, `lv_canvas_draw_img`, and absence
of the old `make_label`/`make_panel` primitives.

- [ ] **Step 4: Verify the contract**

Run: `node --test tests/package-contract.test.mjs && npx --yes --package=fengari-node-cli fengari tests/orca_hud_model.test.lua`

Expected: all package and model checks pass.

### Task 2: Replace the LVGL object tree with one retained canvas

**Files:**
- Modify: `apps/holo-orca-hud/package/main.lua`
- Test: `tests/package-contract.test.mjs`

**Interfaces:**
- Consumes `hud.canvas_layout()`, existing `APP.sessions`, `APP.orca`, weather state, and packaged asset paths.
- Produces one `APP.canvas` object and `render()` that writes one complete frame only when dirty.

- [ ] **Step 1: Write failing static assertions for the retained canvas**

```javascript
assert.match(source, /APP\.canvas = canvas_create\(APP\.root, L\.width, L\.height, CANVAS_FMT\)/);
assert.match(source, /canvas_frame_begin\(APP\.canvas\)/);
assert.match(source, /canvas_frame_end\(APP\.canvas, explicit_frame\)/);
assert.doesNotMatch(source, /local function make_label/);
assert.doesNotMatch(source, /local function make_panel/);
```

- [ ] **Step 2: Verify the assertions fail**

Run: `node --test tests/package-contract.test.mjs`

Expected: failure because the object-tree renderer is still present.

- [ ] **Step 3: Implement canvas helpers and the two accepted screens**

```lua
local explicit_frame = canvas_frame_begin(APP.canvas)
canvas_fill(APP.canvas, C.black, 255)
draw_header()
if APP.page == 1 then draw_home() else draw_sessions() end
draw_footer()
canvas_frame_end(APP.canvas, explicit_frame)
```

Use `draw_rect` for 1px rails, `draw_text` with `font_size = 8`, `10`, `12`,
or `14`, and `draw_img` with the existing `assets/*.png` source paths. Draw
the System content as one compact text line at `system_row_y + 7`. Do not add
new assets or alter the current bridge/input functions.

- [ ] **Step 4: Verify local behavior**

Run: `node --test tests/*.test.mjs && npx --yes --package=fengari-node-cli fengari tests/orca_hud_model.test.lua && git diff --check`

Expected: all tests pass and the diff has no whitespace errors.

### Task 3: Verify the real cube loop

**Files:**
- Modify: `scripts/verify-orca-hud-device.mjs`
- Test: `tests/package-contract.test.mjs`

**Interfaces:**
- Consumes the local bridge config and deployed canvas HUD.
- Produces a hostname-only launch/bridge/soak/exit/relaunch proof and leaves the HUD foregrounded.

- [ ] **Step 1: Write a failing verifier contract check**

```javascript
assert.match(source, /await delay\(20_000\)/, 'soaks the canvas HUD across several bridge polls');
assert.match(source, /lifecycle\.txt/, 'requires the canvas HUD to avoid an unexpected lifecycle stop');
```

- [ ] **Step 2: Verify the verifier check fails**

Run: `node --test tests/package-contract.test.mjs`

Expected: failure because the verifier has no 20-second canvas soak.

- [ ] **Step 3: Extend the verifier and deploy**

Make `launchHud()` verify the foreground app after a 20-second delay, then
check `runtime-error.txt` is absent and `lifecycle.txt` remains `started`.
Deploy with:

```bash
node scripts/start-orca-bridge.mjs
node scripts/deploy-orca-hud.mjs
node scripts/verify-orca-hud-device.mjs
```

- [ ] **Step 4: Confirm live device state**

Run:

```bash
curl --fail --silent --show-error --max-time 15 \
  'http://clocteck-cubic.local/api/system/state'
```

Expected: `current_app.id` is `holo-orca-hud`; bridge status returns the current Orca sessions; the app stays active through the soak and relaunch cycle.
