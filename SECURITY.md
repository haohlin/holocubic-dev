# Security policy

## Supported threat model

Holo Orca HUD supports a trusted home LAN only. The Mac and cube are assumed
to be owner-controlled, and no hostile device is assumed to have LAN access.
The bridge and cube management endpoints must never be exposed through router
port forwarding, DMZ mode, UPnP mappings, public Wi-Fi, or an untrusted VLAN.

Under this model, the project accepts plaintext HTTP between the paired cube
and Mac. This is a deliberate usability tradeoff, not a claim that HTTP is
secure on hostile networks.

## Implemented controls

- Bridge binds to the discovered private LAN interface by default.
- `ORCA_HUD_BIND_HOST` provides an explicit operator override.
- Every bridge route requires a random bearer token.
- Token comparison is timing-safe.
- At most four authenticated bridge requests run concurrently; excess work
  receives HTTP `429` without starting another Orca snapshot.
- Session identifiers are opaque and resolved through fresh server-side state.
- Transcript output is read-only, sanitized, and bounded to eight short rows.
- Bridge exposes no terminal command-send endpoint.
- Local credentials and generated runtime files are excluded from Git and
  created with owner-only permissions where the host filesystem supports it.

## Operator requirements

- Use WPA2 or WPA3 with a strong unique password.
- Keep the cube and Mac off guest or untrusted networks.
- Confirm no router rule exposes TCP port `47631` or cube management APIs.
- Prefer disabling cube DevTools outside deployment and maintenance windows.
- Rotate the bridge token after suspected LAN or cube compromise.
- Do not publish `.local/`, `connection.lua`, logs, or captured transcripts.

## Accepted residual risks

- Plain HTTP can expose or replay the bearer token and transcript traffic if
  the trusted-LAN assumption becomes false.
- Cube DevTools can read the deployed `connection.lua` while its unauthenticated
  file API is reachable. A LAN peer could then reuse the token.
- Exact-interface binding reduces exposure but is not client authentication or
  a firewall. Operators may additionally restrict port `47631` to the cube IP.

These risks are not accepted for office, guest, public, shared, or hostile LANs.
Such environments require authenticated encrypted transport and authenticated
cube management.

## Reporting

Do not open a public issue containing tokens, transcripts, private addresses,
or device configuration. Report the vulnerability privately to the repository
owner with reproduction steps and affected version.

See [the initial security scan disposition](docs/security/2026-08-12-initial-security-scan.md).
