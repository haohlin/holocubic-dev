import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const packageDir = new URL('../apps/holo-flight-deck/package/', import.meta.url);
const read = (name) => readFileSync(new URL(name, packageDir), 'utf8');

test('Flight Deck declares its launcher entry and safe firmware bindings', () => {
  assert.equal(existsSync(new URL('app.info', packageDir)), true);
  assert.equal(existsSync(new URL('main.lua', packageDir)), true);
  assert.match(read('app.info'), /^name = Holo Flight Deck$/m);
  assert.match(read('app.info'), /^entry = main.lua$/m);

  const source = read('main.lua');
  assert.match(source, /app_api\.on, "imu"/);
  assert.match(source, /app_api\.set_home_exit, false/);
  assert.match(source, /key_api\.on, function/);
  assert.match(source, /key_api\.off/);
  assert.match(source, /app_api\.on, "imu", nil/);
  assert.match(source, /tmr_api\.create/);
});
