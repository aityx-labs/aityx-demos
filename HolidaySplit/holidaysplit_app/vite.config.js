// The app's build and dev server. The index server (Index/bin/server.dart,
// port 8800) serves the build, build/web/, at /demos/holidaysplit/, beside
// the demos page (the key) and its dev proxy (/demos/aityx/). `npm run dev`
// serves the sources on 18811 and proxies the rest of /demos/ to the index,
// so the key and the dev proxy work the same way in development.
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { defineConfig } from 'vitest/config';

const here = fileURLToPath(new URL('.', import.meta.url));
// The shared package, linked from node_modules to its real folder outside
// this one: Vite must be allowed to serve files from there.
const aityxJs = fileURLToPath(new URL('../../packages/aityx_js', import.meta.url));
const read = (name) => readFileSync(new URL(`../${name}`, import.meta.url), 'utf8').trim();
// X.Y.Z: X and Y from version.X.txt and version.Y.txt, Z the build time
// (UTC, yyyymmddHHMM), as the Flutter demos' scripts/version.sh makes it.
const z = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 12);
const version = process.env.VERSION ?? `${read('version.X.txt')}.${read('version.Y.txt')}.${z}`;

export default defineConfig({
  base: '/demos/holidaysplit/',
  define: { __APP_VERSION__: JSON.stringify(version) },
  server: {
    port: 18811,
    strictPort: true,
    proxy: {
      '^/demos/(?!holidaysplit/)': `http://localhost:${process.env.INDEX_PORT ?? 8800}`,
    },
    fs: { allow: [here, aityxJs] },
  },
  build: {
    outDir: 'build/web',
    emptyOutDir: true,
    // The recorded aityx calls are about 300 KB of JSON: expected.
    chunkSizeWarningLimit: 1024,
  },
  test: {
    environment: 'node',
    include: ['test/**/*.test.js'],
  },
});
