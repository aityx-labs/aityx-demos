// The title: the synthwave sun setting behind the grid, the five bots in
// a row over it, each with its letter, name and part; under them, a card
// per team with its strategy: a preset to pick (◀ ▶), or the team's own,
// uploaded as JSON, and any of them downloaded to edit. Play leads to the
// map, and starts the music (the user's act the browser asks for); it
// asks to sign in first.
import Phaser from 'phaser';

import { synthwave } from '../audio/synthwave';
import { BOTS, type Bot } from '../game/bots';
import { BadStrategy, cyclePreset, isOwn, lineup, parseStrategy, setStrategy, strategyFile } from '../game/lineup';
import { TEAMS, type Team } from '../game/teams';
import { auth } from '../ui/auth';
import { enterInTour } from '../ui/tour';
import type { Shell } from '../ui/shell';
import { button, drawScanlines, drawSynthwave, FONT, PALETTE, setButtonEnabled } from './look';

interface CardView {
  name: Phaser.GameObjects.Text;
  tagline: Phaser.GameObjects.Text;
  status: Phaser.GameObjects.Text;
}

export class TitleScene extends Phaser.Scene {
  private cards = new Map<string, CardView>();
  private playLabel: Phaser.GameObjects.Text | null = null;

  constructor() {
    super('title');
  }

  create(): void {
    const { width, height } = this.scale;
    const shell = this.registry.get('shell') as Shell;
    shell.controls.show(null);
    drawSynthwave(this, 540);

    this.add
      .text(width / 2, 50, 'tatyx', { fontFamily: FONT, fontSize: '56px', fontStyle: 'bold', color: PALETTE.orangeLight })
      .setOrigin(0.5)
      .setShadow(0, 0, PALETTE.orange, 18, false, true);
    this.add
      .text(width / 2, 94, 'BUILD THE SITES, HACK THE MAINFRAME', {
        fontFamily: FONT,
        fontSize: '14px',
        color: PALETTE.fg,
        letterSpacing: 3,
      })
      .setOrigin(0.5)
      .setShadow(0, 0, PALETTE.sun, 10, false, true);

    const gap = width / (BOTS.length + 1);
    BOTS.forEach((bot, i) => this.roster(bot, gap * (i + 1), 170, i));

    this.cards.clear();
    TEAMS.forEach((t, i) => this.teamCard(t, width / 2 + (i - 1) * 404, 470));

    const play = button(this, width / 2, height - 46, 'Play', () => {
      if (auth.player === null) {
        shell.openTab('profile');
        return;
      }
      synthwave.start();
      this.scene.start('map');
    });
    this.playLabel = play.list[1] as Phaser.GameObjects.Text;
    // Off without a key to play on.
    const showPlay = () => {
      this.playLabel?.setText(auth.player === null ? 'Sign in to play' : 'Play');
      setButtonEnabled(play, shell.hasKey());
    };
    showPlay();
    const off = shell.onKeyChange(showPlay);
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, off);

    drawScanlines(this, 0.1);
  }

  /** One bot: its portrait, bobbing; under it the letter, the name on the line below, and the part. */
  private roster(bot: Bot, x: number, y: number, i: number): void {
    const portrait = this.add.image(x, y, `bot-${bot.id}`).setDisplaySize(96, 96);
    this.tweens.add({ targets: portrait, y: y - 6, duration: 1600 + i * 120, yoyo: true, repeat: -1, ease: 'Sine.easeInOut', delay: i * 150 });
    this.add
      .text(x, y + 62, bot.id, { fontFamily: FONT, fontSize: '20px', fontStyle: 'bold', color: PALETTE.orange })
      .setOrigin(0.5)
      .setShadow(0, 0, PALETTE.orange, 10, false, true);
    this.add
      .text(x, y + 84, bot.name.toUpperCase(), { fontFamily: FONT, fontSize: '13px', fontStyle: 'bold', color: PALETTE.fg, letterSpacing: 2 })
      .setOrigin(0.5);
    this.add
      .text(x, y + 98, bot.motto, { fontFamily: FONT, fontSize: '11.5px', color: PALETTE.muted, align: 'center', wordWrap: { width: 196 }, lineSpacing: 2 })
      .setOrigin(0.5, 0);
  }

  /** A team's card: its strategy, ◀ ▶ through the presets, Download, Upload. */
  private teamCard(t: Team, x: number, y: number): void {
    const w = 384;
    const h = 196;
    const card = this.add.graphics();
    card.fillStyle(0x07070f, 0.78);
    card.fillRoundedRect(x - w / 2, y - h / 2, w, h, 14);
    card.lineStyle(1.5, t.color, 0.7);
    card.strokeRoundedRect(x - w / 2, y - h / 2, w, h, 14);
    this.add
      .text(x, y - h / 2 + 18, `${t.name.toUpperCase()} TEAM`, { fontFamily: FONT, fontSize: '13px', fontStyle: 'bold', color: t.css, letterSpacing: 3 })
      .setOrigin(0.5);
    const name = this.add.text(x, y - h / 2 + 46, '', { fontFamily: FONT, fontSize: '17px', fontStyle: 'bold', color: PALETTE.fg }).setOrigin(0.5);
    const arrow = (dx: number, label: string, step: 1 | -1) => {
      const a = this.add
        .text(x + dx, y - h / 2 + 46, label, { fontFamily: FONT, fontSize: '18px', fontStyle: 'bold', color: t.css })
        .setOrigin(0.5)
        .setInteractive({ useHandCursor: true });
      a.on('pointerup', () => {
        cyclePreset(t.id, step);
        this.showCard(t);
      });
    };
    arrow(-w / 2 + 24, '◀', -1);
    arrow(w / 2 - 24, '▶', 1);
    const tagline = this.add
      .text(x, y - h / 2 + 68, '', { fontFamily: FONT, fontSize: '12px', color: PALETTE.muted, align: 'center', wordWrap: { width: w - 40 }, lineSpacing: 2 })
      .setOrigin(0.5, 0);
    const status = this.add.text(x, y + h / 2 - 58, '', { fontFamily: FONT, fontSize: '11.5px', color: PALETTE.muted, align: 'center', wordWrap: { width: w - 30 } }).setOrigin(0.5, 0.5);
    button(this, x - 92, y + h / 2 - 26, 'Download', () => this.download(t), { width: 160, height: 32, size: 13 });
    button(this, x + 92, y + h / 2 - 26, 'Upload', () => void this.upload(t), { width: 160, height: 32, size: 13 });
    this.cards.set(t.id, { name, tagline, status });
    this.showCard(t);
  }

  private showCard(t: Team, message?: { text: string; bad: boolean }): void {
    const view = this.cards.get(t.id);
    if (!view) return;
    const s = lineup()[t.id];
    view.name.setText(s.name);
    view.tagline.setText(s.tagline);
    if (message) view.status.setText(message.text).setColor(message.bad ? '#F0506E' : PALETTE.muted);
    else view.status.setText(isOwn(s) ? 'The team’s own strategy, uploaded.' : 'A preset: ◀ ▶ for another, or upload your own.').setColor(PALETTE.muted);
  }

  /** The team's strategy as a JSON file, to edit and upload. */
  private download(t: Team): void {
    const s = lineup()[t.id];
    const blob = new Blob([strategyFile(s)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `tatyx-${t.id}-${s.id}.json`;
    document.body.append(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  /** A strategy file from the player's disk, checked, as the team's own. */
  private async upload(t: Team): Promise<void> {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json,.json';
    const file = await new Promise<File | null>((resolve) => {
      input.addEventListener('change', () => resolve(input.files?.[0] ?? null), { once: true });
      input.addEventListener('cancel', () => resolve(null), { once: true });
      input.click();
    });
    if (file === null) return;
    try {
      const s = parseStrategy(await file.text());
      setStrategy(t.id, s);
      // Signed in, it goes to the tour too, and the leaderboard plays it.
      if (auth.player === null) this.showCard(t, { text: `${s.name}: uploaded, and checked. Sign in to enter it in the tour.`, bad: false });
      else {
        this.showCard(t, { text: `${s.name}: uploaded, and checked; entering it in the tour…`, bad: false });
        const outcome = await enterInTour(s);
        this.showCard(t, { text: outcome.ok ? `${s.name}: uploaded, and ${outcome.text}.` : `${s.name}: uploaded, but not in the tour: ${outcome.text}.`, bad: !outcome.ok });
      }
    } catch (error) {
      this.showCard(t, { text: error instanceof BadStrategy ? `Not uploaded: ${error.message}.` : 'Not uploaded: the file could not be read.', bad: true });
    }
  }
}
