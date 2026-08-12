import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const startSource = readFileSync(new URL('../scripts/start-orca-bridge.mjs', import.meta.url), 'utf8');
const deploySource = readFileSync(new URL('../scripts/deploy-orca-hud.mjs', import.meta.url), 'utf8');

test('Orca bridge binds to its advertised LAN interface unless explicitly overridden', () => {
  assert.match(startSource, /ORCA_HUD_BIND_HOST/, 'the bridge has a separate bind address');
  assert.match(startSource, /refreshBridgeConfig/, 'the bridge refreshes a stale advertised LAN address');
  assert.match(startSource, /resolveBridgeBindHost/, 'the listener resolves the exact configured interface');
  assert.doesNotMatch(startSource, /'0\.0\.0\.0'/, 'the default listener does not expose every interface');
  assert.match(startSource, /bridgeReady\(bridgeBindHost, config\.port\)/,
    'local readiness checks the actual listener interface, including an explicit override');
  assert.match(deploySource, /host: config\.host/, 'deployment checks the exact listener interface');
});
