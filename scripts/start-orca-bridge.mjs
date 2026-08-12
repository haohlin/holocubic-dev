import { randomBytes } from 'node:crypto';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { createConnection } from 'node:net';
import { networkInterfaces } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createBridgeServer } from '../companion/orca_bridge.mjs';
import { pickLanAddress, refreshBridgeConfig, resolveBridgeBindHost } from '../companion/orca_hud_config.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const configPath = resolve(root, '.local/orca-hud.json');
const bridgePath = resolve(root, 'companion/orca_bridge.mjs');

function validConfig(config) {
  return config && typeof config.host === 'string' && Number.isInteger(config.port)
    && typeof config.token === 'string' && config.token.length >= 16;
}

async function ensureConfig() {
  const host = pickLanAddress(networkInterfaces());
  if (!host) throw new Error('no private IPv4 LAN address found');
  try {
    const existing = JSON.parse(await readFile(configPath, 'utf8'));
    if (validConfig(existing)) {
      const refreshed = refreshBridgeConfig(existing, host);
      if (refreshed.host !== existing.host) {
        await writeFile(configPath, `${JSON.stringify(refreshed)}\n`, { mode: 0o600 });
      }
      return refreshed;
    }
  } catch {}
  const config = { host, port: 47631, token: randomBytes(24).toString('base64url') };
  await mkdir(dirname(configPath), { recursive: true, mode: 0o700 });
  await writeFile(configPath, `${JSON.stringify(config)}\n`, { mode: 0o600 });
  return config;
}

async function bridgeReady(host, port) {
  return new Promise((resolve) => {
    const socket = createConnection({ host, port });
    const finish = (ready) => {
      socket.destroy();
      resolve(ready);
    };
    socket.setTimeout(800);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
  });
}

async function waitForBridge(host, port) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (await bridgeReady(host, port)) return true;
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  return false;
}

async function main() {
  const config = await ensureConfig();
  const bridgeBindHost = resolveBridgeBindHost(config, process.env.ORCA_HUD_BIND_HOST);
  if (process.argv.includes('--serve')) {
    const server = createBridgeServer({ token: config.token });
    server.listen(config.port, bridgeBindHost, () => {
      console.log(`[orca-hud] bridge listening on http://${config.host}:${config.port}`);
    });
    return;
  }
  if (process.argv.includes('--check')) {
    if (!await bridgeReady(bridgeBindHost, config.port)) throw new Error('bridge is not responding');
    console.log(`[orca-hud] bridge ready at http://${config.host}:${config.port}`);
    return;
  }
  if (!await bridgeReady(bridgeBindHost, config.port)) {
    const child = spawn(process.execPath, [bridgePath], {
      detached: true,
      stdio: 'ignore',
      env: {
        ...process.env,
        ORCA_HUD_BIND_HOST: bridgeBindHost,
        ORCA_HUD_PORT: String(config.port),
        ORCA_HUD_TOKEN: config.token,
      },
    });
    child.unref();
    if (!await waitForBridge(bridgeBindHost, config.port)) throw new Error('bridge did not become ready');
  }
  console.log(`[orca-hud] bridge ready at http://${config.host}:${config.port}`);
}

main().catch((error) => {
  console.error(`[orca-hud] ${error.message}`);
  process.exitCode = 1;
});
