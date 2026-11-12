// The aityx status light, top right on every screen. The TypeScript twin
// of packages/aityx_web/lib/src/status_light.dart, as a DOM element.

import { checkAityx, stateTooltip, type AityxState, type CheckOptions } from './check';
import { browserKeyStore, type AityxKeyStore } from './keyStore';

export interface StatusLightOptions extends CheckOptions {
  /** The check: checkAityx with these options unless a test gives its own. */
  check?: () => Promise<AityxState>;
  /** On click: the app's key form, usually. Nothing happens without one. */
  onClick?: () => void;
  /** The least time between two checks on focus, in milliseconds. */
  minIntervalMs?: number;
}

export interface StatusLight {
  readonly element: HTMLButtonElement;
  /** The last check's result; null while it checks. */
  state(): AityxState | null;
  /** A check now. */
  refresh(): void;
  dispose(): void;
}

/** The aityx palette's dim, green and red. */
export const LIGHT_COLORS = { checking: '#47474D', ok: '#4CC38A', fail: '#F0506E' };

const STYLE_ID = 'aityx-js-status-light';

function ensureStyles(): void {
  if (typeof document === 'undefined' || document.getElementById(STYLE_ID)) return;
  const style = document.createElement('style');
  style.id = STYLE_ID;
  style.textContent = `
.aityx-light { all: unset; cursor: pointer; display: inline-grid; place-items: center; width: 14px; height: 14px; border-radius: 50%; }
.aityx-light:focus-visible { outline: 2px solid #EB7B58; outline-offset: 2px; }
.aityx-light .aityx-dot { width: 8px; height: 8px; border-radius: 50%; background: ${LIGHT_COLORS.checking}; opacity: .85; transition: background .2s; }
.aityx-light[data-state="ok"] .aityx-dot { background: ${LIGHT_COLORS.ok}; box-shadow: 0 0 0 3px rgba(76, 195, 138, .18); }
.aityx-light[data-state="fail"] .aityx-dot { background: ${LIGHT_COLORS.fail}; }
`;
  document.head.append(style);
}

/**
 * An 8 px dot: grey while it checks, green when aityx accepts the key,
 * red otherwise; why, on hover and for screen readers. It checks on
 * start, when the key store changes (the key form, or another tab, sets
 * or forgets the key), and when the window regains focus, at most once
 * every `minIntervalMs` for focus. No timer polling: each check spends a
 * request of the user's quota.
 */
export function mountStatusLight(parent: Element, options: StatusLightOptions = {}): StatusLight {
  ensureStyles();
  const store: AityxKeyStore = options.store ?? browserKeyStore();
  const minInterval = options.minIntervalMs ?? 30_000;
  const check = options.check ?? (() => checkAityx({ ...options, store }));

  const element = document.createElement('button');
  element.type = 'button';
  element.className = 'aityx-light';
  const dot = document.createElement('span');
  dot.className = 'aityx-dot';
  element.append(dot);
  parent.append(element);

  let current: AityxState | null = null;
  let last: number | null = null;
  let running = false;
  let again = false;
  let disposed = false;

  const show = (state: AityxState | null) => {
    current = state;
    const message = state === null ? 'aityx: checking' : stateTooltip(state);
    element.title = message;
    element.setAttribute('aria-label', message);
    element.dataset['state'] = state === null ? 'checking' : state.ok ? 'ok' : 'fail';
  };

  const run = async (grey: boolean) => {
    running = true;
    last = Date.now();
    if (grey) show(null);
    let state: AityxState;
    try {
      state = await check();
    } catch (error) {
      state = {
        ok: false,
        key: store.key !== null,
        source: store.key !== null ? 'user' : 'none',
        url: null,
        detail: `the check failed: ${error instanceof Error ? error.name : 'Error'}`,
        kind: 'failing',
        whose: store.key !== null ? 'your key' : 'no key',
      };
    }
    running = false;
    if (disposed) return;
    if (again) {
      again = false;
      void run(false);
      return;
    }
    show(state);
  };

  /** A check now; unless `force`, only if the last one is old enough. */
  const trigger = (force: boolean) => {
    if (disposed) return;
    if (!force && last !== null && Date.now() - last < minInterval) return;
    if (running) {
      again = true;
      // The key changed: what the light shows is stale.
      if (force && current !== null) show(null);
      return;
    }
    void run(force && current !== null);
  };

  const stopStore = store.onChange(() => trigger(true));
  const onFocus = () => trigger(false);
  const onVisible = () => {
    if (document.visibilityState === 'visible') trigger(false);
  };
  window.addEventListener('focus', onFocus);
  document.addEventListener('visibilitychange', onVisible);
  element.addEventListener('click', () => options.onClick?.());

  show(null);
  trigger(true);

  return {
    element,
    state: () => current,
    refresh: () => trigger(true),
    dispose: () => {
      disposed = true;
      stopStore();
      window.removeEventListener('focus', onFocus);
      document.removeEventListener('visibilitychange', onVisible);
      element.remove();
    },
  };
}
