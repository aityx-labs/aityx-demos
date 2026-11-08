// The key, as the key form (or the aityx index page) stores it. The
// TypeScript twin of packages/aityx_web/lib/src/key_store.dart.

import { AITYX_KEY_NAME, AITYX_URL_NAME, normalizeAityxUrl } from './connection';

/** One storage: localStorage, sessionStorage, or a map. */
export interface StorageArea {
  read(name: string): string | null;
  write(name: string, value: string): void;
  remove(name: string): void;
}

/** A StorageArea in memory. */
export class MapArea implements StorageArea {
  readonly entries: Map<string, string>;

  constructor(entries?: Record<string, string> | Map<string, string>) {
    this.entries = entries instanceof Map ? new Map(entries) : new Map(Object.entries(entries ?? {}));
  }

  read(name: string): string | null {
    return this.entries.get(name) ?? null;
  }

  write(name: string, value: string): void {
    this.entries.set(name, value);
  }

  remove(name: string): void {
    this.entries.delete(name);
  }
}

export type Unsubscribe = () => void;

/**
 * The user's aityx key and URL, in localStorage ("remember on this
 * device") or sessionStorage ("only this session"), under `aityx.key` and
 * `aityx.url`. sessionStorage wins when both hold a key.
 */
export interface AityxKeyStore {
  /** The key, trimmed; null when none is set. */
  readonly key: string | null;
  /** The aityx URL stored with the key; null when none is (a key saved without one: callers default to https://api.aityx.ai). */
  readonly url: string | null;
  /** Whether the key comes from sessionStorage ("only this session"). */
  readonly sessionOnly: boolean;
  /**
   * Stores the key (and the URL, unless empty: production's too, so the
   * key keeps going where it was saved for) in
   * sessionStorage when `sessionOnly`, else in localStorage, and clears
   * the other storage. Throws on an empty key.
   */
  save(key: string, options?: { url?: string | null; sessionOnly?: boolean }): void;
  /** Removes the key and URL from both storages. */
  forget(): void;
  /**
   * Calls `listener` whenever the key or URL changes: on save and forget,
   * and in the browser when another tab changes them. Returns the
   * unsubscribe.
   */
  onChange(listener: () => void): Unsubscribe;
}

/** An AityxKeyStore over two StorageAreas, the browser's semantics. */
export class StorageKeyStore implements AityxKeyStore {
  private readonly listeners = new Set<() => void>();
  private stopExternal: Unsubscribe | null = null;

  constructor(
    readonly local: StorageArea,
    readonly session: StorageArea,
    /** Changes from elsewhere (the browser's storage event): called with the notifier once someone listens. */
    private readonly external?: (notify: () => void) => Unsubscribe,
  ) {}

  /** The area that holds the key: session first. */
  private get holder(): StorageArea | null {
    if (read(this.session, AITYX_KEY_NAME) !== null) return this.session;
    if (read(this.local, AITYX_KEY_NAME) !== null) return this.local;
    return null;
  }

  get key(): string | null {
    const holder = this.holder;
    return holder === null ? null : read(holder, AITYX_KEY_NAME);
  }

  get url(): string | null {
    const holder = this.holder;
    if (holder !== null) return read(holder, AITYX_URL_NAME);
    return read(this.session, AITYX_URL_NAME) ?? read(this.local, AITYX_URL_NAME);
  }

  get sessionOnly(): boolean {
    return this.holder === this.session;
  }

  save(key: string, options: { url?: string | null; sessionOnly?: boolean } = {}): void {
    const trimmed = key.trim();
    if (trimmed === '') throw new Error('an empty key');
    const sessionOnly = options.sessionOnly ?? false;
    const into = sessionOnly ? this.session : this.local;
    const other = sessionOnly ? this.local : this.session;
    remove(other, AITYX_KEY_NAME);
    remove(other, AITYX_URL_NAME);
    write(into, AITYX_KEY_NAME, trimmed);
    const url = options.url ?? '';
    if (url.trim() === '') {
      remove(into, AITYX_URL_NAME);
    } else {
      write(into, AITYX_URL_NAME, normalizeAityxUrl(url));
    }
    this.notify();
  }

  forget(): void {
    for (const area of [this.local, this.session]) {
      remove(area, AITYX_KEY_NAME);
      remove(area, AITYX_URL_NAME);
    }
    this.notify();
  }

  onChange(listener: () => void): Unsubscribe {
    this.listeners.add(listener);
    if (this.external && this.stopExternal === null) {
      this.stopExternal = this.external(() => this.notify());
    }
    return () => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0 && this.stopExternal !== null) {
        this.stopExternal();
        this.stopExternal = null;
      }
    };
  }

  private notify(): void {
    for (const listener of [...this.listeners]) listener();
  }
}

// The browser can refuse storage (blocked cookies, some private modes):
// then there's no key, rather than an error.

function read(area: StorageArea, name: string): string | null {
  try {
    const value = area.read(name)?.trim();
    return value === undefined || value === '' ? null : value;
  } catch {
    return null;
  }
}

function write(area: StorageArea, name: string, value: string): void {
  try {
    area.write(name, value);
  } catch {
    // Storage refused: no key, rather than an error.
  }
}

function remove(area: StorageArea, name: string): void {
  try {
    area.remove(name);
  } catch {
    // Storage refused.
  }
}

/**
 * An in-memory store, for tests: `local` and `session` are the two
 * storages' starting entries.
 */
export function memoryKeyStore(options: { local?: Record<string, string>; session?: Record<string, string> } = {}): AityxKeyStore {
  return new StorageKeyStore(new MapArea(options.local), new MapArea(options.session));
}

/** One Storage, looked up on each use: reading window.localStorage can throw when the browser blocks storage. */
class WebArea implements StorageArea {
  constructor(private readonly storage: () => Storage) {}
  read(name: string): string | null {
    return this.storage().getItem(name);
  }
  write(name: string, value: string): void {
    this.storage().setItem(name, value);
  }
  remove(name: string): void {
    this.storage().removeItem(name);
  }
}

let browserStore: AityxKeyStore | null = null;

/**
 * The one browser store, shared by every page on the origin, so every
 * part of the app shares its changes; an in-memory store off the browser
 * (tests, Node).
 */
export function browserKeyStore(): AityxKeyStore {
  if (browserStore !== null) return browserStore;
  if (typeof window === 'undefined') return (browserStore = memoryKeyStore());
  return (browserStore = new StorageKeyStore(
    new WebArea(() => window.localStorage),
    new WebArea(() => window.sessionStorage),
    (notify) => {
      // The storage event fires in the other tabs of the origin when one
      // changes localStorage; a null key means storage was cleared.
      const onStorage = (event: StorageEvent) => {
        if (event.key === null || event.key === AITYX_KEY_NAME || event.key === AITYX_URL_NAME) notify();
      };
      window.addEventListener('storage', onStorage);
      return () => window.removeEventListener('storage', onStorage);
    },
  ));
}
