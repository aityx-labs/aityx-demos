// The map: the mainframe in the middle, the three sectors in a triangle
// around it, each with its team's origin and squad, the sites between
// them and the links the Explorers find and the Combinators make. Tron's
// look: a neon hexagonal grid on black, glowing lines, scanlines. The match plays
// itself (game/play.ts): the world ticks, the bots move, the links rot
// and are renewed, and every megabyte a team collects is a question to
// its strategy on aityx, shown in the calls panel. The scene draws what
// it finds, each frame.
import Phaser from 'phaser';

import { AityxClient } from 'aityx-js';

import { aityxDecider } from '../game/aityx';
import { bot, textureOf, type BotId } from '../game/bots';
import { lineup } from '../game/lineup';
import { Match } from '../game/play';
import { SYSTEM, TEAMS, team, type TeamId } from '../game/teams';
import {
  MAINFRAME_ID,
  MAP,
  MB,
  SECTOR_ANGLES,
  botsAt,
  fmtBytes,
  hackedPct,
  knowsLink,
  knowsNode,
  onRing,
  originAt,
  spent,
  type BotState,
  type Node,
  type Point,
  type World,
} from '../game/world';
import { aityxOptions, auth } from '../ui/auth';
import type { PlayState, Shell } from '../ui/shell';
import { button, drawScanlines, FONT, NEON, ORANGE, PALETTE, setButtonEnabled } from './look';

const RAD = Math.PI / 180;

/** Where each sector's name goes: a far corner of it, clear of everything else. */
const SECTOR_LABELS: Readonly<Record<TeamId, { at: Point; originX: number }>> = {
  cyan: { at: { x: 24, y: 66 }, originX: 0 },
  magenta: { at: { x: 1256, y: 690 }, originX: 1 },
  green: { at: { x: 24, y: 690 }, originX: 0 },
};

/** A site's hexagon until it is found; found, it shows its size (siteRadius). */
const SITE_RADIUS = 21;
const BOT_SIZE = 34;
/** The background grid's cells: hexagons of this radius, about as wide as the old square grid's 40 px. */
const GRID_HEX = 23;

/** Plain points as the Vector2s Phaser 4's Graphics ask for. */
const vec = (points: readonly Point[]): Phaser.Math.Vector2[] => points.map((p) => new Phaser.Math.Vector2(p.x, p.y));

/** A found site's hexagon: the bigger the site, the bigger the hexagon. */
const siteRadius = (s: Node): number => 13 + 1.5 * (s.capacity / MB);

/** Megabytes with one decimal, the unit left to the caller. */
const mb = (n: number): string => (n / MB).toFixed(1);

interface BotView {
  sprite: Phaser.GameObjects.Image;
  ring: Phaser.GameObjects.Graphics;
  label: Phaser.GameObjects.Text;
}

export class MapScene extends Phaser.Scene {
  private match!: Match;
  private core!: Phaser.GameObjects.Graphics;
  private linksLayer!: Phaser.GameObjects.Graphics;
  private hud = new Map<string, Phaser.GameObjects.Text>();
  /** Each site as drawn, with a signature of the state it was drawn for. */
  private siteViews = new Map<string, { g: Phaser.GameObjects.Graphics; label: Phaser.GameObjects.Text; signature: string }>();
  private botViews = new Map<string, BotView>();
  private banner: Phaser.GameObjects.Container | null = null;
  private overlay: Phaser.GameObjects.Container | null = null;
  private shell!: Shell;
  private state: Exclude<PlayState, null> = 'ready';
  /** Which match the calls panel shows: a late answer of an earlier one is dropped. */
  private matchNumber = 0;

  constructor() {
    super('map');
  }

  create(): void {
    const shell = (this.shell = this.registry.get('shell') as Shell);
    const client = new AityxClient(aityxOptions);
    const number = ++this.matchNumber;
    this.match = new Match(
      aityxDecider(client, (call) => {
        if (number === this.matchNumber) shell.showCall(call);
      }),
      lineup(),
    );
    this.overlay = null;
    this.setState('ready');
    shell.controls.onPlay(() => this.toggle());
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => {
      this.matchNumber += 1;
      shell.controls.onPlay(null);
      shell.controls.show(null);
    });
    this.siteViews.clear();
    this.botViews.clear();
    this.hud.clear();
    this.banner = null;
    this.drawGrid();
    this.drawSectors();
    this.linksLayer = this.add.graphics().setDepth(2);
    for (const n of this.match.world.nodes) {
      if (n.kind === 'site') this.drawSite(n, this.match.world);
      else if (n.kind === 'origin') this.drawOrigin(n.team!, n.at);
    }
    this.drawMainframe();
    this.drawHud();
    drawScanlines(this, 0.1);
    this.showAll();
    this.drawStart();
  }

  override update(_time: number, delta: number): void {
    if (this.state === 'running') this.match.advance((Math.min(delta, 250) / 1000) * this.shell.controls.speed);
    this.core.setRotation(this.match.world.tick * 0.004);
    this.showAll();
    if (this.match.world.winner !== null && this.state !== 'over') this.setState('over');
  }

  private setState(state: Exclude<PlayState, null>): void {
    this.state = state;
    this.shell.controls.show(state);
    this.hud.get('paused')?.setVisible(state === 'paused');
  }

  /** Start, Pause, Resume, Play again: the bar's button, the overlay's, or Space. */
  private toggle(): void {
    switch (this.state) {
      case 'ready':
        if (auth.player === null || !this.shell.hasKey()) {
          this.shell.openTab('profile');
          this.hud.get('hint')?.setText(auth.player === null ? 'Sign in to play: see Profile, in the sidebar.' : 'No aityx key to play on: set yours in Profile.');
          return;
        }
        this.overlay?.destroy();
        this.overlay = null;
        this.shell.clearCalls();
        this.shell.openTab('calls');
        this.setState('running');
        return;
      case 'running':
        this.setState('paused');
        return;
      case 'paused':
        this.setState('running');
        return;
      case 'over':
        this.scene.restart();
    }
  }

  /** Before the match: the lineup, and Start. */
  private drawStart(): void {
    const { width, height } = this.scale;
    const box = this.add.graphics();
    box.fillStyle(0x07070f, 0.88);
    box.fillRoundedRect(-280, -100, 560, 200, 16);
    box.lineStyle(1, NEON, 0.4);
    box.strokeRoundedRect(-280, -100, 560, 200, 16);
    const items: Phaser.GameObjects.GameObject[] = [box];
    items.push(
      this.add
        .text(0, -74, 'THE MATCH', { fontFamily: FONT, fontSize: '13px', fontStyle: 'bold', color: PALETTE.neon, letterSpacing: 4 })
        .setOrigin(0.5),
    );
    TEAMS.forEach((t, i) => {
      items.push(
        this.add
          .text(0, -42 + i * 24, `${t.name} plays ${this.match.strategyOf(t.id).name}`, { fontFamily: FONT, fontSize: '15px', color: t.css })
          .setOrigin(0.5),
      );
    });
    const start = button(this, 0, 60, 'Start', () => this.toggle(), { width: 160, height: 40, size: 16 });
    items.push(start);
    this.overlay = this.add.container(width / 2, height / 2 - 10, items).setDepth(45);
    // Off without a key to play on.
    const showStart = () => setButtonEnabled(start, this.shell.hasKey());
    showStart();
    const off = this.shell.onKeyChange(showStart);
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, off);
    start.once(Phaser.GameObjects.Events.DESTROY, off);
  }

  /** Everything that changes: the links, the sites, the bots, the HUD, the end. */
  private showAll(): void {
    const w = this.match.world;
    this.drawLinks(w);
    for (const n of w.nodes) if (n.kind === 'site') this.drawSite(n, w);
    this.drawBots(w);
    this.showHud(w);
    if (w.winner !== null && this.banner === null) this.showWinner(w.winner);
  }

  /**
   * The neon grid over black, hexagonal as the sites (pointy-top cells,
   * odd rows half a cell over), every fifth cell of every other row
   * brighter, and the glow around the mainframe.
   */
  private drawGrid(): void {
    const { width, height } = this.scale;
    const g = this.add.graphics();
    g.fillStyle(0x07070f, 1);
    g.fillRect(0, 0, width, height);
    const r = GRID_HEX;
    const across = Math.sqrt(3) * r;
    const down = 1.5 * r;
    // One cell past every edge, so the cells there are whole; each cell draws
    // its left and two top edges only, so no edge is drawn twice.
    for (let row = -1; row <= Math.ceil(height / down) + 1; row++) {
      for (let col = -1; col <= Math.ceil(width / across) + 1; col++) {
        // hexagon()'s corners: upper right, lower right, bottom, lower left, upper left, top.
        const [upperRight, , , lowerLeft, upperLeft, top] = hexagon(col * across + (row & 1 ? across / 2 : 0), row * down, r);
        g.lineStyle(1, NEON, row % 2 === 0 && col % 5 === 0 ? 0.16 : 0.06);
        g.lineBetween(lowerLeft!.x, lowerLeft!.y, upperLeft!.x, upperLeft!.y);
        g.lineBetween(upperLeft!.x, upperLeft!.y, top!.x, top!.y);
        g.lineBetween(top!.x, top!.y, upperRight!.x, upperRight!.y);
      }
    }
    for (let i = 8; i >= 1; i--) {
      g.fillStyle(ORANGE, 0.03);
      g.fillCircle(MAP.center.x, MAP.center.y, 60 + i * 26);
    }
  }

  /** The three sectors: a wedge of the map per team, tinted with its tag, its edges drawn, its name in a corner. */
  private drawSectors(): void {
    const g = this.add.graphics();
    const far = 1100;
    for (const t of TEAMS) {
      const middle = SECTOR_ANGLES[t.id];
      const points: Point[] = [MAP.center];
      for (let a = middle - 60; a <= middle + 60; a += 10) {
        points.push({ x: MAP.center.x + far * Math.cos(a * RAD), y: MAP.center.y + far * Math.sin(a * RAD) });
      }
      g.fillStyle(t.color, 0.045);
      g.fillPoints(vec(points), true);
      const edge = (middle + 60) * RAD;
      g.lineStyle(2, t.color, 0.35);
      g.lineBetween(MAP.center.x, MAP.center.y, MAP.center.x + far * Math.cos(edge), MAP.center.y + far * Math.sin(edge));
      const label = SECTOR_LABELS[t.id];
      this.add
        .text(label.at.x, label.at.y, `${t.name.toUpperCase()} SECTOR`, { fontFamily: FONT, fontSize: '12px', color: t.css, letterSpacing: 3 })
        .setOrigin(label.originX, 0.5)
        .setAlpha(0.7);
    }
    g.lineStyle(1, NEON, 0.18);
    g.strokeEllipse(MAP.center.x, MAP.center.y, MAP.rx * 2, MAP.ry * 2);
    const corners = TEAMS.map((t) => onRing(SECTOR_ANGLES[t.id]));
    g.lineStyle(1, NEON, 0.2);
    g.strokePoints(vec(corners), true, true);
  }

  /**
   * The live links, each frame: an ivory line between two nodes that
   * fades as the link rots (a shortcut in the colour of the team that
   * made it), and, for every team that knows the link, a thin line in
   * that team's colour beside it.
   */
  private drawLinks(w: World): void {
    const g = this.linksLayer;
    g.clear();
    for (const l of w.links) {
      const from = w.nodes.find((n) => n.id === l.a)!.at;
      const to = w.nodes.find((n) => n.id === l.b)!.at;
      const life = l.health / 100;
      const color = l.by === null ? 0xf2e9dc : team(l.by).color;
      g.lineStyle(l.by === null ? 2 : 3, color, 0.1 + 0.55 * life);
      g.lineBetween(from.x, from.y, to.x, to.y);
      const length = Math.hypot(to.x - from.x, to.y - from.y) || 1;
      const nx = -(to.y - from.y) / length;
      const ny = (to.x - from.x) / length;
      const knowers = w.teams.filter((t) => knowsLink(t, l.id));
      knowers.forEach((t, i) => {
        const offset = (i - (knowers.length - 1) / 2) * 4 + (l.by === null ? 0 : 5);
        g.lineStyle(1.5, team(t.id).color, 0.35 + 0.5 * life);
        g.lineBetween(from.x + nx * offset, from.y + ny * offset, to.x + nx * offset, to.y + ny * offset);
      });
    }
  }

  /**
   * A site: a hexagon with a diamond inside and its bytes under it. Dim and
   * nameless until a team finds it; orange, the computer's, once found,
   * as big as the site is, with what it has built over its size under it,
   * a thin hexagon around it for every team that knows it, filled in a
   * team's colour while that team's Anchor holds it; dim again once spent.
   * Drawn again whenever any of that changes.
   */
  private drawSite(s: Node, w: World): void {
    const knowers = w.teams.filter((t) => knowsNode(t, s.id)).map((t) => t.id);
    const holders = botsAt(w, s.id).filter((b) => b.kind === 'anchor').map((b) => b.team);
    const signature = `${Math.round(s.bytes / 1024)}|${knowers.join()}|${holders.join()}`;
    const known = this.siteViews.get(s.id);
    if (known?.signature === signature) return;
    const { x, y } = s.at;
    const found = knowers.length > 0;
    const done = found && spent(s);
    const radius = found ? siteRadius(s) : SITE_RADIUS;
    const g = known?.g ?? this.add.graphics().setDepth(4);
    const label =
      known?.label ??
      this.add
        .text(x, y, '', { fontFamily: FONT, fontSize: '10px', letterSpacing: 1 })
        .setOrigin(0.5, 0)
        .setDepth(4);
    label.setPosition(x, y + radius + 4);
    g.clear();
    const owner = found && !done ? SYSTEM : { color: 0x5a5a66, css: '#5A5A66' };
    const fill = holders.length === 1 ? team(holders[0]!).color : null;
    if (found) {
      for (let i = 2; i >= 1; i--) {
        g.fillStyle(fill ?? owner.color, 0.06);
        g.fillPoints(hexagon(x, y, radius + i * 6), true);
      }
    }
    const tile = hexagon(x, y, radius);
    g.fillStyle(fill ?? 0x07070f, fill === null ? 1 : 0.28);
    if (fill !== null) {
      g.fillStyle(0x07070f, 1);
      g.fillPoints(tile, true);
      g.fillStyle(fill, 0.28);
    }
    g.fillPoints(tile, true);
    g.lineStyle(2, fill ?? owner.color, found && !done ? 0.95 : 0.5);
    g.strokePoints(tile, true, true);
    knowers.forEach((id, i) => {
      g.lineStyle(1.5, team(id).color, done ? 0.35 : 0.8);
      g.strokePoints(hexagon(x, y, radius + 3 + i * 3), true, true);
    });
    const size = 3 + 3 * s.richness;
    g.fillStyle(found && !done ? ORANGE : owner.color, found && !done ? 0.95 : 0.5);
    g.fillPoints(diamond(x, y, size), true);
    const text = !found ? '?' : done ? `×${s.richness} · spent · ${mb(s.capacity)} MB` : `×${s.richness} · ${mb(s.bytes)}/${mb(s.capacity)} MB`;
    label.setText(text).setColor(fill === null ? owner.css : team(holders[0]!).css);
    if (known === undefined) {
      this.tweens.add({ targets: g, alpha: 0.7, duration: 1100 + (x % 5) * 110, yoyo: true, repeat: -1, ease: 'Sine.easeInOut' });
    }
    this.siteViews.set(s.id, { g, label, signature });
  }

  /** The mainframe: a hexagonal core in orange with two counter-rotating rings, its name and each team's progress into the hack over it, in its colour. */
  private drawMainframe(): void {
    const { x, y } = MAP.center;
    const still = this.add.graphics().setDepth(10);
    for (let i = 3; i >= 1; i--) {
      still.fillStyle(ORANGE, 0.08);
      still.fillCircle(x, y, 36 + i * 9);
    }
    still.fillStyle(0x07070f, 1);
    still.fillPoints(hexagon(x, y, 34), true);
    still.lineStyle(3, ORANGE, 1);
    still.strokePoints(hexagon(x, y, 34), true, true);
    still.lineStyle(1, ORANGE, 0.6);
    still.strokePoints(hexagon(x, y, 20), true, true);
    still.fillStyle(ORANGE, 1);
    still.fillCircle(x, y, 5);
    this.core = this.add.graphics({ x, y }).setDepth(10);
    this.core.lineStyle(2, ORANGE, 0.8);
    for (let i = 0; i < 6; i++) {
      const a0 = i * 60 * RAD;
      this.core.beginPath();
      this.core.arc(0, 0, 50, a0, a0 + 38 * RAD, false);
      this.core.strokePath();
    }
    this.core.lineStyle(1, ORANGE, 0.5);
    for (let i = 0; i < 3; i++) {
      const a0 = (i * 120 + 20) * RAD;
      this.core.beginPath();
      this.core.arc(0, 0, 62, a0, a0 + 80 * RAD, false);
      this.core.strokePath();
    }
    this.add
      .text(x, y - 112, 'MAINFRAME', { fontFamily: FONT, fontSize: '13px', fontStyle: 'bold', color: PALETTE.orange, letterSpacing: 4 })
      .setOrigin(0.5)
      .setDepth(10)
      .setShadow(0, 0, PALETTE.orange, 8, false, true);
    TEAMS.forEach((t, i) => {
      this.hud.set(
        `hack-${t.id}`,
        this.add
          .text(x + (i - 1) * 64, y - 94, '', { fontFamily: FONT, fontSize: '12px', fontStyle: 'bold', color: t.css })
          .setOrigin(0.5)
          .setDepth(10),
      );
    });
  }

  /** A team's origin, its database: a hexagon in its colour with another inside, glowing, and its name on the outer side. */
  private drawOrigin(id: TeamId, at: Point): void {
    const t = team(id);
    const g = this.add.graphics().setDepth(5);
    for (let i = 3; i >= 1; i--) {
      g.fillStyle(t.color, 0.06);
      g.fillPoints(hexagon(at.x, at.y, 28 + i * 8), true);
    }
    const outer = hexagon(at.x, at.y, 26);
    g.fillStyle(0x07070f, 1);
    g.fillPoints(outer, true);
    g.fillStyle(t.color, 0.25);
    g.fillPoints(outer, true);
    g.lineStyle(2.5, t.color, 1);
    g.strokePoints(outer, true, true);
    g.lineStyle(1.5, t.color, 0.7);
    g.strokePoints(hexagon(at.x, at.y, 14), true, true);
    g.fillStyle(t.color, 1);
    g.fillCircle(at.x, at.y, 3);
    // The label: to the right of the top origin, under the HUD; under the lower ones.
    const top = at.y < MAP.center.y;
    this.add
      .text(top ? at.x + 40 : at.x, top ? at.y : at.y + 34, t.name.toUpperCase(), { fontFamily: FONT, fontSize: '11px', fontStyle: 'bold', color: t.css, letterSpacing: 2 })
      .setOrigin(top ? 0 : 0.5, top ? 0.5 : 0)
      .setDepth(5);
  }

  /**
   * The bots, each frame: a portrait in its team's colours over a ring
   * in that colour, with its letter under it, where the world has it;
   * the ones standing at the same node spread around it. A bot bought
   * during the match gets its view when it first appears.
   */
  private drawBots(w: World): void {
    const seen = new Set<string>();
    const standing = new Map<string, BotState[]>();
    for (const b of w.bots) {
      if (b.node !== null && b.travel === null) {
        const list = standing.get(b.node) ?? [];
        list.push(b);
        standing.set(b.node, list);
      }
    }
    for (const b of w.bots) {
      seen.add(b.uid);
      let view = this.botViews.get(b.uid);
      if (view === undefined) {
        view = this.newBotView(b);
        this.botViews.set(b.uid, view);
      }
      let { x, y } = b.at;
      const group = b.node !== null && b.travel === null ? standing.get(b.node)! : null;
      if (group !== null && group.length > 1) {
        const i = group.indexOf(b);
        const a = (i / group.length) * Math.PI * 2 - Math.PI / 2;
        const at = w.nodes.find((n) => n.id === b.node)!;
        const r = b.node === MAINFRAME_ID ? 74 : (at.kind === 'site' ? siteRadius(at) : SITE_RADIUS) + 8 + Math.min(12, group.length * 2);
        x += r * Math.cos(a);
        y += r * Math.sin(a);
      } else if (group !== null && b.node === MAINFRAME_ID) {
        y -= 74;
      }
      view.sprite.setPosition(x, y - 3);
      view.ring.setPosition(x, y);
      view.label.setPosition(x, y + 15);
      const busy = b.travel !== null || (b.kind === 'explorer' && b.target !== null);
      view.sprite.setAlpha(busy ? 1 : 0.92);
    }
    for (const [uid, view] of this.botViews) {
      if (seen.has(uid)) continue;
      view.sprite.destroy();
      view.ring.destroy();
      view.label.destroy();
      this.botViews.delete(uid);
    }
  }

  private newBotView(b: BotState): BotView {
    const t = team(b.team);
    const ring = this.add.graphics().setDepth(6);
    ring.fillStyle(t.color, 0.22);
    ring.fillEllipse(0, 11, 28, 9);
    ring.lineStyle(2, t.color, 0.95);
    ring.strokeEllipse(0, 11, 28, 9);
    const sprite = this.add.image(b.at.x, b.at.y, textureOf(b.id as BotId, b.team)).setDisplaySize(BOT_SIZE, BOT_SIZE).setDepth(7);
    const label = this.add
      .text(b.at.x, b.at.y + 15, b.id, { fontFamily: FONT, fontSize: '9px', fontStyle: 'bold', color: t.css })
      .setOrigin(0.5, 0)
      .setDepth(7);
    sprite.setInteractive({ useHandCursor: true });
    sprite.on('pointerover', () => {
      const sent = this.match.world.bots.find((o) => o.uid === b.uid)?.hacker === true;
      const part = sent ? 'Sent to the mainframe: builds the hack there for the rest of the match.' : bot(b.id).part;
      this.hud.get('hint')?.setText(`${b.id} · ${bot(b.id).name} · ${t.name} team · ${part}`);
    });
    sprite.on('pointerout', () => this.hud.get('hint')?.setText(''));
    return { sprite, ring, label };
  }

  /** The HUD: a chip per team along the top (its strategy, bytes, bots and progress), the clock, the legend and the hint line along the bottom. */
  private drawHud(): void {
    const { width, height } = this.scale;
    const bar = this.add.graphics().setDepth(30);
    bar.fillStyle(0x07070f, 0.85);
    bar.fillRect(0, 0, width, 46);
    bar.lineStyle(1, NEON, 0.3);
    bar.lineBetween(0, 46, width, 46);
    this.add
      .text(20, 23, 'HACK THE MAINFRAME', { fontFamily: FONT, fontSize: '13px', fontStyle: 'bold', color: PALETTE.orange, letterSpacing: 3 })
      .setOrigin(0, 0.5)
      .setDepth(31);
    TEAMS.forEach((t, i) => {
      const x = 236 + i * 285;
      const chip = this.add.graphics().setDepth(31);
      chip.fillStyle(t.color, 1);
      chip.fillCircle(x, 23, 5);
      this.hud.set(
        `top-${t.id}`,
        this.add.text(x + 12, 23, '', { fontFamily: FONT, fontSize: '12px', color: t.css }).setOrigin(0, 0.5).setDepth(31),
      );
    });
    this.hud.set(
      'paused',
      this.add
        .text(width / 2, 70, 'PAUSED · click a call in the sidebar to read it', { fontFamily: FONT, fontSize: '13px', fontStyle: 'bold', color: PALETTE.orange, letterSpacing: 2 })
        .setOrigin(0.5)
        .setDepth(31)
        .setVisible(false),
    );
    this.hud.set(
      'clock',
      this.add.text(width - 140, 23, '', { fontFamily: FONT, fontSize: '12px', color: PALETTE.muted }).setOrigin(1, 0.5).setDepth(31),
    );
    button(this, width - 76, 23, 'Title', () => this.scene.start('title'), { width: 110, height: 32, size: 13 }).setDepth(31);
    const legend = this.add.graphics().setDepth(31);
    const entries = [
      ...TEAMS.map((t) => ({ color: t.color, css: t.css, label: `${t.name} team` })),
      { color: SYSTEM.color, css: SYSTEM.css, label: `${SYSTEM.name}'s: the mainframe, and the sites nobody holds` },
      { color: 0xf2e9dc, css: '#F2E9DC', label: 'a link, fading as it rots' },
    ];
    let x = width / 2 - 400;
    this.add.text(x, height - 16, 'TAGS', { fontFamily: FONT, fontSize: '10px', color: PALETTE.muted, letterSpacing: 2 }).setOrigin(0, 0.5).setDepth(31);
    x += 44;
    for (const e of entries) {
      legend.fillStyle(e.color, 1);
      legend.fillCircle(x, height - 16, 4);
      const text = this.add.text(x + 10, height - 16, e.label, { fontFamily: FONT, fontSize: '11px', color: e.css }).setOrigin(0, 0.5).setDepth(31);
      x += text.width + 24;
    }
    this.hud.set(
      'hint',
      this.add.text(width / 2, height - 38, '', { fontFamily: FONT, fontSize: '12px', color: PALETTE.muted }).setOrigin(0.5).setDepth(31),
    );
  }

  private showHud(w: World): void {
    for (const t of TEAMS) {
      const state = w.teams.find((s) => s.id === t.id)!;
      const bots = w.bots.filter((b) => b.team === t.id).length;
      const pct = Math.round(hackedPct(w, t.id));
      this.hud.get(`top-${t.id}`)?.setText(`${t.name} · ${this.match.strategyOf(t.id).name.replace(/^The /, '')} · ${fmtBytes(state.bytes)} · ${bots} bots · ${pct}%`);
      this.hud.get(`hack-${t.id}`)?.setText(`${pct}%`);
    }
    this.hud.get('clock')?.setText(`${Math.floor(w.seconds / 60)}:${String(Math.floor(w.seconds % 60)).padStart(2, '0')}`);
  }

  /** The end: the winner's name across the map, and a way to play again. */
  private showWinner(id: TeamId): void {
    const t = team(id);
    const { width, height } = this.scale;
    const box = this.add.graphics();
    box.fillStyle(0x07070f, 0.86);
    box.fillRoundedRect(-300, -70, 600, 140, 16);
    box.lineStyle(2, t.color, 0.9);
    box.strokeRoundedRect(-300, -70, 600, 140, 16);
    const text = this.add
      .text(0, -26, `${t.name.toUpperCase()} HACKED THE MAINFRAME`, { fontFamily: FONT, fontSize: '24px', fontStyle: 'bold', color: t.css, letterSpacing: 4 })
      .setOrigin(0.5)
      .setShadow(0, 0, t.css, 14, false, true);
    const line = this.add
      .text(0, 8, `${this.match.strategyOf(id).name} · ${Math.round(this.match.world.seconds)} s · ${this.match.made.length} decisions on aityx`, {
        fontFamily: FONT,
        fontSize: '13px',
        color: PALETTE.muted,
        letterSpacing: 1,
      })
      .setOrigin(0.5);
    const again = button(this, 0, 44, 'Play again', () => this.scene.restart(), { width: 150, height: 34, size: 14 });
    this.setState('over');
    this.banner = this.add.container(width / 2, height / 2, [box, text, line, again]).setDepth(40);
  }
}

function hexagon(x: number, y: number, r: number): Phaser.Math.Vector2[] {
  return vec([0, 1, 2, 3, 4, 5].map((i) => ({ x: x + r * Math.cos((i * 60 - 30) * RAD), y: y + r * Math.sin((i * 60 - 30) * RAD) })));
}

function diamond(x: number, y: number, r: number): Phaser.Math.Vector2[] {
  return vec([
    { x, y: y - r },
    { x: x + r, y },
    { x, y: y + r },
    { x: x - r, y },
  ]);
}
