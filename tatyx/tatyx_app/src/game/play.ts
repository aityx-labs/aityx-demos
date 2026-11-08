// A match: the world, ticking, and the three teams' strategies asked
// what each next megabyte buys. Whenever a team has a megabyte and no
// question pending, its strategy is asked (a `Decider`: aityx in the
// app, the table itself in tests and the headless runner); the answer
// buys a bot, sends one of the team's bots to the mainframe to build the
// hack, or saves the megabyte, in which case
// the team is asked again a little later. No Phaser here: the scene
// calls `advance` with the time that passed and draws what it finds.

import { TEAMS, type TeamId } from './teams';
import { strategy, type Build, type Decision, type Strategy } from './strategy';

import { buy, hackerFor, newWorld, RULES, sendHacker, situation, step, type Situation, type World } from './world';

/** Which preset each team plays, to begin with. */
export const LINEUP: Readonly<Record<TeamId, string>> = {
  cyan: 'farmer',
  magenta: 'sprinter',
  green: 'swarm',
};

/** A lineup of preset ids as the strategies themselves. */
export function strategiesOf(ids: Readonly<Record<TeamId, string>>): Record<TeamId, Strategy> {
  return Object.fromEntries(TEAMS.map((t) => [t.id, strategy(ids[t.id])])) as Record<TeamId, Strategy>;
}

/** Asks a strategy what a team's next megabyte buys. */
export type Decider = (team: TeamId, s: Strategy, state: Situation) => Promise<Decision>;

/** One decision as it went, for the panel and the summary. */
export interface Made {
  readonly team: TeamId;
  readonly seconds: number;
  readonly state: Situation;
  readonly decision: Decision | null;
  readonly error: string | null;
}

/** After `save`, how long before the team is asked again. */
export const ASK_AGAIN_SECONDS = 5;
/** After a failed question (no key, no answer, a strategy aityx refused), how long before the team tries again. */
export const RETRY_SECONDS = 15;

export class Match {
  world: World;
  readonly made: Made[] = [];
  private pending = new Set<TeamId>();
  /** The questions on their way, to wait for (`settle`). */
  private inflight = new Set<Promise<void>>();
  private askAt = new Map<TeamId, number>();
  private carry = 0;
  /** Which match a late answer belongs to. */
  private generation = 0;

  constructor(
    private readonly decider: Decider,
    /** Each team's strategy: a preset, or one of the team's own. */
    readonly lineup: Readonly<Record<TeamId, Strategy>> = strategiesOf(LINEUP),
    private readonly onMade?: (made: Made) => void,
    /** The map's seed: a new map each match unless given, to replay one. */
    seed?: number,
  ) {
    this.world = newWorld(seed);
  }

  strategyOf(team: TeamId): Strategy {
    return this.lineup[team];
  }

  /** Starts over, on a new map unless given a seed. */
  reset(seed?: number): void {
    this.generation += 1;
    this.world = newWorld(seed);
    this.made.length = 0;
    this.pending.clear();
    this.inflight.clear();
    this.askAt.clear();
    this.carry = 0;
  }

  /** Whether a question is on its way. */
  get asking(): boolean {
    return this.pending.size > 0;
  }

  /** Waits for every question on its way: a headless match calls it after each tick, so it never runs ahead of its decisions. */
  async settle(): Promise<void> {
    while (this.inflight.size > 0) await Promise.all([...this.inflight]);
  }

  /** Plays the time that passed, in whole ticks, and asks whoever can afford a question. */
  advance(seconds: number): void {
    this.carry += seconds;
    while (this.carry >= RULES.tickSeconds) {
      this.carry -= RULES.tickSeconds;
      this.world = step(this.world);
    }
    if (this.world.winner !== null) return;
    for (const t of TEAMS) {
      if (this.pending.has(t.id)) continue;
      if (this.world.teams.find((s) => s.id === t.id)!.bytes < RULES.botCost) continue;
      if ((this.askAt.get(t.id) ?? 0) > this.world.seconds) continue;
      const asking = this.ask(t.id);
      this.inflight.add(asking);
      void asking.finally(() => this.inflight.delete(asking));
    }
  }

  private async ask(team: TeamId): Promise<void> {
    const generation = this.generation;
    const state = situation(this.world, team);
    const s = this.strategyOf(team);
    this.pending.add(team);
    let made: Made;
    try {
      const decision = await this.decider(team, s, state);
      made = { team, seconds: state.seconds, state, decision, error: null };
    } catch (error) {
      made = { team, seconds: state.seconds, state, decision: null, error: error instanceof Error ? error.message : String(error) };
    }
    if (generation !== this.generation) return;
    this.pending.delete(team);
    this.made.push(made);
    this.onMade?.(made);
    if (made.decision === null) {
      this.askAt.set(team, this.world.seconds + RETRY_SECONDS);
      return;
    }
    this.apply(team, made.decision.build);
  }

  /**
   * What a decision does to the world. A team that can no longer afford
   * it (it can't happen; the bytes only grow), or answers `hack` with
   * every bot already sent, saves.
   */
  private apply(team: TeamId, build: Build): void {
    if (this.world.winner !== null) return;
    const bytes = this.world.teams.find((s) => s.id === team)!.bytes;
    if (build === 'save' || bytes < RULES.botCost || (build === 'hack' && hackerFor(this.world, team) === null)) {
      this.askAt.set(team, this.world.seconds + ASK_AGAIN_SECONDS);
      return;
    }
    this.world = build === 'hack' ? sendHacker(this.world, team) : buy(this.world, team, build);
  }
}
