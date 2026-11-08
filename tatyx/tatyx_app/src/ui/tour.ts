// The tour's strategies on the server: a player's upload entered in it
// (POST /api/strategies, which asks for a tournament, queued behind the
// one being played), the entries listed, and a player's withdrawn. The
// session cookie says who; the server checks the file again.

import type { Strategy } from '../game/strategy';

export interface Entry {
  id: string;
  name: string;
  tagline: string;
  /** Whose it is: the owner's alias. */
  by: string;
  mine: boolean;
}

/** What entering a strategy came to, in a line for the player. */
export interface Entered {
  ok: boolean;
  text: string;
}

const listeners = new Set<() => void>();

/** Calls `listener` whenever the entries may have changed; returns the unsubscribe. */
export function onEntriesChange(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

async function errorOf(answer: Response): Promise<string> {
  const body = (await answer.json().catch(() => ({}))) as { error?: string };
  return body.error ?? `HTTP ${answer.status}`;
}

/** Enters `s` in the tour for the signed-in player. */
export async function enterInTour(s: Strategy): Promise<Entered> {
  let answer: Response;
  try {
    answer = await fetch('/api/strategies', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ name: s.name, tagline: s.tagline, decisions: s.decisions }),
    });
  } catch {
    return { ok: false, text: 'the server did not answer' };
  }
  if (!answer.ok) return { ok: false, text: await errorOf(answer) };
  const body = (await answer.json()) as { tournament: string | null };
  listeners.forEach((l) => l());
  const next =
    body.tournament === 'started'
      ? 'a tournament is starting for it'
      : body.tournament === 'queued'
        ? 'a tournament for it is queued, after the one being played'
        : body.tournament === 'waiting'
          ? 'it plays in the tournament waiting its turn'
          : 'the leaderboard plays it in its next tournament';
  return { ok: true, text: `in the tour: ${next}` };
}

/** The strategies in the tour; null when signed out or the server did not answer. */
export async function tourEntries(): Promise<Entry[] | null> {
  try {
    const answer = await fetch('/api/strategies', { headers: { Accept: 'application/json' } });
    if (!answer.ok) return null;
    return ((await answer.json()) as { strategies: Entry[] }).strategies;
  } catch {
    return null;
  }
}

/** Withdraws the player's entry `id`; the reason when it could not be. */
export async function withdraw(id: string): Promise<string | null> {
  try {
    const answer = await fetch(`/api/strategies/${encodeURIComponent(id)}`, { method: 'DELETE' });
    if (!answer.ok) return errorOf(answer);
    listeners.forEach((l) => l());
    return null;
  } catch {
    return 'the server did not answer';
  }
}
