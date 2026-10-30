// The index page: a card per demo, "Your aityx key", and the status light.
// The key is kept the way every demo reads it (packages/aityx_web), on this
// origin: localStorage or, for this session only, sessionStorage, under
// aityx.key, with aityx.url beside it. Never in a URL, in a log, or on the
// page once saved (only its last four characters).
'use strict';

// The demos, in the order shown. "folder" matches the repository's folders;
// each is served from this origin at /<folder in lower case>/ (bin/server.dart);
// "codespace" is the group whose dev container (.devcontainer/<group>/) opens
// it, or false.
const demos = [
  {
    folder: 'MortgageHub', name: 'Mortgage Hub',
    what: 'A mortgage application, from request to verdict',
    desc: 'A buyer fills in a proposal request, and a regulatory check says whether a lender can process it under current US rules: Fannie Mae’s eligibility matrix, the 2026 FHFA and FHA limits, FHA, VA and USDA rules and DTI limits, executed as a decision model on aityx.',
    chips: ['aityx decision model'],
    // Its own dev container is archived; the default one starts it with the rest.
    icon: 'home', codespace: 'aityx',
  },
  {
    folder: 'ContactHub', name: 'Contact Hub',
    what: 'Ask anything, and it reaches the right person',
    desc: 'A request, typed or dictated on the device, is classified and checked by aityx and routed by a decision model to the department, the person and the priority; for an order, the store’s policy says what is refunded and by when. The app shows why, and the aityx call itself.',
    chips: ['aityx decision model', 'speech on the device'],
    icon: 'chat', codespace: 'aityx',
  },
  {
    folder: 'Cellfie', name: 'Cellfie',
    what: 'The cells take a picture of themselves, and aityx says who’s in it',
    desc: 'Conway’s Game of Life on an infinite board, with the rules of birth and death (Conway’s, HighLife’s and Life without death, as switches) and a catalogue of its patterns, as an aityx decision model: one aityx call per generation names what lives, what dies and which clusters are blocks, gliders or pulsars, with the request and the response in a side panel.',
    chips: ['aityx decision model'],
    icon: 'grid', codespace: 'aityx',
  },
  {
    folder: 'RoboRules', name: 'RoboRules',
    what: 'Robocode on the web, every turn played by aityx',
    desc: 'Tanks fight until one is left. Every robot’s behavior is an aityx decision model, its rules a table you can edit, and the whole battle (sensors, moves, bullets, hits, damage, scores) is played by aityx; the app only draws it.',
    chips: ['aityx decision model'],
    icon: 'robot', codespace: 'aityx',
  },
  {
    folder: 'PokerFace', name: 'PokerFace',
    what: 'A poker simulator where every player is a set of rules',
    desc: 'No-limit hold’em at a table of up to nine. At each turn the app works out the player’s situation and one aityx call runs their strategy on it: the action, the amount, and the rule that decided it. Five strategies to read, or write your own; every call in a sidebar; the pace in your hands.',
    chips: ['aityx decision model', 'strategies as rules'],
    icon: 'cards', codespace: 'aityx',
  },
  {
    folder: 'RiverRace', name: 'RiverRace',
    what: 'The Atari river raid, three planes at once, two flown by aityx',
    desc: 'The 1982 Atari river shooter, remade: banks and islands, bridges, tankers, helicopters, jets and fuel depots, with three planes up one river at once. Two are flown by aityx, each by its own rules (a decision table you can edit while they fly); the yellow one is yours. Who scores more? Every aityx call, sent and received, in a side panel.',
    chips: ['aityx decision model', 'strategies as rules'],
    icon: 'plane', codespace: 'aityx',
  },
];
const icons = {
  home: '<path d="M4 11 L12 4 L20 11 V20 H14 V14 H10 V20 H4 Z"/>',
  chat: '<path d="M4 5 H20 V16 H10 L6 20 V16 H4 Z"/>',
  grid: '<path d="M4 4h4v4H4zM10 4h4v4h-4zM16 4h4v4h-4zM4 10h4v4H4zM16 10h4v4h-4zM4 16h4v4H4zM10 16h4v4h-4zM16 16h4v4h-4z"/>',
  robot: '<path d="M5 9 H19 V19 H5 Z M8 12 H10 V14 H8 Z M14 12 H16 V14 H14 Z M11 4 H13 V9 H11 Z M2 12 H5 V17 H2 Z M19 12 H22 V17 H19 Z"/>',
  cards: '<path d="M7 3 H17 A2 2 0 0 1 19 5 V19 A2 2 0 0 1 17 21 H7 A2 2 0 0 1 5 19 V5 A2 2 0 0 1 7 3 Z M12 7 C13 9 16 10 16 13 C16 14.5 14.7 15.5 13.4 14.8 L14 17 H10 L10.6 14.8 C9.3 15.5 8 14.5 8 13 C8 10 11 9 12 7 Z" fill-rule="evenodd"/>',
  plane: '<path d="M12 2 L13.5 8 L21 12 V14 L13.5 12 L13 18 L16 20 V21.5 L12 20.5 L8 21.5 V20 L11 18 L10.5 12 L3 14 V12 L10.5 8 Z"/>',
};
const github = 'https://github.com/aityx-labs/aityx-demos/tree/main/';
const codespaces = (d) =>
  'https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=' +
  encodeURIComponent('.devcontainer/' + d.codespace + '/devcontainer.json') +
  '&machine=standardLinux32gb';
// A demo's app: on this origin, so it reads the key saved here.
const appPath = (d) => '/' + d.folder.toLowerCase() + '/';
const ext = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 4h6v6M20 4l-9 9M19 14v6H4V5h6"/></svg>';

function card(d) {
  const el = document.createElement('article');
  el.className = 'card';
  el.id = 'demo-' + d.folder;
  const chips = d.chips.map(c => '<span class="chip' + (c.includes('aityx') ? ' aityx' : '') + '">' + c + '</span>').join('');
  el.innerHTML =
    '<div class="head"><div class="icon"><svg viewBox="0 0 24 24" fill="currentColor">' + icons[d.icon] + '</svg></div>' +
    '<div><h2>' + d.name + '</h2><p class="what">' + d.what + '</p></div></div>' +
    '<p class="desc">' + d.desc + '</p>' +
    '<div class="chips">' + chips + '</div>' +
    '<div class="status" hidden></div>' +
    '<div class="actions">' +
    '<a class="btn primary" href="' + appPath(d) + '" target="_blank" rel="noopener">Open' + ext + '</a>' +
    '<a class="btn" href="' + github + d.folder + '" target="_blank" rel="noopener">Source ' + ext + '</a>' +
    (d.codespace ? '<a class="btn" href="' + codespaces(d) + '" target="_blank" rel="noopener">Codespace ' + ext + '</a>' : '') +
    '</div>';
  return el;
}

document.getElementById('apps').replaceChildren(...demos.map(card));

// Which builds the index server has (/api/demos): a card whose app isn't
// built, or was built for another path, says so. On a static host there's
// no /api/demos, and the cards stay as they are.
async function markBuilds() {
  let list;
  try {
    const r = await fetch('/api/demos', { cache: 'no-store' });
    if (!r.ok) return;
    list = (await r.json()).demos;
  } catch (_) {
    return;
  }
  if (!Array.isArray(list)) return;
  for (const d of list) {
    const el = document.getElementById('demo-' + d.folder);
    if (!el) continue;
    const status = el.querySelector('.status');
    const why = !d.built
      ? 'Not built yet: run ./build-all.sh ' + d.folder
      : !d.served ? 'Built for another path: run ./build-all.sh ' + d.folder : '';
    status.textContent = why;
    status.hidden = !why;
  }
}
markBuilds();

// The key ---------------------------------------------------------------

const defaultUrl = 'https://api.aityx.ai';

// Each storage, or null where the browser refuses it (some private modes).
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

// The user's key, as every demo reads it: sessionStorage wins over
// localStorage. Null when there is none.
function userKey() {
  for (const [s, sessionOnly] of [[session, true], [local, false]]) {
    const key = s && s.getItem('aityx.key');
    if (key) return { key, url: (s.getItem('aityx.url') || defaultUrl), sessionOnly };
  }
  return null;
}

function saveKey(key, url, sessionOnly) {
  const [to, other] = sessionOnly ? [session, local] : [local, session];
  if (!to) throw new Error(sessionOnly ? 'this browser keeps no session storage' : 'this browser keeps no local storage');
  for (const s of [other, to]) {
    if (!s) continue;
    s.removeItem('aityx.key');
    s.removeItem('aityx.url');
  }
  to.setItem('aityx.key', key);
  to.setItem('aityx.url', url);
}

function forgetKey() {
  for (const s of [local, session]) {
    if (!s) continue;
    s.removeItem('aityx.key');
    s.removeItem('aityx.url');
  }
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

// The dev key: the index server's /aityx/config, which says whether it
// holds a key (never the key). Absent on a static host: not available.
async function devConfig() {
  try {
    const r = await fetch('/aityx/config', { cache: 'no-store' });
    if (!r.ok || !(r.headers.get('content-type') || '').includes('json')) return null;
    const c = await r.json();
    return c && c.available === true ? c : null;
  } catch (_) {
    return null;
  }
}

// One empty POST to <url>/v1/systemone: aityx checks the key first, so a
// working key gets 400 invalid_request and no model runs. With a key, from
// the browser to aityx; without, through the index server's dev proxy.
async function check(url, key) {
  const headers = { 'Content-Type': 'application/json' };
  if (key) headers.Authorization = 'Bearer ' + key;
  let r;
  try {
    r = await fetch(url + '/v1/systemone', {
      method: 'POST', headers, body: '{}', cache: 'no-store',
      credentials: key ? 'omit' : 'same-origin', referrerPolicy: 'no-referrer',
    });
  } catch (_) {
    return { ok: false, detail: 'aityx did not answer (the network, or the URL is wrong)', reason: 'not reachable' };
  }
  let body = null;
  try {
    body = await r.json();
  } catch (_) {
    body = null;
  }
  const code = body && body.code;
  const detail = body && typeof body.detail === 'string' ? body.detail : '';
  if (r.status === 400 && code === 'invalid_request') return { ok: true, detail: 'aityx accepts the key' };
  if (r.status === 401 || r.status === 403) {
    return { ok: false, detail: 'aityx rejected the key' + (detail ? ': ' + detail : ''), reason: 'key rejected' };
  }
  if (typeof code === 'string' && code.startsWith('proxy_')) {
    return { ok: false, detail: detail || code, reason: 'not reachable' };
  }
  return { ok: false, detail: 'aityx answered HTTP ' + r.status + (detail ? ': ' + detail : ''), reason: 'not working' };
}

const last4 = (key) => '…' + key.slice(-4);

// Whether the user asked for the form over the dev key ("Use my own key").
let wantOwn = false;

// What the section says now. With a key in use (yours, or the dev key) it
// says so and hides the form: yours comes back only after "Forget key",
// the dev key's after "Use my own key".
async function describeKey() {
  const now = document.getElementById('key-now');
  const user = userKey();
  const dev = user ? null : await devConfig();
  if (!user && userKey()) return describeKey();
  now.innerHTML = '';
  if (user) {
    now.append('Your key ', strong(last4(user.key)), ' is set, ' +
      (user.sessionOnly ? 'for this session only' : 'on this device') + '.');
  } else if (dev) {
    now.append('A key is set.');
  } else {
    now.append(strong('No key yet.'), ' The demos open, but they can’t call aityx until you set one.');
  }
  if (user || dev) now.append(' ', keyCheck());
  const form = !user && (!dev || wantOwn);
  document.getElementById('key-form').hidden = !form;
  document.getElementById('key-help').hidden = !form;
  document.getElementById('key-actions').hidden = form;
  document.getElementById('key-forget').hidden = !user;
  document.getElementById('key-own').hidden = !!user || !dev;
  document.getElementById('key-cancel').hidden = !dev;
  if (form && wantOwn) document.getElementById('key-input').focus();
}

// The key in use, checked against its URL by checkAityx: whether it
// works there, as a sentence. Filled in when the check answers.
let lastCheckResult = null;

function keyCheck() {
  const el = document.createElement('span');
  el.id = 'key-check';
  el.textContent = lastCheckResult || 'Checking it with aityx…';
  return el;
}

function strong(text) {
  const el = document.createElement('strong');
  el.textContent = text;
  return el;
}

function result(text, ok) {
  const el = document.getElementById('key-result');
  el.textContent = text;
  el.className = 'result ' + (ok === true ? 'ok' : ok === false ? 'bad' : '');
}

document.getElementById('url-input').value = (userKey() || {}).url || defaultUrl;

document.getElementById('key-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const input = document.getElementById('key-input');
  const key = input.value.trim();
  const url = cleanUrl(document.getElementById('url-input').value);
  const sessionOnly = document.querySelector('input[name=keep]:checked').value === 'session';
  if (!key) return result('Paste your key first.', false);
  if (/\s/.test(key)) return result('That doesn’t look like a key: it has spaces in it.', false);
  if (!url) {
    document.getElementById('key-advanced').open = true;
    return result('The aityx URL must be an https URL on aityx.ai, like ' + defaultUrl + '.', false);
  }
  const button = document.getElementById('key-save');
  button.disabled = true;
  result('Checking the key with aityx…');
  try {
    const answer = await check(url, key);
    if (!answer.ok) return result(answer.detail + '. Not saved.', false);
    try {
      saveKey(key, url, sessionOnly);
    } catch (error) {
      return result('aityx accepts the key, but it could not be saved: ' + error.message + '.', false);
    }
    input.value = '';
    wantOwn = false;
    lastCheckResult = null;
    result('aityx accepts the key ' + last4(key) + ': saved ' +
      (sessionOnly ? 'for this session.' : 'on this device.'), true);
    await describeKey();
    checkAityx(true);
  } finally {
    button.disabled = false;
  }
});

document.getElementById('key-forget').addEventListener('click', async () => {
  forgetKey();
  lastCheckResult = null;
  result('Key forgotten.', true);
  await describeKey();
  checkAityx(true);
});

document.getElementById('key-own').addEventListener('click', () => {
  wantOwn = true;
  result('');
  describeKey();
});

document.getElementById('key-cancel').addEventListener('click', () => {
  wantOwn = false;
  document.getElementById('key-input').value = '';
  result('');
  describeKey();
});

// The status light ------------------------------------------------------

// Top right: the same order as every demo (your key, else the dev key
// through the index server), and the same check. On start, when the key
// changes (here or in another tab), and when the page regains focus, at
// most once every 30 s: each check is a call on the user's quota.
let lastCheck = 0;
let checking = null;

async function checkAityx(force = false) {
  if (checking) return checking;
  if (!force && Date.now() - lastCheck < 30000) return;
  lastCheck = Date.now();
  checking = (async () => {
    const status = document.getElementById('aityx-status');
    const dot = status.querySelector('.dot');
    let state;
    const user = userKey();
    const dev = user ? null : await devConfig();
    if (user || dev) {
      const url = user ? user.url : dev.url;
      const a = user ? await check(user.url, user.key) : await check('/aityx', null);
      state = { ok: a.ok, label: a.ok ? 'aityx: ready' : 'aityx: ' + a.reason,
        tip: a.ok ? 'aityx: ready — the key works with ' + url : 'aityx: ' + a.detail };
      lastCheckResult = a.ok
        ? 'It works with ' + url + ': every demo here uses it.'
        : 'It doesn’t work with ' + url + ': ' + a.detail + '.';
    } else {
      lastCheckResult = null;
      state = { ok: false, label: 'aityx: no key', tip: 'aityx: no key — set yours on the index page' };
    }
    const shown = document.getElementById('key-check');
    if (shown) {
      shown.textContent = lastCheckResult || '';
      shown.className = state.ok ? 'ok' : 'bad';
    }
    dot.className = 'dot ' + (state.ok ? 'ok' : 'bad');
    status.querySelector('.label').textContent = state.label;
    // The reason, on hover and for screen readers.
    status.title = state.tip;
    status.setAttribute('aria-label', state.tip);
  })();
  try {
    await checking;
  } finally {
    checking = null;
  }
}

describeKey();
checkAityx(true);
window.addEventListener('focus', () => checkAityx());
window.addEventListener('storage', (event) => {
  if (event.key === null || (event.key || '').startsWith('aityx.')) {
    lastCheckResult = null;
    describeKey();
    checkAityx(true);
  }
});
