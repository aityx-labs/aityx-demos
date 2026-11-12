// One systemone call: the request body in, the answer out, timed. The
// TypeScript twin of packages/aityx_web/lib/src/client.dart.

import { AityxConnection } from './connection';
import { browserKeyStore, type AityxKeyStore } from './keyStore';
import { isRecord, resolveConnection, spoken, tryJson, type ResolveOptions } from './settings';

/** Thrown when there is no key at all. */
export class AityxNoKey extends Error {
  /** What to show people. */
  static readonly message = 'aityx is not set up: set your key (the light, top right)';
  constructor() {
    super(AityxNoKey.message);
    this.name = 'AityxNoKey';
  }
}

/**
 * Thrown when the request never got an answer: the network, CORS, an ad
 * blocker, or the timeout. The browser doesn't say which.
 */
export class AityxUnreachable extends Error {
  /** What to show people. */
  static readonly message = 'aityx did not answer';
  constructor(
    /** Why, as far as the app can tell: "timed out after 90 s", or the error's name. Never holds the key. */
    readonly why?: string,
  ) {
    super(AityxUnreachable.message);
    this.name = 'AityxUnreachable';
  }
}

/** aityx's answer to one call. */
export class AityxAnswer {
  constructor(
    /** The HTTP status: aityx's, or (in dev mode) the proxy's 502. */
    readonly status: number,
    /** The body as JSON; null when it isn't JSON. */
    readonly json: unknown,
    /** The body as text. */
    readonly text: string,
    /** From sending the request to reading the whole answer, in milliseconds. */
    readonly tookMs: number,
  ) {}

  /** Whether aityx answered 200. */
  get ok(): boolean {
    return this.status === 200;
  }

  /** aityx's error `code` ("invalid_request", "proxy_unreachable"...), if the body has one. */
  get code(): string | null {
    return this.field('code');
  }

  /** aityx's error `detail`, if the body has one. */
  get detail(): string | null {
    return this.field('detail');
  }

  /** What went wrong, for people; null when ok. */
  get problem(): string | null {
    if (this.ok) return null;
    if (this.status === 401 || this.status === 403) return 'aityx rejected the key';
    const why = this.detail;
    return `aityx answered HTTP ${this.status}${why === null ? '' : `: ${why}`}`;
  }

  private field(name: string): string | null {
    if (!isRecord(this.json)) return null;
    const value = this.json[name];
    return typeof value === 'string' && value !== '' ? value : null;
  }
}

export interface ClientOptions extends ResolveOptions {
  /** A connection to use always (tests); without one, the client resolves it. */
  connection?: AityxConnection;
}

/**
 * Calls aityx's systemone on the connection's key.
 *
 * Give it a `connection` to use that one always (tests); without one, it
 * resolves it (resolveConnection) on the first call and again once the
 * key store's key or URL changes, or while there's no key (the dev key
 * may turn up).
 */
export class AityxClient {
  private readonly fixed: AityxConnection | null;
  private readonly store: AityxKeyStore;
  private readonly fetcher: typeof fetch;
  private resolving: Promise<AityxConnection> | null = null;
  private resolved: AityxConnection | null = null;
  private resolvedFor: string | null = null;

  constructor(private readonly options: ClientOptions = {}) {
    this.fixed = options.connection ?? null;
    this.store = options.store ?? browserKeyStore();
    this.fetcher = options.fetch ?? ((input, init) => globalThis.fetch(input, init));
  }

  /** What the store holds now, and the relay, to tell when either changed. */
  private snapshot(): string {
    return `${this.store.sessionOnly} ${this.store.url} ${this.options.relay?.()?.endpoint.href ?? ''} ${this.store.key}`;
  }

  /** The connection calls use now. */
  connection(): Promise<AityxConnection> {
    if (this.fixed !== null) return Promise.resolve(this.fixed);
    const now = this.snapshot();
    if (this.resolving !== null && this.resolvedFor === now) return this.resolving;
    if (this.resolved !== null && this.resolvedFor === now && this.resolved.source !== 'none') {
      return Promise.resolve(this.resolved);
    }
    this.resolvedFor = now;
    const next = resolveConnection({ ...this.options, store: this.store, fetch: this.fetcher });
    this.resolving = next;
    return next.then((connection) => {
      if (this.resolving === next) {
        this.resolving = null;
        this.resolved = connection;
      }
      return connection;
    });
  }

  /**
   * POSTs `body` (a JSON string, or anything JSON.stringify takes) to
   * systemone. Answers whatever aityx answers, errors included: check
   * `ok` and `problem`. Throws AityxNoKey with no key and AityxUnreachable
   * when no answer comes within the timeout.
   */
  async systemone(body: unknown, options: { timeoutMs?: number } = {}): Promise<AityxAnswer> {
    const to = await this.connection();
    if (to.source === 'none') throw new AityxNoKey();
    const timeoutMs = options.timeoutMs ?? 90_000;
    const payload = typeof body === 'string' ? body : JSON.stringify(body);
    const started = performance.now();
    let response: Response;
    try {
      response = await this.fetcher(to.systemone, {
        method: 'POST',
        headers: to.headers(),
        body: payload,
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      if (error instanceof Error && error.name === 'TimeoutError') {
        throw new AityxUnreachable(`timed out after ${spoken(timeoutMs)}`);
      }
      throw new AityxUnreachable(error instanceof Error ? error.name : 'Error');
    }
    const text = await response.text();
    return new AityxAnswer(response.status, tryJson(text), text, Math.round(performance.now() - started));
  }
}
