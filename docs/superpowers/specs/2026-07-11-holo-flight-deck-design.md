# Holo Flight Deck: design

## Purpose

Holo Flight Deck is the first current-firmware Holocubic app. It is a
transparent, tilt-controlled cockpit HUD that validates the real device input
surface before larger applications are built.

The app must be visually effective on the holographic display: full black is
the transparent field; cyan and white are primary illuminated elements; muted
blue-grey is reserved for low-priority guides. It must not need a network
connection, change firmware settings, or make any Orca calls.

## Screen and controls

The 320 x 240 screen contains the following elements:

- A small `FLIGHT DECK` label and mode indicator at the top.
- A centered, fixed flight reticle.
- A cyan artificial-horizon line. Device roll rotates the line; forward/back
  tilt moves it vertically. Roll/pitch values remain visible for calibration.
- A faint scan ring and sweep line, toggled by the HOME short-press action.
- A compact bottom input telemetry line showing the latest IMU/key event and
  the current scan state.

The UI has no opaque panels other than black. It uses a true-black root
background, with no backgrounds behind labels, so the physical optics retain
their transparent HUD effect.

## Tilt behavior

The firmware provides `app.on("imu")` roll and pitch angles. The app keeps the
callback light: it stores only the newest values. A 25 ms timer renders and
smooths them.

- The first valid IMU event establishes a neutral roll/pitch baseline.
- Delta angles use a 1.5-degree dead zone, are clamped to plus/minus 45
  degrees, and use exponential smoothing with a 0.28 target contribution per
  render tick.
- Pitch maps to a plus/minus 75-pixel horizon offset.
- Roll maps to a bounded plus/minus 35-degree horizon-line rotation.
- The app displays the filtered angles, neutral state, and callback age so a
  device test can distinguish bad calibration from absent IMU events.

## Button and key probing

The app calls `app.set_home_exit(false)` and subscribes with `key.on(fn)` to
record every key code and event type visibly. This is a probe, not an
assumption about the physical button.

If `key.HOME` is emitted:

- `SHORT` toggles the scan animation.
- `LONG_START` requests a clean app exit.
- Every event, including unrecognised codes, appears in the telemetry line.

No power-management API is invoked. If the physical button does not generate
a Lua key event, the app remains tilt-only and the test result is reported as
such.

## Structure

```text
apps/holo-flight-deck/
  package/
    app.info
    main.lua
    main.png
    info.html
  src/
    flight_math.lua
tests/
  test_flight_math.lua
docs/
  superpowers/specs/...
```

`flight_math.lua` is pure Lua and owns calibration, dead-zone, smoothing, and
horizon geometry. `main.lua` owns current-firmware bindings, LVGL rendering,
timer lifecycle, and cleanup. This keeps the hardware-specific app thin and
makes the control law testable on the Mac.

## Failure handling and cleanup

- Missing IMU/key/LVGL capability is shown on the HUD rather than causing a
  Lua error.
- The app always unregisters its timer, `key` listeners, and `app.on("imu")`
  callback before exit or reload.
- Rendering is fixed-rate and bounded; no network or file I/O runs in the IMU
  callback.

## Validation

1. Host tests first verify neutral calibration, dead-zone handling, clamping,
   smoothing, and horizon geometry.
2. The packaged app is inspected for the required manifest and clean syntax.
3. The package is deployed through the existing DevTools interface to
   `/sd/apps/holo-flight-deck/` and rescanned.
4. Device validation checks a stationary neutral state, each tilt axis,
   diagonal tilt, scan toggle, long-press exit, and the recorded button code.

## Follow-on work

Holo Context HUD reuses the visual primitives and data-provider boundary. A
future local Mac companion can expose a sanitized, read-only Orca status
snapshot (runtime readiness, worktree state, agent state, terminal counts).
Navigation is deliberately deferred; it will require an explicit confirmation
gesture and a separate approved design.
