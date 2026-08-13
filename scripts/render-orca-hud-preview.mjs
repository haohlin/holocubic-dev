import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export const transcriptPreviewLayout = Object.freeze({
  sectionLabelY: 39,
  sessionY: 48,
  sessionH: 32,
  sessionIconY: 55,
  sessionTitleY: 52,
  sessionMetaY: 68,
  sessionDotY: 60,
  panelY: 87,
  panelH: 121,
  textX: 20,
  textY: 104,
  textW: 276,
  lineStep: 13,
  fontSize: 10,
  fontLineH: 10,
  visibleLines: 8,
  maxChars: 42,
  bottomPadding: 3,
});

function escapeXml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

export function validateTranscriptLayout(layout = transcriptPreviewLayout) {
  const lastBottom = layout.textY + (layout.visibleLines - 1) * layout.lineStep + layout.fontLineH;
  const paneBottom = layout.panelY + layout.panelH - layout.bottomPadding;
  if (layout.lineStep < layout.fontLineH + 3) throw new Error('transcript rows overlap');
  if (lastBottom > paneBottom) throw new Error('transcript rows exceed the terminal pane');
  return { ok: true };
}

export function renderTranscriptPreview(lines = [
  'Preparing verification', 'Bridge connected', 'Reading transcript', 'Waiting for action',
  'Checking live state', 'Refreshing terminal', 'Latest output ready', 'Use a flick to scroll',
]) {
  validateTranscriptLayout();
  const l = transcriptPreviewLayout;
  if (lines.some((line) => String(line).length > l.maxChars)) throw new Error('preview row exceeds the device-safe text width');
  const rows = lines.slice(0, l.visibleLines).map((line, index) => {
    const y = l.textY + index * l.lineStep + l.fontSize;
    return `<text x="${l.textX}" y="${y}" fill="#F4F7FB" font-size="${l.fontSize}" font-family="Arial, sans-serif">${escapeXml(line)}</text>`;
  }).join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="960" height="720" viewBox="0 0 320 240">
  <rect width="320" height="240" fill="#000000"/>
  <rect x="12" y="9" width="296" height="29" rx="9" fill="#575C60" stroke="#717274"/>
  <text x="160" y="29" text-anchor="middle" fill="#F4F7FB" font-size="14" font-family="Arial, sans-serif">ORCA</text>
  <circle cx="270" cy="23" r="4" fill="#65D6A2"/><text x="282" y="27" fill="#F4F7FB" font-size="9" font-family="Arial, sans-serif">11:22</text>
  <text x="12" y="${l.sectionLabelY + 10}" fill="#C1C9D4" font-size="10" font-family="Arial, sans-serif">TRANSCRIPT</text>
  <rect x="12" y="${l.sessionY}" width="296" height="${l.sessionH}" rx="8" fill="#484D53" stroke="#78A7FF"/>
  <text x="45" y="${l.sessionTitleY + 11}" fill="#F4F7FB" font-size="11" font-family="Arial, sans-serif">focused session</text>
  <text x="45" y="${l.sessionMetaY + 8}" fill="#C1C9D4" font-size="8" font-family="Arial, sans-serif">DONE / 4T</text>
  <circle cx="260" cy="${l.sessionDotY}" r="4" fill="#65D6A2"/>
  <rect x="12" y="${l.panelY}" width="296" height="${l.panelH}" rx="7" fill="#484D53" stroke="#717274"/>
  <text x="20" y="${l.panelY + 12}" fill="#929CAA" font-size="8" font-family="Arial, sans-serif">RECENT OUTPUT</text>
  <g clip-path="url(#transcript-clip)">${rows}</g>
  <rect x="12" y="214" width="296" height="18" rx="6" fill="#484D53" stroke="#717274"/>
  <text x="20" y="227" fill="#C1C9D4" font-size="8" font-family="Arial, sans-serif">FLICK UP/DOWN SCROLL  LEFT: BACK</text>
  <defs><clipPath id="transcript-clip"><rect x="20" y="${l.textY}" width="${l.textW}" height="${l.panelH - (l.textY - l.panelY) - l.bottomPadding}"/></clipPath></defs>
</svg>`;
}

async function main() {
  const output = resolve(root, '.local', 'orca-hud-preview.svg');
  await mkdir(dirname(output), { recursive: true, mode: 0o700 });
  await writeFile(output, renderTranscriptPreview(), { mode: 0o600 });
  console.log(`[orca-hud] preview written to ${output}`);
}

if (process.argv[1] && import.meta.url === new URL(process.argv[1], 'file:').href) {
  main().catch((error) => {
    console.error(`[orca-hud] ${error.message}`);
    process.exitCode = 1;
  });
}
