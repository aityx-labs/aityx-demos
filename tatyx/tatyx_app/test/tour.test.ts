import { describe, expect, it } from 'vitest';
import { parseStrategy, strategyFile } from '../src/game/lineup';
import { STRATEGIES, decideLocally } from '../src/game/strategy';
import { TEAMS } from '../src/game/teams';
import { FIELD, pickField, playMatch, standings, strategiesFrom, type MatchResult } from '../src/game/tournament';

// A player's entry: the Farmer's rules under a name of its own.
const mine = { ...parseStrategy(JSON.stringify({ name: 'My Farm', tagline: 'Mine', decisions: STRATEGIES[0]!.decisions })), id: 'u-1' };

describe('the players’ strategies in a tournament', () => {
  it('a field of five, the fewest matches played first, a player’s before a preset', () => {
    const played: Record<string, number> = { farmer: 18, sprinter: 18, swarm: 36, doubler: 18, fortress: 18 };
    const field = pickField([...STRATEGIES, mine], (id) => played[id] ?? 0, () => 0.5);
    expect(field).toHaveLength(FIELD);
    expect(field[0]).toBe(mine);
    expect(field.map((s) => s.id)).not.toContain('swarm');
    // On a tie, the player's first.
    expect(pickField([...STRATEGIES, mine], () => 0)[0]).toBe(mine);
  });

  it('a lineup names its strategies from the pool, an entry too', async () => {
    const lineup = { cyan: 'u-1', magenta: 'farmer', green: 'swarm' } as const;
    expect(strategiesFrom(lineup, [...STRATEGIES, mine]).cyan).toBe(mine);
    expect(() => strategiesFrom(lineup)).toThrow(/no strategy u-1/);
    const result = await playMatch(async (_team, s, state) => decideLocally(s, state), lineup, 30, 7, [...STRATEGIES, mine]);
    expect(result.lineup.cyan).toBe('u-1');
    expect(result.decisions).toBeGreaterThan(0);
  });

  it('the standings: every strategy that played, by wins per match', () => {
    const result = (cyan: string, magenta: string, green: string, winner: 'cyan' | 'magenta' | 'green' | null): MatchResult => ({
      lineup: { cyan, magenta, green },
      seed: 1,
      winner,
      winnerStrategy: winner === null ? null : { cyan, magenta, green }[winner],
      seconds: 100,
      progress: Object.fromEntries(TEAMS.map((t) => [t.id, 50])) as MatchResult['progress'],
      bots: Object.fromEntries(TEAMS.map((t) => [t.id, 3])) as MatchResult['bots'],
      decisions: 10,
      failed: 0,
    });
    // The Farmer wins 2 of 3; the entry 1 of 1: the entry first.
    const rows = standings(
      [result('farmer', 'sprinter', 'swarm', 'cyan'), result('farmer', 'doubler', 'fortress', 'cyan'), result('farmer', 'u-1', 'swarm', 'magenta')],
      [...STRATEGIES, mine],
    );
    expect(rows.map((r) => r.strategy).slice(0, 2)).toEqual(['u-1', 'farmer']);
    expect(rows.find((r) => r.strategy === 'u-1')).toMatchObject({ name: 'My Farm', played: 1, wins: 1 });
    expect(rows).toHaveLength(6);
  });

  it('an entry round-trips through its file', () => {
    expect(parseStrategy(strategyFile(mine)).decisions).toEqual(mine.decisions);
  });
});
