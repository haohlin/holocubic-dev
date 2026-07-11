import assert from 'node:assert/strict';
import test from 'node:test';

import { pickLanAddress, renderConnectionLua } from '../companion/orca_hud_config.mjs';

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
