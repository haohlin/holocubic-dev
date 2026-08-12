import assert from 'node:assert/strict';
import test from 'node:test';

import * as bridgeConfig from '../companion/orca_hud_config.mjs';

const { pickLanAddress, refreshBridgeConfig, renderConnectionLua } = bridgeConfig;

test('prefers the device LAN address and renders a Lua-safe connection file', () => {
  const address = pickLanAddress({
    bridge0: [{ family: 'IPv4', address: '10.0.0.1', internal: false }],
    en0: [{ family: 'IPv4', address: '192.168.0.42', internal: false }],
    lo0: [{ family: 'IPv4', address: '127.0.0.1', internal: true }],
  });
  assert.equal(address, '192.168.0.42');

  assert.equal(renderConnectionLua({ host: address, port: 47631, token: 'a"b\\c' }), [
    'return {',
    '  base_url = "http://192.168.0.42:47631",',
    '  token = "a\\"b\\\\c",',
    '}',
    '',
  ].join('\n'));
});

test('refreshes a stale advertised bridge address without rotating the pairing token', () => {
  const refreshed = refreshBridgeConfig({
    host: '192.168.0.252',
    port: 47631,
    token: 'stable-pairing-token',
  }, '192.168.10.10');

  assert.deepEqual(refreshed, {
    host: '192.168.10.10',
    port: 47631,
    token: 'stable-pairing-token',
  });
});

test('binds to the advertised private interface by default while preserving an explicit override', () => {
  const config = { host: '192.168.10.10', port: 47631, token: 'stable-pairing-token' };

  assert.equal(bridgeConfig.resolveBridgeBindHost?.(config), '192.168.10.10');
  assert.equal(bridgeConfig.resolveBridgeBindHost?.(config, '127.0.0.1'), '127.0.0.1');
});
