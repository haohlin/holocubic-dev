# Holo Orca Frosted Glass and Five-Page Transcript Plan

**Goal:** Restyle the retained Holo Context HUD as a light, rounded, matte-glass interface and make transcript loading reliable within the cube's memory and CPU budget.

**Architecture:** Preserve the proven single 320×240 retained canvas. Use the current firmware's canvas rectangle descriptor (`radius`, border, and opacity) plus a few translucent inset bands to suggest frosted vertical depth; do not create dynamic LVGL widgets or add image effects. The paired bridge reads only the newest 40 terminal rows, sanitizes and returns the newest 35 lines—five seven-line cube pages. The app retains visible content during refresh, reports an empty/disconnected/error state explicitly, and abandons an unanswered transcript request after seven seconds.

## Required behavior

- Background is a light smoked-aluminum gray; panels are cool-gray, transparent-looking, rounded, and subtly vertically graduated.
- Transcript tail is capped to 35 sanitized lines, newest first on entry, with up/down tilt scrolling older/newer content.
- Physical `left/right` and `up/down` are inverted at the IMU mapping boundary to match the user's observed device orientation. Logical right-enter/left-back and vertical scrolling semantics stay unchanged.
- Loading never remains indefinite: a failed, disconnected, empty, or timed-out read has a visible terminal state.
- All cube calls remain hostname-only through an operator-supplied `HOLOCUBIC_HOST`; no command, speech, or raw-terminal-handle capability is added.

## Validation

1. Bridge tests prove a 40-row fixture returns 35 sanitized newest rows and calls the CLI with limit 40.
2. Static/app-model tests prove rounded native canvas descriptors, five-page client cap, light palette, and both IMU inversions.
3. Deploy to the live cube, verify bridge response size/count, lifecycle/runtime fault state, launch and exit/relaunch loop through the hostname, then leave the HUD foregrounded.
