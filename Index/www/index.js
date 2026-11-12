// The index page, at /demos/: a card per demo, "Your aityx key", and the
// status light. Every path here is relative to the page, so the same
// files serve from the index server (Index/bin/server.dart) and from a
// static host's /demos/ (the aityx website).
// The key is kept the way every demo reads it (packages/aityx_web), on this
// origin: always in localStorage, until "Forget key", under aityx.key, with
// aityx.url beside it. Never in a URL, in a log, or on the page once saved
// (only its last four characters).
'use strict';

// The demos, in two groups: "kind" is 'game' (under "Games") or 'app' (the
// business apps, under "Apps"). Each group is shown sorted by name.
// "folder" matches the repository's folders;
// each is served beside this page, at /demos/<folder in lower case>/
// (bin/server.dart);
// "codespace" is the group whose dev container (.devcontainer/<group>/) opens
// it, or false.
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
    icon: 'bulb', codespace: 'aityx',
  },
  {
    kind: 'app', folder: 'HealthPlan', name: 'Health Plan',
    what: 'Which 2027 health plan will actually cost you less?',
    desc: 'Describe your family’s year in plain words. In one aityx call, Jev reads each person’s care and any pregnancy from the message, and the plan rules price Bronze, Silver and Gold for that year: premium plus what you pay for care, after deductibles, coinsurance and the family cap. A receipt per plan gives every number and where it came from, and what-if switches show the winner change.',
    chips: ['aityx', 'natural language processing', 'accountable results'],
    icon: 'health', codespace: 'aityx',
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
    icon: 'receipt', codespace: 'aityx',
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
// A demo's app: beside this page (/demos/<slug>/), on this origin, so it
// reads the key saved here, in localStorage, which every tab shares. Opened
// in a new tab without an opener, which starts with an empty
// sessionStorage: a key an older page left in this tab's sessionStorage
// ("only this session", before the page dropped that choice) isn't copied
// into it. The demos read sessionStorage first, so a copy would outlive
// this page's Save and Forget key, which clear only this tab's.
const appPath = (d) => d.folder.toLowerCase() + '/';
const appTab = 'target="_blank" rel="noopener"';
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
    '<a class="shot" href="' + appPath(d) + '" ' + appTab + ' tabindex="-1" aria-hidden="true">' +
    '<img src="' + d.folder.toLowerCase() + '.gif" alt="" width="720" height="362" loading="lazy" decoding="async"></a>') +
    '<div class="head"><div class="icon"><svg viewBox="0 0 24 24" fill="currentColor">' + icons[d.icon] + '</svg></div>' +
    '<div><h2>' + d.name + '</h2><p class="what">' + d.what + '</p></div></div>' +
    '<p class="desc">' + d.desc + '</p>' +
    '<div class="chips">' + chips + '</div>' +
    '<div class="actions">' +
    '<a class="btn primary" href="' + appPath(d) + '" ' + appTab + '>Open ' + ext + '</a>' +
    '<a class="btn" href="' + github + d.folder + '" target="_blank" rel="noopener">Source ' + ext + '</a>' +
    (d.codespace ? '<a class="btn" href="' + codespaces(d) + '" target="_blank" rel="noopener">Codespace ' + ext + '</a>' : '') +
    '</div>';
  return el;
}

// Each group's cards into its grid: #games, #apps. The key page alone
// (key.html, embedded in the aityx website) has neither.
for (const kind of ['game', 'app']) {
  const grid = document.getElementById(kind + 's');
  if (grid) grid.replaceChildren(...demos.filter(d => d.kind === kind)
    .sort((a, b) => a.name.localeCompare(b.name, 'en', { sensitivity: 'base' }))
    .map(card));
}

// The key ---------------------------------------------------------------

const defaultUrl = 'https://api.aityx.ai';

// key.html in a frame of the aityx website's blueprint page (see the end).
const embedded = document.body.hasAttribute('data-embed') && window.parent !== window;

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

// Always on the device, in localStorage: the page has no "only this
// session". A key in sessionStorage (one saved there before, which would
// win over this one) is cleared.
function saveKey(key, url) {
  if (!local) throw new Error('this browser keeps no local storage');
  forgetKey();
  local.setItem('aityx.key', key);
  local.setItem('aityx.url', url);
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

// The dev key: the index server's aityx/config (beside the page), which
// says whether it holds a key (never the key). Absent on a static host:
// not available.
async function devConfig() {
  try {
    const r = await fetch('aityx/config', { cache: 'no-store' });
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
  // Framed (key.html), the modal around the form already says there's no
  // key: the line shows only once one is set.
  now.hidden = embedded && !user && !dev;
  const form = !user && (!dev || wantOwn);
  document.getElementById('key-form').hidden = !form;
  document.getElementById('key-help').hidden = !form;
  document.getElementById('key-actions').hidden = form;
  document.getElementById('key-forget').hidden = !user;
  document.getElementById('key-own').hidden = !!user || !dev;
  document.getElementById('key-cancel').hidden = !dev;
  if (form && wantOwn) document.getElementById('key-input').focus();
  postForm();
}

// Framed: whether the form shows and is checking a key, for the modal's
// own Check and save button, which submits it (see the end). Never what's
// typed in it.
function postForm() {
  if (!embedded) return;
  window.parent.postMessage({
    type: 'aityx:key-form',
    open: !document.getElementById('key-form').hidden,
    busy: document.getElementById('key-save').disabled,
  }, '*');
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
  if (!key) return result('Paste your key first.', false);
  if (/\s/.test(key)) return result('That doesn’t look like a key: it has spaces in it.', false);
  if (!url) {
    document.getElementById('key-advanced').open = true;
    return result('The aityx URL must be an https URL on aityx.ai, like ' + defaultUrl + '.', false);
  }
  const button = document.getElementById('key-save');
  button.disabled = true;
  postForm();
  result('Checking the key with aityx…');
  try {
    const answer = await check(url, key);
    if (!answer.ok) return result(answer.detail + '. Not saved.', false);
    try {
      saveKey(key, url);
    } catch (error) {
      return result('aityx accepts the key, but it could not be saved: ' + error.message + '.', false);
    }
    input.value = '';
    wantOwn = false;
    lastCheckResult = null;
    result('aityx accepts the key ' + last4(key) + ': saved on this device.', true);
    await describeKey();
    checkAityx(true);
  } finally {
    button.disabled = false;
    postForm();
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
      const a = user ? await check(user.url, user.key) : await check('aityx', null);
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
    // Framed, the page around it learns only whether a working key is set.
    if (embedded) window.parent.postMessage({ type: 'aityx:key-state', ready: state.ok }, '*');
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

// A key in the request ----------------------------------------------------

// AITYX_API_KEY in the page's URL fragment (/demos/#AITYX_API_KEY=...),
// optionally with AITYX_URL beside it, on any host, static or not: checked
// with aityx like a pasted key, then saved on this device for every demo,
// replacing any key set before. Only the fragment: the browser never sends
// it to a server, so it reaches no access log. A key in the query string
// (/demos/?AITYX_API_KEY=...) has already reached the server's logs, so it
// is refused, and the page says so. Either way the key is taken out of the
// address bar first, so it isn't kept in the history or shared with the
// page's address. A key aityx rejects is not saved, and the form says so.
async function keyFromRequest() {
  const url = new URL(window.location.href);
  const query = url.searchParams;
  const hash = new URLSearchParams(url.hash.replace(/^#/, ''));
  const inQuery = query.has('AITYX_API_KEY') || query.has('AITYX_URL');
  const inHash = hash.has('AITYX_API_KEY');
  if (!inQuery && !inHash) return false;
  const key = (hash.get('AITYX_API_KEY') || '').trim();
  const urlGiven = hash.get('AITYX_URL');
  for (const params of [query, hash]) {
    params.delete('AITYX_API_KEY');
    params.delete('AITYX_URL');
  }
  url.search = query.toString();
  url.hash = hash.toString() ? '#' + hash.toString() : '#aityx-key';
  window.history.replaceState(null, '', url.toString());
  if (inQuery) {
    result('A key in the link’s query string (?AITYX_API_KEY=) reaches the server and its logs: not used. ' +
      'Put it in the fragment instead (#AITYX_API_KEY=), and consider replacing that key in the aityx console.', false);
    return false;
  }
  if (!key) return result('The link carries an empty AITYX_API_KEY: nothing saved.', false), false;
  if (/\s/.test(key)) return result('The link’s AITYX_API_KEY doesn’t look like a key: it has spaces in it.', false), false;
  const aityxUrl = cleanUrl(urlGiven || (userKey() || {}).url || defaultUrl);
  if (!aityxUrl) return result('The link’s AITYX_URL must be an https URL on aityx.ai, like ' + defaultUrl + '.', false), false;
  result('Checking the key from the link with aityx…');
  const answer = await check(aityxUrl, key);
  if (!answer.ok) {
    result('The key in the link: ' + answer.detail + '. Not saved.', false);
    return false;
  }
  try {
    saveKey(key, aityxUrl, false);
  } catch (error) {
    result('aityx accepts the key in the link, but it could not be saved: ' + error.message + '.', false);
    return false;
  }
  wantOwn = false;
  lastCheckResult = null;
  document.getElementById('url-input').value = aityxUrl;
  result('aityx accepts the key ' + last4(key) + ' from the link: saved on this device, for every demo here.', true);
  return true;
}

keyFromRequest().finally(() => {
  describeKey();
  checkAityx(true);
});
window.addEventListener('focus', () => checkAityx());

// Embedded: key.html in a frame of the aityx website's blueprint page,
// which sizes the frame to the page's height as this posts it, and enables
// its Run button once checkAityx posts that the key works. Only the height
// and that yes or no: never the key, nor anything typed.
// The page around it also says its theme (?theme=light or dark).
if (embedded) {
  const theme = new URLSearchParams(window.location.search).get('theme');
  if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;
  const postHeight = () => window.parent.postMessage(
    { type: 'aityx:key-height', height: document.documentElement.scrollHeight }, '*');
  new ResizeObserver(postHeight).observe(document.body);
  postHeight();
  // The modal's Check and save: submits the form as it is, the same as
  // Enter in it. Only from the page around this one (which frame-ancestors
  // limits to the website), and it carries nothing.
  window.addEventListener('message', (event) => {
    if (event.source !== window.parent || !event.data || event.data.type !== 'aityx:key-save') return;
    const form = document.getElementById('key-form');
    if (!form.hidden && !document.getElementById('key-save').disabled) form.requestSubmit();
  });
}
window.addEventListener('storage', (event) => {
  if (event.key === null || (event.key || '').startsWith('aityx.')) {
    lastCheckResult = null;
    describeKey();
    checkAityx(true);
  }
});
