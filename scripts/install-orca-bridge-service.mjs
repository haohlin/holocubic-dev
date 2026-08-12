import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execFileAsync = promisify(execFile);
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const label = 'com.holocubic.orca-hud-bridge';
const userId = process.getuid();
const launchAgents = resolve(homedir(), 'Library', 'LaunchAgents');
const plistPath = resolve(launchAgents, `${label}.plist`);
const bridgePath = resolve(root, 'companion', 'orca_bridge.mjs');
const launcherPath = resolve(root, 'scripts', 'start-orca-bridge.mjs');
const stdoutPath = resolve(root, '.local', 'orca-hud-bridge.out.log');
const stderrPath = resolve(root, '.local', 'orca-hud-bridge.err.log');

function xml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function renderPlist() {
  const args = ['/opt/homebrew/bin/node', launcherPath, '--serve'];
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    `  <key>Label</key><string>${xml(label)}</string>`,
    '  <key>ProgramArguments</key>',
    '  <array>',
    ...args.map((arg) => `    <string>${xml(arg)}</string>`),
    '  </array>',
    `  <key>WorkingDirectory</key><string>${xml(root)}</string>`,
    '  <key>RunAtLoad</key><true/>',
    '  <key>KeepAlive</key><true/>',
    '  <key>ThrottleInterval</key><integer>5</integer>',
    '  <key>EnvironmentVariables</key>',
    '  <dict>',
    '    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>',
    '  </dict>',
    `  <key>StandardOutPath</key><string>${xml(stdoutPath)}</string>`,
    `  <key>StandardErrorPath</key><string>${xml(stderrPath)}</string>`,
    '</dict>',
    '</plist>',
    '',
  ].join('\n');
}

async function command(file, args, allowFailure = false) {
  try {
    return await execFileAsync(file, args, { encoding: 'utf8' });
  } catch (error) {
    if (allowFailure) return { stdout: '', stderr: String(error.stderr || '') };
    throw error;
  }
}

async function stopDetachedBridge() {
  const { stdout } = await command('/usr/sbin/lsof', ['-nP', '-t', '-iTCP:47631', '-sTCP:LISTEN'], true);
  const pids = stdout.split(/\s+/).map(Number).filter(Number.isInteger);
  for (const pid of pids) {
    const result = await command('/bin/ps', ['-p', String(pid), '-o', 'command='], true);
    if (result.stdout.includes(bridgePath)) process.kill(pid, 'SIGTERM');
  }
}

async function waitForBridge() {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const result = await command('/usr/sbin/lsof', ['-nP', '-iTCP:47631', '-sTCP:LISTEN'], true);
    if (result.stdout.includes('LISTEN')) return true;
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  return false;
}

async function main() {
  await mkdir(launchAgents, { recursive: true });
  await mkdir(resolve(root, '.local'), { recursive: true, mode: 0o700 });
  await writeFile(plistPath, renderPlist(), { mode: 0o644 });
  await command('/bin/launchctl', ['bootout', `gui/${userId}`, plistPath], true);
  await stopDetachedBridge();
  await command('/bin/launchctl', ['bootstrap', `gui/${userId}`, plistPath]);
  await command('/bin/launchctl', ['kickstart', '-k', `gui/${userId}/${label}`]);
  if (!await waitForBridge()) throw new Error('launchd bridge did not become ready');
  console.log(`[orca-hud] supervised bridge ready on port 47631 (${label})`);
}

main().catch((error) => {
  console.error(`[orca-hud] ${error.message}`);
  process.exitCode = 1;
});
