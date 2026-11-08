// The leaderboard's runner, bundled for Node: src/game/runner.ts and the
// game it plays (the world, the strategies, the tournament; no Phaser,
// no DOM) into dist-runner/runner.mjs, one file the server imports.
import { defineConfig } from 'vite';

export default defineConfig({
  // The portraits and the favicon are the app's, not the runner's.
  publicDir: false,
  build: {
    ssr: 'src/game/runner.ts',
    outDir: 'dist-runner',
    emptyOutDir: true,
    target: 'node22',
    rolldownOptions: { output: { entryFileNames: 'runner.mjs' } },
  },
});
