// The teams, and their colour tags. Three teams, one per sector of the
// map, each tagged with a colour of its own; orange, the aityx colour, is
// never a team's: it tags what the computer defines (the mainframe, the
// sites' bytes until taken), so a player can always tell its own from
// the system's.
//
// The list itself is teams.json, so that tool/recolor.mjs, which paints
// each team's portraits from the orange originals, reads the same
// colours. Change a colour there, run `npm run recolor`, and the map
// follows.

import list from './teams.json';

export type TeamId = 'cyan' | 'magenta' | 'green';

export interface Tag {
  readonly id: TeamId | 'system';
  readonly name: string;
  /** The colour, for Phaser. */
  readonly color: number;
  /** The colour, for CSS and Phaser text. */
  readonly css: string;
}

export interface Team extends Tag {
  readonly id: TeamId;
}

export const TEAMS: readonly Team[] = list.map((t) => ({
  id: t.id as TeamId,
  name: t.name,
  css: t.color.toUpperCase(),
  color: Number.parseInt(t.color.slice(1), 16),
}));

/** The computer's tag: orange, and no team may have it. */
export const SYSTEM: Tag = { id: 'system', name: 'the computer', color: 0xe36742, css: '#E36742' };

export function team(id: TeamId): Team {
  const found = TEAMS.find((t) => t.id === id);
  if (!found) throw new Error(`no team ${id}`);
  return found;
}

export function tag(id: TeamId | 'system'): Tag {
  return id === 'system' ? SYSTEM : team(id);
}
