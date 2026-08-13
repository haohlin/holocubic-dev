# Holo Orca Tilt Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or an equivalent inline task-by-task execution) to implement this plan task-by-task.

**Goal:** Make Holo Context HUD deliberate to tilt, navigate its hierarchy horizontally, and scroll full retained terminal history vertically.

**Architecture:** Pure Lua model helpers provide hysteretic tilt latching, horizontal page navigation, bounded session cursor movement, and transcript scroll-window geometry. The bridge returns the full retained `terminal.tail` and provenance metadata. The retained canvas stores a transcript scroll offset and uses `right = enter`, `left = back`, with forward/back reserved for vertical scroll.

**Tech Stack:** HoloCubic Lua canvas runtime, Node.js bridge and built-in test runner, Fengari model tests, public Orca terminal CLI, hostname-only HoloCubic DevTools validation.

## Global Constraints

- Every device request uses an operator-supplied `HOLOCUBIC_HOST`.
- Do not create dynamic LVGL widgets or add command, voice, or TTS capability.
- Horizontal tilt is hierarchy only: right enters and left backs out.
- Forward/back tilt is vertical list/chat scrolling only.
- Use 24° engage and 12° release thresholds for every directional gesture.
- Return all retained terminal tail rows, but never raw terminal handles or data older than Orca retains.
- Do not commit existing user changes without explicit authorization.

---

### Task 1: Prove retained-chat bridge behavior

**Files:**
- Modify: `tests/orca_bridge.test.mjs`
- Modify: `companion/orca_bridge.mjs`

**Interfaces:**
- `GET /v1/transcript?id=<opaque-id>` returns every sanitized retained tail row (up to the CLI's 1,000-row request) and `{ retainedLines, truncated, limited }` metadata.

- [x] Write a failing bridge test with 10 tail rows that asserts all rows and history metadata are returned.
- [x] Run `node --test tests/orca_bridge.test.mjs`; confirm the current eight-line cap fails the test.
- [x] Request `orca terminal read --limit 1000 --json`, retain its sanitized `terminal.tail`, and return only count/retention metadata.
- [x] Run the bridge test again until all assertions pass.

### Task 2: Prove deliberate directional-model behavior

**Files:**
- Modify: `tests/orca_hud_model.test.lua`
- Modify: `apps/holo-orca-hud/package/hud_model.lua`

**Interfaces:**
- `hud.move_selection(index, count, axis, latched, 24, 12)` ignores motion inside 24°, latches after one move, and releases only inside 12°.
- `hud.move_page(index, axis, latched, 24, 12)` moves among the three pages from horizontal input.
- `hud.transcript_window(lines, scroll, visible)` returns the visible retained-chat slice and clamped scroll position.

- [x] Add failing Fengari cases for 18° rejection, 25° one-shot movement, 12° release, horizontal page enter/back, and vertical chat-window bounds.
- [x] Run the model test and confirm the prior threshold/page contract fails.
- [x] Implement the minimal pure helpers and maintain the explicit semantic-status model.
- [x] Re-run the model test until all assertions pass.

### Task 3: Render and operate the scrollable hierarchy

**Files:**
- Modify: `tests/package-contract.test.mjs`
- Modify: `apps/holo-orca-hud/package/main.lua`
- Modify: `apps/holo-orca-hud/package/app.info`

**Interfaces:**
- Canvas footer copy names horizontal enter/back and vertical scrolling.
- `APP.transcript_scroll` persists while Chat is visible; new data stays at the latest tail only when the user is already there.

- [x] Add failing static contract checks for 24/12 thresholds, `RIGHT: CHAT`, `LEFT:`, scroll window use, and no command endpoint.
- [x] Run `node --test tests/package-contract.test.mjs`; confirm the current forward/back page navigation fails the new contract.
- [x] Change IMU dispatch to use pitch for horizontal enter/back and roll for vertical scrolling; render seven-line scroll windows without overlap.
- [x] Set package version to `0.4.0` and run package/model contract tests until all pass.

### Task 4: Validate bridge, cube, and physical-control loop

**Files:**
- Modify: `scripts/verify-orca-hud-device.mjs`
- Modify: `tests/package-contract.test.mjs`

**Interfaces:**
- Device verifier confirms a transcript response can exceed the former eight-line preview and leaves v0.4.0 foregrounded.

- [x] Add a failing verifier assertion for retained-chat metadata or a multi-line transcript response.
- [x] Run the focused contract test and observe failure.
- [x] Update verifier to record only response status, response length, and line count—never chat text.
- [x] Run all local tests, Lua parse, `git diff --check`, `graphify update .`, restart the bridge if needed, deploy, and verify the cube using its hostname.
