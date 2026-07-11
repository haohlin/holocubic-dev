import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const orcaPackageDir = new URL('../apps/holo-orca-hud/package/', import.meta.url);
const readOrca = (name) => readFileSync(new URL(name, orcaPackageDir), 'utf8');

test('Holo Context HUD declares its controller package', () => {
  assert.equal(existsSync(new URL('app.info', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('main.lua', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('hud_model.lua', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('main.png', orcaPackageDir)), true);
  assert.equal(existsSync(new URL('connection.example.lua', orcaPackageDir)), true);
  assert.match(readOrca('app.info'), /^name = Holo Context HUD$/m);
  assert.match(readOrca('app.info'), /^entry = main.lua$/m);
  assert.match(readOrca('app.info'), /^icon = main.png$/m);

  const source = readOrca('main.lua');
  assert.match(source, /http_api\.get/);
  assert.match(source, /http_api\.post/);
  assert.match(source, /http_api\.cubicserver\.get/);
  assert.match(source, /app_api\.on, "imu"/);
  assert.match(source, /hud\.move_selection/);
  assert.match(source, /hud\.move_page/);
  assert.match(source, /time_api\.getlocal/);
  assert.match(source, /sys_api\.version/);
  assert.match(source, /wifi_api\.sta\.getip/);
  assert.match(source, /key_api\.HOME/);
  assert.match(source, /key_api\.LONG_START/);
  assert.match(source, /CONTEXT/);
  assert.match(source, /ORCA NAV/);
});

test('Holo Flight Deck source has been removed', () => {
  assert.equal(existsSync(new URL('../apps/holo-flight-deck/package/main.lua', import.meta.url)), false);
});
