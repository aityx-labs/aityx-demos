// The leaderboard's tournament: the preset strategies play every lineup
// (each strategy in each seat, so no sector favours anyone), one headless
// match each, and the standings follow from the results. A headless match
// waits for its decisions after every tick, so how fast aityx answers
// never changes how it ends. Pure: the decider is given (the server's, on
// the leaderboard key; the table itself in tests).

import { Match, strategiesOf, type Decider } from './play';
import { STRATEGIES } from './strategy';
import { TEAMS, type TeamId } from './teams';
import { hackedPct, randomSeed, RULES } from './world';

export type Lineup = Readonly<Record<TeamId, string>>;

/** A match with no winner by then ends there, and counts as a draw. */
export const MAX_MATCH_SECONDS = 600;

export interface MatchResult {
  readonly lineup: Lineup;
  /** The map's seed: the same seed and lineup play the same match. */
  readonly seed: number;
  readonly winner: TeamId | null;
  readonly winnerStrategy: string | null;
  readonly seconds: number;
  /** Each team's progress into the hack at the end, 0 to 100. */
  readonly progress: Readonly<Record<TeamId, number>>;
  /** Each team's bots at the end. */
  readonly bots: Readonly<Record<TeamId, number>>;
  readonly decisions: number;
  readonly failed: number;
}

export interface Standing {
  readonly strategy: string;
  readonly name: string;
  readonly played: number;
  readonly wins: number;
  /** Mean progress into the hack at the end of its matches, 0 to 100. */
  readonly progress: number;
  /** Mean time of its wins, in seconds; null without a win. */
  readonly winSeconds: number | null;
}

/**
 * The tournament's lineups: every trio of the strategies, each trio
 * three times, turned a seat each time, so every strategy plays every
 * sector against every pair of the others.
 */
export function lineups(ids: readonly string[] = STRATEGIES.map((s) => s.id)): Lineup[] {
  if (ids.length < TEAMS.length) throw new Error(`a lineup takes ${TEAMS.length} strategies`);
  const out: Lineup[] = [];
  for (let i = 0; i < ids.length; i++) {
    for (let j = i + 1; j < ids.length; j++) {
      for (let k = j + 1; k < ids.length; k++) {
        const trio = [ids[i]!, ids[j]!, ids[k]!];
        for (let turn = 0; turn < TEAMS.length; turn++) {
          out.push(Object.fromEntries(TEAMS.map((t, seat) => [t.id, trio[(seat + turn) % trio.length]!])) as Record<TeamId, string>);
        }
      }
    }
  }
  return out;
}

export class AityxFailing extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AityxFailing';
  }
}

/** One headless match: ticks, waiting for every decision, until a winner or MAX_MATCH_SECONDS; on a new map unless given a seed. */
export async function playMatch(decider: Decider, lineup: Lineup, maxSeconds = MAX_MATCH_SECONDS, seed: number = randomSeed()): Promise<MatchResult> {
  const match = new Match(decider, strategiesOf(lineup), undefined, seed);
  while (match.world.winner === null && match.world.seconds < maxSeconds) {
    match.advance(RULES.tickSeconds);
    await match.settle();
    // aityx refusing every question (a bad key, a broken strategy): no point playing on.
    const failed = match.made.filter((m) => m.error !== null);
    if (failed.length >= 3 && failed.length === match.made.length) throw new AityxFailing(failed[failed.length - 1]!.error!);
  }
  const w = match.world;
  return {
    lineup,
    seed,
    winner: w.winner,
    winnerStrategy: w.winner === null ? null : lineup[w.winner],
    seconds: Math.round(w.seconds * 10) / 10,
    progress: Object.fromEntries(TEAMS.map((t) => [t.id, Math.round(hackedPct(w, t.id) * 10) / 10])) as Record<TeamId, number>,
    bots: Object.fromEntries(TEAMS.map((t) => [t.id, w.bots.filter((b) => b.team === t.id).length])) as Record<TeamId, number>,
    decisions: match.made.length,
    failed: match.made.filter((m) => m.error !== null).length,
  };
}

/** The standings over some results: most wins first, then the most progress, then the fastest wins. */
export function standings(results: readonly MatchResult[]): Standing[] {
  const rows = STRATEGIES.map((s) => {
    const seats = results.flatMap((r) => TEAMS.filter((t) => r.lineup[t.id] === s.id).map((t) => ({ r, team: t.id })));
    const wins = seats.filter(({ r, team }) => r.winner === team);
    const mean = (xs: number[]) => (xs.length === 0 ? 0 : xs.reduce((a, b) => a + b, 0) / xs.length);
    return {
      strategy: s.id,
      name: s.name,
      played: seats.length,
      wins: wins.length,
      progress: Math.round(mean(seats.map(({ r, team }) => r.progress[team])) * 10) / 10,
      winSeconds: wins.length === 0 ? null : Math.round(mean(wins.map(({ r }) => r.seconds))),
    };
  });
  return rows.sort(
    (a, b) => b.wins - a.wins || b.progress - a.progress || (a.winSeconds ?? Infinity) - (b.winSeconds ?? Infinity) || a.name.localeCompare(b.name),
  );
}

/**
 * A whole tournament: every lineup, one match each, in turn: 30 matches
 * for five strategies. A trio plays its three turns on the same map, so
 * the seats are compared fairly: a new map per trio, or, given a seed,
 * the trio's maps from it, to replay the tournament.
 */
export async function playTournament(
  decider: Decider,
  onMatch?: (done: number, of: number, result: MatchResult) => void,
  seed?: number,
): Promise<{ results: MatchResult[]; standings: Standing[] }> {
  const all = lineups();
  const results: MatchResult[] = [];
  const seeds = new Map<number, number>();
  for (const [i, lineup] of all.entries()) {
    const trio = Math.floor(i / TEAMS.length);
    if (!seeds.has(trio)) seeds.set(trio, seed === undefined ? randomSeed() : (seed + trio) >>> 0);
    const result = await playMatch(decider, lineup, MAX_MATCH_SECONDS, seeds.get(trio)!);
    results.push(result);
    onMatch?.(results.length, all.length, result);
  }
  return { results, standings: standings(results) };
}
