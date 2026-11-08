// What the scenes share: the palette (the aityx one, as style.css, with
// the neon of the map), the font, a button, and the synthwave backdrop
// (the sun, the horizon, the grid running to it).
import Phaser from 'phaser';

export const FONT = 'system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif';

export const PALETTE = {
  bg0: '#07070F',
  bg1: '#201E24',
  bg2: '#2A272E',
  border: '#37333C',
  dim: '#47474D',
  fg: '#EFF2F4',
  muted: '#A9ACB6',
  orange: '#E36742',
  orangeLight: '#EB7B58',
  ivory: '#F2E9DC',
  neon: '#00F0FF',
  sun: '#BC6CFF',
} as const;

export const NEON = 0x00f0ff;
export const SUN = 0xbc6cff;
export const ORANGE = 0xe36742;

/** A rounded orange button with a label; `onClick` on a pointer up. */
export function button(
  scene: Phaser.Scene,
  x: number,
  y: number,
  label: string,
  onClick: () => void,
  options: { width?: number; height?: number; size?: number } = {},
): Phaser.GameObjects.Container {
  const width = options.width ?? 220;
  const height = options.height ?? 54;
  const box = scene.add.graphics();
  const paint = (color: number) => {
    box.clear();
    box.fillStyle(color, 1);
    box.fillRoundedRect(-width / 2, -height / 2, width, height, 12);
  };
  paint(0xe36742);
  const text = scene.add
    .text(0, 0, label, { fontFamily: FONT, fontSize: `${options.size ?? 20}px`, fontStyle: 'bold', color: '#FFFFFF' })
    .setOrigin(0.5);
  const container = scene.add.container(x, y, [box, text]);
  container.setSize(width, height);
  container.setInteractive({ useHandCursor: true });
  container.setData('paint', paint);
  // A click is a press and a release on the button itself: a release
  // alone (Phaser reports one for a pointer that was never down here)
  // must not fire it.
  let armed = false;
  container.on('pointerover', () => paint(0xeb7b58));
  container.on('pointerout', () => {
    armed = false;
    paint(0xe36742);
  });
  container.on('pointerdown', () => {
    armed = true;
  });
  container.on('pointerup', () => {
    if (!armed) return;
    armed = false;
    onClick();
  });
  return container;
}

/** Turns a button() on or off: off, it's grey and takes no clicks. */
export function setButtonEnabled(button: Phaser.GameObjects.Container, enabled: boolean): void {
  const paint = button.getData('paint') as (color: number) => void;
  if (enabled) {
    button.setInteractive({ useHandCursor: true });
    paint(0xe36742);
  } else {
    button.disableInteractive();
    paint(0x4a4650);
  }
  button.setAlpha(enabled ? 1 : 0.7);
}

/**
 * The synthwave backdrop: a starfield, a sun of banded magenta and orange
 * setting behind a horizon at `horizonY`, and a neon grid running from
 * the bottom of the stage to a vanishing point on that horizon.
 */
export function drawSynthwave(scene: Phaser.Scene, horizonY: number): void {
  const { width, height } = scene.scale;
  const g = scene.add.graphics();
  const random = new Phaser.Math.RandomDataGenerator(['tatyx-sky']);
  // Stars.
  for (let i = 0; i < 120; i++) {
    const x = random.between(0, width);
    const y = random.between(0, horizonY - 10);
    g.fillStyle(0xffffff, random.realInRange(0.15, 0.7));
    g.fillCircle(x, y, random.realInRange(0.6, 1.6));
  }
  // The sun: rings from magenta to orange, then the dark bands across its lower half.
  const sunX = width / 2;
  const sunY = horizonY - 20;
  const sunR = 150;
  for (let i = 0; i <= 24; i++) {
    const t = i / 24;
    const color = Phaser.Display.Color.Interpolate.ColorWithColor(
      Phaser.Display.Color.ValueToColor(SUN),
      Phaser.Display.Color.ValueToColor(ORANGE),
      24,
      i,
    );
    g.fillStyle(Phaser.Display.Color.GetColor(color.r, color.g, color.b), 0.9);
    g.fillCircle(sunX, sunY, sunR * (1 - t * 0.96));
  }
  // The glow around it.
  for (let i = 1; i <= 6; i++) {
    g.fillStyle(SUN, 0.035);
    g.fillCircle(sunX, sunY, sunR + i * 22);
  }
  g.fillStyle(0x07070f, 1);
  for (let i = 0; i < 9; i++) {
    const y = sunY + 8 + i * (10 + i * 2.2);
    g.fillRect(sunX - sunR - 2, y, sunR * 2 + 4, 3 + i * 1.3);
  }
  // Below the horizon: the floor, then the grid.
  g.fillStyle(0x07070f, 1);
  g.fillRect(0, horizonY, width, height - horizonY);
  g.lineStyle(2, NEON, 0.7);
  g.lineBetween(0, horizonY, width, horizonY);
  g.lineStyle(1, SUN, 0.35);
  for (let i = -16; i <= 16; i++) {
    const xBottom = width / 2 + i * 120;
    g.lineBetween(width / 2 + i * 6, horizonY, xBottom, height);
  }
  for (let i = 1; i <= 12; i++) {
    const t = i / 12;
    const y = horizonY + (height - horizonY) * t * t;
    g.lineStyle(1, SUN, 0.2 + t * 0.4);
    g.lineBetween(0, y, width, y);
  }
  // A haze over the horizon, so the grid fades into it.
  for (let i = 0; i < 6; i++) {
    g.fillStyle(0x07070f, 0.22);
    g.fillRect(0, horizonY + 1, width, 20 - i * 3);
  }
}

/** Thin dark lines every third row: the screen's scanlines, over everything. */
export function drawScanlines(scene: Phaser.Scene, alpha = 0.12): Phaser.GameObjects.Graphics {
  const { width, height } = scene.scale;
  const g = scene.add.graphics();
  g.fillStyle(0x000000, alpha);
  for (let y = 0; y < height; y += 3) g.fillRect(0, y, width, 1);
  g.setDepth(1000);
  return g;
}
