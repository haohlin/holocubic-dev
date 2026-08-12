# Holo Orca Transcript and Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or an equivalent inline task-by-task execution) to implement these checked steps.

**Goal:** Give Holo Context HUD a stable smoked-gray Liquid Glass treatment, explicit agent-state labels, and a safe read-only transcript view.

**Architecture:** The Node bridge gains an authenticated, opaque-session-id `GET /v1/transcript` endpoint. It resolves the id against the current status snapshot and returns a sanitized, bounded terminal tail. The Lua model owns the state labels and a three-page navigation contract; `main.lua` remains a single retained canvas and paints the new glass primitives and transcript page without dynamic LVGL objects.

**Tech Stack:** Node.js built-in HTTP and test runner, public `orca` CLI, HoloCubic Lua canvas API, Fengari Lua model tests, hostname-only HoloCubic DevTools verification.

## Global Constraints

- Device requests use `clocteck-cubic.local` only.
- Preserve the single-canvas runtime and do not add dynamic LVGL widgets.
- Use `#3E424A` as the fully opaque canvas base.
- Transcript requests accept opaque ids only; raw terminal handles never cross the bridge.
- Transcript output is read-only, ANSI/control-sequence-free, line- and width-bounded.
- Keep short-press focus limited to the Sessions page. Do not add voice, text entry, terminal command, or TTS capability.
- Do not commit existing user changes without explicit authorization.

---

### Task 1: Specify and prove the transcript bridge contract

**Files:**
- Modify: `tests/orca_bridge.test.mjs`
- Modify: `companion/orca_bridge.mjs`

**Interfaces:**
- `GET /v1/transcript?id=<opaque-session-id>` returns `{ transcript: { session, lines } }`.
- Unknown, disconnected, or missing ids return a non-200 structured error without executing `orca terminal read`.
- `lines` contains sanitized display-safe strings only.

- [x] Add failing Node tests for valid opaque-id transcript lookup, unknown-id rejection, terminal-read sanitization, and the existing bearer-auth behavior.
- [x] Run `node --test tests/orca_bridge.test.mjs` and observe the missing endpoint failure.
- [x] Add bounded query parsing, status-snapshot lookup, read-only `orca terminal read`, and result normalization/sanitization.
- [x] Re-run `node --test tests/orca_bridge.test.mjs` until all assertions pass.

### Task 2: Add model contracts for page and agent state

**Files:**
- Modify: `tests/orca_hud_model.test.lua`
- Modify: `apps/holo-orca-hud/package/hud_model.lua`

**Interfaces:**
- `hud.session_indicator(session)` yields `WORKING`, `DONE`, `OFFLINE`, `ATTENTION`, or `FOCUSED` plus its semantic tone.
- `hud.page_after_tilt(page, direction)` clamps the page within `Overview=1`, `Sessions=2`, `Transcript=3`.
- `hud.transcript_lines(payload, max_lines, max_width)` supplies display-safe compact rows.

- [x] Add failing Fengari assertions for working, done, offline, and attention states; third-page navigation; and transcript compaction.
- [x] Run the Fengari model test and observe each missing or mismatched behavior.
- [x] Implement the small pure-model helpers without changing network or rendering code.
- [x] Re-run the Fengari test until all assertions pass.

### Task 3: Render the three-page glass HUD using the stable canvas

**Files:**
- Modify: `tests/package-contract.test.mjs`
- Modify: `apps/holo-orca-hud/package/main.lua`
- Modify: `apps/holo-orca-hud/package/app.info`

**Interfaces:**
- `main.lua` fetches a selected transcript only while page 3 is active or on its short press.
- One canvas paint draws the `#3E424A` background, glass panels, explicit labels, and an eight-line transcript tail.
- Footer guidance matches the specified three-page physical controls.

- [x] Add failing static contract checks for the gray base, third page, transcript endpoint, and no command-send endpoint.
- [x] Run `node --test tests/package-contract.test.mjs` and observe failure.
- [x] Add glass drawing helpers, explicit label rendering, transcript state/fetching, page handling, and version `0.3.0`.
- [x] Run package and Lua model contract tests until all pass.

### Task 4: Validate the complete local and device loop

**Files:**
- Modify: `scripts/verify-orca-hud-device.mjs`
- Modify: `tests/package-contract.test.mjs`

**Interfaces:**
- Device verifier proves the cube can fetch both `/v1/status` and an opaque-id `/v1/transcript` from the paired bridge without writing terminal content to the device check file.

- [x] Add a failing verifier-contract test that requires a transcript bridge probe.
- [x] Run its focused test and observe failure.
- [x] Extend the DevRun probe to derive a current opaque id, issue the transcript GET, and record only status code and response length.
- [x] Run all local tests, `git diff --check`, `graphify update .`, start the bridge, deploy, and run the hostname-only device verifier.
- [x] Verify the device's foreground app and absence of `runtime-error.txt`; report any physical-display limitation plainly.
