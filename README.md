# Holo Orca HUD

Holo Orca HUD is a private-LAN physical companion for Orca. A HoloCubic device
shows sanitized session state and a bounded recent terminal transcript, then
lets the user focus a connected Orca terminal through cube controls.

## Components

- `apps/holo-orca-hud/`: Lua application deployed to HoloCubic.
- `companion/orca_bridge.mjs`: token-protected Mac bridge to the `orca` CLI.
- `scripts/`: local bridge startup, launchd installation, deployment, preview,
  and device verification.
- `tests/`: Node and Lua contract tests.

## Intended environment

This project is designed only for a trusted home LAN:

- Mac and cube are on the same private network.
- No hostile or untrusted devices can join that network.
- Neither bridge port `47631` nor cube management APIs are forwarded to the
  internet.
- Guest, office, dormitory, hotel, and public Wi-Fi are unsupported.

The bridge binds to its discovered private LAN address by default, not every
network interface. Set `ORCA_HUD_BIND_HOST` only when an explicit override is
needed.

## Local setup

Start the bridge and create its ignored local token configuration:

```sh
node scripts/start-orca-bridge.mjs
```

Install the supervised macOS service when desired:

```sh
node scripts/install-orca-bridge-service.mjs
```

Deploy after the cube is online:

```sh
HOLOCUBIC_HOST=your-cube.local node scripts/deploy-orca-hud.mjs
HOLOCUBIC_HOST=your-cube.local node scripts/verify-orca-hud-device.mjs
```

Local secrets live under `.local/` and must never be committed. Deployment
generates `connection.lua` temporarily and uploads it to the cube.

## Validation

```sh
node --test tests/*.test.mjs
lua tests/orca_hud_model.test.lua
```

Cube deployment and live verification require the physical device. See
[SECURITY.md](SECURITY.md) before running outside the intended environment.
