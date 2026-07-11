# Holo Orca HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local-network HoloCubic app that monitors sanitized Orca sessions and activates a selected session.

**Architecture:** A Node bridge owns all `orca` CLI calls and exposes a token-protected two-endpoint API. A Lua app polls that API, renders a compact HUD, uses physical horizontal tilt for selection, and uses short HOME to request `orca terminal switch` for the selected session.

**Tech Stack:** Node.js standard library, `orca` CLI JSON output, HoloCubic Lua/LVGL/HTTP/sjson APIs, Node and Fengari host tests.

## Global Constraints

- Bridge port is `47631`; it binds only to the configured local LAN interface.
- The bridge response must exclude prompts, previews, terminal output, paths, branches, raw IDs, and terminal handles.
- The bridge may invoke only `orca status`, `orca worktree ps`, `orca terminal list`, and `orca terminal switch`.
- The HoloCubic app short press activates and long press exits.
- Local bridge configuration and rendered device connection details are Git-ignored.

---

### Task 1: Build and test the sanitized Orca bridge

**Files:**
- Create: `companion/orca_bridge.mjs`
- Create: `tests/orca_bridge.test.mjs`

**Interfaces:**
- Produces: `createBridgeServer({ token, runOrca }) -> http.Server`.
- `runOrca(args) -> Promise<object>` receives a complete `orca` JSON result.

- [ ] **Step 1: Write the failing bridge tests**

```js
const response = await fetch(`${base}/v1/status`, {
  headers: { authorization: 'Bearer test-token' },
});
assert.equal(response.status, 200);
const body = await response.json();
assert.deepEqual(Object.keys(body.sessions[0]).sort(),
  ['active', 'agentState', 'canActivate', 'id', 'label', 'status', 'terminalCount']);
```

Also assert an unauthenticated request returns `401`, sensitive metadata is
absent, and `POST /v1/select` calls `orca terminal switch --terminal <mapped
handle> --json` for a listed controllable session.

- [ ] **Step 2: Run the test to verify it fails**

Run: `node --test tests/orca_bridge.test.mjs`

Expected: failure because `companion/orca_bridge.mjs` does not exist.

- [ ] **Step 3: Implement the minimal bridge**

Use `node:http`, `node:child_process`, and `node:crypto`. Parse only Orca JSON
envelopes with `ok: true`; construct opaque SHA-256-derived session IDs; map
those IDs to currently connected terminal handles only within the bridge.

- [ ] **Step 4: Run the bridge tests**

Run: `node --test tests/orca_bridge.test.mjs`

Expected: all bridge tests pass.

### Task 2: Add device control-law tests and package contract

**Files:**
- Create: `apps/holo-orca-hud/package/hud_model.lua`
- Create: `tests/orca_hud_model.test.lua`
- Modify: `tests/package-contract.test.mjs`

**Interfaces:**
- Produces: `hud_model.move_selection(index, count, physical_horizontal, latched, threshold) -> index, latched, changed`.

- [ ] **Step 1: Write failing pure-Lua tests**

```lua
local index, latched, changed = hud.move_selection(2, 4, 16, false, 12)
equal(index, 3)
equal(latched, true)
assert(changed)
```

Cover negative tilt, neutral unlatching, and list bounds. Extend the package
contract to require `app.info`, `main.lua`, `hud_model.lua`, and `main.png`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `npx --yes --package=fengari-node-cli fengari tests/orca_hud_model.test.lua && node --test tests/package-contract.test.mjs`

Expected: failure because the app package does not exist.

- [ ] **Step 3: Implement the model and manifest**

Use a 12-degree threshold and a return-to-neutral latch. Declare the launcher
icon in `app.info`.

- [ ] **Step 4: Run tests**

Run: `npx --yes --package=fengari-node-cli fengari tests/orca_hud_model.test.lua && node --test tests/package-contract.test.mjs`

Expected: model and package tests pass.

### Task 3: Implement the Holo Orca HUD and deployment helpers

**Files:**
- Create: `apps/holo-orca-hud/package/main.lua`
- Create: `apps/holo-orca-hud/package/main.svg`
- Create: `apps/holo-orca-hud/package/connection.example.lua`
- Create: `scripts/start-orca-bridge.mjs`
- Create: `scripts/deploy-orca-hud.mjs`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: bridge `GET /v1/status` and `POST /v1/select`; `hud_model.move_selection`.
- Produces: a deployable `/sd/apps/holo-orca-hud` package plus a local bridge process.

- [ ] **Step 1: Write failing static assertions**

Extend `tests/package-contract.test.mjs` to require async HTTP polling,
`key_api.HOME`, long-press exit, and `hud.move_selection` in the device source.

- [ ] **Step 2: Run the package test to verify it fails**

Run: `node --test tests/package-contract.test.mjs`

Expected: failure because `main.lua` is absent.

- [ ] **Step 3: Implement the HUD**

Build the LVGL labels and selection marker, call `http.get` asynchronously every
five seconds, decode with `sjson`/`json`, move on physical horizontal IMU tilt,
and `http.post` the selected opaque ID on short HOME. The app must unregister
the IMU, key, timer, and clean the screen on exit.

- [ ] **Step 4: Implement local configuration and deployment**

The start script chooses the current LAN IP, creates a random token if absent,
and starts the bridge detached. The deploy script renders a Git-ignored
`connection.lua`, uploads the app files through DevTools, then requests
`app.rescan()`.

- [ ] **Step 5: Run host validation and deploy**

Run:

```bash
node --test tests/orca_bridge.test.mjs tests/package-contract.test.mjs
npx --yes --package=fengari-node-cli fengari tests/orca_hud_model.test.lua
node scripts/start-orca-bridge.mjs --check
node scripts/deploy-orca-hud.mjs
```

Expected: all tests pass, the bridge health endpoint responds, and the device
launcher lists Holo Orca HUD.
