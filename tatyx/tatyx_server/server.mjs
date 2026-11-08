// The tatyx server: one process on one port, serving the app's build
// under /app/, its API under /api/ (the sign-in, the leaderboard), and a
// relay to its aityx for the app's calls on the player's own key (aityx
// staging takes no calls from browsers). Every player brings their own
// key; the leaderboard plays on a key of its own, which never leaves
// this server. Plain Node (node:http), no packages, so `node server.mjs`
// runs it.
//
//   GET    /                        302 to /app/
//   GET    /app/, /app/<file>       the app's build (WEB_ROOT): a path that
//                                   isn't a file gets index.html
//   GET    /api/health              {"ok": true}
//   GET    /api/config              how to sign in (the Google client id,
//                                   the domains), aityx's URL and the
//                                   relay's path; never a key
//   GET    /api/session             the signed-in player, or 401
//   POST   /api/session             {"credential": <Google ID token>}: a
//                                   session (an HttpOnly cookie)
//   DELETE /api/session             the session's end
//   PUT    /api/me                  {"alias": ...}: what the leaderboard
//                                   calls the player (32 characters at
//                                   most; empty: their name)
//   GET    /api/leaderboard         the standings, the latest tournament,
//                                   what it is doing; open to all
//   POST   /api/leaderboard/run     a tournament now: admins only
//   GET    /api/strategies          the signed-in player's entries in the
//                                   tour, {"strategies": [...]}
//   POST   /api/strategies          a strategy file (name, tagline,
//                                   decisions): entered in the tour,
//                                   checked on aityx first; 201
//   DELETE /api/strategies/{id}     withdraws one of the player's; 204
//   POST   /aityx/v1/systemone      the relay: the body, forwarded to
//                                   <AITYX_URL>/v1/systemone with the
//                                   browser's own Authorization header
//                                   (the player's key), never one of the
//                                   server's; this origin's pages only
//
// Settings (the environment, else this folder's or the repository's
// .env, read again at most every 10 s): TATYX_PORT (else FLUTTER_WEB_PORT;
// 9710), TATYX_BIND_HOST (127.0.0.1), WEB_ROOT, AITYX_URL, the
// leaderboard's key TATYX_LEADERBOARD_KEY (else AITYX_API_KEY; staging's
// here, production's TATYX_PROD_LEADERBOARD_KEY is a deployment's only),
// TATYX_OIDC_CLIENT_ID (the
// Google client; none: nobody can sign in), TATYX_ALLOWED_DOMAINS
// (aletyx.com,aletyx.ai), TATYX_ADMIN_DOMAINS (the allowed ones),
// TATYX_SESSION_SECRET (else a random one per start), TATYX_LEADERBOARD
// (on|off), TATYX_LEADERBOARD_EVERY_HOURS (6; 0: only on demand),
// TATYX_LEADERBOARD_COOLDOWN_MINUTES (10), TATYX_DATA_DIR (../data).
// The keys, the tokens, the cookies and the bodies are never logged.

import { mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { AuthError, SESSION_COOKIE, cookieOf, domainOf, sessionHeader, sessions, verifyGoogleIdToken } from './auth.mjs';
import { EntryError, createLeaderboard } from './leaderboard.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const env = process.env;
const port = Number(env.TATYX_PORT || env.FLUTTER_WEB_PORT || 9710);
const host = env.TATYX_BIND_HOST || '127.0.0.1';
const webRoot = resolve(env.WEB_ROOT || join(here, '..', 'tatyx_app', 'dist'));
const envFiles = [join(here, '..', '.env'), join(here, '..', '..', '.env')];
const DEFAULT_URL = 'https://api.aityx.ai';
const MAX_BODY = 2 * 1024 * 1024;
const PROXY_TIMEOUT_MS = 120_000;
const DEFAULT_DOMAINS = 'aletyx.com,aletyx.ai';
const dataDir = resolve(env.TATYX_DATA_DIR || join(here, '..', 'data'));
const runnerPath = resolve(env.TATYX_RUNNER || join(here, '..', 'tatyx_app', 'dist-runner', 'runner.mjs'));
const session = sessions(env.TATYX_SESSION_SECRET || undefined);
const MAX_ALIAS = 32;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.map': 'application/json',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.mp3': 'audio/mpeg',
  '.ogg': 'audio/ogg',
  '.txt': 'text/plain; charset=utf-8',
};

const server = createServer((request, response) => {
  handle(request, response).catch((error) => {
    console.error(`error: ${request.method} ${request.url}: ${error?.name ?? error}`);
    if (!response.headersSent) json(response, 500, { error: 'internal error' });
    else response.end();
  });
});
const leaderboard = createLeaderboard({
  dataDir,
  runnerPath,
  settings: () => settings(),
  ownerName: (email) => ownerName(email),
  everyHours: Number(env.TATYX_LEADERBOARD_EVERY_HOURS ?? 6),
  cooldownMinutes: Number(env.TATYX_LEADERBOARD_COOLDOWN_MINUTES ?? 10),
  log: (line) => console.log(line),
});

server.listen(port, host, () => {
  console.log(`tatyx on http://${host}:${port}/app/ (build: ${webRoot})`);
});

async function handle(request, response) {
  const url = new URL(request.url ?? '/', 'http://localhost');
  const path = url.pathname;
  if (path === '/aityx/v1/systemone') return relay(request, response);
  if (path === '/api/session') return sessionRoute(request, response);
  if (path === '/api/me') return meRoute(request, response);
  if (path === '/api/leaderboard/run') return runRoute(request, response);
  if (path === '/api/strategies' || path.startsWith('/api/strategies/')) return strategiesRoute(request, response, path);
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.setHeader('Allow', 'GET, HEAD');
    return json(response, 405, { error: 'method not allowed' });
  }
  // /app without its slash too: the page's relative paths (the bots'
  // portraits) resolve only under /app/.
  if (path === '/' || path === '/app') {
    response.statusCode = 302;
    response.setHeader('Location', `/app/${url.search}`);
    return response.end();
  }
  if (path === '/api/health') return json(response, 200, { ok: true });
  if (path === '/api/config') return json(response, 200, await apiConfig(), 'no-store');
  if (path === '/api/leaderboard') return json(response, 200, await leaderboard.view(), 'no-store');
  if (path.startsWith('/app/')) return file(response, path.slice('/app'.length));
  return json(response, 404, { error: 'not found' });
}

/** A file of the build, by its path under /app/; the app's index.html for anything that isn't one. */
async function file(response, path) {
  let name = decodeURIComponent(path).replace(/^\/+/, '');
  if (name === '' || name.endsWith('/')) name = `${name}index.html`;
  // Never outside the build folder.
  const target = normalize(join(webRoot, name));
  if (target !== webRoot && !target.startsWith(webRoot + sep)) return json(response, 404, { error: 'not found' });
  let chosen = target;
  let info = await stat(chosen).catch(() => null);
  if (info === null || !info.isFile()) {
    chosen = join(webRoot, 'index.html');
    info = await stat(chosen).catch(() => null);
    if (info === null || !info.isFile()) {
      return json(response, 503, { error: 'no build yet: run `bash scripts/build.sh` in tatyx/' });
    }
    name = 'index.html';
  }
  const type = TYPES[extname(name)] ?? 'application/octet-stream';
  response.statusCode = 200;
  response.setHeader('Content-Type', type);
  // Vite names its bundles by content hash: those never change; the page, always fresh.
  response.setHeader('Cache-Control', name.startsWith('assets/') ? 'public, max-age=31536000, immutable' : 'no-cache');
  response.setHeader('X-Content-Type-Options', 'nosniff');
  response.end(await readFile(chosen));
}

function json(response, status, body, cache) {
  response.statusCode = status;
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  if (cache) response.setHeader('Cache-Control', cache);
  response.end(JSON.stringify(body));
}

// The key and where it goes, as this server reads them.

let settingsCache = null;
let settingsAt = 0;

/** A codespace's secrets, as Codespaces keeps them for its processes: NAME=<base64>, one per line. */
async function codespaceSecrets() {
  const secrets = {};
  try {
    const text = await readFile('/workspaces/.codespaces/shared/.env-secrets', 'utf8');
    for (const line of text.split('\n')) {
      const at = line.indexOf('=');
      if (at <= 0) continue;
      try {
        secrets[line.slice(0, at)] = Buffer.from(line.slice(at + 1).trim(), 'base64').toString('utf8').trim();
      } catch {
        continue;
      }
    }
  } catch {
    // Not a codespace, or no secrets.
  }
  return secrets;
}

/** NAME=value lines of the first .env that exists (this folder's, else the repository's). */
async function dotEnv() {
  for (const file of envFiles) {
    try {
      const text = await readFile(file, 'utf8');
      const values = {};
      for (let line of text.split('\n')) {
        line = line.trim();
        if (line.startsWith('export ')) line = line.slice(7).trimStart();
        const at = line.indexOf('=');
        if (at <= 0 || line.startsWith('#')) continue;
        let value = line.slice(at + 1).trim();
        if (value.length >= 2 && (value[0] === '"' || value[0] === "'") && value.endsWith(value[0])) {
          value = value.slice(1, -1);
        }
        values[line.slice(0, at).trim()] = value;
      }
      return values;
    } catch {
      continue;
    }
  }
  return {};
}

/**
 * The key and URL: each from the environment (a Codespaces secret, also
 * read from the codespace's secrets file), else from .env, read again at
 * most every 10 s, so a key added after the start is picked up.
 */
async function settings() {
  if (settingsCache !== null && Date.now() - settingsAt < 10_000) return settingsCache;
  const secrets = await codespaceSecrets();
  const fromFile = await dotEnv();
  // A setting: the environment (or a Codespaces secret), else the .env file.
  const read = (name) => env[name] || secrets[name] || fromFile[name] || '';
  // The leaderboard's key alone: the players bring their own.
  const leaderboardKey = read('TATYX_LEADERBOARD_KEY') || read('AITYX_API_KEY');
  const list = (value) => value.split(',').map((d) => d.trim().toLowerCase()).filter(Boolean);
  const domains = list(read('TATYX_ALLOWED_DOMAINS') || DEFAULT_DOMAINS);
  const envUrl = env.AITYX_URL || secrets.AITYX_URL || '';
  let url = (envUrl || fromFile.AITYX_URL || DEFAULT_URL).replace(/\/+$/, '');
  let base = null;
  try {
    const parsed = new URL(url);
    if (parsed.protocol === 'https:' && parsed.hostname && !parsed.search && !parsed.hash) base = parsed;
  } catch {
    base = null;
  }
  settingsAt = Date.now();
  return (settingsCache = {
    leaderboardKey,
    leaderboardOff: read('TATYX_LEADERBOARD').toLowerCase() === 'off',
    url,
    base,
    clientId: read('TATYX_OIDC_CLIENT_ID'),
    domains,
    adminDomains: list(read('TATYX_ADMIN_DOMAINS')).length ? list(read('TATYX_ADMIN_DOMAINS')) : domains,
  });
}

/** The signed-in player of a request, with whether they are an admin; null when signed out. */
async function playerOf(request) {
  const user = session.read(cookieOf(request, SESSION_COOKIE));
  if (user === null) return null;
  const s = await settings();
  const domain = domainOf(user.email);
  if (!s.domains.includes(domain)) return null;
  return { email: user.email, name: user.name ?? null, picture: user.picture ?? null, alias: (await aliases())[user.email] ?? null, admin: s.adminDomains.includes(domain) };
}

// ---- The players' aliases: what the leaderboard calls them, in <data>/players.json.
const playersFile = join(dataDir, 'players.json');
let aliasCache = null;

/** Every alias, by email. */
async function aliases() {
  if (aliasCache === null) {
    try {
      const parsed = JSON.parse(await readFile(playersFile, 'utf8'));
      aliasCache = parsed && typeof parsed.aliases === 'object' ? parsed.aliases : {};
    } catch {
      aliasCache = {};
    }
  }
  return aliasCache;
}

/** Sets `email`'s alias; empty removes it (their name again). */
async function saveAlias(email, alias) {
  const all = { ...(await aliases()) };
  if (alias === '') delete all[email];
  else all[email] = alias;
  await mkdir(dataDir, { recursive: true });
  const temp = `${playersFile}.tmp`;
  await writeFile(temp, JSON.stringify({ aliases: all }, null, 2), { mode: 0o600 });
  await rename(temp, playersFile);
  aliasCache = all;
}

/** What the leaderboard shows for a strategy's owner: their alias, else a name that isn't their email. */
async function ownerName(email) {
  return (await aliases())[email] ?? String(email).split('@')[0];
}

/** Whether the request came over https (directly, or through a proxy that says so). */
function secure(request) {
  return request.socket.encrypted === true || request.headers['x-forwarded-proto'] === 'https';
}

/** GET /api/config: how to sign in, and what this server can do; never a key. */
async function apiConfig() {
  const s = await settings();
  return {
    signIn: s.clientId ? { clientId: s.clientId, domains: s.domains } : null,
    aityxUrl: s.url,
    // Where the player's calls to aityxUrl go: aityx staging takes none from browsers.
    aityxRelay: s.base === null ? null : '/aityx/',
  };
}

/** /api/session: who is signed in (GET), a sign-in with a Google ID token (POST), a sign-out (DELETE). */
async function sessionRoute(request, response) {
  if (request.method === 'GET') {
    const player = await playerOf(request);
    return player === null ? json(response, 401, { error: 'signed out' }, 'no-store') : json(response, 200, player, 'no-store');
  }
  if (!sameOrigin(request)) return json(response, 403, { error: "this origin's pages only" }, 'no-store');
  if (request.method === 'DELETE') {
    response.setHeader('Set-Cookie', sessionHeader(null, secure(request)));
    return json(response, 200, { ok: true }, 'no-store');
  }
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'GET, POST, DELETE');
    return json(response, 405, { error: 'method not allowed' });
  }
  const s = await settings();
  if (!s.clientId) return json(response, 503, { error: 'sign-in is not set up: the server has no TATYX_OIDC_CLIENT_ID' }, 'no-store');
  let body;
  try {
    body = JSON.parse((await readBody(request, 16 * 1024)).toString('utf8'));
  } catch {
    return json(response, 400, { error: 'a JSON body with the credential' }, 'no-store');
  }
  let claims;
  try {
    claims = await verifyGoogleIdToken(body?.credential, s.clientId);
  } catch (error) {
    if (error instanceof AuthError) return json(response, 401, { error: `Google's sign-in did not check out: ${error.message}` }, 'no-store');
    throw error;
  }
  const domain = domainOf(claims.email);
  if (!s.domains.includes(domain)) {
    return json(response, 403, { error: `${claims.email} is not in the tour's domains (${s.domains.join(', ')})` }, 'no-store');
  }
  const user = { email: claims.email, name: claims.name ?? null, picture: claims.picture ?? null };
  response.setHeader('Set-Cookie', sessionHeader(session.issue(user), secure(request)));
  console.log(`session: a player of ${domain} signed in`);
  return json(response, 200, { ...user, alias: (await aliases())[user.email] ?? null, admin: s.adminDomains.includes(domain) }, 'no-store');
}

/** PUT /api/me: the signed-in player's alias, {"alias": ...}; empty for their name. */
async function meRoute(request, response) {
  if (request.method !== 'PUT') {
    response.setHeader('Allow', 'PUT');
    return json(response, 405, { error: 'method not allowed' });
  }
  if (!sameOrigin(request)) return json(response, 403, { error: "this origin's pages only" }, 'no-store');
  const player = await playerOf(request);
  if (player === null) return json(response, 401, { error: 'sign in first' }, 'no-store');
  let body;
  try {
    body = JSON.parse((await readBody(request, 4 * 1024)).toString('utf8'));
  } catch {
    return json(response, 400, { error: 'a JSON body with the alias' }, 'no-store');
  }
  if (typeof body?.alias !== 'string') return json(response, 400, { error: 'the alias must be a string' }, 'no-store');
  const alias = body.alias.replace(/\s+/g, ' ').trim();
  if (alias.length > MAX_ALIAS) return json(response, 400, { error: `the alias takes ${MAX_ALIAS} characters at most` }, 'no-store');
  // Empty, or the name itself: no alias, the name.
  await saveAlias(player.email, alias === player.name ? '' : alias);
  return json(response, 200, await playerOf(request), 'no-store');
}

/** POST /api/leaderboard/run: a tournament now, for a signed-in admin. */
async function runRoute(request, response) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return json(response, 405, { error: 'method not allowed' });
  }
  if (!sameOrigin(request)) return json(response, 403, { error: "this origin's pages only" }, 'no-store');
  const player = await playerOf(request);
  if (player === null) return json(response, 401, { error: 'sign in first' }, 'no-store');
  if (!player.admin) return json(response, 403, { error: "only the tour's admins can start a tournament" }, 'no-store');
  const outcome = await leaderboard.playNow();
  return json(response, outcome.started ? 202 : 409, outcome, 'no-store');
}

/** /api/strategies: the signed-in player's entries in the tour (GET), a new one (POST), and /api/strategies/{id} to withdraw one (DELETE). */
async function strategiesRoute(request, response, path) {
  const id = path === '/api/strategies' ? null : decodeURIComponent(path.slice('/api/strategies/'.length));
  const allowed = id === null ? 'GET, POST' : 'DELETE';
  if (!allowed.split(', ').includes(request.method ?? '')) {
    response.setHeader('Allow', allowed);
    return json(response, 405, { error: 'method not allowed' });
  }
  if (request.method !== 'GET' && !sameOrigin(request)) return json(response, 403, { error: "this origin's pages only" }, 'no-store');
  const player = await playerOf(request);
  if (player === null) return json(response, 401, { error: 'sign in first' }, 'no-store');
  if (request.method === 'GET') return json(response, 200, { strategies: await leaderboard.entriesOf(player.email) }, 'no-store');
  if (request.method === 'DELETE') {
    if (!(await leaderboard.withdraw(player.email, id))) return json(response, 404, { error: 'no strategy of yours by that id' }, 'no-store');
    response.statusCode = 204;
    return response.end();
  }
  let text;
  try {
    text = (await readBody(request, 64 * 1024)).toString('utf8');
  } catch {
    return json(response, 413, { error: 'a strategy file is 64 KB at most' }, 'no-store');
  }
  try {
    return json(response, 201, await leaderboard.enter(player.email, text), 'no-store');
  } catch (error) {
    if (error instanceof EntryError) return json(response, error.status, { error: error.message }, 'no-store');
    throw error;
  }
}

/** A request's body, up to `limit` bytes. */
async function readBody(request, limit) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > limit) throw new Error('too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

/** Whether the request comes from a page of this origin (or a loopback one): the relay answers no other. */
function sameOrigin(request) {
  const from = request.headers.origin ?? request.headers.referer;
  if (!from) return true; // A plain fetch of this origin sends Origin; a tool without one is let in.
  let fromHost;
  try {
    fromHost = new URL(from).hostname;
  } catch {
    return false;
  }
  const ownHost = (request.headers.host ?? '').replace(/:\d+$/, '').replace(/^\[|\]$/g, '');
  return (
    fromHost === ownHost ||
    fromHost === 'localhost' ||
    fromHost.endsWith('.localhost') ||
    fromHost === '127.0.0.1' ||
    fromHost === '::1'
  );
}

/**
 * POST /aityx/v1/systemone: the body, forwarded to aityx with the
 * browser's own Authorization header, the player's key, passed on as it
 * is and never logged; aityx's status and body back unchanged. The
 * server never adds a key of its own: without the player's, it is a 401.
 * Redirects are not followed (502: AITYX_URL is likely behind a login),
 * and an aityx that doesn't answer is a 502 too.
 */
async function relay(request, response) {
  if (request.method !== 'POST') {
    response.setHeader('Allow', 'POST');
    return json(response, 405, { code: 'method_not_allowed', detail: 'the relay takes POST only' }, 'no-store');
  }
  if (!sameOrigin(request)) {
    return json(response, 403, { code: 'proxy_cross_site', detail: "the relay answers this origin's pages only" }, 'no-store');
  }
  const authorization = request.headers.authorization ?? '';
  if (!/^Bearer \S{4,}$/.test(authorization)) {
    return json(response, 401, { code: 'unauthorized', detail: 'no aityx key: set yours in Profile' }, 'no-store');
  }
  const s = await settings();
  if (s.base === null) {
    return json(response, 503, { code: 'proxy_bad_url', detail: 'AITYX_URL must be an https URL' }, 'no-store');
  }
  const declared = Number(request.headers['content-length'] ?? 0);
  if (declared > MAX_BODY) {
    return json(response, 413, { code: 'proxy_too_large', detail: `the request is over ${MAX_BODY / (1024 * 1024)} MB` }, 'no-store');
  }
  const chunks = [];
  let size = 0;
  try {
    for await (const chunk of request) {
      size += chunk.length;
      if (size > MAX_BODY) {
        return json(response, 413, { code: 'proxy_too_large', detail: `the request is over ${MAX_BODY / (1024 * 1024)} MB` }, 'no-store');
      }
      chunks.push(chunk);
    }
  } catch {
    return json(response, 408, { code: 'proxy_request_timeout', detail: 'the request body did not arrive' }, 'no-store');
  }
  const target = `${s.base.href.replace(/\/+$/, '')}/v1/systemone`;
  const started = Date.now();
  let answer;
  try {
    answer = await fetch(target, {
      method: 'POST',
      headers: {
        Authorization: authorization,
        'Content-Type': request.headers['content-type'] || 'application/json',
        'User-Agent': 'aityx-demos-tatyx',
      },
      body: Buffer.concat(chunks),
      redirect: 'manual',
      signal: AbortSignal.timeout(PROXY_TIMEOUT_MS),
    });
  } catch (error) {
    console.error(`aityx relay: no answer (${error?.name ?? 'error'})`);
    return json(response, 502, { code: 'proxy_unreachable', detail: `aityx did not answer: ${error?.name ?? 'error'}` }, 'no-store');
  }
  console.log(`aityx relay: HTTP ${answer.status} in ${Date.now() - started} ms`);
  if (answer.status >= 300 && answer.status < 400) {
    let where = s.base.hostname;
    try {
      where = new URL(answer.headers.get('location') ?? '', target).hostname || where;
    } catch {
      // Keep the target's host.
    }
    return json(response, 502, { code: 'proxy_redirect', detail: `AITYX_URL redirected to ${where}: it may be behind a login` }, 'no-store');
  }
  response.statusCode = answer.status;
  response.setHeader('Cache-Control', 'no-store');
  const type = answer.headers.get('content-type');
  if (type) response.setHeader('Content-Type', type);
  response.end(Buffer.from(await answer.arrayBuffer()));
}
