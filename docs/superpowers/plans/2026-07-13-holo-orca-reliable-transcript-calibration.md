# Holo Orca Reliable Transcript and Calibration Plan

**Goal:** Correct the dark material level, establish the cube's physical vertical centre, and ensure each worktree's transcript comes from a connected terminal that actually retains chat history.

**Evidence:** At the resting pose, the cube reports `roll +4.646°`, `pitch −0.839°`; user observation identifies the positive roll as the device's 5° backward cant. Live Orca inspection found the HoloCubic ESP32 worktree had three connected terminals: the bridge selected the first empty terminal, while another contained 29 retained rows.

**Implementation:** Darken the base and every frost layer by 50% from v0.5.1 while retaining bright text and semantic status colors. Set the vertical middle to a fixed `+5°` roll, use `36°` engage and `18°` release bands, and map vertical movement from `raw_roll - 5`. The bridge ranks a worktree's connected terminals by latest output and falls back through candidates until it finds sanitized retained rows; it still returns only the opaque session and no raw terminal handle.

**Validation:** Regression tests simulate a newest empty terminal followed by a terminal with history. Live verification must prove the HoloCubic ESP32 session has a nonzero bridge transcript response, the cube can read the bounded response through its hostname, and the deployed HUD remains foregrounded without `runtime-error.txt`.
