// Each team's strategy, as the player set it on the title: one of the
// presets, or the team's own, uploaded as JSON (a strategy file, as
// downloaded). Kept in this browser (localStorage, best effort: a private
// window or blocked storage just starts from the presets). No Phaser.

import { LINEUP } from './play';
import { BUILDS, STRATEGIES, TEAM_MODEL, strategy, type Build, type Strategy } from './strategy';
import { TEAMS, type TeamId } from './teams';

const STORAGE_KEY = 'tatyx.lineup';
/** The most a strategy file may hold. */
export const MAX_STRATEGY_BYTES = 64 * 1024;

export class BadStrategy extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BadStrategy';
  }
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/**
 * A strategy from a file's text, checked as aityx will need it: a name,
 * and a `build` table whose rows look only at the team model's inputs
 * and answer one of the builds. Throws BadStrategy with what to fix.
 */
export function parseStrategy(text: string): Strategy {
  if (new TextEncoder().encode(text).length > MAX_STRATEGY_BYTES) throw new BadStrategy(`the file is over ${MAX_STRATEGY_BYTES / 1024} KB`);
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new BadStrategy('the file is not JSON');
  }
  if (!isRecord(json)) throw new BadStrategy('a strategy is a JSON object');
  const name = json['name'];
  if (typeof name !== 'string' || name.trim() === '' || name.length > 60) throw new BadStrategy('"name" must be a text of 1 to 60 characters');
  const decisions = json['decisions'];
  const build = isRecord(decisions) ? decisions['build'] : undefined;
  const table = isRecord(build) ? build['table'] : undefined;
  if (!Array.isArray(table) || table.length < 2) throw new BadStrategy('"decisions.build.table" must be a table: a header row, then the rules');
  const inputs = new Set(Object.keys(TEAM_MODEL.inputs));
  table.slice(1).forEach((row, i) => {
    if (!isRecord(row)) throw new BadStrategy(`rule ${i + 1} is not an object`);
    const then = row['then'];
    if (typeof then !== 'string' || !BUILDS.includes(then as Build)) throw new BadStrategy(`rule ${i + 1}: "then" must be one of ${BUILDS.join(', ')}`);
    const when = row['when'];
    if (when !== undefined && !isRecord(when)) throw new BadStrategy(`rule ${i + 1}: "when" must be an object`);
    for (const input of Object.keys(when ?? {})) {
      if (!inputs.has(input)) throw new BadStrategy(`rule ${i + 1} looks at "${input}", which is not an input of the team model`);
    }
  });
  const tagline = typeof json['tagline'] === 'string' ? (json['tagline'] as string).slice(0, 200) : 'A strategy of the team’s own.';
  const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'own';
  return { id: `own-${slug}`, name: name.trim(), tagline, decisions: decisions as Record<string, unknown> };
}

/** A strategy as a file to download: what parseStrategy reads back, and a line on how to edit it. */
export function strategyFile(s: Strategy): string {
  return `${JSON.stringify(
    {
      about: `A tatyx strategy: the build table is tried top to bottom, and the first rule whose "when" holds answers what the team's next megabyte buys (${BUILDS.join(', ')}). The inputs a rule may look at: ${Object.keys(TEAM_MODEL.inputs).join(', ')}. A cell is a comparison (">= 2", "< 1", "3") or true/false.`,
      id: s.id,
      name: s.name,
      tagline: s.tagline,
      decisions: s.decisions,
    },
    null,
    2,
  )}\n`;
}

type Saved = Partial<Record<TeamId, { preset: string } | { own: Strategy }>>;

function load(): Record<TeamId, Strategy> {
  const start = Object.fromEntries(TEAMS.map((t) => [t.id, strategy(LINEUP[t.id])])) as Record<TeamId, Strategy>;
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}') as Saved;
    for (const t of TEAMS) {
      const entry = saved[t.id];
      if (entry && 'preset' in entry && STRATEGIES.some((s) => s.id === entry.preset)) start[t.id] = strategy(entry.preset);
      if (entry && 'own' in entry) {
        try {
          start[t.id] = parseStrategy(JSON.stringify(entry.own));
        } catch {
          // A saved strategy that no longer checks out: the preset.
        }
      }
    }
  } catch {
    // No storage: the presets.
  }
  return start;
}

function save(current: Record<TeamId, Strategy>): void {
  const out: Saved = {};
  for (const t of TEAMS) {
    const s = current[t.id];
    out[t.id] = STRATEGIES.includes(s) ? { preset: s.id } : { own: s };
  }
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(out));
  } catch {
    // No storage: it lasts as long as the page.
  }
}

let current: Record<TeamId, Strategy> | null = null;

/** Each team's strategy now. */
export function lineup(): Readonly<Record<TeamId, Strategy>> {
  current ??= load();
  return current;
}

export function setStrategy(team: TeamId, s: Strategy): void {
  current = { ...lineup(), [team]: s } as Record<TeamId, Strategy>;
  save(current);
}

/** Whether a strategy is the team's own (not a preset). */
export function isOwn(s: Strategy): boolean {
  return !STRATEGIES.includes(s);
}

/** The next (or previous) preset after the team's strategy; from its own, the first. */
export function cyclePreset(team: TeamId, step: 1 | -1): Strategy {
  const now = lineup()[team];
  const at = STRATEGIES.indexOf(now);
  const next = at < 0 ? STRATEGIES[0]! : STRATEGIES[(at + step + STRATEGIES.length) % STRATEGIES.length]!;
  setStrategy(team, next);
  return next;
}
