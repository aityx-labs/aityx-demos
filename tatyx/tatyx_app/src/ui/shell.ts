// The page around the canvas: the bar (the brand, home on a click, the match's controls,
// the music and the aityx light), the game pane, and
// the sidebar of three tabs, as Poker Tour's: the leaderboard, the aityx
// calls (a line each; a click opens the whole call) and the profile (the
// account and the aityx key). Plain DOM, in the aityx palette (style.css).
import { browserKeyStore, mountKeyForm, mountStatusLight, type StatusLight } from 'aityx-js';

import { synthwave } from '../audio/synthwave';
import { aityxOptions, aityxRelay, auth } from './auth';
import { mountLeaderboard } from './leaderboard';

/** One call as the panel shows it. */
export interface ShownCall {
  /** The line: who decided what. */
  readonly title: string;
  /** The rule's why, or what went wrong. */
  readonly detail: string | null;
  /** The team's name and colour. */
  readonly team: { name: string; css: string } | null;
  /** The match's clock when asked, "0:23". */
  readonly at: string | null;
  readonly request: unknown;
  readonly response: unknown;
  readonly tookMs: number;
  readonly ok: boolean;
}

export type Tab = 'leaderboard' | 'calls' | 'profile';
/** The match, as the bar's controls show it; null: no match on screen. */
export type PlayState = 'ready' | 'running' | 'paused' | 'over' | null;

export interface Controls {
  show(state: PlayState): void;
  /** What Start / Pause / Resume / Play again does; null: nothing. */
  onPlay(handler: (() => void) | null): void;
  /** The simulation's speed: 1 is real time. */
  readonly speed: number;
}

export interface Shell {
  /** Where the game canvas goes. */
  readonly game: HTMLElement;
  readonly light: StatusLight;
  readonly controls: Controls;
  /** Adds a call to the panel, newest first. */
  showCall(call: ShownCall): void;
  clearCalls(): void;
  openTab(tab: Tab): void;
  /** Whether the game has a key to play on: the player's own (nobody lends one). */
  hasKey(): boolean;
  /** Calls `listener` whenever hasKey() may have changed; returns the unsubscribe. */
  onKeyChange(listener: () => void): () => void;
  /** What the brand in the bar does when clicked: home, the title. */
  onHome(handler: () => void): void;
}

/** The logo: the board in small (public/favicon.svg, the tab's icon too). */
const LOGO = `<img src="./favicon.svg" alt="" width="26" height="26">`;

const SPEEDS = [0.5, 1, 2, 4, 8];

export function mountShell(root: HTMLElement): Shell {
  root.innerHTML = `
<header class="bar">
  <a class="brand" id="home" href="./" title="Home">${LOGO}<span>tatyx</span></a>
  <div class="controls" id="controls" hidden>
    <button class="btn primary" id="play" type="button">Start</button>
    <label class="speed">speed
      <select id="speed" aria-label="Simulation speed">${SPEEDS.map((s) => `<option value="${s}"${s === 1 ? ' selected' : ''}>${s === 0.5 ? '½' : s}×</option>`).join('')}</select>
    </label>
  </div>
  <div class="spacer"></div>
  <button class="btn" id="toggle-music" type="button" aria-pressed="true" title="The synthwave soundtrack, played by the browser itself">music</button>
  <input class="volume" id="volume" type="range" min="0" max="100" step="1" aria-label="Music volume">
  <div class="status"><span id="light-label">aityx</span><span id="light"></span></div>
</header>
<div class="stage">
  <div id="game"></div>
  <aside id="side" aria-label="Sidebar">
    <nav class="tabs" role="tablist">
      <button role="tab" type="button" data-tab="leaderboard">Leaderboard</button>
      <button role="tab" type="button" data-tab="calls">aityx calls <span class="count" id="calls-count">(0)</span></button>
      <button role="tab" type="button" data-tab="profile">Profile <span class="nokey" id="nokey" title="No aityx key to play on" hidden></span></button>
    </nav>
    <section class="panel" data-panel="leaderboard" id="leaderboard"></section>
    <section class="panel" data-panel="calls">
      <div class="list" id="calls-list"><p class="empty" id="calls-empty"></p></div>
    </section>
    <section class="panel" data-panel="profile" id="profile">
      <h3>Account</h3>
      <div id="account"></div>
      <h3>Your aityx key</h3>
      <p class="note" id="key-note"></p>
      <div id="key-form"></div>
      <p class="muted small">Get a key from the API keys page of the aityx console (<a href="https://console.aityx.ai" target="_blank" rel="noopener">console.aityx.ai</a>). It stays in this browser, with its URL; for this server’s aityx it goes through the server, which passes it on and never keeps it.</p>
    </section>
  </aside>
</div>
<dialog class="call-view" id="call-view">
  <button class="close" type="button" aria-label="Close" id="call-close">×</button>
  <h2 id="call-title"></h2>
  <p class="detail" id="call-detail"></p>
  <div class="section-head"><span>request</span><button class="btn small" type="button" data-copy="req">Copy request</button></div>
  <pre id="call-req"></pre>
  <div class="section-head"><span>response</span><button class="btn small" type="button" data-copy="res">Copy response</button></div>
  <pre id="call-res"></pre>
</dialog>`;

  const $ = <T extends HTMLElement>(sel: string) => root.querySelector<T>(sel)!;
  const game = $('#game');
  const store = browserKeyStore();

  // ---- The sidebar's tabs -------------------------------------------------
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
  const panels = [...root.querySelectorAll<HTMLElement>('[data-panel]')];
  let current: Tab = 'leaderboard';
  const tabListeners = new Set<(tab: Tab) => void>();
  const openTab = (tab: Tab) => {
    current = tab;
    for (const t of tabs) t.setAttribute('aria-selected', String(t.dataset['tab'] === tab));
    for (const p of panels) p.hidden = p.dataset['panel'] !== tab;
    for (const l of tabListeners) l(tab);
  };
  for (const t of tabs) t.addEventListener('click', () => openTab(t.dataset['tab'] as Tab));

  // ---- The light and the key ----------------------------------------------
  const light = mountStatusLight($('#light'), { ...aityxOptions, store, onClick: () => openTab('profile') });
  const hasKey = () => store.key !== null;
  const keyListeners = new Set<() => void>();
  const onKeyChange = (listener: () => void) => {
    keyListeners.add(listener);
    return () => void keyListeners.delete(listener);
  };
  const keyChanged = () => {
    for (const l of keyListeners) l();
  };
  store.onChange(keyChanged);
  auth.onChange(keyChanged);

  // ---- The profile -------------------------------------------------------
  const account = $('#account');
  const keyNote = $('#key-note');
  const nokey = $('#nokey');
  const showProfile = () => {
    const signIn = auth.config?.signIn ?? null;
    const p = auth.player;
    if (!auth.loaded) {
      account.innerHTML = '<p class="muted">…</p>';
    } else if (p !== null) {
      account.innerHTML = `
<div class="who">${p.picture ? '<img alt="" referrerpolicy="no-referrer">' : ''}<div><div class="name"></div><div class="email muted"></div></div>${p.admin ? '<span class="badge">admin</span>' : ''}</div>
<button class="btn" type="button" id="sign-out">Sign out</button>
<div class="alias">
  <label for="alias">Your name on the leaderboard</label>
  <input id="alias" name="alias" maxlength="32" autocomplete="off" spellcheck="false">
</div>`;
      if (p.picture) account.querySelector('img')!.src = p.picture;
      const name = p.name ?? p.email.split('@')[0]!;
      account.querySelector('.name')!.textContent = p.name ?? p.email;
      account.querySelector('.email')!.textContent = p.email;
      account.querySelector('#sign-out')!.addEventListener('click', () => void auth.signOut());
      // The alias, else the name: what the leaderboard shows under the player's strategies,
      // saved with the key by Save profile; Enter saves too.
      const aliasInput = account.querySelector<HTMLInputElement>('#alias')!;
      aliasInput.value = p.alias ?? name;
      aliasInput.placeholder = name;
      aliasInput.addEventListener('keydown', (e) => {
        if (e.key !== 'Enter') return;
        e.preventDefault();
        keyForm.element.requestSubmit();
      });
    } else if (signIn === null) {
      account.innerHTML = '<p class="note bad">Sign-in is not set up on this server yet (it has no Google client: TATYX_OIDC_CLIENT_ID), so nobody can play here.</p>';
    } else {
      const base = import.meta.env.BASE_URL;
      account.innerHTML = `<p>Sign in to play.</p><div id="gsi"></div><p class="note bad" id="auth-error" hidden></p>`
        + `<p class="note">By signing in you agree to the <a href="${base}tos" target="_blank" rel="noopener">Terms</a> and the <a href="${base}privacy" target="_blank" rel="noopener">Privacy Policy</a>.</p>`;
      void auth.renderButton(account.querySelector('#gsi')!);
    }
    const error = account.querySelector<HTMLElement>('#auth-error');
    if (error) {
      error.hidden = auth.error === null;
      error.textContent = auth.error ?? '';
    }
    // Which key the game runs on.
    if (store.key !== null) {
      keyNote.className = 'note';
      keyNote.textContent = 'Your games run on your own key, below, kept in this browser with its URL until you forget it.';
    } else {
      keyNote.className = 'note bad';
      keyNote.textContent = 'There is no aityx key for your games yet. Set yours below to play: every player brings their own.';
    }
    nokey.hidden = hasKey();
  };
  // The profile's one button, Save profile: the name on the leaderboard when it changed, then the key when it did.
  const saveAlias = async (): Promise<string | null> => {
    const p = auth.player;
    const input = account.querySelector<HTMLInputElement>('#alias');
    if (p === null || input === null) return null;
    const name = p.name ?? p.email.split('@')[0]!;
    const alias = input.value.replace(/\s+/g, ' ').trim();
    if (alias === (p.alias ?? name) || (alias === '' && p.alias === null)) return null;
    await auth.setAlias(alias);
    return 'Your name on the leaderboard is saved.';
  };
  const keyForm = mountKeyForm($('#key-form'), {
    store,
    submitLabel: 'Save profile',
    alsoSave: saveAlias,
    // This server's aityx (staging locally, production deployed) until /api/config answers.
    defaultUrl: auth.config?.aityxUrl,
    // The check goes where the game's calls go: through the relay to this server's aityx.
    relay: aityxRelay,
    onSaved: () => {
      light.refresh();
      showProfile();
    },
    onForgot: () => {
      light.refresh();
      showProfile();
    },
  });
  auth.onChange(() => {
    if (auth.config?.aityxUrl) keyForm.setDefaultUrl(auth.config.aityxUrl);
    showProfile();
    light.refresh();
  });
  showProfile();
  // Where the sidebar opens: Profile when there's no key to play on, else the leaderboard.
  let firstLoad = true;
  auth.onChange(() => {
    if (!auth.loaded) return;
    if (!hasKey()) openTab('profile');
    else if (firstLoad) openTab('leaderboard');
    firstLoad = false;
  });

  // ---- The leaderboard ----------------------------------------------------
  const board = mountLeaderboard($('#leaderboard'));
  tabListeners.add((tab) => board.visible(tab === 'leaderboard'));

  // ---- The calls --------------------------------------------------------
  const list = $('#calls-list');
  const empty = $('#calls-empty');
  const count = $('#calls-count');
  const EMPTY =
    'Every megabyte a team collects is one question to its strategy on aityx: what does it buy, an Anchor, a Builder, a Tester, a Combinator, an Explorer, or a bot sent to hack the mainframe? Each call shows here as a line; click one for the request and the answer, in full. Nothing yet: start a match.';
  empty.textContent = EMPTY;
  let n = 0;
  const view = $<HTMLDialogElement>('#call-view');
  let shown: ShownCall | null = null;
  const openCall = (call: ShownCall) => {
    shown = call;
    $('#call-title').textContent = `${call.ok ? '✓' : '✗'} ${call.at ? `${call.at} · ` : ''}${call.title} · ${call.tookMs} ms`;
    $('#call-detail').textContent = call.detail ?? '';
    $('#call-req').textContent = pretty(call.request);
    $('#call-res').textContent = pretty(call.response);
    view.showModal();
  };
  $('#call-close').addEventListener('click', () => view.close());
  view.addEventListener('click', (e) => {
    if (e.target === view) view.close();
  });
  for (const b of view.querySelectorAll<HTMLButtonElement>('[data-copy]')) {
    b.addEventListener('click', () => {
      if (shown === null) return;
      void navigator.clipboard?.writeText(pretty(b.dataset['copy'] === 'req' ? shown.request : shown.response)).then(() => {
        const was = b.textContent;
        b.textContent = 'Copied';
        setTimeout(() => (b.textContent = was), 1200);
      });
    });
  }
  const showCall = (call: ShownCall) => {
    empty.hidden = true;
    n += 1;
    count.textContent = `(${n})`;
    const line = document.createElement('button');
    line.type = 'button';
    line.className = `call-line${call.ok ? '' : ' failed'}`;
    line.innerHTML = '<span class="dot"></span><span class="at"></span><span class="what"></span><span class="ms"></span>';
    const dot = line.querySelector<HTMLElement>('.dot')!;
    dot.style.background = call.ok ? (call.team?.css ?? 'var(--muted)') : 'var(--red)';
    line.querySelector('.at')!.textContent = call.at ?? '';
    line.querySelector('.what')!.textContent = call.title;
    line.querySelector('.ms')!.textContent = `${call.tookMs} ms`;
    line.title = call.detail ?? call.title;
    line.addEventListener('click', () => openCall(call));
    empty.after(line);
  };
  const clearCalls = () => {
    n = 0;
    count.textContent = '(0)';
    for (const line of list.querySelectorAll('.call-line')) line.remove();
    empty.hidden = false;
  };

  // ---- The match's controls ------------------------------------------------
  const controls = $('#controls');
  const play = $<HTMLButtonElement>('#play');
  const speedSelect = $<HTMLSelectElement>('#speed');
  let playHandler: (() => void) | null = null;
  let speed = 1;
  try {
    const saved = Number(localStorage.getItem('tatyx.speed'));
    if (SPEEDS.includes(saved)) speed = saved;
  } catch {
    // No storage: real time.
  }
  speedSelect.value = String(speed);
  speedSelect.addEventListener('change', () => {
    speed = Number(speedSelect.value);
    try {
      localStorage.setItem('tatyx.speed', String(speed));
    } catch {
      // Kept for the page.
    }
  });
  let playState: PlayState = null;
  // Start takes a key to play on: off without one.
  const showPlayable = () => {
    play.disabled = playState === 'ready' && !hasKey();
    play.title = play.disabled ? 'No aityx key to play on: set yours in Profile.' : '';
  };
  onKeyChange(showPlayable);
  play.addEventListener('click', () => playHandler?.());
  // Space starts, pauses and resumes, unless typing.
  document.addEventListener('keydown', (e) => {
    if (e.key !== ' ' || playHandler === null || controls.hidden || play.disabled) return;
    const t = e.target as HTMLElement | null;
    if (t && (t.closest('input, textarea, select, button, dialog') !== null)) return;
    e.preventDefault();
    playHandler();
  });
  const LABELS: Record<Exclude<PlayState, null>, string> = { ready: 'Start', running: 'Pause', paused: 'Resume', over: 'Play again' };
  const controlsApi: Controls = {
    show(state) {
      playState = state;
      showPlayable();
      controls.hidden = state === null;
      if (state !== null) {
        play.textContent = LABELS[state];
        play.classList.toggle('primary', state !== 'running');
      }
    },
    onPlay(handler) {
      playHandler = handler;
    },
    get speed() {
      return speed;
    },
  };

  // ---- The music --------------------------------------------------------
  const music = $<HTMLButtonElement>('#toggle-music');
  music.setAttribute('aria-pressed', String(synthwave.enabled));
  music.addEventListener('click', () => synthwave.toggle());
  synthwave.onChange((on) => music.setAttribute('aria-pressed', String(on)));
  const volume = $<HTMLInputElement>('#volume');
  const showVolume = () => {
    volume.title = `Music volume: ${volume.value}%`;
  };
  volume.value = String(Math.round(synthwave.volume * 100));
  showVolume();
  volume.addEventListener('input', () => {
    synthwave.setVolume(Number(volume.value) / 100);
    showVolume();
  });

  // ---- The brand: home, from anywhere ----------------------------------
  let homeHandler: (() => void) | null = null;
  $('#home').addEventListener('click', (e) => {
    if (homeHandler === null) return;
    e.preventDefault();
    homeHandler();
  });
  const onHome = (handler: () => void) => {
    homeHandler = handler;
  };

  openTab('leaderboard');
  void auth.load();
  return { game, light, controls: controlsApi, showCall, clearCalls, openTab, hasKey, onKeyChange, onHome };
}

function pretty(value: unknown): string {
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}
