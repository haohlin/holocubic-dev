import { createHash, timingSafeEqual } from 'node:crypto';
import { execFile } from 'node:child_process';
import { createServer } from 'node:http';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

const execFileAsync = promisify(execFile);
const MAX_BODY_BYTES = 2048;

function text(value, fallback = '') {
  const normalized = String(value ?? '').replace(/\s+/g, ' ').trim();
  return (normalized || fallback).slice(0, 48);
}

function state(value, fallback) {
  const normalized = text(value, fallback).toLowerCase();
  return /^[a-z-]{1,20}$/.test(normalized) ? normalized : fallback;
}

function sessionId(worktreeId) {
  return createHash('sha256').update(String(worktreeId)).digest('base64url').slice(0, 18);
}

function authorized(request, token) {
  const actual = Buffer.from(String(request.headers.authorization || ''));
  const expected = Buffer.from(`Bearer ${token}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function writeJson(response, statusCode, body) {
  response.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  response.end(JSON.stringify(body));
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let size = 0;
    let body = '';
    request.setEncoding('utf8');
    request.on('data', (chunk) => {
      size += Buffer.byteLength(chunk);
      if (size > MAX_BODY_BYTES) {
        reject(new Error('request body too large'));
        request.destroy();
        return;
      }
      body += chunk;
    });
    request.on('end', () => {
      try {
        resolve(JSON.parse(body || '{}'));
      } catch {
        reject(new Error('invalid JSON'));
      }
    });
    request.on('error', reject);
  });
}

function unwrap(envelope) {
  if (envelope && typeof envelope === 'object' && Object.hasOwn(envelope, 'ok')) {
    if (!envelope.ok) throw new Error('orca command failed');
    return envelope.result || {};
  }
  return envelope || {};
}

async function runOrcaCli(args) {
  const { stdout } = await execFileAsync('orca', args, {
    encoding: 'utf8',
    timeout: 10_000,
    maxBuffer: 1024 * 1024,
  });
  return unwrap(JSON.parse(stdout));
}

async function snapshot(runOrca) {
  const [orca, worktreeResult, terminalResult] = await Promise.all([
    runOrca(['status', '--json']),
    runOrca(['worktree', 'ps', '--limit', '40', '--json']),
    runOrca(['terminal', 'list', '--limit', '80', '--json']),
  ]);
  const worktrees = unwrap(worktreeResult).worktrees || [];
  const terminals = unwrap(terminalResult).terminals || [];
  const connectedByWorktree = new Map();
  for (const terminal of terminals) {
    if (terminal.connected && terminal.worktreeId && terminal.handle && !connectedByWorktree.has(terminal.worktreeId)) {
      connectedByWorktree.set(terminal.worktreeId, terminal.handle);
    }
  }

  const selections = new Map();
  const sessions = worktrees.map((worktree) => {
    const id = sessionId(worktree.worktreeId);
    const handle = connectedByWorktree.get(worktree.worktreeId) || null;
    selections.set(id, handle);
    return {
      id,
      label: text(worktree.displayName || worktree.repo, 'Untitled session'),
      status: state(worktree.status, 'unknown'),
      agentState: state(worktree.agents?.[0]?.state, 'idle'),
      active: Boolean(worktree.isActive),
      terminalCount: Math.max(0, Math.min(99, Number(worktree.liveTerminalCount) || 0)),
      canActivate: Boolean(handle),
    };
  });
  const status = unwrap(orca);
  return {
    body: {
      orca: {
        running: Boolean(status.app?.running),
        reachable: Boolean(status.runtime?.reachable),
        state: state(status.runtime?.state, 'unknown'),
      },
      sessions,
    },
    selections,
  };
}

export function createBridgeServer({ token, runOrca = runOrcaCli }) {
  if (typeof token !== 'string' || token.length < 16) {
    throw new Error('ORCA_HUD_TOKEN must be at least 16 characters');
  }

  return createServer(async (request, response) => {
    if (!authorized(request, token)) {
      writeJson(response, 401, { ok: false, error: 'unauthorized' });
      return;
    }
    try {
      if (request.method === 'GET' && request.url === '/v1/status') {
        const { body } = await snapshot(runOrca);
        writeJson(response, 200, body);
        return;
      }
      if (request.method === 'POST' && request.url === '/v1/select') {
        const payload = await readJson(request);
        if (typeof payload.id !== 'string' || !/^[A-Za-z0-9_-]{18}$/.test(payload.id)) {
          writeJson(response, 400, { ok: false, error: 'invalid session id' });
          return;
        }
        const { selections } = await snapshot(runOrca);
        const handle = selections.get(payload.id);
        if (handle === undefined) {
          writeJson(response, 404, { ok: false, error: 'unknown session' });
          return;
        }
        if (!handle) {
          writeJson(response, 409, { ok: false, error: 'session has no connected terminal' });
          return;
        }
        await runOrca(['terminal', 'switch', '--terminal', handle, '--json']);
        writeJson(response, 200, { ok: true, selected: payload.id });
        return;
      }
      writeJson(response, 404, { ok: false, error: 'not found' });
    } catch (error) {
      console.error('[orca-hud] bridge request failed:', error.message);
      writeJson(response, 502, { ok: false, error: 'orca unavailable' });
    }
  });
}

function start() {
  const token = process.env.ORCA_HUD_TOKEN;
  const host = process.env.ORCA_HUD_HOST || '127.0.0.1';
  const port = Number(process.env.ORCA_HUD_PORT || '47631');
  const server = createBridgeServer({ token });
  server.listen(port, host, () => console.log(`[orca-hud] bridge listening on http://${host}:${port}`));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) start();
