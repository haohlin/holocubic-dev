# Initial public-release security scan

Date: 2026-08-12

Scope: root Holo Orca HUD publication candidate. Ignored local secrets and
upstream reference clones were checked for publication boundaries but are not
part of the public root repository.

The standard Codex Security scan reported three medium-severity findings.

## Disposition

### Authenticated request concurrency

Status: fixed for the initial public release.

The bridge now admits at most four authenticated requests. Additional requests
receive HTTP `429` before any additional Orca CLI work starts.

### All-interface bridge binding

Status: hardened for the initial public release.

The managed bridge now binds to its advertised private LAN address by default.
An explicit `ORCA_HUD_BIND_HOST` override remains available.

### Plaintext bridge transport

Status: accepted residual risk under the documented threat model.

The cube firmware supports the required local HTTP client workflow, while a
full TLS identity and certificate-provisioning design would add pairing,
renewal, recovery, memory, and troubleshooting costs. Plaintext transport is
accepted only for an owner-controlled trusted home LAN with no untrusted peers
and no internet exposure.

### Bridge token stored on cube SD storage

Status: accepted residual risk under the documented threat model.

The cube must retain connection configuration across restarts. Its DevTools
file API can read that storage while DevTools is reachable. Operators should
disable DevTools outside maintenance windows and rotate the token after any
suspected LAN or cube compromise.

## Publication gate

- No real credentials may appear in the Git publication set.
- `.local/`, generated `connection.lua`, runtime logs, and code-graph outputs
  must remain ignored.
- Automated Node tests must pass.
- Live cube deployment and verification must be reported separately when the
  physical device is unavailable.
