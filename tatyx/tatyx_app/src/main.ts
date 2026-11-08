// tatyx: the shell (the bar, the aityx light and key form, the music
// button, the calls panel) around the game, and the game itself, a
// Phaser 4 game with three scenes: boot, the title and the map.
import Phaser from 'phaser';

import './style.css';
import { BootScene } from './scenes/boot';
import { MapScene } from './scenes/map';
import { TitleScene } from './scenes/title';
import { mountShell } from './ui/shell';

const shell = mountShell(document.getElementById('shell')!);

/** The stage: 16:9, scaled to fit the game pane, letterboxed. */
export const STAGE = { width: 1280, height: 720 } as const;

export const game = new Phaser.Game({
  type: Phaser.AUTO,
  parent: shell.game,
  width: STAGE.width,
  height: STAGE.height,
  backgroundColor: '#07070F',
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
  },
  scene: [BootScene, TitleScene, MapScene],
});

// The scenes reach the shell (the calls panel) through the registry.
game.registry.set('shell', shell);
