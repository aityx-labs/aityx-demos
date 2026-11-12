// The app's build and dev server. The app is served under /tatyx/ by the
// tatyx server (tatyx_server/server.mjs, port 9710), which also
// answers /api/ and the relay to its aityx at /aityx/; `npm run dev`
// serves the sources on 9711 and proxies those two paths to the server,
// so the key and the relay work the same way in development.
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vitest/config';

const here = fileURLToPath(new URL('.', import.meta.url));
// The shared package, linked from node_modules to its real folder outside
// this one: Vite must be allowed to serve files from there.
const aityxJs = fileURLToPath(new URL('../../packages/aityx_js', import.meta.url));

export default defineConfig({
  base: '/tatyx/',
  server: {
    port: 9711,
    strictPort: true,
    proxy: {
      '/api': 'http://localhost:9710',
      '/aityx': 'http://localhost:9710',
    },
    fs: { allow: [here, aityxJs] },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // Phaser alone is over a megabyte: expected, not a warning.
    chunkSizeWarningLimit: 2048,
  },
  test: {
    environment: 'node',
    include: ['test/**/*.test.ts'],
  },
});
