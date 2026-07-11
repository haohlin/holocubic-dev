import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createConnection } from 'node:net';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { renderConnectionLua } from '../companion/orca_hud_config.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const packageDir = resolve(root, 'apps/holo-orca-hud/package');
const configPath = resolve(root, '.local/orca-hud.json');
const deviceHost = process.env.HOLOCUBIC_HOST || 'clocteck-cubic.local';

async function readConfig() {
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  if (!config || typeof config.host !== 'string' || !Number.isInteger(config.port)
      || typeof config.token !== 'string' || config.token.length < 16) {
    throw new Error('invalid local bridge config; run start-orca-bridge.mjs first');
  }
  return config;
}

async function requireBridge(config) {
  const reachable = await new Promise((resolve) => {
    const socket = createConnection({ host: config.host, port: config.port });
    const finish = (ready) => {
      socket.destroy();
      resolve(ready);
    };
    socket.setTimeout(1500);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
  });
  if (!reachable) throw new Error('local Orca bridge port is not reachable');
}

async function upload(name, sourcePath) {
  const payload = await readFile(sourcePath);
  const url = new URL(`http://${deviceHost}/devtools/api/upload`);
  url.searchParams.set('path', `/sd/apps/holo-orca-hud/${name}`);
  url.searchParams.set('offset', '0');
  url.searchParams.set('total', String(payload.length));
  const response = await fetch(url, { method: 'PUT', body: payload, signal: AbortSignal.timeout(15_000) });
  const body = await response.json();
  if (!response.ok || !body.ok || !body.done) throw new Error(`upload failed for ${name}`);
}

async function ensureAppDirectory() {
  const statUrl = new URL(`http://${deviceHost}/devtools/api/stat`);
  statUrl.searchParams.set('path', '/sd/apps/holo-orca-hud');
  const statResponse = await fetch(statUrl, { signal: AbortSignal.timeout(15_000) });
  if (statResponse.ok) {
    const stat = await statResponse.json();
    if (stat.ok && stat.is_dir) return;
    throw new Error('device app path exists but is not a directory');
  }
  if (statResponse.status !== 404) throw new Error('could not inspect device app directory');
  const url = new URL(`http://${deviceHost}/devtools/api/mkdir`);
  url.searchParams.set('path', '/sd/apps/holo-orca-hud');
  const response = await fetch(url, { method: 'POST', signal: AbortSignal.timeout(15_000) });
  const body = await response.json();
  if (!response.ok || !body.ok) throw new Error('could not create device app directory');
}

async function rescan() {
  const response = await fetch(`http://${deviceHost}/devtools/api/code/run`, {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: 'if app and app.rescan then app.rescan() end\nif app and app.exit then app.exit() end\n',
    signal: AbortSignal.timeout(15_000),
  });
  const body = await response.json();
  if (!response.ok || !body.ok) throw new Error('device app rescan failed');
}

async function main() {
  const config = await readConfig();
  await requireBridge(config);
  const tempDir = await mkdtemp(join(tmpdir(), 'holo-orca-hud-'));
  const connectionPath = join(tempDir, 'connection.lua');
  try {
    await writeFile(connectionPath, renderConnectionLua(config), { mode: 0o600 });
    await ensureAppDirectory();
    for (const name of ['app.info', 'hud_model.lua', 'main.lua', 'main.png']) {
      await upload(name, join(packageDir, name));
    }
    await upload('connection.lua', connectionPath);
    await rescan();
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
  console.log(`[orca-hud] deployed to ${deviceHost}`);
}

main().catch((error) => {
  console.error(`[orca-hud] ${error.message}`);
  process.exitCode = 1;
});
