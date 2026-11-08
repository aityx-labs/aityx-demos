import { describe, expect, it } from 'vitest';
import { check, matches, type Call } from '../src/game/runner';
import { STRATEGIES, decideLocally, type Strategy } from '../src/game/strategy';
import { lineups, playMatch, standings } from '../src/game/tournament';
import type { Situation } from '../src/game/world';

/** A player's entry: the Farmer's rules under a name of its own. */
const ENTRY: Strategy = { ...STRATEGIES[0]!, id: 'e-1', name: 'My Farm' };

/** aityx, as the table itself decides. */
const local: Call = async (body) => {
  const decision = body['decision'] as { decisions: Record<string, unknown> };
  const made = decideLocally({ id: 'x', name: 'x', tagline: '', decisions: decision.decisions }, body['state'] as Situation);
  return { status: 200, json: { answers: { build: { choice: made.build } }, receipt: { decisions: { build: { rule: made.rule } } } } };
};

describe("the players' entries", () => {
  it('make the tournament every trio of the presets and the entries seated', () => {
    expect(matches()).toBe(30);
    expect(matches(2)).toBe(105);
    expect(lineups([...STRATEGIES.map((s) => s.id), ENTRY.id]).filter((l) => Object.values(l).includes(ENTRY.id))).toHaveLength(30);
  });

  it('play their matches and stand with the presets', async () => {
    const field = [...STRATEGIES, ENTRY];
    const result = await playMatch(async (_team, s, state) => decideLocally(s, state), { cyan: ENTRY.id, magenta: 'sprinter', green: 'swarm' }, 60, 7, field);
    expect(result.lineup.cyan).toBe(ENTRY.id);
    expect(result.decisions).toBeGreaterThan(0);
    const rows = standings([result], field);
    expect(rows).toHaveLength(6);
    expect(rows.find((r) => r.strategy === ENTRY.id)).toMatchObject({ name: 'My Farm', played: 1 });
    expect(rows.find((r) => r.strategy === 'farmer')).toMatchObject({ played: 0 });
  });

  it('refuse an id the tournament has no strategy for', async () => {
    await expect(playMatch(async (_team, s, state) => decideLocally(s, state), { cyan: 'nobody', magenta: 'sprinter', green: 'swarm' }, 10)).rejects.toThrow(/no strategy nobody/);
  });

  it('are checked once on aityx before they enter', async () => {
    await expect(check(local, ENTRY)).resolves.toBeUndefined();
    await expect(check(async () => ({ status: 400, json: { detail: 'bad table' } }), ENTRY)).rejects.toThrow(/HTTP 400: bad table/);
    await expect(check(async () => ({ status: 401, json: null }), ENTRY)).rejects.toThrow(/rejected the key/);
    await expect(check(async () => ({ status: 200, json: { decision_error: { code: 'eval', detail: 'no such input' } } }), ENTRY)).rejects.toThrow(/the strategy failed: eval/);
  });
});
