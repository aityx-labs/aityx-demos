// The index page, at /demos/: a card per demo. Every path here is relative
// to the page, so the same files serve from the index server
// (Index/bin/server.dart) and from a static host's /demos/ (the aityx
// website).
// On the aityx website, Open goes to the aityx console's Demos tab, which
// signs the visitor in and runs the demo there, on their account (it serves
// these files from its own origin). Anywhere else (the index server, a
// codespace) Open runs the demo beside this page. The status at the top
// right always says whether there is a key and whether it works: the
// console's sign-in, else the index server's key, else the visitor's own,
// which the form under the header asks for (see "The aityx status").
'use strict';

// The demos, in two groups: "kind" is 'game' (under "Games") or 'app' (the
// business apps, under "Apps"). Each group is shown sorted by name.
// "console: false": Open runs it beside this page even where there is a
// console (see appPath).
// "folder" matches the repository's folders;
// each is served beside this page, at /demos/<folder in lower case>/
// (bin/server.dart);
// "codespace" is the group whose dev container (.devcontainer/<group>/) opens
// it, or false.
// The aityx website can leave some out: its console.json's "hide" lists
// their slugs (see findConsole).
const demos = [
  {
    kind: 'game', folder: 'Cellfie', name: 'Cellfie',
    what: 'The cells take a picture of themselves, and aityx says who’s in it',
    desc: 'Conway’s Game of Life on an infinite board, with the rules of birth and death (Conway’s, HighLife’s and Life without death, as switches) and a catalogue of its patterns, as an aityx decision model: one aityx call per generation names what lives, what dies and which clusters are blocks, gliders or pulsars, with the request and the response in a side panel.',
    chips: ['aityx', 'simulation'],
    icon: 'grid', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'PokerFace', name: 'PokerFace',
    what: 'A poker simulator where every player is a set of rules',
    desc: 'No-limit hold’em at a table of up to nine. At each turn the app works out the player’s situation and one aityx call runs their strategy on it: the action, the amount, and the rule that decided it. Five strategies to read, or write your own; every call in a sidebar; the pace in your hands.',
    chips: ['aityx', 'simulation', 'multiplayer'],
    icon: 'cards', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'RoboRules', name: 'RoboRules',
    what: 'Robocode on the web, every turn played by aityx',
    desc: 'Tanks fight until one is left. Every robot’s behavior is an aityx decision model, its rules a table you can edit, and the whole battle (sensors, moves, bullets, hits, damage, scores) is played by aityx; the app only draws it.',
    chips: ['aityx', 'simulation', 'multiplayer'],
    icon: 'robot', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'RiverRace', name: 'RiverRace',
    what: 'The Atari river raid, three planes at once, two flown by aityx',
    desc: 'The 1982 Atari river shooter, remade: banks and islands, bridges, tankers, helicopters, jets and fuel depots, with three planes up one river at once. Two are flown by aityx, each by its own rules (a decision table you can edit while they fly); the yellow one is yours. Who scores more? Every aityx call, sent and received, in a side panel.',
    chips: ['aityx', 'simulation', 'game', 'user playable'],
    icon: 'plane', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'Outpost', name: 'Outpost',
    what: 'Keep a growing city’s lights on, one aityx call per night',
    desc: 'Run the power of a city that grows every night. By day, build a solar panel, a battery or a wind turbine; before night, write the rules for what goes dark first. aityx runs the whole night, hour by hour, as a decision model, and the page only draws it: every number on the map and every line of the receipt, with the rule behind it. How many nights can your city survive?',
    chips: ['aityx', 'simulation', 'game', 'user playable'],
    icon: 'bulb', codespace: 'aityx', console: false,
  },
  {
    kind: 'app', folder: 'HealthPlan', name: 'Health Plan',
    what: 'Which 2027 health plan will actually cost you less?',
    desc: 'Describe your family’s year in plain words. In one aityx call, Jev reads each person’s care and any pregnancy from the message, and the plan rules price Bronze, Silver and Gold for that year: premium plus what you pay for care, after deductibles, coinsurance and the family cap. A receipt per plan gives every number and where it came from, and what-if switches show the winner change.',
    chips: ['aityx', 'natural language processing', 'accountable results'],
    icon: 'health', codespace: 'aityx', console: false,
  },
  {
    kind: 'app', folder: 'MortgageHub', name: 'Mortgage Hub',
    what: 'A mortgage application, from request to verdict',
    desc: 'A buyer fills in a proposal request, and a regulatory check says whether a lender can process it under current US rules: Fannie Mae’s eligibility matrix, the 2026 FHFA and FHA limits, FHA, VA and USDA rules and DTI limits, executed as a decision model on aityx.',
    chips: ['aityx', 'form processing', 'accountable results'],
    // Its own dev container is archived; the default one starts it with the rest.
    icon: 'home', codespace: 'aityx',
  },
  {
    kind: 'app', folder: 'ContactHub', name: 'Contact Hub',
    what: 'Ask anything, and it reaches the right person',
    desc: 'A request, typed or dictated on the device, is classified and checked by aityx and routed by a decision model to the department, the person and the priority; for an order, the store’s policy says what is refunded and by when. The app shows why, and the aityx call itself.',
    chips: ['aityx', 'natural language processing'],
    icon: 'chat', codespace: 'aityx',
  },
  {
    kind: 'app', folder: 'HolidaySplit', name: 'Holiday Split',
    what: 'Who owes what for the holidays, settled by house rules',
    desc: 'Write the family’s group chat about a trip, from Thanksgiving at Mom’s to New Year’s at the lake with fifteen people. aityx reads who comes, for how many nights, what was spent, who isn’t paying and who doesn’t drink, and the house rules, a decision model on aityx, say who pays whom, how much and by when, with a receipt for everyone.',
    chips: ['aityx', 'natural language processing', 'accountable results'],
    icon: 'receipt', codespace: 'aityx', console: false,
  },
];
const icons = {
  home: '<path d="M4 11 L12 4 L20 11 V20 H14 V14 H10 V20 H4 Z"/>',
  health: '<path d="M12 2 L20 5 V11 C20 16 16.5 20 12 22 C7.5 20 4 16 4 11 V5 Z M10.75 7.5 V10.75 H7.5 V13.25 H10.75 V16.5 H13.25 V13.25 H16.5 V10.75 H13.25 V7.5 Z" fill-rule="evenodd"/>',
  chat: '<path d="M4 5 H20 V16 H10 L6 20 V16 H4 Z"/>',
  grid: '<path d="M4 4h4v4H4zM10 4h4v4h-4zM16 4h4v4h-4zM4 10h4v4H4zM16 10h4v4h-4zM4 16h4v4H4zM10 16h4v4h-4zM16 16h4v4h-4z"/>',
  robot: '<path d="M5 9 H19 V19 H5 Z M8 12 H10 V14 H8 Z M14 12 H16 V14 H14 Z M11 4 H13 V9 H11 Z M2 12 H5 V17 H2 Z M19 12 H22 V17 H19 Z"/>',
  cards: '<path d="M7 3 H17 A2 2 0 0 1 19 5 V19 A2 2 0 0 1 17 21 H7 A2 2 0 0 1 5 19 V5 A2 2 0 0 1 7 3 Z M12 7 C13 9 16 10 16 13 C16 14.5 14.7 15.5 13.4 14.8 L14 17 H10 L10.6 14.8 C9.3 15.5 8 14.5 8 13 C8 10 11 9 12 7 Z" fill-rule="evenodd"/>',
  receipt: '<path d="M5 2 H19 V21 L17 19.5 L15 21 L13 19.5 L11 21 L9 19.5 L7 21 L5 19.5 Z M8 6 V8 H16 V6 Z M8 10 V12 H14 V10 Z M8 14 V16 H15 V14 Z" fill-rule="evenodd"/>',
  bulb: '<path d="M12 2a7 7 0 0 0-4 12.7V17h8v-2.3A7 7 0 0 0 12 2Z M9 18.5h6V20H9Z M10 21h4v1h-4Z"/>',
  plane: '<path d="M12 2 L13.5 8 L21 12 V14 L13.5 12 L13 18 L16 20 V21.5 L12 20.5 L8 21.5 V20 L11 18 L10.5 12 L3 14 V12 L10.5 8 Z"/>',
};
const github = 'https://github.com/aityx-labs/aityx-demos/tree/main/';
const codespaces = (d) =>
  'https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=' +
  encodeURIComponent('.devcontainer/' + d.codespace + '/devcontainer.json') +
  '&machine=standardLinux32gb';
// The aityx console this page belongs to: Open runs the demo there
// (#/demos?demo=<slug>). The aityx website says which in console.json,
// beside this page (its PUBLIC_CONSOLE_URL), so production, stage, each
// preview link and its dev server all open their own console. Elsewhere
// (the index server, a codespace) there is no such file: null.
// The same file's "hide" lists the slugs of the demos this page leaves out
// (each demo's "demos": false on the website); anything but a list of
// strings, or no file, hides none.
let consoleUrl = null;
let hidden = [];
async function findConsole() {
  try {
    const r = await fetch('console.json', { cache: 'no-cache' });
    if (!r.ok) return null;
    const json = await r.json();
    const url = json.console, hide = json.hide;
    if (Array.isArray(hide) && hide.every(s => typeof s === 'string')) hidden = hide;
    // An origin only: http(s), a host, no path.
    return typeof url === 'string' && /^https?:\/\/[^/?#]+$/.test(url) ? url : null;
  } catch (_) {
    return null;
  }
}
// Where Open goes: the console's Demos tab, or the app beside this page
// (/demos/<slug>/) where there is no console, or for a demo marked
// console: false (one that can't yet ask the console to make its calls,
// nor is in its Demos tab: Outpost, Health Plan, Holiday Split).
const slug = (d) => d.folder.toLowerCase();
const inConsole = (d) => !!consoleUrl && d.console !== false;
const appPath = (d) => inConsole(d)
  ? consoleUrl + '/#/demos?demo=' + encodeURIComponent(slug(d))
  : slug(d) + '/';
const ext = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4h6v6M20 4l-9 9M19 14v6H4V5h6"/></svg>';

function card(d) {
  const el = document.createElement('article');
  el.className = 'card';
  el.id = 'demo-' + d.folder;
  const chips = d.chips.map(c => '<span class="chip' + (c.includes('aityx') ? ' aityx' : '') + '">' + c + '</span>').join('');
  // Its animation, www/<slug>.gif (a recording of the app, 720 px wide),
  // opens the app too.
  el.innerHTML =
    (d.gif === false ? '' :
    '<a class="shot" href="' + appPath(d) + '" tabindex="-1" aria-hidden="true">' +
    '<img src="' + slug(d) + '.gif" alt="" width="720" height="362" loading="lazy" decoding="async"></a>') +
    '<div class="head"><div class="icon"><svg viewBox="0 0 24 24" fill="currentColor">' + icons[d.icon] + '</svg></div>' +
    '<div><h2>' + d.name + '</h2><p class="what">' + d.what + '</p></div></div>' +
    '<p class="desc">' + d.desc + '</p>' +
    '<div class="chips">' + chips + '</div>' +
    '<div class="actions">' +
    '<a class="btn primary" href="' + appPath(d) + '"' + (inConsole(d) ? ' title="Opens it in the aityx console, after you sign in"' : '') + '>Open</a>' +
    '<a class="btn" href="' + github + d.folder + '" target="_blank" rel="noopener">Source ' + ext + '</a>' +
    (d.codespace ? '<a class="btn" href="' + codespaces(d) + '" target="_blank" rel="noopener">Codespace ' + ext + '</a>' : '') +
    '</div>';
  return el;
}

// Each group's cards into its grid: #games, #apps, sorted by name, less
// the hidden ones (a group left with none loses its title too). Once the
// console is known, so no Open ever points anywhere else first.
async function render() {
  consoleUrl = await findConsole();
  for (const kind of ['game', 'app']) {
    const grid = document.getElementById(kind + 's');
    const shown = demos.filter(d => d.kind === kind && !hidden.includes(slug(d)));
    if (grid) grid.replaceChildren(...shown
      .sort((a, b) => a.name.localeCompare(b.name, 'en', { sensitivity: 'base' }))
      .map(card));
    const title = document.getElementById(kind + 's-title');
    if (title) title.hidden = !shown.length;
  }
}
// The aityx status, top right ---------------------------------------------
//
// Always says whether there is a key and whether it works. The key, in
// this order:
// 1. The aityx console's sign-in, when the console frames this page
//    (?bridge=1): it makes the calls on the signed-in account, as it does
//    for a demo, and a check goes the same way. Not possible otherwise: the
//    console keeps its session on its own origin.
// 2. The index server's key, from its environment (or the repository's
//    .env): aityx/config, beside this page, says whether it holds one (never
//    the key), and the check goes through its proxy.
// 3. Else the visitor's own: the one saved in this browser, as every demo
//    reads it, or the form asks for one.
// A check is one empty POST to /v1/systemone: aityx checks the key first,
// so a working key gets 400 invalid_request and no model runs.
const defaultUrl = 'https://api.aityx.ai';

// The browser's storage, or null where it is blocked.
function storage(name) {
  try {
    const s = window[name];
    const probe = '__aityx_probe__';
    s.setItem(probe, '1');
    s.removeItem(probe);
    return s;
  } catch (_) {
    return null;
  }
}
const local = storage('localStorage');
const session = storage('sessionStorage');

// The visitor's key, as every demo reads it: sessionStorage first. Null
// when there is none.
function userKey() {
  for (const s of [session, local]) {
    const key = s && s.getItem('aityx.key');
    if (key) return { key, url: s.getItem('aityx.url') || defaultUrl };
  }
  return null;
}
function forgetKey() {
  for (const s of [local, session]) {
    if (!s) continue;
    s.removeItem('aityx.key');
    s.removeItem('aityx.url');
  }
}
// Kept on the device, in localStorage, until "Forget key".
function saveKey(key, url) {
  if (!local) throw new Error('this browser keeps no local storage');
  forgetKey();
  local.setItem('aityx.key', key);
  local.setItem('aityx.url', url);
}

// The aityx URL as typed: https, on a host under aityx.ai (all this page's
// content security policy lets it reach), no trailing slash. Null when it
// isn't one.
function cleanUrl(text) {
  const value = (text || '').trim() || defaultUrl;
  let u;
  try {
    u = new URL(value);
  } catch (_) {
    return null;
  }
  if (u.protocol !== 'https:' || u.search || u.hash || u.username || u.password) return null;
  if (!u.hostname.endsWith('.aityx.ai')) return null;
  return (u.origin + u.pathname).replace(/\/+$/, '');
}

// What aityx's answer to the empty call says of the key.
function verdict(status, body) {
  const code = body && body.code;
  const detail = body && typeof body.detail === 'string' ? body.detail : '';
  if (status === 400 && code === 'invalid_request') return { ok: true };
  if (status === 401 || status === 403) return { ok: false, label: 'key rejected', detail: 'aityx rejected it' + (detail ? ': ' + detail : '') };
  if (typeof code === 'string' && code.startsWith('proxy_')) return { ok: false, label: 'not reachable', detail: detail || code };
  return { ok: false, label: 'not working', detail: 'aityx answered HTTP ' + status + (detail ? ': ' + detail : '') };
}

// 1. The console's sign-in: the page around this one makes the call. The
// message carries the body and nothing else, as a demo's does.
const bridged = new URLSearchParams(location.search).get('bridge') === '1' && window.parent !== window;
let nextCall = 0;
function askConsole(body, ms = 10000) {
  return new Promise((resolve) => {
    const id = 'index' + nextCall++;
    const done = (answer) => { removeEventListener('message', listen); clearTimeout(timer); resolve(answer); };
    const listen = (e) => {
      const d = e.data;
      if (!d || d.aityx !== 1 || d.type !== 'answer' || d.id !== id) return;
      done({ status: typeof d.status === 'number' ? d.status : 0, body: typeof d.body === 'string' ? d.body : '' });
    };
    const timer = setTimeout(() => done({ status: 0, body: '' }), ms);
    addEventListener('message', listen);
    window.parent.postMessage({ aityx: 1, type: 'call', id, body }, '*');
  });
}
async function checkConsole() {
  const a = await askConsole('{}');
  if (a.status === 0) return { ok: false, label: 'not reachable', detail: 'the aityx console did not answer' };
  let body = null;
  try { body = JSON.parse(a.body); } catch (_) { body = null; }
  return verdict(a.status, body);
}

// A fetch and its JSON body (null when it has none), given up after `ms`:
// a server that never answers, or keeps the body open, throws as one that
// can't be reached does, so no check waits forever.
async function fetchJson(url, init, ms = 15000) {
  const stop = new AbortController();
  const timer = setTimeout(() => stop.abort(), ms);
  try {
    const r = await fetch(url, { ...init, signal: stop.signal });
    let body = null;
    if ((r.headers.get('content-type') || '').includes('json')) {
      try { body = await r.json(); } catch (_) { body = null; }
    } else {
      await r.text().catch(() => '');
    }
    if (stop.signal.aborted) throw new Error('timed out');
    return { r, body };
  } finally {
    clearTimeout(timer);
  }
}

// 2. The index server's key.
async function serverKey() {
  try {
    const { r, body } = await fetchJson('aityx/config', { cache: 'no-store' });
    return r.ok && body && body.available === true ? body : null;
  } catch (_) {
    return null;
  }
}

// One empty call: through the index server's proxy (no key: it adds its
// own), or with the visitor's key straight to their aityx URL.
async function checkCall(url, key) {
  const headers = { 'Content-Type': 'application/json' };
  if (key) headers.Authorization = 'Bearer ' + key;
  try {
    const { r, body } = await fetchJson(url + '/v1/systemone', {
      method: 'POST', headers, body: '{}', cache: 'no-store',
      credentials: key ? 'omit' : 'same-origin', referrerPolicy: 'no-referrer',
    });
    return verdict(r.status, body);
  } catch (_) {
    return { ok: false, label: 'not reachable', detail: key ? 'aityx did not answer (the network, or the URL is wrong)' : 'the index server did not answer' };
  }
}

function showStatus(state, label, tip, onClick) {
  const box = document.getElementById('aityx-status');
  if (!box) return;
  const el = document.createElement(onClick ? 'button' : 'span');
  el.className = 'pill ' + state;
  if (onClick) { el.type = 'button'; el.addEventListener('click', onClick); }
  const dot = document.createElement('span');
  dot.className = 'dot';
  dot.setAttribute('aria-hidden', 'true');
  el.append(dot, label);
  el.title = tip;
  box.replaceChildren(el);
}

// 3. The form: shown when nothing else gives a working key, or to change
// the visitor's own (a tap on the status).
const $ = (id) => document.getElementById(id);
let changing = false;
function showForm(open, message = '') {
  const own = userKey();
  $('aityx-key').hidden = !open;
  $('key-forget').hidden = !own;
  $('key-cancel').hidden = !changing;
  const result = $('key-result');
  result.textContent = message;
  result.className = 'result' + (message ? ' bad' : '');
  if (consoleUrl) $('key-console').href = consoleUrl;
}
function changeKey() {
  changing = true;
  // The URL field starts with the saved key's URL (production by default).
  $('url-input').value = (userKey() || {}).url || defaultUrl;
  showForm(true);
  $('key-input').focus();
}

// At most one check every 30 s (on start, and when the page comes back into
// view): each check is a call on the key's account, though no model runs.
// A forced check (the key saved, forgotten or changed, here or in another
// tab) asked for while one runs is queued: the running one's answers are
// then about a key that may be gone, so `stale()` drops them and the queued
// check runs as soon as it ends.
let lastCheck = 0;
let checking = false;
let again = false;
const stale = () => again;
async function checkAityx(force = false) {
  if (checking) { if (force) again = true; return; }
  if (!force && Date.now() - lastCheck < 30000) return;
  checking = true;
  lastCheck = Date.now();
  try {
    showStatus('wait', 'Checking aityx…', 'Checking for an aityx key that works');
    if (bridged) {
      const a = await checkConsole();
      if (stale()) return;
      if (a.ok) { showStatus('ok', 'aityx: working · signed in', 'The aityx console makes the calls, on the account you signed in with.'); showForm(false); return; }
      showStatus('bad', 'aityx: ' + a.label, 'Through the aityx console: ' + a.detail + '.');
      showForm(false);
      return;
    }
    const server = await serverKey();
    if (stale()) return;
    if (server) {
      const a = await checkCall('aityx');
      if (stale()) return;
      const where = server.url ? ' (' + server.url + ')' : '';
      if (a.ok) { showStatus('ok', 'aityx: working · server key', 'This server’s aityx key, from its environment' + where + ', works: every demo here uses it.'); showForm(changing); return; }
      // A server key that fails: say so, and offer the visitor's own.
      if (!userKey()) {
        showStatus('bad', 'aityx: server key ' + a.label, 'This server’s aityx key' + where + ' doesn’t work: ' + a.detail + '. Set your own below.');
        showForm(true);
        return;
      }
    }
    const own = userKey();
    if (!own) {
      showStatus('bad', 'aityx: no key', 'No aityx key: set yours below' + (consoleUrl ? ', or sign in to the aityx console' : '') + '.');
      showForm(true);
      return;
    }
    const a = await checkCall(own.url, own.key);
    if (stale()) return;
    const last4 = '…' + own.key.slice(-4);
    if (a.ok) { showStatus('ok', 'aityx: working · your key ' + last4, 'Your aityx key, saved in this browser, works. Tap to change or forget it.', changeKey); showForm(changing); return; }
    showStatus('bad', 'aityx: your key ' + a.label, 'Your aityx key ' + last4 + ': ' + a.detail + '. Tap to change it.', changeKey);
    showForm(true, 'Your saved key ' + last4 + ': ' + a.detail + '.');
  } finally {
    checking = false;
    if (again) { again = false; checkAityx(true); }
  }
}

$('key-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const key = $('key-input').value.trim();
  const url = cleanUrl($('url-input').value);
  const say = (t) => showForm(true, t);
  if (!key) return say('Paste your aityx key first.');
  if (!url) return say('The aityx URL must be https, on a host under aityx.ai.');
  $('key-save').disabled = true;
  $('key-result').className = 'result';
  $('key-result').textContent = 'Checking the key with aityx…';
  try {
    const a = await checkCall(url, key);
    if (!a.ok) return say('Not saved: ' + a.detail + '.');
    try { saveKey(key, url); } catch (err) { return say('Not saved: ' + err.message + '.'); }
    $('key-input').value = '';
    $('url-input').value = defaultUrl;
    changing = false;
    checkAityx(true);
  } finally {
    $('key-save').disabled = false;
  }
});
$('key-forget').addEventListener('click', () => { forgetKey(); $('url-input').value = defaultUrl; changing = false; checkAityx(true); });
$('key-cancel').addEventListener('click', () => { changing = false; showForm(false); checkAityx(true); });
// Another tab (a demo) saved or forgot the key.
addEventListener('storage', (e) => { if (e.key === null || e.key === 'aityx.key' || e.key === 'aityx.url') checkAityx(true); });

render().then(() => checkAityx(true));
addEventListener('focus', () => checkAityx());
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') checkAityx(); });
