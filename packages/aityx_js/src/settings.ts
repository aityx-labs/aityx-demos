// Where the key comes from: the user's, then the dev proxy, then none.
// The TypeScript twin of packages/aityx_web/lib/src/settings.dart.

import { AityxConnection, type AityxRelay } from './connection';
import { browserKeyStore, type AityxKeyStore } from './keyStore';

/**
 * Where an app's server answers for aityx on the app's origin: `config`
 * under it says whether the server has a dev key, and `v1/systemone`
 * under it is the proxy that adds it. The tatyx demos' servers use
 * `/aityx/`; the aityx index uses `/demos/aityx/`.
 */
export const DEFAULT_PROXY_PATH = '/aityx/';

export interface ResolveOptions {
  /** The key store; the browser's unless given. */
  store?: AityxKeyStore;
  /** The page's origin; the window's unless given. Off http(s) there's no dev proxy to ask. */
  origin?: URL;
  /** The dev proxy's path on the origin; DEFAULT_PROXY_PATH unless given. */
  proxyPath?: string;
  /** The fetch to use; the global one unless given (tests). */
  fetch?: typeof fetch;
  timeoutMs?: number;
  /**
   * Whether to ask the origin for a dev key it lends (true unless given).
   * False where every user brings their own key (the multyx games).
   */
  lend?: boolean;
  /** The server's relay for the user's key, asked on each resolve; none unless given. */
  relay?: () => AityxRelay | null;
}

/** The page's origin, or null off the browser. */
export function pageOrigin(): URL | null {
  if (typeof window === 'undefined' || !window.location) return null;
  try {
    return new URL(window.location.href);
  } catch {
    return null;
  }
}

/**
 * Reads the key the way every app agrees on:
 *
 * 1. the user's key from the store (sessionStorage, then localStorage),
 *    sent straight to its URL, or through `relay` when it relays there;
 * 2. else, unless `lend` is false, the dev key, when the origin's
 *    `<proxyPath>config` says the server has one: calls go to
 *    `<origin><proxyPath>`, which adds it;
 * 3. else none.
 *
 * Never throws: a missing, failing or non-JSON config (a static host's
 * 404 or its index.html) means no dev key.
 */
export async function resolveConnection(options: ResolveOptions = {}): Promise<AityxConnection> {
  const keys = options.store ?? browserKeyStore();
  const key = keys.key;
  if (key !== null) return AityxConnection.user(key, keys.url, options.relay?.() ?? null);
  if (options.lend === false) return AityxConnection.none;

  const page = options.origin ?? pageOrigin();
  if (page === null || (page.protocol !== 'http:' && page.protocol !== 'https:')) {
    return AityxConnection.none;
  }
  const proxyPath = options.proxyPath ?? DEFAULT_PROXY_PATH;
  const ask = options.fetch ?? globalThis.fetch;
  if (typeof ask !== 'function') return AityxConnection.none;
  try {
    const answer = await ask(new URL(`${proxyPath}config`, page), {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(options.timeoutMs ?? 10_000),
    });
    const config: unknown = tryJson(await answer.text());
    if (answer.status !== 200 || !isRecord(config) || config['available'] !== true) {
      return AityxConnection.none;
    }
    const url = config['url'];
    const from = config['source'];
    return AityxConnection.dev(page, proxyPath, typeof url === 'string' ? url : '', typeof from === 'string' ? from : null);
  } catch {
    return AityxConnection.none;
  }
}

/** `text` as JSON, or null when it isn't JSON. */
export function tryJson(text: string): unknown {
  try {
    return JSON.parse(text) as unknown;
  } catch {
    return null;
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/** A duration for people: "90 s", or "250 ms" when not whole seconds. */
export function spoken(ms: number): string {
  return ms % 1000 === 0 ? `${ms / 1000} s` : `${ms} ms`;
}
