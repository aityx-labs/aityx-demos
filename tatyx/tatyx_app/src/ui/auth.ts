// Who is playing: the server's config (how to sign in, its aityx and the
// relay to it) and the signed-in player. Signing in is Google's own
// button (Google Identity Services, loaded from accounts.google.com only
// when the server has a client id); its ID token goes to the server once,
// which checks it and opens a session (an HttpOnly cookie the page never
// sees). Signing out ends the session.

import type { AityxRelay, ResolveOptions } from 'aityx-js';

export interface Player {
  readonly email: string;
  readonly name: string | null;
  readonly picture: string | null;
  /** What the leaderboard calls them; null: their name. */
  readonly alias: string | null;
  readonly admin: boolean;
}

export interface ServerConfig {
  readonly signIn: { clientId: string; domains: string[] } | null;
  /** This environment's aityx: staging on a laptop, production deployed. */
  readonly aityxUrl: string;
  /** The path on this origin that relays the player's calls to aityxUrl (on their own key); null for none. */
  readonly aityxRelay: string | null;
}

type Listener = () => void;

interface GoogleId {
  initialize(options: Record<string, unknown>): void;
  renderButton(parent: HTMLElement, options: Record<string, unknown>): void;
  disableAutoSelect(): void;
}

declare global {
  interface Window {
    google?: { accounts: { id: GoogleId } };
  }
}

const GSI = 'https://accounts.google.com/gsi/client';

class Auth {
  config: ServerConfig | null = null;
  player: Player | null = null;
  /** What went wrong with the last sign-in, for people. */
  error: string | null = null;
  /** Whether the first load is done. */
  loaded = false;
  private listeners = new Set<Listener>();
  private gsi: Promise<GoogleId> | null = null;

  onChange(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(): void {
    for (const l of this.listeners) l();
  }

  /** Asks the server how to sign in and who is signed in. */
  async load(): Promise<void> {
    try {
      const config = await fetch('/api/config', { headers: { Accept: 'application/json' } });
      this.config = config.ok ? ((await config.json()) as ServerConfig) : null;
      const who = await fetch('/api/session', { headers: { Accept: 'application/json' } });
      this.player = who.ok ? ((await who.json()) as Player) : null;
    } catch {
      this.config = null;
      this.player = null;
    }
    this.loaded = true;
    this.emit();
  }

  private loadGsi(): Promise<GoogleId> {
    this.gsi ??= new Promise((resolve, reject) => {
      if (window.google?.accounts?.id) return resolve(window.google.accounts.id);
      const script = document.createElement('script');
      script.src = GSI;
      script.async = true;
      script.onload = () => (window.google?.accounts?.id ? resolve(window.google.accounts.id) : reject(new Error('Google sign-in did not load')));
      script.onerror = () => reject(new Error('Google sign-in could not be loaded'));
      document.head.append(script);
    });
    return this.gsi;
  }

  /** Google's button, in `parent`; signs in when pressed. */
  async renderButton(parent: HTMLElement): Promise<void> {
    const clientId = this.config?.signIn?.clientId;
    if (!clientId) return;
    try {
      const id = await this.loadGsi();
      id.initialize({
        client_id: clientId,
        callback: (answer: { credential?: string }) => void this.signIn(answer.credential ?? ''),
        auto_select: false,
        ux_mode: 'popup',
      });
      parent.replaceChildren();
      id.renderButton(parent, { theme: 'filled_black', size: 'large', shape: 'pill', text: 'signin_with' });
    } catch (error) {
      this.error = error instanceof Error ? error.message : String(error);
      this.emit();
    }
  }

  /** Hands Google's ID token to the server, which opens the session. */
  private async signIn(credential: string): Promise<void> {
    this.error = null;
    try {
      const answer = await fetch('/api/session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ credential }),
      });
      const body = (await answer.json().catch(() => ({}))) as Record<string, unknown>;
      if (answer.ok) this.player = body as unknown as Player;
      else this.error = typeof body['error'] === 'string' ? body['error'] : `the server answered HTTP ${answer.status}`;
    } catch {
      this.error = 'the server did not answer';
    }
    this.emit();
  }

  /** Sets what the leaderboard calls the player; empty for their name. Throws what went wrong, for people. */
  async setAlias(alias: string): Promise<void> {
    let answer: Response;
    try {
      answer = await fetch('/api/me', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ alias }),
      });
    } catch {
      throw new Error('the server did not answer');
    }
    const body = (await answer.json().catch(() => ({}))) as Record<string, unknown>;
    if (!answer.ok) throw new Error(typeof body['error'] === 'string' ? body['error'] : `the server answered HTTP ${answer.status}`);
    this.player = body as unknown as Player;
    this.emit();
  }

  async signOut(): Promise<void> {
    try {
      await fetch('/api/session', { method: 'DELETE' });
    } catch {
      // Signed out here regardless.
    }
    window.google?.accounts?.id?.disableAutoSelect();
    this.player = null;
    this.emit();
  }
}

export const auth = new Auth();

/** The server's relay to its aityx, once its config arrived: the player's calls to that aityx go through it. */
export function aityxRelay(): AityxRelay | null {
  const c = auth.config;
  if (!c?.aityxRelay) return null;
  return { url: c.aityxUrl, endpoint: new URL(c.aityxRelay, window.location.origin) };
}

/** How the game reaches aityx: the player's own key, through the relay to this server's aityx; nobody lends one. */
export const aityxOptions: ResolveOptions = { lend: false, relay: aityxRelay };
