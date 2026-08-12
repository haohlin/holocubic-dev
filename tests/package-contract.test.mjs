import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const orcaPackageDir = new URL('../apps/holo-orca-hud/package/', import.meta.url);
const readOrca = (name) => readFileSync(new URL(name, orcaPackageDir), 'utf8');
const deploySource = readFileSync(new URL('../scripts/deploy-orca-hud.mjs', import.meta.url), 'utf8');
const deviceVerifyPath = new URL('../scripts/verify-orca-hud-device.mjs', import.meta.url);

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
  assert.doesNotMatch(source, /http_api\.cubicserver\.get/, 'does not keep a weather-service dependency');
  assert.match(source, /app_api\.on, "imu"/);
  assert.match(source, /hud\.move_selection/);
  assert.match(source, /hud\.move_page/);
  assert.match(source, /time_api\.getlocal/);
  assert.match(source, /sys_api\.version/);
  assert.match(source, /wifi_api\.sta\.getip/);
  assert.match(source, /key_api\.HOME/);
  assert.match(source, /key_api\.LONG_START/);
  assert.match(source, /ORCA/);
  assert.match(source, /SESSIONS/);
});

test('Holo Context HUD packages the Orca-mobile visual system', () => {
  for (const name of [
    'assets/orca-logo.png',
    'assets/monitor.png',
    'assets/terminal.png',
    'assets/cloud-sun.png',
    'assets/chevron-right.png',
  ]) {
    assert.equal(existsSync(new URL(name, orcaPackageDir)), true, `${name} is packaged`);
  }

  const source = readOrca('main.lua');
  assert.match(source, /lv_canvas_draw_img/, 'draws source image assets rather than text-symbol stand-ins');
  assert.match(source, /assets\//, 'uses packaged visual assets');
  assert.match(source, /orca-logo\.png/, 'uses the official Orca mark');
  assert.match(source, /RESUME/, 'keeps the mobile app resume hierarchy');
  assert.match(source, /HOST/, 'keeps the mobile app host hierarchy');
  assert.match(source, /SESSION/, 'labels the session navigator clearly');
  assert.match(source, /green = 0x65D6A2/, 'uses a bright semantic connected color on the dark glass');
  assert.match(source, /purple = 0xC6A4FF/, 'keeps a bright focused/resume accent on the dark glass');
  assert.match(source, /runtime-error\.txt/, 'persists a timer callback failure for device-side diagnosis');
  assert.match(source, /xpcall/, 'contains timer callback failures instead of silently exiting');
  assert.match(source, /lifecycle\.txt/, 'records an unexpected app stop reason on the device');
  assert.match(source, /function guard_callback\(name, fn\)/, 'contains asynchronous callback faults instead of letting the app terminate');
  assert.match(source, /canvas_frame_begin/, 'uses a bounded canvas frame for each visible state change');
  assert.match(source, /canvas_frame_end/, 'closes each canvas frame without retaining temporary LVGL objects');
  assert.match(source, /C\.muted, 10/, 'uses compact canvas metadata to prevent row overlap');
  assert.match(source, /hud\.render_due/, 'bounds redraw frequency instead of rerendering every IMU tick');
  assert.match(deploySource, /readdir/, 'deploys package assets recursively');
  assert.match(deploySource, /assets/, 'deploy includes the visual asset directory');
  assert.match(deploySource, /setDefaultResultOrder\('ipv4first'\)/, 'deployment preserves the required .local hostname while preferring its reachable IPv4 record');
});

test('Holo Context HUD uses one retained canvas instead of a dynamic LVGL object tree', () => {
  const source = readOrca('main.lua');
  assert.match(source, /lv_canvas_create/, 'creates the firmware-supported canvas surface');
  assert.match(source, /hud\.canvas_layout\(\)/, 'uses the tested fixed display geometry');
  assert.match(source, /lv_canvas_draw_text/, 'draws text directly into the retained canvas');
  assert.match(source, /lv_canvas_draw_img/, 'draws packaged source assets directly into the retained canvas');
  assert.doesNotMatch(source, /local function make_label/, 'does not allocate dynamic LVGL labels');
  assert.doesNotMatch(source, /local function make_panel/, 'does not allocate dynamic LVGL panels');
});

test('Holo Context HUD renders the light frosted-glass transcript extension without a command path', () => {
  const source = readOrca('main.lua');
  const model = readOrca('hud_model.lua');
  assert.match(readOrca('app.info'), /^version = 0\.5\.10$/m, 'declares the exact original-transcript presentation release');
  assert.match(source, /base = 0x3A3C3F/, 'darkens the balanced smoked-gray cube background by another fifty percent');
  assert.match(source, /glass_bottom = 0x484D53/, 'darkens the frosted glass treatment by the same proportion');
  assert.match(source, /local function draw_glass_panel/, 'renders depth with canvas-native glass panels');
  assert.match(source, /radius = radius/, 'uses native rounded canvas panels rather than square cards');
  assert.match(source, /glass_top/, 'layers translucent cool-gray bands into a frosted gradient');
  assert.match(source, /CHAT_HISTORY_LIMIT = 8/, 'restores the original compact eight-line chat tail');
  assert.match(source, /CHAT_VISIBLE_LINES = TRANSCRIPT\.visible_lines/, 'keeps the page size coupled to the tested physical layout');
  assert.match(source, /CHAT_TEXT_WIDTH = 42/, 'keeps the original compact transcript width');
  assert.match(source, /hud\.transcript_lines\(payload, CHAT_HISTORY_LIMIT, CHAT_TEXT_WIDTH\)/, 'restores simple one-row-per-terminal-line transcript compaction');
  assert.doesNotMatch(source, /LV_FONT_MONTSERRAT_/, 'uses the firmware default compact text renderer rather than a special terminal font that changes size');
  assert.match(source, /transcript_timeout_ms = 7000/, 'leaves a terminal loading state if the cube request never returns');
  assert.match(source, /TRANSCRIPT TIMEOUT/, 'reports a timed-out transcript instead of an endless spinner state');
  assert.match(source, /native_http_timeout_ms = 5000/, 'uses the firmware HTTP timeout before the app-level watchdog');
  assert.match(source, /status_started = 0/, 'also watches a hung status request so it cannot starve chat forever');
  assert.match(source, /hud\.next_poll/, 'prioritizes the selected chat refresh over background status polling');
  assert.match(source, /timeout = APP\.native_http_timeout_ms/, 'passes an explicit native HTTP timeout to every request');
  assert.doesNotMatch(source, /ORCA HTTP/, 'does not expose raw native HTTP negative codes as user-facing text');
  assert.match(source, /local function draw_transcript/, 'has a dedicated transcript canvas view');
  assert.doesNotMatch(source, /local function draw_terminal_panel/, 'removes the later fancy terminal-card formatting');
  assert.doesNotMatch(source, /local function draw_terminal_text/, 'removes the special terminal text renderer');
  assert.match(source, /hud\.transcript_layout\(\)/, 'uses shared physical transcript geometry instead of untested row offsets');
  assert.match(source, /"TRANSCRIPT", C\.muted, 10/, 'restores the original transcript heading treatment');
  assert.match(source, /"RECENT OUTPUT", C\.dim, 8/, 'restores the original plain-history label');
  assert.match(model, /section_label_y = 39/, 'restores the original transcript heading baseline');
  assert.match(model, /session_y = 48/, 'restores the original session-card placement');
  assert.match(model, /panel_y = 87/, 'restores the original history-panel placement');
  assert.match(model, /text_y = 104/, 'restores the original history-row baseline');
  assert.match(model, /font_size = 10/, 'restores the original readable transcript type size');
  assert.match(source, /TRANSCRIPT\.line_step/, 'spaces rendered transcript baselines from the shared readable geometry');
  assert.match(source, /hud\.vertical_motion_pulse/, 'uses a sudden vertical motion signal instead of a large absolute tilt deadzone');
  assert.match(source, /vertical_flick_degrees = 10/, 'requires one deliberate ten-degree vertical flick');
  assert.match(source, /vertical_sudden_degrees = 3/, 'requires a meaningful per-sample angle change before acting');
  assert.match(source, /vertical_anchor_roll/, 'calibrates the actual resting cant instead of hard-coding an old angle');
  assert.match(source, /vertical_action_cooldown_ms = 1000/, 'locks vertical snap actions for one second after each accepted action');
  assert.match(source, /hud\.rate_limit_pulse/, 'applies the vertical snap cooldown before either session or chat movement');
  assert.doesNotMatch(source, /hud\.terminal_lines\(payload, CHAT_HISTORY_LIMIT, CHAT_TEXT_WIDTH\)/, 'does not reflow terminal rows a second time on the cube');
  assert.doesNotMatch(source, /hud\.transcript_tone/, 'does not add semantic per-line formatting to the restored plain transcript');
  assert.doesNotMatch(source, /vertical_center_roll/, 'does not depend on a hard-coded vertical rest angle');
  assert.doesNotMatch(source, /move_scroll_repeat/, 'does not keep scrolling just because the cube remains tilted');
  assert.match(source, /hud\.move_page\(\s*APP\.page, horizontal/, 'uses horizontal tilt for enter/back hierarchy navigation');
  assert.match(source, /local horizontal = APP\.neutral_pitch - APP\.raw_pitch/, 'reverses physical left/right mapping to match the cube orientation');
  assert.match(source, /local vertical_pulse = APP\.vertical_pulse/, 'consumes one queued vertical motion command per tick');
  assert.match(source, /hud\.move_selection_pulse\(\s*APP\.selected, #APP\.sessions, vertical_pulse/, 'uses forward/back flicks for session-list scrolling');
  assert.match(source, /hud\.move_scroll_pulse/, 'uses forward/back flicks to scroll retained chat');
  assert.match(source, /hud\.transcript_window/, 'renders a bounded visible window from retained chat history');
  assert.match(source, /draw_tile\(3, "terminal\.png", focused and "1" or "0", "FOCUSED"\)/, 'uses the freed weather tile to surface the active focused session');
  assert.doesNotMatch(source, /request_weather|WEATHER WAIT|weather_poll_ms|weather_inflight/, 'removes weather polling and its no-data state from the HUD');
  assert.match(source, /RIGHT: CHAT/, 'teaches right tilt as the session enter action');
  assert.match(source, /FLICK UP\/DOWN SCROLL/, 'teaches the sudden-motion transcript control');
  assert.match(source, /LEFT: BACK/, 'teaches left tilt as the chat back action');
  assert.match(source, /\/v1\/transcript\?id=/, 'fetches transcript data through the authenticated bridge');
  assert.match(source, /APP\.page == 3/, 'keeps transcript behavior isolated to its own view');
  assert.doesNotMatch(source, /terminal\s*send|\/v1\/command|\/v1\/speak/, 'does not add command or speech controls');
});

test('local preview gate renders the same 320 by 240 transcript geometry before deployment', async () => {
  const preview = await import('../scripts/render-orca-hud-preview.mjs');
  assert.deepEqual(preview.validateTranscriptLayout(), { ok: true }, 'preview rejects overlapping transcript rows before a device upload');
  const svg = preview.renderTranscriptPreview();
  assert.match(svg, /viewBox="0 0 320 240"/, 'preview matches the physical canvas dimensions');
  assert.match(svg, /RECENT OUTPUT/, 'preview includes the original plain-history label');
  assert.match(svg, /font-size="10"/, 'preview checks the original readable transcript type scale');
});

test('bridge service is supervised across a Mac process restart', () => {
  const servicePath = new URL('../scripts/install-orca-bridge-service.mjs', import.meta.url);
  assert.equal(existsSync(servicePath), true, 'provides an installable launchd service rather than a one-shot detached process');
  const source = readFileSync(servicePath, 'utf8');
  assert.match(source, /KeepAlive/, 'launchd relaunches the bridge after an unexpected exit');
  assert.match(source, /RunAtLoad/, 'launchd restores the bridge after login');
  assert.match(source, /start-orca-bridge\.mjs/, 'service runs the bridge through its configuration-aware launcher');
  assert.match(source, /launchctl/, 'installer bootstraps the service in the current user domain');
});

test('Holo Flight Deck source has been removed', () => {
  assert.equal(existsSync(new URL('../apps/holo-flight-deck/package/main.lua', import.meta.url)), false);
});

test('device verifier uses the requested hostname and proves the live app loop', () => {
  assert.equal(existsSync(deviceVerifyPath), true, 'device verifier is present');
  const source = readFileSync(deviceVerifyPath, 'utf8');
  assert.match(source, /clocteck-cubic\.local/, 'uses the requested device hostname');
  assert.match(source, /setDefaultResultOrder\('ipv4first'\)/, 'verification uses the required hostname without attempting an unreachable IPv6 route');
  assert.match(source, /api\/system\/exit/, 'tests that the app can leave the foreground');
  assert.match(source, /api\/system\/launch/, 'tests app relaunch');
  assert.match(source, /runtime-error\.txt/, 'checks device-side runtime faults');
  assert.match(source, /lifecycle\.txt/, 'checks that the canvas HUD did not terminate itself');
  assert.match(source, /await delay\(20_000\)/, 'soaks the canvas HUD across several bridge polls');
  assert.match(source, /bridge-check/, 'checks the cube-to-Orca bridge request');
  assert.match(source, /\/v1\/transcript/, 'proves the cube can request the read-only transcript endpoint');
  assert.match(source, /sjson\.decode/, 'derives an opaque session id without recording terminal output');
  assert.match(source, /retainedLines/, 'confirms the cube receives scrollable retained-chat metadata without recording chat text');
  assert.match(source, /async function exitToHome/, 'treats the verifier precondition as an idempotent device transition');
  assert.match(source, /no running app/, 'accepts an already-idle device before launching the HUD');
});
