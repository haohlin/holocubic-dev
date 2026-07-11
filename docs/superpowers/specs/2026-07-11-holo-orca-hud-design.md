# Holo Context HUD Design

## Purpose

Holo Context HUD is the daily-glance display for the HoloCubic: local time,
configured location, current weather, Wi-Fi/firmware health, and Orca activity.
It also provides a deliberate, visible way to focus an Orca session on the Mac.

## Visual System

The 320×240 screen uses true black (`#000000`) as the transparent optical
background. Cyan (`#8FE9FF`) marks the active mode and selected session, white
is primary live information, muted blue-grey (`#36515A`) is structure and
instructions, and amber (`#FFC857`) marks unavailable services. The layout is
an open HUD with two thin rails; it deliberately avoids card surfaces and
decorative panels that would look opaque on the display.

## Context Overview

Context is the startup screen. It presents, in order:

1. Local time and configured location.
2. Native weather condition and temperature.
3. Wi-Fi link and firmware version.
4. Orca reachability and working-session count.
5. The session most recently focused from the HUD.

Short press refreshes context. Forward tilt opens Orca Navigator.

## Orca Navigator

Navigator lists four sessions at a time. Physical left/right tilt moves one
selected row after returning through neutral. Each row identifies its current
state and whether it has a connected terminal. Short press sends `orca terminal
switch` for the selected connected terminal, then returns to Context with a
four-and-a-half-second `FOCUS SENT: <session>` confirmation and a persistent
focused-session indicator.

The display never shows prompts, paths, terminal output, raw handles, or shell
commands. “Focus” is intentional wording: it changes the active terminal tab
in the Mac Orca UI; it does not turn the cube into a remote terminal.

## Sources and Failure Behavior

Location and timezone use `/sd/apps/settings.json`; the existing device Weather
service supplies current conditions. Orca state and session metadata arrive via
the LAN bridge. If either service is unavailable, the HUD retains valid prior
data and shows a concise amber status rather than replacing the display with an
error screen.

## Validation Constraint

The current firmware/DevTools interface has no display screenshot or simulator
surface. UI validation is therefore source-level layout review plus on-device
launch and control smoke testing; it is not a claim of browser screenshot
fidelity verification.
