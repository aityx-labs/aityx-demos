// The index page, at /demos/: a card per demo. Every path here is relative
// to the page, so the same files serve from the index server
// (Index/bin/server.dart) and from a static host's /demos/ (the aityx
// website).
// No key is asked for here. On the aityx website, Open goes to the aityx
// console's Demos tab, which signs the visitor in, has them choose one of
// their API keys and runs the demo there (it serves these files from its
// own origin). Anywhere else (the index server, a codespace) Open runs the
// demo beside this page, on the dev key or none.
'use strict';

// The demos, in the order shown, in two groups: "kind" is 'game' (under
// "Games") or 'app' (the business apps, under "Apps").
// "folder" matches the repository's folders;
// each is served beside this page, at /demos/<folder in lower case>/
// (bin/server.dart);
// "codespace" is the group whose dev container (.devcontainer/<group>/) opens
// it, or false.
const demos = [
  {
    kind: 'game', folder: 'RiverRace', name: 'RiverRace',
    what: 'The Atari river raid, three planes at once, two flown by aityx',
    desc: 'The 1982 Atari river shooter, remade: banks and islands, bridges, tankers, helicopters, jets and fuel depots, with three planes up one river at once. Two are flown by aityx, each by its own rules (a decision table you can edit while they fly); the yellow one is yours. Who scores more? Every aityx call, sent and received, in a side panel.',
    chips: ['aityx', 'simulation', 'game', 'multiplayer', 'user playable'],
    icon: 'plane', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'PokerFace', name: 'PokerFace',
    what: 'A poker simulator where every player is a set of rules',
    desc: 'No-limit hold’em at a table of up to nine. At each turn the app works out the player’s situation and one aityx call runs their strategy on it: the action, the amount, and the rule that decided it. Five strategies to read, or write your own; every call in a sidebar; the pace in your hands.',
    chips: ['aityx', 'simulation', 'multiplayer'],
    icon: 'cards', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'Cellfie', name: 'Cellfie',
    what: 'The cells take a picture of themselves, and aityx says who’s in it',
    desc: 'Conway’s Game of Life on an infinite board, with the rules of birth and death (Conway’s, HighLife’s and Life without death, as switches) and a catalogue of its patterns, as an aityx decision model: one aityx call per generation names what lives, what dies and which clusters are blocks, gliders or pulsars, with the request and the response in a side panel.',
    chips: ['aityx', 'simulation'],
    icon: 'grid', codespace: 'aityx',
  },
  {
    kind: 'game', folder: 'RoboRules', name: 'RoboRules',
    what: 'Robocode on the web, every turn played by aityx',
    desc: 'Tanks fight until one is left. Every robot’s behavior is an aityx decision model, its rules a table you can edit, and the whole battle (sensors, moves, bullets, hits, damage, scores) is played by aityx; the app only draws it.',
    chips: ['aityx', 'simulation', 'multiplayer'],
    icon: 'robot', codespace: 'aityx',
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
// The aityx console of the website this page is on, by its host: Open runs
// the demo there (#/demos?demo=<slug>). Elsewhere, null.
const consoles = {
  'aityx.ai': 'https://console.aityx.ai',
  'stage.aityx.ai': 'https://console-stage.aityx.ai',
  'localhost:4330': 'http://localhost:9004',
};
const consoleUrl = consoles[window.location.host] || null;
// Where Open goes: the console's Demos tab, or the app beside this page
// (/demos/<slug>/) where there is no console.
const slug = (d) => d.folder.toLowerCase();
const appPath = (d) => consoleUrl
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
    '<a class="shot" href="' + appPath(d) + '" tabindex="-1" aria-hidden="true">' +
    '<img src="' + slug(d) + '.gif" alt="" width="720" height="362" loading="lazy" decoding="async"></a>' +
    '<div class="head"><div class="icon"><svg viewBox="0 0 24 24" fill="currentColor">' + icons[d.icon] + '</svg></div>' +
    '<div><h2>' + d.name + '</h2><p class="what">' + d.what + '</p></div></div>' +
    '<p class="desc">' + d.desc + '</p>' +
    '<div class="chips">' + chips + '</div>' +
    '<div class="status" hidden></div>' +
    '<div class="actions">' +
    '<a class="btn primary" href="' + appPath(d) + '"' + (consoleUrl ? ' title="Opens it in the aityx console, with your API key"' : '') + '>Open</a>' +
    '<a class="btn" href="' + github + d.folder + '" target="_blank" rel="noopener">Source ' + ext + '</a>' +
    (d.codespace ? '<a class="btn" href="' + codespaces(d) + '" target="_blank" rel="noopener">Codespace ' + ext + '</a>' : '') +
    '</div>';
  return el;
}

// Each group's cards into its grid: #games, #apps.
for (const kind of ['game', 'app']) {
  const grid = document.getElementById(kind + 's');
  if (grid) grid.replaceChildren(...demos.filter(d => d.kind === kind).map(card));
}

// Which builds the index server has (api/demos, beside the page): a card
// whose app isn't built, or was built for another path, says so. On a
// static host there's no api/demos, and the cards stay as they are.
async function markBuilds() {
  let list;
  try {
    const r = await fetch('api/demos', { cache: 'no-store' });
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
