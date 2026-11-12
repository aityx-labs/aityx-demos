// The index of the multyx group (Poker Tour and tatyx): serves www/ (the
// page) and says which of its demos are up. Plain Node (node:http), no
// packages, so `node bin/server.mjs` runs it. The aityx demos have their
// own index (Index/), and the datyx group its own (datyx-index/).
//
//   GET /, /app/        www/index.html (the page; /app/ so start-all.sh
//                       checks it like a demo)
//   GET /<file>         a file in www/
//   GET /api/health     {"ok": true}
//   GET /api/demos      every folder beside this one with a
//                       process-compose.yaml whose group.id.txt says
//                       INDEX_GROUP (multyx): its web and API ports (the
//                       defaults in that file) and whether its web app
//                       answers right now; for scripts. With INDEX_DEMOS,
//                       exactly the folders it names instead, each with
//                       its URL and whether that answers right now
//   GET /api/settings   {"cluster": false, "ports": {"TATYX_PORT": 9710,
//                       ...}}: where this run publishes each demo, by
//                       the name of its setting below, and whether this
//                       is the local Kubernetes cluster's copy. The page
//                       builds its links, the ports in its text and its
//                       footer from it
//
// Settings: INDEX_PORT (default 9700), INDEX_BIND_HOST (127.0.0.1),
// INDEX_GROUP (multyx), INDEX_DEMOS (unset): <folder>=<URL to check>,
// comma-separated, for where the folders aren't beside this one (an
// image, on Kubernetes: tatyx=http://tatyx:9710/tatyx/,...).
//
// And what /api/settings answers, the ports as a browser reaches them (a
// local run needs none of these; k8s/deployment.yaml sets the cluster's):
// TATYX_PORT (9710), POKERTOUR_WEB_PORT (9810), the other indexes'
// AITYX_INDEX_PORT (8800) and DATYX_INDEX_PORT (9800), and
// INDEX_ON_CLUSTER (false; true or 1 on the cluster).

import { readdir, readFile, stat } from 'node:fs/promises';
import { createServer } from 'node:http';
import { basename, dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const www = join(here, 'www');
const root = resolve(here, '..');
const env = process.env;

/**
 * The port the setting `name` says, `usual` when it's unset or empty.
 * Anything but a whole number from 1 to 65535 stops the server at start:
 * "tcp://10.96.0.12:9710", say, which Kubernetes sets as TATYX_PORT in a
 * pod beside a Service named tatyx unless the pod opts out.
 */
function portSetting(name, usual) {
  const value = (env[name] ?? '').trim();
  if (value === '') return usual;
  const number = Number(value);
  if (!/^\d+$/.test(value) || number < 1 || number > 65535) {
    console.error(`${name}: "${value}" is not a port (1 to 65535)`);
    process.exit(64);
  }
  return number;
}

/** Whether the setting `name` says true (true or 1) and not false (false, 0, empty or unset). */
function flagSetting(name) {
  const value = (env[name] ?? '').trim().toLowerCase();
  if (value === 'true' || value === '1') return true;
  if (value === '' || value === 'false' || value === '0') return false;
  console.error(`${name}: "${env[name]}" is not true or false`);
  process.exit(64);
}

const port = portSetting('INDEX_PORT', 9700);
// What GET /api/settings answers: the ports the page links to and names,
// each a setting with its usual port, a local run's, as the default.
// TATYX_PORT is tatyx's own name for it; Poker Tour's is FLUTTER_WEB_PORT,
// as every Flutter demo's, so here it has a name of its own.
const settings = {
  cluster: flagSetting('INDEX_ON_CLUSTER'),
  ports: {
    AITYX_INDEX_PORT: portSetting('AITYX_INDEX_PORT', 8800),
    DATYX_INDEX_PORT: portSetting('DATYX_INDEX_PORT', 9800),
    TATYX_PORT: portSetting('TATYX_PORT', 9710),
    POKERTOUR_WEB_PORT: portSetting('POKERTOUR_WEB_PORT', 9810),
  },
};
const host = env.INDEX_BIND_HOST || '127.0.0.1';
const group = env.INDEX_GROUP || 'multyx';
// The demos INDEX_DEMOS names, [folder, URL] in folder order; null when
// it's unset, and the folders beside this one are read instead.
const listed = env.INDEX_DEMOS
  ? env.INDEX_DEMOS.split(',')
      .map((item) => item.trim())
      .filter((item) => item.includes('='))
      .map((item) => [item.slice(0, item.indexOf('=')).trim(), item.slice(item.indexOf('=') + 1).trim()])
      .sort((a, b) => a[0].localeCompare(b[0]))
  : null;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
};

createServer((request, response) => {
  handle(request, response).catch((error) => {
    console.error(`error: ${request.method} ${request.url}: ${error?.name ?? error}`);
    if (!response.headersSent) json(response, 500, { error: 'internal error' });
    else response.end();
  });
}).listen(port, host, () => console.log(`multyx index on http://${host}:${port}/`));

async function handle(request, response) {
  const path = new URL(request.url ?? '/', 'http://localhost').pathname;
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    return json(response, 405, { error: 'method not allowed' });
  }
  if (path === '/api/health') return json(response, 200, { ok: true });
  if (path === '/api/demos') return json(response, 200, { demos: await demos() });
  if (path === '/api/settings') return json(response, 200, settings);
  return file(response, path);
}

async function file(response, path) {
  let name = path === '/' || path === '/app' || path === '/app/' ? 'index.html' : path.startsWith('/app/') ? path.slice(5) : path.slice(1);
  if (name === '') name = 'index.html';
  // Only files right in www/: no path parts.
  if (name.includes('..') || name.includes('/')) return json(response, 404, { error: 'not found' });
  const target = join(www, name);
  const info = await stat(target).catch(() => null);
  if (info === null || !info.isFile()) return json(response, 404, { error: 'not found' });
  response.statusCode = 200;
  response.setHeader('Content-Type', TYPES[extname(name)] ?? 'application/octet-stream');
  response.setHeader('Cache-Control', 'no-cache');
  response.end(await readFile(target));
}

function json(response, status, body) {
  response.statusCode = status;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.end(JSON.stringify(body));
}

/** Every folder of the group, with its ports and whether it answers. */
async function demos() {
  if (listed !== null) {
    return Promise.all(listed.map(async ([folder, url]) => ({ folder, url, up: await answers(url) })));
  }
  const found = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name === basename(here)) continue;
    const dir = join(root, entry.name);
    const compose = await readFile(join(dir, 'process-compose.yaml'), 'utf8').catch(() => null);
    if (compose === null) continue;
    const own = await readFile(join(dir, 'group.id.txt'), 'utf8').catch(() => '');
    if (own.trim() !== group) continue;
    const web = Number(/\$\{FLUTTER_WEB_PORT:-(\d+)\}/.exec(compose)?.[1] ?? NaN);
    const api = Number(/\$\{API_PORT:-(\d+)\}/.exec(compose)?.[1] ?? NaN);
    found.push({ folder: entry.name, web: Number.isNaN(web) ? null : web, api: Number.isNaN(api) ? null : api });
  }
  found.sort((a, b) => a.folder.localeCompare(b.folder));
  return Promise.all(
    found.map(async (demo) => ({
      ...demo,
      up: demo.web !== null ? await answers(`http://127.0.0.1:${demo.web}/app/`) : demo.api !== null && (await answers(`http://127.0.0.1:${demo.api}/api/health`)),
    })),
  );
}

/** Whether the URL answers 2xx (or 3xx) within 2 s. */
async function answers(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(2000), redirect: 'manual' });
    await response.arrayBuffer();
    // A redirect is an answer too: Poker Tour sends /app/ to /pokertour/.
    return response.status >= 200 && response.status < 400;
  } catch {
    return false;
  }
}
