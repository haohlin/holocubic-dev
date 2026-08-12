# Holo Context HUD — Orca Mobile Adaptation

## Selected visual target

The real Orca Mobile home screen is the source visual target. Its recognizable
structure is a compact Orca header, three utility statistics, then the
**Host**, **Resume**, and system status rows. Its navigator is a sparse list of
terminal/worktree rows with left-hand icons, semantic status dots, and
right-hand chevrons. The app source uses the official Orca mark and Lucide
icons—the same icon library used by Orca Mobile.

The HoloCubic has a 320×240 autostereoscopic screen, no touch UI, gyro-based
left/right and forward/back navigation, and one short-press button. It cannot
be a keyboard or full terminal mirror. This app therefore preserves Orca's
information hierarchy and focus workflow, but makes the cube a clear glance,
select, and focus companion.

## Display design system

| Role | Orca Mobile source | HoloCubic adaptation |
| --- | --- | --- |
| Canvas | `#111111` graphite | true black `#000000` so unlit pixels remain optically transparent |
| Surfaces | graphite `#1A1A1A`, raised `#242424` | no opaque fills; 1px graphite `#2A2A2A` rails preserve transparent depth |
| Primary copy | `#E0E0E0` | `#E0E0E0` |
| Secondary copy | `#888888`, muted `#555555` | same values for section labels, metadata, and the footer rail |
| Selection | blue `#3B82F6` | blue 1px selected-session border, never a filled card |
| Connected / ready | green `#22C55E` | green dot plus explicit `READY` copy |
| Working | amber `#F59E0B` | amber dot plus explicit `WORKING` copy |
| Attention | red `#EF4444` | red dot plus explicit `ATTENTION` copy |
| Resume | purple `#A78BFA` | purple dot plus explicit `FOCUSED` copy |
| Geometry | 6px rows, 14px cards | 6px transparent outlined rows and tiles; no nested card stack |

The app uses actual source assets rather than text glyph stand-ins:

- Orca logo, top left
- Monitor, Host and session-count tile
- Terminal, Resume and session rows
- Cloud/Sun, weather tile and system row
- Chevron, actionable rows

## Information architecture and controls

### Home

1. Orca header: logo, bridge state dot, and local time.
2. Three compact counters: working sessions, all sessions, weather.
3. **Host**: the Mac bridge and connection/session count.
4. **Resume**: the last session focused from this cube, with its purple or
   semantic status indicator.
5. **System**: location, weather, and Wi-Fi state.
6. Persistent status/control rail.

### Sessions

1. Same Orca header.
2. **Sessions** title and `working / total` summary.
3. Four visible rows at a time: terminal icon, session name, readable state and
   terminal availability, semantic dot, and chevron.
4. Thin blue outline indicates the currently selected row.
5. Persistent status/control rail.

| Physical input | Home | Sessions |
| --- | --- | --- |
| Forward/back tilt | switches between Home and Sessions | switches between Sessions and Home |
| Left/right tilt | no action | moves the selected session after returning to neutral |
| Short press | refreshes bridge and weather data | focuses the selected connected terminal on the Mac, then returns Home |
| Long press | exits | exits |

"Focus" means `orca terminal switch` on the paired Mac. The cube intentionally
does not expose terminal prompts, terminal output, paths, raw handles, or shell
commands.

## Fidelity inventory

- Header/logo: official Orca source mark, not a text approximation.
- Icons: official Lucide paths rasterized at 18×18 transparent PNG, matching
  the icon family used by Orca Mobile.
- Hierarchy: header → three counters → Host → Resume → system/list.
- Status treatment: color-coded dots are accompanied by readable state text.
- Navigation: functional two-screen hierarchy with selection and focus states;
  the bottom rail always names the current physical controls.

## Validation constraint

The device firmware's DevTools API has no framebuffer screenshot or simulator
surface. Automated validation covers package contents, asset deployment,
navigation model, and the live launch path. Visual fidelity still needs the
user's physical-device viewing because no tool can capture this display.

## Design QA record — 2026-07-11

The accepted reference was visually inspected from the official Orca Mobile
product imagery and the public Orca Mobile source. A direct implementation
screenshot is unavailable: the firmware exposes control, file, and launcher
APIs but no framebuffer capture. The app is therefore live-validated on-device,
not declared pixel-perfect from a browser capture.

| Comparison point | Reference evidence | Holo result / intentional adaptation |
| --- | --- | --- |
| Header | Orca mark, wordmark, compact status utility | official mark, `ORCA`, connected-state dot, local time |
| First viewport hierarchy | three compact stats before navigation rows | working, sessions, weather counters before Host / Resume / System |
| Row anatomy | left icon, title/meta, colored state, chevron | same anatomy with actual icons, explicit status copy, and chevron |
| Palette | graphite, white, muted copy, blue selection, green/amber/red/purple semantics | same semantic colors; card fills intentionally removed to retain transparent optics |
| Navigation | Home → desktop/session rows → resume focus | Home ↔ Sessions via forward/back tilt; left/right selection; press focuses the Mac terminal |
| Status rail | concise operational feedback appears in the mobile shell | persistent bottom rail names the active gyro/button operation and reports focus/refresh feedback |

The above-fold copy is intentionally Holo-specific rather than a literal copy:
`HOST`, `RESUME`, `SYSTEM`, and physical-control guidance replace mobile-only
items such as account usage, settings, touch actions, and terminal keyboards.
Those omissions are required by the 320×240 screen and one-button/gyro input,
not visual drift.

## Runtime architecture revision — approved 2026-07-12

The original implementation used a tree of dynamic LVGL labels, images,
panels, dots, and a line. On the real cube the app entered the foreground but
was later removed by the firmware without a Lua error, runtime-error record,
or app-exit notification. Three measured mitigations (bounded redraws,
serialized HTTP requests, and a retained line-point buffer) did not make that
object graph stable.

The approved replacement is one retained 320×240 `LV_IMG_CF_TRUE_COLOR`
canvas. Rendering happens only after meaningful application state changes.
The canvas frame is opened, painted black, rendered with the existing assets
and Orca design tokens, then closed. No dynamic LVGL label, image, panel,
line, or dot objects are created after startup.

The canvas preserves the visible contract:

- Home retains header, three utility counters, Host, Resume, System, and the
  control rail.
- Sessions retains the header, working/total summary, four rows, terminal
  asset, colored state square, selection outline, and actionable chevron.
- All title/meta pairs use fixed canvas coordinates and 12px/10px font sizes;
  the System row is intentionally one line so no text shares its vertical
  space.
- The existing Orca bridge, sanitized session payload, gyro latches,
  short-press refresh/focus behavior, and long-press exit behavior remain
  unchanged.

The canvas API is an established current-firmware pattern documented in
`README_LVGL.md` and used by the supplied Photo, Spectrum, FluidPendant, and
Weather applications. The single-canvas approach reduces the persistent
native object count to the root plus one canvas while retaining the accepted
visual design.

## Status and transcript extension — approved 2026-07-12

The cube is an at-a-glance companion rather than a terminal. Its next revision
adds a read-only terminal transcript and makes the agent state explicit without
adding command, microphone, or text-to-speech controls.

### Visual system

The full 320×240 canvas uses Apple's recommended medium smoked-gray graphite
base, `#3E424A`, instead of optical black transparency. Raised regions are
drawn with translucent blue-gray graphite fills, a single pale top highlight,
and a restrained cool outline. A selected row receives a low-opacity blue
halo plus a clear blue outline. This gives the depth cue of Liquid Glass
without blur, animation, or extra native objects that could compromise the
proven stable canvas loop.

Primary text is near-white and metadata is cool light gray. State is always
communicated twice: by a colored square and one explicit word:

| Cube state | Meaning | Treatment |
| --- | --- | --- |
| `WORKING` | the selected session has an active Orca agent | amber square and copy |
| `DONE` | the agent is idle, ready, or completed its latest action | green square and copy |
| `OFFLINE` | no actionable terminal is presently connected | muted-gray square and copy |
| `ATTENTION` | blocked, interrupted, or errored work needs review | red square and copy |
| `FOCUSED` | the cube last activated the session on the paired Mac | violet square and copy |

### Navigation and safety

The screen order is **Overview → Sessions → Transcript**. Forward/back tilt
moves one screen at a time. On Sessions and Transcript, left/right tilt moves
the same selected session so a user can see the selected session's current
state and then its recent output without a second selector.

| Physical input | Overview | Sessions | Transcript |
| --- | --- | --- | --- |
| Forward/back tilt | move to Sessions / remain at Overview | move to Transcript / Overview | remain at Transcript / move to Sessions |
| Left/right tilt | no action | select a session | select a session |
| Short press | refresh status and weather | focus the selected connected terminal | refresh status and selected transcript |
| Long press | exit | exit | exit |

Transcript content is read-only and bounded: the paired Mac bridge accepts an
opaque current-session id, resolves it from the current status snapshot, reads
only the final 24 terminal lines through `orca terminal read`, removes ANSI
and control sequences, and returns at most eight compact display lines. The
cube never receives a raw terminal handle and never sends commands. Voice
command, text composition, and text-to-speech are explicitly deferred.

## Tilt navigation and retained-chat extension — approved 2026-07-13

The earlier layout used forward/back tilt to change pages and left/right tilt
to change a selected row. That conflicts with the cube's physical orientation
and makes small incidental motions navigate the application. The revised
interaction separates hierarchy from scrolling:

| Physical input | Overview | Sessions | Chat |
| --- | --- | --- | --- |
| Right tilt | enter Sessions | open the centred session's Chat | no action |
| Left tilt | remains at Overview | return to Overview | return to Sessions |
| Forward/back tilt | no list to scroll | scroll the session list | scroll newer/older chat lines |
| Short press | refresh status/weather | focus the centred session on the Mac | refresh retained chat |
| Long press | exit | exit | exit |

On Sessions, vertical movement scrolls the list and places the centre cursor
on the session that right tilt opens. This is not a second hidden gesture:
the footer names `F/B: SCROLL`, `RIGHT: CHAT`, and `LEFT: HOME`. On Chat, the
same vertical gesture scrolls a stable read-only buffer. Newest lines open
first; moving away from the newest line does not force the view back to the
tail on the next poll.

Every directional gesture uses a hysteretic deadzone: a tilt must exceed 24°
to act and must return inside 12° before the next gesture can act. This
applies to horizontal enter/back and vertical list/chat scrolling alike.

The paired bridge now requests up to 1,000 terminal rows and returns all rows
the Orca runtime still retains, with no raw terminal handle. A live probe
returned 334 retained rows and reported that older rows had already been
trimmed by Orca. The Chat screen therefore presents the complete retained
terminal/chat history, not an eight-line preview; it cannot reconstruct rows
that Orca itself has discarded.

## Frosted glass and five-page transcript revision — approved 2026-07-13

The physical display read darker and flatter than the intended material, and a
large terminal response could leave the constrained Lua HTTP path visibly
loading. The canvas remains the stability boundary, but its visual and data
budgets change together.

### Material treatment

The opaque base is now a balanced smoked-aluminum gray, `#74787D`, halfway
between the prior dark graphite and the first bright prototype, chosen to sit
beside the cube's gray enclosure without washing out the holographic depth.
Every card is a native canvas rounded
rectangle—not an approximation made from square rails—with a pale border, a
very low-opacity offset shadow, a cool lower glass fill, two translucent
inset bands, and a thin white top reflection. Together those layers give a
matte, transparent-looking vertical gradient without blur, animation, bitmap
generation, or additional LVGL objects. Dark graphite copy provides contrast;
the blue selection halo and semantic dots remain visible but restrained.

### Transcript budget and response states

The bridge asks Orca for at most 40 tail rows, sanitizes them, and returns the
latest 35. Seven lines are visible at once, so this is exactly five physical
pages. The Lua client repeats that 35-line bound before rendering. It keeps a
previously visible buffer on screen while refreshing and explicitly renders
`NO CONNECTED TERMINAL`, `TRANSCRIPT UNAVAILABLE`, `TRANSCRIPT CHANGED`, or
`TRANSCRIPT TIMEOUT` rather than remaining indefinitely on a loading message.
A seven-second request guard releases the serialized HTTP transport after an
unanswered callback.

### Physical-control calibration

Device testing established that the firmware reports both tilt axes opposite
to the user's natural left/right and up/down orientation. The IMU values are
therefore inverted once at the app boundary. The logical navigation contract
does not change: right enters, left goes back, and up/down scrolls the session
or chat history after the existing 24° engage / 12° release hysteresis.

## Dark material, terminal fallback, and calibrated tilt revision — 2026-07-13

The first balanced-gray material was still too light on the real optical
display. The base and every glass-layer color are now reduced by another 50%
to a dark smoked system (`#3A3C3F` base; `#484D53` lower glass), while primary
copy and semantic state colors remain bright for legibility. Rounded panels,
the matte gradient, and the transparent-like layering remain intact.

At the cube's resting pose, live IMU sampling measured `roll +4.646°`, which
matches the observed 5° backward cant. The fixed vertical centre is therefore
`+5°`; forward tilt is negative relative to that centre. Every directional
gesture now needs 36° to engage and returns only inside 18°, eliminating the
previously overly sensitive response.

Live Orca inspection found that a worktree can own more than one connected
terminal. The previous bridge used the first terminal in the list, which made
the HoloCubic ESP32 session appear empty even while another terminal for the
same worktree had 29 retained rows. The bridge now ranks candidates by latest
output and reads fallbacks when the first is empty or stale. It returns the
first nonempty sanitized tail, still capped to 35 lines and still never
exposing terminal handles to the cube.

## Finalized physical controls and focused home context — 2026-07-13

The user-confirmed vertical convention is `vertical = +5° - raw_roll`: the
cube's positive 5° backward resting cant is its middle, and the opposite sign
from the prior revision is the correct physical up/down behavior. This mapping
is a user-validated device convention and must not be reversed without new
physical testing.

Weather is removed from the HUD and no longer triggers a background service
request. The freed third tile reports whether a focused session exists, while
the System row now shows the cube's network and firmware state. The bridge
promotes Orca's `isActive` worktree into the sanitized `focused` field, so the
Home `Resume` row shows the desktop's active session immediately after a
bridge restart—not only after the cube itself sends a focus action.

## Desktop-terminal transcript formatting revision — 2026-07-13

The desktop Orca transcript is a dark charcoal terminal surface with light
text, a subtle divider, calm blue prompt accents, and distinct error/status
colors. Its live output does not include ANSI colors, but it does preserve
leading whitespace and can contain rows far wider than the cube. The older
HUD collapsed whitespace to a paragraph and clipped each line, making code
and nested output unreadable.

The bridge now sanitizes control codes without flattening spaces, wraps rows
at the cube's 42-character terminal width, and retains the newest 35 visual
rows (five seven-row pages). The canvas renders those rows in a dedicated
`#1E2024` terminal viewport with a compact terminal header, divider, scroll
thumb, and prompt/error/warning/success/indented-output tones. It uses the
existing single retained canvas and adds no terminal input or command path.
