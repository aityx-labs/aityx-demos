// A team's strategy: the one decision aityx makes in tatyx, what the
// team's next megabyte buys (a bot of one of the five kinds, a bot sent
// to the mainframe to build the hack, or nothing yet), as a decision table on the team's situation.
// The team model (models/team.json) declares the situation's inputs; a
// strategy (strategies/*.json) is the `build` decision on them, in the
// shape of PokerFace's strategies. This module builds the systemone
// request and reads the answer; it never calls anything.

import type { BotKind } from './bots';
import teamModel from './models/team.json';
import doubler from './strategies/doubler.json';
import farmer from './strategies/farmer.json';
import fortress from './strategies/fortress.json';
import sprinter from './strategies/sprinter.json';
import swarm from './strategies/swarm.json';
import type { Situation } from './world';

/** What a strategy answers: a bot to buy, a bot to send to the mainframe, or save for later. */
export type Build = BotKind | 'hack' | 'save';

export const BUILDS: readonly Build[] = ['anchor', 'builder', 'tester', 'combinator', 'explorer', 'hack', 'save'];

export interface Strategy {
  readonly id: string;
  readonly name: string;
  readonly tagline: string;
  /** The decisions: `build`, a table on the team model's inputs. */
  readonly decisions: Record<string, unknown>;
}

/** The presets, in the order shown. */
export const STRATEGIES: readonly Strategy[] = [farmer, sprinter, swarm, doubler, fortress].map((s) => ({
  id: s.id,
  name: s.name,
  tagline: s.tagline,
  decisions: s.decisions as Record<string, unknown>,
}));

export function strategy(id: string): Strategy {
  const found = STRATEGIES.find((s) => s.id === id);
  if (!found) throw new Error(`no strategy ${id}`);
  return found;
}

/** The team model: the name, the types and the inputs every strategy decides on. */
export const TEAM_MODEL = teamModel as { name: string; types: Record<string, string>; inputs: Record<string, unknown> };

/** The body of the systemone call: the team model with the strategy's decisions, and the situation as its state. */
export function buildRequest(s: Strategy, state: Situation): Record<string, unknown> {
  return {
    decision: {
      name: `${TEAM_MODEL.name} · ${s.name}`,
      types: TEAM_MODEL.types,
      inputs: TEAM_MODEL.inputs,
      decisions: s.decisions,
    },
    state,
  };
}

/** A strategy's answer, as read from aityx's. */
export interface Decision {
  readonly build: Build;
  /** The 1-based row of the table that fired, when aityx says. */
  readonly rule: number | null;
  /** That row's `why`. */
  readonly why: string | null;
}

export class DecisionFailed extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DecisionFailed';
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/** The decision in aityx's answer to a request built by `buildRequest`. Throws DecisionFailed when there is none. */
export function readDecision(sent: Record<string, unknown>, answer: unknown): Decision {
  if (!isRecord(answer)) throw new DecisionFailed('unexpected answer from aityx');
  const error = answer['decision_error'];
  if (isRecord(error)) {
    const detail = typeof error['detail'] === 'string' ? `, ${error['detail']}` : '';
    throw new DecisionFailed(`the strategy failed: ${String(error['code'])}${detail}`);
  }
  const answers = answer['answers'];
  const receipt = answer['receipt'];
  if (!isRecord(answers) || !isRecord(receipt)) throw new DecisionFailed('no answers');
  const build = isRecord(answers['build']) ? answers['build']['choice'] : undefined;
  if (typeof build !== 'string' || !BUILDS.includes(build as Build)) throw new DecisionFailed('no build');
  const table = tableOf(sent);
  const decisions = receipt['decisions'];
  const rule = isRecord(decisions) && isRecord(decisions['build']) ? decisions['build']['rule'] : undefined;
  const fired = typeof rule === 'number' && Number.isInteger(rule) && rule >= 1 && rule < table.length ? rule : null;
  const row = fired === null ? undefined : table[fired];
  const why = isRecord(row) && typeof row['why'] === 'string' ? row['why'] : null;
  return { build: build as Build, rule: fired, why };
}

function tableOf(sent: Record<string, unknown>): unknown[] {
  const decision = sent['decision'];
  const decisions = isRecord(decision) ? decision['decisions'] : undefined;
  const build = isRecord(decisions) ? decisions['build'] : undefined;
  const table = isRecord(build) ? build['table'] : build;
  return Array.isArray(table) ? table : [];
}

/**
 * The same decision, taken by the table itself, without aityx: what the
 * headless runner and the tests use, and the only thing to compare
 * aityx's answer against. Rows are tried top to bottom; a cell is a
 * number comparison (`>= 2`, `< 1`, `3`) or a boolean (`true`, `false`).
 */
export function decideLocally(s: Strategy, state: Situation): Decision {
  const table = tableOf({ decision: { decisions: s.decisions } });
  for (let i = 1; i < table.length; i++) {
    const row = table[i];
    if (!isRecord(row)) continue;
    const when = isRecord(row['when']) ? row['when'] : {};
    const matches = Object.entries(when).every(([input, cell]) => holds((state as unknown as Record<string, unknown>)[input], String(cell)));
    if (matches) {
      const then = row['then'];
      if (typeof then !== 'string' || !BUILDS.includes(then as Build)) throw new DecisionFailed(`row ${i} answers ${String(then)}`);
      return { build: then as Build, rule: i, why: typeof row['why'] === 'string' ? row['why'] : null };
    }
  }
  throw new DecisionFailed('no row matched');
}

function holds(value: unknown, cell: string): boolean {
  const c = cell.trim();
  if (typeof value === 'boolean') return c === String(value);
  if (typeof value !== 'number') return false;
  const m = /^(>=|<=|>|<|=)?\s*(-?\d+(?:\.\d+)?)$/.exec(c);
  if (!m) return false;
  const n = Number(m[2]);
  switch (m[1] ?? '=') {
    case '>=':
      return value >= n;
    case '<=':
      return value <= n;
    case '>':
      return value > n;
    case '<':
      return value < n;
    default:
      return value === n;
  }
}
