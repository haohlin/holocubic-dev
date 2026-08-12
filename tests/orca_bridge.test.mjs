import assert from 'node:assert/strict';
import test from 'node:test';

import { createBridgeServer } from '../companion/orca_bridge.mjs';

function makeOrcaFixture() {
  const calls = [];
  const runOrca = async (args) => {
    calls.push(args);
    if (args[0] === 'status') {
      return {
        app: { running: true },
        runtime: { state: 'ready', reachable: true },
      };
    }
    if (args[0] === 'worktree') {
      return {
        worktrees: [
          {
            worktreeId: 'worktree-alpha',
            displayName: 'Alpha\nInternal',
            status: 'working',
            isActive: true,
            liveTerminalCount: 1,
            preview: 'do not return me',
            path: '/private/alpha',
            agents: [{ state: 'working', prompt: 'do not return me' }],
          },
          {
            worktreeId: 'worktree-beta',
            displayName: 'Beta',
            status: 'inactive',
            isActive: false,
            liveTerminalCount: 0,
            preview: 'do not return me either',
            path: '/private/beta',
            agents: [],
          },
        ],
      };
    }
    if (args[0] === 'terminal' && args[1] === 'list') {
      return {
        terminals: [
          {
            handle: 'term_alpha_empty',
            worktreeId: 'worktree-alpha',
            connected: true,
            lastOutputAt: 300,
            preview: 'do not return terminal output',
          },
          {
            handle: 'term_alpha_live',
            worktreeId: 'worktree-alpha',
            connected: true,
            lastOutputAt: 200,
            preview: 'do not return terminal output',
          },
        ],
      };
    }
    if (args[0] === 'terminal' && args[1] === 'switch') {
      return { switched: true };
    }
    if (args[0] === 'terminal' && args[1] === 'read') {
      if (args[3] === 'term_alpha_empty') {
        return { terminal: { tail: [], truncated: false, limited: false } };
      }
      return {
        terminal: {
          tail: Array.from({ length: 40 }, (_, index) => {
            const line = index + 1;
            if (line === 6) return 'Booting \u001b[32magent\u001b[0m';
            if (line === 38) return ' final\tline\r';
            if (line === 34) return '    indentation survives wrapping';
            if (line === 35) return `${'working '.repeat(120)}latest useful status`;
            return `line ${String(line).padStart(2, '0')}`;
          }),
          truncated: true,
          limited: true,
        },
      };
    }
    throw new Error(`unexpected Orca command: ${args.join(' ')}`);
  };
  return { calls, runOrca };
}

async function withBridge(t, run) {
  const fixture = makeOrcaFixture();
  const server = createBridgeServer({ token: 'test-token-012345', runOrca: fixture.runOrca });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  t.after(() => new Promise((resolve) => server.close(resolve)));
  return run({ baseUrl: `http://127.0.0.1:${port}`, ...fixture });
}

test('bridge returns only sanitized session state to authenticated callers', async (t) => {
  await withBridge(t, async ({ baseUrl }) => {
    const denied = await fetch(`${baseUrl}/v1/status`);
    assert.equal(denied.status, 401);

    const response = await fetch(`${baseUrl}/v1/status`, {
      headers: { authorization: 'Bearer test-token-012345' },
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.deepEqual(body.orca, { running: true, reachable: true, state: 'ready' });
    assert.equal(body.sessions.length, 2);
    assert.deepEqual(Object.keys(body.sessions[0]).sort(), [
      'active', 'agentState', 'canActivate', 'focused', 'id', 'label', 'status', 'terminalCount',
    ]);
    assert.equal(body.sessions[0].label, 'Alpha Internal');
    assert.equal(body.sessions[0].canActivate, true);
    assert.equal(body.sessions[0].focused, true, 'the Orca active worktree is immediately available to the home Resume row');
    assert.equal(body.sessions[1].canActivate, false);
    assert.doesNotMatch(JSON.stringify(body), /private|prompt|preview|term_alpha|worktree-alpha/i);
  });
});

test('bridge switches only the selected session terminal from a fresh snapshot', async (t) => {
  await withBridge(t, async ({ baseUrl, calls }) => {
    const headers = { authorization: 'Bearer test-token-012345' };
    const status = await fetch(`${baseUrl}/v1/status`, { headers });
    const alpha = (await status.json()).sessions[0];
    const selection = await fetch(`${baseUrl}/v1/select`, {
      method: 'POST',
      headers: { ...headers, 'content-type': 'application/json' },
      body: JSON.stringify({ id: alpha.id }),
    });
    assert.equal(selection.status, 200);
    assert.deepEqual(await selection.json(), { ok: true, selected: alpha.id });
    assert(calls.some((args) => JSON.stringify(args) === JSON.stringify([
      'terminal', 'switch', '--terminal', 'term_alpha_empty', '--json',
    ])));

    const refreshed = await fetch(`${baseUrl}/v1/status`, { headers });
    const focused = (await refreshed.json()).sessions[0];
    assert.equal(focused.focused, true);
  });
});

test('bridge returns a bounded sanitized transcript for a current connected session', async (t) => {
  await withBridge(t, async ({ baseUrl, calls }) => {
    const headers = { authorization: 'Bearer test-token-012345' };
    const status = await fetch(`${baseUrl}/v1/status`, { headers });
    const alpha = (await status.json()).sessions[0];

    const transcript = await fetch(`${baseUrl}/v1/transcript?id=${alpha.id}`, { headers });
    assert.equal(transcript.status, 200);
    const body = await transcript.json();
    assert.deepEqual(Object.keys(body).sort(), ['transcript']);
    assert.deepEqual(body.transcript.session, alpha);
    assert.equal(body.transcript.lines.length, 8, 'restores the original eight-line cube transcript tail');
    assert.equal(body.transcript.lines.at(-1), 'line 40', 'retains the newest terminal line');
    assert(body.transcript.lines.includes(' final  line'), 'preserves meaningful spacing inside terminal rows');
    assert(body.transcript.lines.some((line) => line.startsWith('    indentation')),
      'keeps each compact terminal row intact instead of reflowing it into subrows');
    assert(body.transcript.lines.join(' ').includes('latest useful status'),
      'collapses a pathological terminal status run to its latest useful tail');
    assert(body.transcript.lines.every((line) => line.length <= 42),
      'returns one bounded display row per terminal row without bridge-side reflow');
    assert.deepEqual(body.transcript.history, { retainedLines: 8, truncated: true, limited: true });
    const readHandles = calls
      .filter((args) => args[0] === 'terminal' && args[1] === 'read')
      .map((args) => args[3]);
    assert.deepEqual(readHandles, ['term_alpha_empty', 'term_alpha_live'],
      'falls back from a recent but empty terminal to a connected terminal with retained history');
    assert.doesNotMatch(JSON.stringify(body), /term_alpha|worktree-alpha|\u001b|private|prompt/i);
  });
});

test('bridge rejects missing, unknown, and disconnected transcript sessions without reading a terminal', async (t) => {
  await withBridge(t, async ({ baseUrl, calls }) => {
    const headers = { authorization: 'Bearer test-token-012345' };
    const missing = await fetch(`${baseUrl}/v1/transcript`, { headers });
    assert.equal(missing.status, 400);
    assert.deepEqual(await missing.json(), { ok: false, error: 'invalid session id' });

    const unknown = await fetch(`${baseUrl}/v1/transcript?id=AAAAAAAAAAAAAAAAAA`, { headers });
    assert.equal(unknown.status, 404);
    assert.deepEqual(await unknown.json(), { ok: false, error: 'unknown session' });

    const status = await fetch(`${baseUrl}/v1/status`, { headers });
    const beta = (await status.json()).sessions[1];
    const disconnected = await fetch(`${baseUrl}/v1/transcript?id=${beta.id}`, { headers });
    assert.equal(disconnected.status, 409);
    assert.deepEqual(await disconnected.json(), { ok: false, error: 'session has no connected terminal' });
    assert.equal(calls.filter((args) => args[0] === 'terminal' && args[1] === 'read').length, 0);
  });
});

test('bridge rejects authenticated work above its concurrency limit without spawning more Orca commands', async (t) => {
  const fixture = makeOrcaFixture();
  let releaseWork;
  const workGate = new Promise((resolve) => { releaseWork = resolve; });
  let invocations = 0;
  const runOrca = async (args) => {
    invocations += 1;
    await workGate;
    return fixture.runOrca(args);
  };
  const server = createBridgeServer({
    token: 'test-token-012345',
    runOrca,
    maxConcurrentRequests: 1,
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  const baseUrl = `http://127.0.0.1:${port}`;
  const headers = { authorization: 'Bearer test-token-012345' };
  t.after(() => new Promise((resolve) => server.close(resolve)));

  const first = fetch(`${baseUrl}/v1/status`, { headers });
  while (invocations < 3) await new Promise((resolve) => setImmediate(resolve));

  try {
    const rejected = await fetch(`${baseUrl}/v1/status`, {
      headers,
      signal: AbortSignal.timeout(250),
    });
    assert.equal(rejected.status, 429);
    assert.deepEqual(await rejected.json(), { ok: false, error: 'bridge busy' });
    assert.equal(invocations, 3, 'rejected work does not launch another Orca snapshot');
  } finally {
    releaseWork();
    await first;
  }
});
