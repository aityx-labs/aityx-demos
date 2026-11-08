// Boot: loads the portraits (the orange originals and each team's) with
// a bar, then the title (or the map, with #map on the URL).
import Phaser from 'phaser';

import { BOTS, portraitOf, textureOf } from '../game/bots';
import { TEAMS } from '../game/teams';

export class BootScene extends Phaser.Scene {
  constructor() {
    super('boot');
  }

  preload(): void {
    const { width, height } = this.scale;
    const bar = this.add.graphics();
    const text = this.add
      .text(width / 2, height / 2 - 30, 'loading the bots…', {
        fontFamily: 'system-ui, sans-serif',
        fontSize: '18px',
        color: '#A9ACB6',
      })
      .setOrigin(0.5);
    this.load.on('progress', (value: number) => {
      bar.clear();
      bar.fillStyle(0x2a272e, 1);
      bar.fillRoundedRect(width / 2 - 160, height / 2, 320, 10, 5);
      bar.fillStyle(0xe36742, 1);
      bar.fillRoundedRect(width / 2 - 160, height / 2, 320 * value, 10, 5);
    });
    this.load.on('complete', () => {
      bar.destroy();
      text.destroy();
    });
    // The originals, in orange, for the title; each team's, in its colour, for the map.
    for (const bot of BOTS) {
      this.load.image(textureOf(bot.id), portraitOf(bot));
      for (const t of TEAMS) this.load.image(textureOf(bot.id, t.id), portraitOf(bot, t.id));
    }
  }

  create(): void {
    // /app/#map opens on the map, for development and screenshots.
    this.scene.start(window.location.hash === '#map' ? 'map' : 'title');
  }
}
