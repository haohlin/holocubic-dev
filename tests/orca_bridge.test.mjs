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
            handle: 'term_alpha',
            worktreeId: 'worktree-alpha',
            connected: true,
            preview: 'do not return terminal output',
          },
        ],
      };
    }
    if (args[0] === 'terminal' && args[1] === 'switch') {
      return { switched: true };
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
    assert.equal(body.sessions[0].focused, false);
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
      'terminal', 'switch', '--terminal', 'term_alpha', '--json',
    ])));

    const refreshed = await fetch(`${baseUrl}/v1/status`, { headers });
    const focused = (await refreshed.json()).sessions[0];
    assert.equal(focused.focused, true);
  });
});
