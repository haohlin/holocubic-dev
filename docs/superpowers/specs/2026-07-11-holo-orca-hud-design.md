# Holo Orca HUD Design

## Goal

Provide a holographic, tilt-controlled controller for the local Orca desktop:
it shows the current Orca runtime state and sessions, then activates a selected
session's connected terminal when the user short-presses the device button.

## Architecture

The display app cannot invoke the Mac's `orca` CLI. A small Node bridge runs on
the Mac's LAN interface and is the sole component that invokes it. The bridge
provides only two authenticated operations:

- `GET /v1/status` returns Orca availability and a sanitized session list.
- `POST /v1/select` accepts a session ID that was issued by `GET /v1/status`,
  resolves its connected terminal, and calls `orca terminal switch`.

The bridge never returns prompts, terminal previews, terminal output, absolute
paths, branches, raw worktree IDs, terminal handles, or command inputs. The
device only receives a short label, activity state, active state, terminal
count, and whether the session can be activated.

## Device Interaction

The app calibrates the IMU at startup. Physical left/right tilt moves one row
through the session list, with a latch so every deliberate tilt advances once.
Short HOME presses activate the selected session. Long HOME exits. It polls the
bridge every five seconds and refreshes immediately after activation.

The display uses a black HUD background, cyan selected row, and compact status
text. It retains no Orca data after exit.

## Failure Handling

If the bridge is unavailable, returns malformed JSON, rejects authentication,
or the selected session has no connected terminal, the HUD presents a concise
local error and keeps the most recent valid session list. A request-in-flight
guard prevents overlapping HTTP calls.

## Configuration and Safety

The bridge binds to the Mac LAN address on port `47631` and requires a random
bearer token. Deployment renders a device-only `connection.lua` from the local
bridge configuration; this file is ignored by Git. The bridge accepts no shell
input from the device and its only mutating command is `orca terminal switch`
with a terminal handle obtained from a fresh Orca metadata snapshot.
