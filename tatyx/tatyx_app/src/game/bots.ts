// The five bots, the characters of tatyx: the letters of aityx, the
// robots of the concept art (art/reference/five-bots.png), each with the
// part it plays on the map. Pure data: no Phaser here. The numbers that
// make the parts real (speeds, rates, costs) are the world's rules, in
// world.ts.

export type BotId = 'A' | 'I' | 'T' | 'Y' | 'X';

/** A bot's kind, as a strategy names it. */
export type BotKind = 'anchor' | 'builder' | 'tester' | 'combinator' | 'explorer';

export interface Bot {
  readonly id: BotId;
  readonly kind: BotKind;
  readonly name: string;
  /** The part, in a line: the roster's caption. */
  readonly motto: string;
  /** What it does on the map, in full: the hint on hover. */
  readonly part: string;
  /** The portrait under public/. */
  readonly portrait: string;
}

export const BOTS: readonly Bot[] = [
  {
    id: 'A',
    kind: 'anchor',
    name: 'Anchor',
    motto: 'Holds a site: while it stands there, only its team builds on it.',
    part: 'Walks the links to the best site it knows, where its team builds, and stays: while it stands there, only its team builds on the site.',
    portrait: 'bots/a-anchor.png',
  },
  {
    id: 'I',
    kind: 'builder',
    name: 'Builder',
    motto: 'Builds bytes on a site: the more it builds, the more bots to deploy.',
    part: 'Walks the links to a site and builds bytes there for its team, twice as fast with a Tester of its team beside it; a site near the mainframe builds twice as fast.',
    portrait: 'bots/i-builder.png',
  },
  {
    id: 'T',
    kind: 'tester',
    name: 'Tester',
    motto: 'Renews the links it crosses, and doubles a Builder.',
    part: 'Renews every link it crosses, the rotting ones first; on a site with its team’s Builder it doubles the Builder, on a site its team’s Anchor holds it builds.',
    portrait: 'bots/t-tester.png',
  },
  {
    id: 'Y',
    kind: 'combinator',
    name: 'Combinator',
    motto: 'Joins two links into a shortcut, and builds like a Builder.',
    part: 'Where two links meet, makes a direct link between their far ends, a shortcut; with none to make, builds on a site like a Builder (a Tester doesn’t double it).',
    portrait: 'bots/y-combinator.png',
  },
  {
    id: 'X',
    kind: 'explorer',
    name: 'Explorer',
    motto: 'Runs free, and finds the sites and the links between them.',
    part: 'The only one that moves off the links: runs anywhere on the map, and every site it reaches, with the links from it, joins the team’s map.',
    portrait: 'bots/x-explorer.png',
  },
];

export function bot(id: BotId): Bot {
  const found = BOTS.find((b) => b.id === id);
  if (!found) throw new Error(`no bot ${id}`);
  return found;
}

export function botOfKind(kind: BotKind): Bot {
  const found = BOTS.find((b) => b.kind === kind);
  if (!found) throw new Error(`no bot of kind ${kind}`);
  return found;
}

/**
 * The portrait in a team's colours: public/bots/<team>/<bot>.png, painted
 * from the orange original by tool/recolor.mjs. Without a team, the
 * original.
 */
export function portraitOf(b: Bot, team?: string): string {
  return team === undefined ? b.portrait : b.portrait.replace('bots/', `bots/${team}/`);
}

/** The texture key the scenes load a portrait under. */
export function textureOf(id: BotId, team?: string): string {
  return team === undefined ? `bot-${id}` : `bot-${team}-${id}`;
}
