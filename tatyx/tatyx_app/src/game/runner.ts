// The leaderboard's runner, for the server: bundled for Node by `npm run
// build` (vite.runner.config.ts) into dist-runner/runner.mjs, which
// tatyx_server/server.mjs imports. It plays a tournament on whatever
// `call` reaches aityx with: the server's, on the leaderboard key, which
// never leaves the server. No DOM, no Phaser, no key here.

import { BadStrategy, parseStrategy } from './lineup';
import type { Decider } from './play';
import { buildRequest, readDecision, STRATEGIES, type Strategy } from './strategy';
import { FIELD, lineups, pickField, playTournament, standings, type MatchResult, type Standing } from './tournament';

export { BadStrategy, FIELD, lineups, parseStrategy, pickField, standings, STRATEGIES, type MatchResult, type Standing, type Strategy };

/** One systemone call: the body in, aityx's status and parsed body out. */
export type Call = (body: Record<string, unknown>) => Promise<{ status: number; json: unknown }>;

function problemOf(status: number, json: unknown): string {
  if (status === 401 || status === 403) return 'aityx rejected the key';
  const detail = typeof json === 'object' && json !== null && typeof (json as Record<string, unknown>)['detail'] === 'string' ? `: ${(json as Record<string, string>)['detail']}` : '';
  return `aityx answered HTTP ${status}${detail}`;
}

/** The decider on a `call`: the strategy's request, aityx's answer read. */
export function deciderOn(call: Call): Decider {
  return async (_team, s, state) => {
    const sent = buildRequest(s, state);
    const answer = await call(sent);
    if (answer.status !== 200) throw new Error(problemOf(answer.status, answer.json));
    return readDecision(sent, answer.json);
  };
}

/** A tournament of the `field` (the presets by default) on aityx through `call`. */
export function run(
  call: Call,
  onMatch?: (done: number, of: number, result: MatchResult) => void,
  field: readonly Strategy[] = STRATEGIES,
): Promise<{ results: MatchResult[]; standings: Standing[] }> {
  return playTournament(deciderOn(call), onMatch, undefined, field);
}

/** How many matches a tournament plays. */
export const MATCHES = lineups().length;
