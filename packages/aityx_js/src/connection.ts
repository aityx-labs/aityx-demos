// Where aityx calls go, and on whose key. The TypeScript twin of
// packages/aityx_web/lib/src/connection.dart.

/** The production aityx: where a user's key goes unless they set a URL. */
export const AITYX_DEFAULT_URL = 'https://api.aityx.ai';

/**
 * The storage entries the key form writes (localStorage, or
 * sessionStorage for "only this session"): the same names the aityx
 * index page uses, so the stores agree on an origin that has both.
 */
export const AITYX_KEY_NAME = 'aityx.key';
export const AITYX_URL_NAME = 'aityx.url';

/**
 * Whose key a call uses: the user's own (an Authorization header, sent
 * straight to aityx), the dev key (the app's server adds it, through its
 * proxy, so it never reaches the browser), or none.
 */
export type AityxSource = 'user' | 'dev' | 'none';

/**
 * `url` trimmed and without trailing slashes, or the default aityx when
 * it's empty or not an http(s) URL with a host.
 */
export function normalizeAityxUrl(url: string | null | undefined): string {
  let trimmed = (url ?? '').trim();
  while (trimmed.endsWith('/')) trimmed = trimmed.slice(0, -1);
  let parsed: URL;
  try {
    parsed = new URL(trimmed);
  } catch {
    return AITYX_DEFAULT_URL;
  }
  if ((parsed.protocol !== 'https:' && parsed.protocol !== 'http:') || !parsed.hostname) {
    return AITYX_DEFAULT_URL;
  }
  return trimmed;
}

/**
 * The app's server's relay to its own environment's aityx, for a user's
 * key: aityx staging takes no calls from browsers (its CORS preflight
 * answers 403), so a key whose URL is `url` goes to `endpoint`, on the
 * app's origin, which passes the user's Authorization header on as it
 * is and never adds a key of its own.
 */
export interface AityxRelay {
  /** The aityx it relays to (the server's AITYX_URL). */
  readonly url: string;
  /** Where to send the calls instead: `<origin>/aityx/`. */
  readonly endpoint: URL;
}

/** Where aityx calls go, and on whose key. */
export class AityxConnection {
  constructor(
    /** The base: https://api.aityx.ai, or `<origin>/aityx/` in dev mode. */
    readonly endpoint: URL,
    readonly source: AityxSource,
    /** The aityx URL to show: the user's, or the dev config's. */
    readonly url: string,
    /** The user's key; null in dev mode (the server adds it) and with none. */
    readonly key: string | null = null,
    /** In dev mode, where the server found the key: ".env" or "environment". */
    readonly devKeyFrom: string | null = null,
  ) {}

  /**
   * The user's `key`, sent to `url` (the default aityx unless the user set
   * one; a URL that isn't http(s) with a host falls back to the default),
   * through `relay` when it relays to that URL.
   */
  static user(key: string, url?: string | null, relay?: AityxRelay | null): AityxConnection {
    const shown = normalizeAityxUrl(url);
    const through = relay && normalizeAityxUrl(relay.url) === shown ? relay.endpoint : new URL(shown);
    return new AityxConnection(through, 'user', shown, key);
  }

  /**
   * The server's dev proxy at `proxyPath` on `origin` (`/aityx/` by
   * default), which forwards to `url` (as its `config` says) with the key
   * from `devKeyFrom`.
   */
  static dev(origin: URL, proxyPath: string, url = '', devKeyFrom: string | null = null): AityxConnection {
    return new AityxConnection(new URL(proxyPath, origin), 'dev', url, null, devKeyFrom);
  }

  /** No key anywhere: calls throw AityxNoKey. */
  static readonly none = new AityxConnection(new URL(AITYX_DEFAULT_URL), 'none', '');

  /** `<endpoint>/v1/systemone`, whether or not the endpoint ends in a slash. */
  get systemone(): URL {
    const base = this.endpoint.href.endsWith('/') ? this.endpoint.href : `${this.endpoint.href}/`;
    return new URL('v1/systemone', base);
  }

  /** The headers for a call: Content-Type and, with a user key, Authorization. Never log these. */
  headers(json = true): Record<string, string> {
    const headers: Record<string, string> = {};
    if (json) headers['Content-Type'] = 'application/json';
    if (this.key !== null) headers['Authorization'] = `Bearer ${this.key}`;
    return headers;
  }

  /** Whose key, for people: "your key", "dev key from .env", "no key". */
  get whose(): string {
    switch (this.source) {
      case 'user':
        return 'your key';
      case 'dev':
        if (this.devKeyFrom === '.env') return 'dev key from .env';
        if (this.devKeyFrom === 'environment') return 'dev key from the environment';
        return 'dev key';
      case 'none':
        return 'no key';
    }
  }

  /** For debugging: never shows the key. */
  toString(): string {
    return `AityxConnection(${this.source}, ${this.systemone.href})`;
  }
}
