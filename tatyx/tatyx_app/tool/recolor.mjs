// Paints each team's portraits from the orange originals: for every bot
// in public/bots/<bot>.png and every team in src/game/teams.json, writes
// public/bots/<team>/<bot>.png with the art's orange (the panels, the
// glow of the eyes, their shading) turned to the team's hue, keeping its
// saturation and brightness (a little darker for a darker tag), so the
// shells stay ivory and the joints dark. Static: run it once (`npm run
// recolor`) and commit the results; run it again after changing a
// colour or a portrait.
//
// A pixel is "the orange" by its hue (5° to 50°) and, smoothly, by its
// saturation (the ivory shell is barely saturated, the panels are) and
// its brightness (the near-black joints are left alone); pixels on the
// edge between a panel and the shell are blended by that measure, so
// there's no halo.
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const teams = JSON.parse(readFileSync(join(app, 'src', 'game', 'teams.json'), 'utf8'));
const bots = ['a-anchor', 'i-builder', 't-tester', 'y-combinator', 'x-explorer'];

/** The hue band of the art's orange, in degrees. */
const ORANGE_HUE = [5, 50];

function rgbToHsv(r, g, b) {
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  if (d !== 0) {
    if (max === r) h = 60 * (((g - b) / d) % 6);
    else if (max === g) h = 60 * ((b - r) / d + 2);
    else h = 60 * ((r - g) / d + 4);
    if (h < 0) h += 360;
  }
  return [h, max === 0 ? 0 : d / max, max / 255];
}

function hsvToRgb(h, s, v) {
  const c = v * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = v - c;
  let [r, g, b] = [0, 0, 0];
  if (h < 60) [r, g, b] = [c, x, 0];
  else if (h < 120) [r, g, b] = [x, c, 0];
  else if (h < 180) [r, g, b] = [0, c, x];
  else if (h < 240) [r, g, b] = [0, x, c];
  else if (h < 300) [r, g, b] = [x, 0, c];
  else [r, g, b] = [c, 0, x];
  return [(r + m) * 255, (g + m) * 255, (b + m) * 255];
}

function smoothstep(from, to, x) {
  const t = Math.min(1, Math.max(0, (x - from) / (to - from)));
  return t * t * (3 - 2 * t);
}

/** How much of a pixel is the orange to repaint, 0 to 1. */
function orangeness(h, s, v) {
  if (h < ORANGE_HUE[0] || h > ORANGE_HUE[1]) return 0;
  return smoothstep(0.22, 0.4, s) * smoothstep(0.14, 0.3, v);
}

function hexToHsv(hex) {
  const n = Number.parseInt(hex.slice(1), 16);
  return rgbToHsv((n >> 16) & 255, (n >> 8) & 255, n & 255);
}

for (const team of teams) {
  const [hue, tintS, tintV] = hexToHsv(team.color);
  const out = join(app, 'public', 'bots', team.id);
  mkdirSync(out, { recursive: true });
  for (const bot of bots) {
    const png = PNG.sync.read(readFileSync(join(app, 'public', 'bots', `${bot}.png`)));
    const px = png.data;
    for (let i = 0; i < px.length; i += 4) {
      if (px[i + 3] === 0) continue;
      const [h, s, v] = rgbToHsv(px[i], px[i + 1], px[i + 2]);
      const w = orangeness(h, s, v);
      if (w === 0) continue;
      // The team's hue; the pixel's own saturation nudged toward the tag's; its own brightness, scaled
      // down a little for a darker tag (a tag at full brightness leaves it as it is).
      const [r, g, b] = hsvToRgb(hue, s * 0.8 + tintS * 0.2, v * (0.6 + 0.4 * tintV));
      px[i] = Math.round(px[i] * (1 - w) + r * w);
      px[i + 1] = Math.round(px[i + 1] * (1 - w) + g * w);
      px[i + 2] = Math.round(px[i + 2] * (1 - w) + b * w);
    }
    writeFileSync(join(out, `${bot}.png`), PNG.sync.write(png));
  }
  console.log(`${team.id} (${team.color}): ${bots.length} portraits in public/bots/${team.id}/`);
}
