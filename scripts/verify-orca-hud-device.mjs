import { setTimeout as delay } from 'node:timers/promises';
import { setDefaultResultOrder } from 'node:dns';

setDefaultResultOrder('ipv4first');

const deviceHost = process.env.HOLOCUBIC_HOST;
const appId = 'holo-orca-hud';
const appRoot = `/sd/apps/${appId}`;
const runtimeErrorPath = `${appRoot}/runtime-error.txt`;
const lifecyclePath = `${appRoot}/lifecycle.txt`;
const bridgeCheckPath = '/sd/apps/devrun/orca-hud-bridge-check.txt';

function requireDeviceHost() {
  if (typeof deviceHost !== 'string' || !deviceHost.trim()) {
    throw new Error('HOLOCUBIC_HOST is required; use your Cube mDNS hostname or LAN address');
  }
  return deviceHost;
}

function deviceUrl(path) {
  return `http://${deviceHost}${path}`;
}

async function request(path, options = {}) {
  const response = await fetch(deviceUrl(path), {
    ...options,
    signal: AbortSignal.timeout(options.timeout ?? 15_000),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${options.method ?? 'GET'} ${path} failed: ${response.status} ${text}`);
  return text;
}

async function requestJson(path, options = {}) {
  const text = await request(path, options);
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`invalid JSON from ${path}: ${text}`);
  }
}

async function waitForState(predicate, description, timeoutMs = 12_000) {
  const deadline = Date.now() + timeoutMs;
  let lastState = null;
  while (Date.now() < deadline) {
    lastState = await requestJson('/api/system/state');
    if (predicate(lastState)) return lastState;
    await delay(350);
  }
  throw new Error(`${description}; last app was ${lastState?.current_app?.id ?? 'none'}`);
}

async function stat(path) {
  const query = new URLSearchParams({ path });
  const response = await fetch(deviceUrl(`/devtools/api/stat?${query}`), { signal: AbortSignal.timeout(15_000) });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : {} };
}

async function assertFile(path) {
  const result = await stat(path);
  if (result.status !== 200 || !result.body.ok || result.body.is_dir) {
    throw new Error(`expected deployed file: ${path}`);
  }
}

async function assertNoRuntimeError() {
  const result = await stat(runtimeErrorPath);
  if (result.status === 404) return;
  if (result.status === 200) throw new Error(`HUD runtime error file exists: ${runtimeErrorPath}`);
  throw new Error(`could not inspect HUD runtime error file: ${result.status}`);
}

async function assertLifecycleStarted() {
  const query = new URLSearchParams({ path: lifecyclePath, offset: '0', size: '256' });
  const value = (await request(`/devtools/api/read?${query}`)).trim();
  if (value !== 'started') throw new Error(`HUD lifecycle is not stable: ${value || 'missing'}`);
}

async function removeFile(path) {
  const query = new URLSearchParams({ path });
  const response = await fetch(deviceUrl(`/devtools/api/remove?${query}`), {
    method: 'DELETE',
    signal: AbortSignal.timeout(15_000),
  });
  if (response.status === 404) return;
  const body = await response.json();
  if (!response.ok || !body.ok) throw new Error(`could not remove temporary device file: ${path}`);
}

async function runDevCode(source) {
  const body = await requestJson('/devtools/api/code/run', {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: source,
  });
  if (!body.ok || !body.launched) throw new Error('device DevRun did not launch');
}

async function rescanAndExit() {
  await runDevCode([
    'if app and app.rescan then app.rescan() end',
    'if app and app.exit then app.exit() end',
    '',
  ].join('\n'));
  await waitForState((state) => !state.current_app, 'DevRun did not exit after rescan');
}

async function exitToHome(description) {
  const response = await fetch(deviceUrl('/api/system/exit'), {
    method: 'POST',
    signal: AbortSignal.timeout(15_000),
  });
  const text = await response.text();
  let body = {};
  try { body = text ? JSON.parse(text) : {}; } catch {}
  if (!response.ok && body.error !== 'no running app') {
    throw new Error(`POST /api/system/exit failed: ${response.status} ${text}`);
  }
  await waitForState((state) => !state.current_app, description);
}

async function launchHud() {
  await removeFile(lifecyclePath);
  const body = await requestJson(`/api/system/launch?id=${appId}`, { method: 'POST' });
  if (!body.ok) throw new Error('HUD launch was rejected');
  await waitForState((state) => state.current_app?.id === appId, 'HUD did not enter the foreground');
  await delay(20_000);
  await waitForState((state) => state.current_app?.id === appId, 'HUD did not remain responsive through the canvas soak');
  await assertNoRuntimeError();
  await assertLifecycleStarted();
}

async function bridgeProbe() {
  const source = [
    `local c=dofile("${appRoot}/connection.lua")`,
    'local headers={ ["Authorization"]="Bearer " .. c.token }',
    'local code, body=http.get(c.base_url .. "/v1/status", {headers=headers, timeout=5000})',
    'local transcript_code, transcript_body, retained_lines = 0, nil, 0',
    'local select_code, select_body = 0, nil',
    'local JSON=(sjson and sjson.decode and sjson) or (json and json.decode and json)',
    'if code == 200 and type(body) == "string" and JSON then',
    '  local ok, doc=pcall(JSON.decode, body)',
    '  local session_id=nil',
    '  if ok and type(doc) == "table" and type(doc.sessions) == "table" then',
    '    for _, session in ipairs(doc.sessions) do',
    '      if session.focused and session.canActivate and type(session.id) == "string" then session_id=session.id; break end',
    '    end',
    '  end',
    '  if session_id then',
    '    transcript_code, transcript_body=http.get(c.base_url .. "/v1/transcript?id=" .. session_id, {headers=headers, timeout=5000})',
    '    if transcript_code == 200 and type(transcript_body) == "string" then',
    '      local transcript_ok, transcript_doc=pcall(JSON.decode, transcript_body)',
    '      local history=transcript_ok and transcript_doc and transcript_doc.transcript and transcript_doc.transcript.history',
    '      retained_lines=type(history) == "table" and tonumber(history.retainedLines) or 0',
    '    end',
    '    local payload=JSON.encode and JSON.encode({id=session_id})',
    '    if payload then select_code, select_body=http.post(c.base_url .. "/v1/select", {headers=headers, timeout=5000}, payload) end',
    '  end',
    'end',
    `file.putcontents("${bridgeCheckPath}", tostring(code) .. " " .. tostring(body and #body or 0) .. " " .. tostring(transcript_code) .. " " .. tostring(transcript_body and #transcript_body or 0) .. " " .. tostring(retained_lines) .. " " .. tostring(select_code) .. " " .. tostring(select_body and #select_body or 0))`,
    '',
  ].join('\n');
  await runDevCode(source);
  await delay(1_000);
  const query = new URLSearchParams({ path: bridgeCheckPath, offset: '0', size: '128' });
  const result = await request(`/devtools/api/read?${query}`);
  if (!/^200\s+\d+\s+200\s+\d+\s+[1-9]\d*\s+200\s+\d+/.test(result)) throw new Error(`cube-to-Orca bridge-check failed: ${result}`);
}

async function main() {
  requireDeviceHost();
  await requestJson('/api/system/state');
  for (const name of [
    'main.lua',
    'hud_model.lua',
    'assets/orca-logo.png',
    'assets/monitor.png',
    'assets/terminal.png',
    'assets/cloud-sun.png',
    'assets/chevron-right.png',
  ]) {
    await assertFile(`${appRoot}/${name}`);
  }

  await exitToHome('previous foreground app did not exit');
  await launchHud();

  await exitToHome('HUD did not exit through the system control path');
  await bridgeProbe();
  await removeFile(bridgeCheckPath);
  await rescanAndExit();
  await launchHud();

  console.log(`[orca-hud] device verification passed on ${deviceHost}`);
}

main().catch(async (error) => {
  try {
    await removeFile(bridgeCheckPath);
    await rescanAndExit();
    await launchHud();
  } catch {}
  console.error(`[orca-hud] device verification failed: ${error.message}`);
  process.exitCode = 1;
});
