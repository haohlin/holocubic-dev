import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const packageDir = new URL('../apps/holo-flight-deck/package/', import.meta.url);
const read = (name) => readFileSync(new URL(name, packageDir), 'utf8');
const orcaPackageDir = new URL('../apps/holo-orca-hud/package/', import.meta.url);
const readOrca = (name) => readFileSync(new URL(name, orcaPackageDir), 'utf8');

test('Flight Deck declares its launcher entry and safe firmware bindings', () => {
  assert.equal(existsSync(new URL('app.info', packageDir)), true);
  assert.equal(existsSync(new URL('main.lua', packageDir)), true);
  assert.equal(existsSync(new URL('main.png', packageDir)), true);
  assert.match(read('app.info'), /^name = Holo Flight Deck$/m);
  assert.match(read('app.info'), /^entry = main.lua$/m);
  assert.match(read('app.info'), /^icon = main.png$/m);

  const source = read('main.lua');
  assert.match(source, /app_api\.on, "imu"/);
  assert.match(source, /app_api\.set_home_exit, false/);
  assert.match(source, /key_api\.on, function/);
  assert.match(source, /key_api\.off/);
  assert.match(source, /app_api\.on, "imu", nil/);
  assert.match(source, /tmr_api\.create/);
});

test('Holo Orca HUD declares its controller package', () => {
  assert.equal(existsSync(new URL('app.info', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('main.lua', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('hud_model.lua', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('main.png', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('connection.example.lua', orcaPackageDir)), true);
  assert.match(readOrca('app.info'), /^name = Holo Orca HUD$/m);
  assert.match(readOrca('app.info'), /^entry = main.lua$/m);
  assert.match(readOrca('app.info'), /^icon = main.png$/m);

  const source = readOrca('main.lua');
  assert.match(source, /http_api\.get/);
  assert.match(source, /http_api\.post/);
  assert.match(source, /app_api\.on, "imu"/);
  assert.match(source, /hud\.move_selection/);
  assert.match(source, /key_api\.HOME/);
  assert.match(source, /key_api\.LONG_START/);
});
