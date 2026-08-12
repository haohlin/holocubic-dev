import { createHash, timingSafeEqual } from 'node:crypto';
import { execFile } from 'node:child_process';
import { createServer } from 'node:http';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';

const execFileAsync = promisify(execFile);
const MAX_BODY_BYTES = 2048;
const TRANSCRIPT_READ_LIMIT = 28;
const TRANSCRIPT_DISPLAY_LINES = 8;
const TRANSCRIPT_LINE_WIDTH = 42;

function text(value, fallback = '') {
  const normalized = String(value ?? '').replace(/\s+/g, ' ').trim();
  return (normalized || fallback).slice(0, 48);
}

function state(value, fallback) {
  const normalized = text(value, fallback).toLowerCase();
  return /^[a-z-]{1,20}$/.test(normalized) ? normalized : fallback;
}

function applyBackspaces(value) {
  let result = '';
  for (const char of value) {
    if (char === '\b') result = result.slice(0, -1);
    else result += char;
  }
  return result;
}

function transcriptRows(value) {
  const source = String(value ?? '')
    .replace(/\u001B\[[0-?]*[ -/]*[@-~]/g, '')
    .replace(/\r\n/g, '\n')
    .replace(/\t/g, '  ')
    .replace(/[\u0000-\u0007\u000B-\u001F\u007F]/g, '');
  return source.split('\n').map((row) => {
    const carriageParts = row.split('\r');
    let latest = carriageParts.at(-1) || '';
    if (!latest) latest = [...carriageParts].reverse().find(Boolean) || '';
    const clean = applyBackspaces(latest).replace(/ +$/g, '');
    if (clean.length <= TRANSCRIPT_LINE_WIDTH) return clean;
    return `... ${clean.slice(-(TRANSCRIPT_LINE_WIDTH - 4)).trimStart()}`;
  });
}

function transcriptLines(result) {
  const value = unwrap(result);
  const terminal = value.terminal && typeof value.terminal === 'object' ? value.terminal : value;
  const rows = Array.isArray(terminal.tail) ? terminal.tail
    : Array.isArray(terminal.rows) ? terminal.rows
      : Array.isArray(terminal.lines) ? terminal.lines
        : Array.isArray(terminal.entries) ? terminal.entries
          : Array.isArray(terminal.output) ? terminal.output
            : typeof terminal.output === 'string' ? terminal.output.split(/\r?\n/)
              : typeof terminal.text === 'string' ? terminal.text.split(/\r?\n/)
              : [];
  return rows
    .flatMap((row) => transcriptRows(typeof row === 'string' ? row : row?.text ?? row?.content ?? row?.line))
    .filter((row) => row.trim())
    .slice(-TRANSCRIPT_DISPLAY_LINES);
}

function transcriptHistory(result, lines) {
  const value = unwrap(result);
  const terminal = value.terminal && typeof value.terminal === 'object' ? value.terminal : value;
  return {
    retainedLines: lines.length,
    truncated: Boolean(terminal.truncated),
    limited: Boolean(terminal.limited),
  };
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

async function snapshot(runOrca, focusedSessionId = null) {
  const [orca, worktreeResult, terminalResult] = await Promise.all([
    runOrca(['status', '--json']),
    runOrca(['worktree', 'ps', '--limit', '40', '--json']),
    runOrca(['terminal', 'list', '--limit', '80', '--json']),
  ]);
  const worktrees = unwrap(worktreeResult).worktrees || [];
  const terminals = unwrap(terminalResult).terminals || [];
  const connectedByWorktree = new Map();
  for (const terminal of terminals) {
    if (terminal.connected && terminal.worktreeId && terminal.handle) {
      const candidates = connectedByWorktree.get(terminal.worktreeId) || [];
      candidates.push({
        handle: terminal.handle,
        lastOutputAt: Math.max(0, Number(terminal.lastOutputAt) || 0),
      });
      connectedByWorktree.set(terminal.worktreeId, candidates);
    }
  }
  for (const candidates of connectedByWorktree.values()) {
    candidates.sort((left, right) => right.lastOutputAt - left.lastOutputAt);
  }

  const selections = new Map();
  const sessionsById = new Map();
  const sessions = worktrees.map((worktree) => {
    const id = sessionId(worktree.worktreeId);
    const terminalCandidates = connectedByWorktree.get(worktree.worktreeId) || [];
    selections.set(id, terminalCandidates);
    const session = {
      id,
      label: text(worktree.displayName || worktree.repo, 'Untitled session'),
      status: state(worktree.status, 'unknown'),
      agentState: state(worktree.agents?.[0]?.state, 'idle'),
      active: Boolean(worktree.isActive),
      focused: Boolean(worktree.isActive) || id === focusedSessionId,
      terminalCount: Math.max(0, Math.min(99, Number(worktree.liveTerminalCount) || 0)),
      canActivate: terminalCandidates.length > 0,
    };
    sessionsById.set(id, session);
    return session;
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
    sessionsById,
  };
}

export function createBridgeServer({ token, runOrca = runOrcaCli, maxConcurrentRequests = 4 }) {
  if (typeof token !== 'string' || token.length < 16) {
    throw new Error('ORCA_HUD_TOKEN must be at least 16 characters');
  }
  if (!Number.isInteger(maxConcurrentRequests) || maxConcurrentRequests < 1) {
    throw new Error('maxConcurrentRequests must be a positive integer');
  }

  let focusedSessionId = null;
  let activeRequests = 0;
  return createServer(async (request, response) => {
    if (!authorized(request, token)) {
      writeJson(response, 401, { ok: false, error: 'unauthorized' });
      return;
    }
    if (activeRequests >= maxConcurrentRequests) {
      writeJson(response, 429, { ok: false, error: 'bridge busy' });
      return;
    }
    activeRequests += 1;
    try {
      if (request.method === 'GET' && request.url === '/v1/status') {
        const { body } = await snapshot(runOrca, focusedSessionId);
        writeJson(response, 200, body);
        return;
      }
      if (request.method === 'GET' && new URL(request.url || '/', 'http://orca-hud.local').pathname === '/v1/transcript') {
        const url = new URL(request.url || '/', 'http://orca-hud.local');
        const id = url.searchParams.get('id');
        if (typeof id !== 'string' || !/^[A-Za-z0-9_-]{18}$/.test(id)) {
          writeJson(response, 400, { ok: false, error: 'invalid session id' });
          return;
        }
        const { selections, sessionsById } = await snapshot(runOrca, focusedSessionId);
        const candidates = selections.get(id);
        const session = sessionsById.get(id);
        if (!session || candidates === undefined) {
          writeJson(response, 404, { ok: false, error: 'unknown session' });
          return;
        }
        if (!candidates.length) {
          writeJson(response, 409, { ok: false, error: 'session has no connected terminal' });
          return;
        }
        let lastOutput = null;
        let lastError = null;
        for (const candidate of candidates) {
          try {
            const output = await runOrca([
              'terminal', 'read', '--terminal', candidate.handle, '--limit', String(TRANSCRIPT_READ_LIMIT), '--json',
            ]);
            const lines = transcriptLines(output);
            lastOutput = output;
            if (lines.length) {
              writeJson(response, 200, { transcript: { session, lines, history: transcriptHistory(output, lines) } });
              return;
            }
          } catch (error) {
            lastError = error;
          }
        }
        if (!lastOutput && lastError) throw lastError;
        const lines = [];
        writeJson(response, 200, {
          transcript: { session, lines, history: lastOutput ? transcriptHistory(lastOutput, lines) : { retainedLines: 0, truncated: false, limited: false } },
        });
        return;
      }
      if (request.method === 'POST' && request.url === '/v1/select') {
        const payload = await readJson(request);
        if (typeof payload.id !== 'string' || !/^[A-Za-z0-9_-]{18}$/.test(payload.id)) {
          writeJson(response, 400, { ok: false, error: 'invalid session id' });
          return;
        }
        const { selections } = await snapshot(runOrca, focusedSessionId);
        const candidates = selections.get(payload.id);
        if (candidates === undefined) {
          writeJson(response, 404, { ok: false, error: 'unknown session' });
          return;
        }
        if (!candidates.length) {
          writeJson(response, 409, { ok: false, error: 'session has no connected terminal' });
          return;
        }
        await runOrca(['terminal', 'switch', '--terminal', candidates[0].handle, '--json']);
        focusedSessionId = payload.id;
        writeJson(response, 200, { ok: true, selected: payload.id });
        return;
      }
      writeJson(response, 404, { ok: false, error: 'not found' });
    } catch (error) {
      console.error('[orca-hud] bridge request failed:', error.message);
      writeJson(response, 502, { ok: false, error: 'orca unavailable' });
    } finally {
      activeRequests -= 1;
    }
  });
}

function start() {
  const token = process.env.ORCA_HUD_TOKEN;
  const host = process.env.ORCA_HUD_BIND_HOST || process.env.ORCA_HUD_HOST || '127.0.0.1';
  const port = Number(process.env.ORCA_HUD_PORT || '47631');
  const server = createBridgeServer({ token });
  server.listen(port, host, () => console.log(`[orca-hud] bridge listening on http://${host}:${port}`));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) start();
