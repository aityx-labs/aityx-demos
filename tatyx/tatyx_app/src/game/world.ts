// The world: the map and what is on it, as plain data and pure functions,
// with no Phaser in it. The scenes draw it; `step` plays it, one tick at
// a time; the one decision a team makes, what its next megabyte buys, is
// aityx's (strategy.ts, play.ts).
//
// The scheme. The map is a hidden graph of SITES joined by LINKS: each
// team's ORIGIN (its database), nine sites where bytes are BUILT (the
// ones near the mainframe build twice as fast as the ones near the
// origins), each up to its size and no further, placed and sized anew
// every game, and the MAINFRAME in the middle, the goal. A team knows only
// what its Explorer has found. A link has health and rots away with time;
// a Tester renews every link it crosses. Bots other than the Explorer walk
// the links only. Builders and Combinators build bytes for their team on
// the site they stand on, as long as the site is connected to the team's
// origin by links it knows and no other team's Anchor holds it; a Tester
// doubles its team's Builders where it stands, or builds itself on a site
// its team's Anchor holds. Every megabyte a team builds buys a bot, or
// sends one of its bots to the mainframe for good: there it builds,
// whatever its kind, and what it builds is its team's hack; the first team to build the
// hack's price wins.

import { BOTS, botOfKind, type BotId, type BotKind } from './bots';
import { TEAMS, type TeamId } from './teams';

export interface Point {
  readonly x: number;
  readonly y: number;
}

export const KB = 1024;
export const MB = 1024 * KB;

/** The rules of the world: the numbers that make the parts real. To be balanced by playing. */
export const RULES = {
  /** What a bot costs, and what sending one to the mainframe costs. */
  botCost: MB,
  /** The bytes a team builds at the mainframe to hack it, from 0 to done. */
  hackCost: 6 * MB,
  /** How fast a node builds: the relays near the origins, the cores near the mainframe, and the mainframe, into the hack. */
  richness: { relay: 1, core: 2, mainframe: 3 },
  /** A link goes from full health to gone in this many seconds. */
  rotSeconds: 45,
  /** A link under this health counts as rotting. */
  rottingBelow: 34,
  /** Bytes a builder (a Builder, a Combinator, a Tester on its team's held site, any bot at the mainframe) builds on a relay, per second; times the node's richness. */
  buildPerSecond: 48 * KB,
  /** A Tester standing with its team's Builders multiplies their building by this (Combinators don't get it). */
  testerBoost: 2,
  /** Pixels per second: the Explorer off the links, the others on them. */
  explorerSpeed: 110,
  linkSpeed: 70,
  /** A shortcut must save at least this many pixels of walking. */
  shortcutMinSaving: 60,
  /** Live shortcuts a team may have at once; a Combinator waits for one to rot before making another. */
  maxShortcuts: 3,
  /** One tick. */
  tickSeconds: 0.1,
} as const;

/** The map, in stage pixels: the mainframe at its centre, the origins on an ellipse around it. */
export const MAP = {
  width: 1280,
  height: 720,
  center: { x: 640, y: 404 } as Point,
  /** The ellipse the three origins sit on: a triangle with one vertex up. */
  rx: 540,
  ry: 296,
  /** The circle the three cores sit on, around the mainframe. */
  coreRadius: 168,
} as const;

/**
 * Each game draws the sites anew, within these bounds: how many bytes a
 * site builds before it is spent, in steps of half a megabyte; where a
 * relay sits, as degrees to its side of its origin and a scale toward the
 * centre on the origins' ellipse; where a core sits, as degrees off its
 * sector boundary and pixels from the mainframe. No two nodes closer than
 * `apart` pixels.
 */
export const SITE_DRAW = {
  size: { relay: [1.5 * MB, 5 * MB], core: [5 * MB, 10 * MB] },
  relay: { degrees: [28, 50], scale: [0.62, 0.86] },
  core: { degrees: [-14, 14], radius: [135, 195] },
  apart: 100,
} as const;

/** Where each team's origin is, as an angle from the centre: up, lower right, lower left. */
export const SECTOR_ANGLES: Readonly<Record<TeamId, number>> = {
  cyan: -90,
  magenta: 30,
  green: 150,
};

export const MAINFRAME_ID = 'mainframe';

export function originId(team: TeamId): string {
  return `origin-${team}`;
}

export type NodeKind = 'origin' | 'site' | 'mainframe';

/** A node of the map: a team's origin, a site with bytes, or the mainframe. */
export interface Node {
  readonly id: string;
  readonly kind: NodeKind;
  readonly at: Point;
  /** The origin's team. */
  readonly team: TeamId | null;
  /** The bytes built at a site so far, or into the hack at the mainframe, all teams together; 0 at an origin. */
  readonly bytes: number;
  /** How fast it builds: 1 for a relay, 2 for a core, 3 for the mainframe; 0 for an origin. */
  readonly richness: number;
  /** The most bytes a site builds, all teams together: once there, it is spent. 0 for an origin and the mainframe, which the hack's price bounds. */
  readonly capacity: number;
}

/** A pair of nodes the hidden map joins: a link the Explorer can find. */
export interface Pair {
  readonly a: string;
  readonly b: string;
}

/** A live link: found, or made as a shortcut, with health that rots. */
export interface Link {
  readonly id: string;
  readonly a: string;
  readonly b: string;
  /** 100 when found or made; gone at 0. */
  readonly health: number;
  /** The team whose Combinator made it; null for the map's own. */
  readonly by: TeamId | null;
}

/** A bot on its way along a link. */
export interface Travel {
  readonly link: string;
  readonly from: string;
  readonly to: string;
  /** How far along, 0 to 1. */
  readonly t: number;
}

export interface BotState {
  /** Unique: a team may have several of a kind. */
  readonly uid: string;
  readonly id: BotId;
  readonly kind: BotKind;
  readonly team: TeamId;
  readonly at: Point;
  /** The node it stands at, or null on its way. */
  readonly node: string | null;
  /** On a link (never for the Explorer, which runs free). */
  readonly travel: Travel | null;
  /** Where it is heading. */
  readonly target: string | null;
  /** The tick it arrived where it stands: the first Anchor on a site holds it. */
  readonly since: number;
  /** Sent to the mainframe by a `hack` answer: it goes there and builds the hack for the rest of the match. */
  readonly hacker: boolean;
}

export interface Knowledge {
  readonly nodes: readonly string[];
  readonly links: readonly string[];
}

export interface TeamState {
  readonly id: TeamId;
  /** Bytes collected and not yet spent. */
  readonly bytes: number;
  /** Bytes built at the mainframe: the team's progress into the hack. */
  readonly hacked: number;
  readonly known: Knowledge;
  /** Bytes taken per second, lately. */
  readonly income: number;
  /** Bots bought. */
  readonly bought: number;
}

export interface World {
  /** What the map was drawn from: the same seed, the same sites. */
  readonly seed: number;
  /** Ticks since the start. */
  readonly tick: number;
  readonly seconds: number;
  readonly nodes: readonly Node[];
  /** The hidden map: the links there are to find. */
  readonly map: readonly Pair[];
  /** The live links. */
  readonly links: readonly Link[];
  readonly bots: readonly BotState[];
  readonly teams: readonly TeamState[];
  /** The team that built the hack, if any. */
  readonly winner: TeamId | null;
  /** The next bot's and link's numbers. */
  readonly serial: number;
}

const RAD = Math.PI / 180;

/** A point on the origins' ellipse, at `angle` degrees from the centre, scaled toward it. */
export function onRing(angle: number, scale = 1): Point {
  return {
    x: MAP.center.x + MAP.rx * scale * Math.cos(angle * RAD),
    y: MAP.center.y + MAP.ry * scale * Math.sin(angle * RAD),
  };
}

function onCoreRing(angle: number, radius: number = MAP.coreRadius): Point {
  return {
    x: MAP.center.x + radius * Math.cos(angle * RAD),
    y: MAP.center.y + radius * Math.sin(angle * RAD),
  };
}

export function originAt(team: TeamId): Point {
  return onRing(SECTOR_ANGLES[team]);
}

export function distance(a: Point, b: Point): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

/** A seed for a new map. */
export function randomSeed(): number {
  return Math.floor(Math.random() * 2 ** 32);
}

/** A small seeded generator (mulberry32): numbers in [0, 1), the same for the same seed. */
export function seeded(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 2 ** 32;
  };
}

/**
 * The hidden map, drawn from a seed. Each team's origin is joined to two
 * **relays**, one to either side of it, toward the mainframe, that build
 * at the plain rate; each relay to the **core** on its side (the cores
 * sit near the sector boundaries, close to the mainframe, and build twice
 * as fast) and to the relay across the boundary, the other team's; each
 * core to the mainframe. So from an origin it is relay, core, mainframe,
 * and every core lies between two teams. Where each site sits, and its
 * size, are drawn within SITE_DRAW's bounds; the graph is always the same.
 */
export function buildMap(seed: number): { nodes: Node[]; map: Pair[] } {
  const random = seeded(seed);
  const between = ([lo, hi]: readonly [number, number]) => lo + random() * (hi - lo);
  const size = (range: readonly [number, number]) => Math.round(between(range) / (MB / 2)) * (MB / 2);
  const nodes: Node[] = [];
  const map: Pair[] = [];
  const join = (a: string, b: string) => map.push({ a, b });
  /** A point from `draw`, redrawn until it is clear of every node so far; after many tries, `fallback`. */
  const place = (draw: () => Point, fallback: Point): Point => {
    for (let i = 0; i < 400; i++) {
      const at = draw();
      if (nodes.every((n) => distance(n.at, at) >= SITE_DRAW.apart)) return at;
    }
    return fallback;
  };
  const norm = (angle: number) => ((angle % 360) + 360) % 360;
  const coreAt = (angle: number) => `core-${norm(angle)}`;
  nodes.push({ id: MAINFRAME_ID, kind: 'mainframe', at: MAP.center, team: null, bytes: 0, richness: RULES.richness.mainframe, capacity: 0 });
  for (const team of TEAMS) {
    nodes.push({ id: originId(team.id), kind: 'origin', at: originAt(team.id), team: team.id, bytes: 0, richness: 0, capacity: 0 });
  }
  for (const team of TEAMS) {
    const boundary = SECTOR_ANGLES[team.id] + 60;
    const at = place(() => onCoreRing(boundary + between(SITE_DRAW.core.degrees), between(SITE_DRAW.core.radius)), onCoreRing(boundary));
    const id = coreAt(boundary);
    nodes.push({ id, kind: 'site', at, team: null, bytes: 0, richness: RULES.richness.core, capacity: size(SITE_DRAW.size.core) });
    join(id, MAINFRAME_ID);
  }
  let n = 0;
  const relays = new Map<string, string>();
  for (const team of TEAMS) {
    for (const side of [-1, 1]) {
      const angle = SECTOR_ANGLES[team.id];
      const at = place(() => onRing(angle + side * between(SITE_DRAW.relay.degrees), between(SITE_DRAW.relay.scale)), onRing(angle + side * 40, 0.75));
      const id = `relay-${++n}`;
      relays.set(`${team.id}${side}`, id);
      nodes.push({ id, kind: 'site', at, team: null, bytes: 0, richness: RULES.richness.relay, capacity: size(SITE_DRAW.size.relay) });
      join(originId(team.id), id);
      join(id, coreAt(angle + side * 60));
    }
  }
  // Across each boundary: a team's relay on the side of the greater angle, to the next team's on its other side.
  TEAMS.forEach((team, i) => {
    const next = TEAMS[(i + 1) % TEAMS.length]!;
    join(relays.get(`${team.id}1`)!, relays.get(`${next.id}-1`)!);
  });
  return { nodes, map };
}

function newBot(uid: string, kind: BotKind, team: TeamId, at: Point, node: string, since = 0): BotState {
  return { uid, id: botOfKind(kind).id, kind, team, at, node, travel: null, target: null, since, hacker: false };
}

/** A new game, on a map drawn from `seed` (a new one each time, unless given). */
export function newWorld(seed: number = randomSeed()): World {
  const { nodes, map } = buildMap(seed);
  let serial = 0;
  return {
    seed,
    tick: 0,
    seconds: 0,
    nodes,
    map,
    links: [],
    bots: TEAMS.flatMap((t) => BOTS.map((b) => newBot(`${t.id}-${++serial}`, b.kind, t.id, originAt(t.id), originId(t.id)))),
    teams: TEAMS.map((t) => ({
      id: t.id,
      bytes: 0,
      hacked: 0,
      known: { nodes: [originId(t.id)], links: [] },
      income: 0,
      bought: 0,
    })),
    winner: null,
    serial,
  };
}

// ---- Queries --------------------------------------------------------------

export function node(world: World, id: string): Node {
  const found = world.nodes.find((n) => n.id === id);
  if (!found) throw new Error(`no node ${id}`);
  return found;
}

export function teamState(world: World, id: TeamId): TeamState {
  const found = world.teams.find((t) => t.id === id);
  if (!found) throw new Error(`no team ${id}`);
  return found;
}

export function link(world: World, id: string): Link | undefined {
  return world.links.find((l) => l.id === id);
}

/** The live link between two nodes, if any. */
export function linkBetween(world: World, a: string, b: string): Link | undefined {
  return world.links.find((l) => (l.a === a && l.b === b) || (l.a === b && l.b === a));
}

export function knowsNode(team: TeamState, id: string): boolean {
  return team.known.nodes.includes(id);
}

export function knowsLink(team: TeamState, id: string): boolean {
  return team.known.links.includes(id);
}

/** The live links a team knows from a node, with the node at the other end. */
export function knownLinksFrom(world: World, team: TeamState, id: string): { link: Link; other: string }[] {
  return world.links
    .filter((l) => knowsLink(team, l.id) && (l.a === id || l.b === id))
    .map((l) => ({ link: l, other: l.a === id ? l.b : l.a }));
}

/**
 * The shortest way for a team from one node to another, by the links
 * it knows, as the distance and the first link to take; null when there
 * is no way.
 */
export function route(world: World, team: TeamState, from: string, to: string): { distance: number; first: Link | null } | null {
  if (from === to) return { distance: 0, first: null };
  const best = new Map<string, { distance: number; first: Link | null }>([[from, { distance: 0, first: null }]]);
  const open = new Set([from]);
  while (open.size) {
    let current: string | null = null;
    for (const id of open) if (current === null || best.get(id)!.distance < best.get(current)!.distance) current = id;
    open.delete(current!);
    const here = best.get(current!)!;
    if (current === to) return here;
    for (const { link: l, other } of knownLinksFrom(world, team, current!)) {
      const d = here.distance + distance(node(world, current!).at, node(world, other).at);
      const known = best.get(other);
      if (known === undefined || d < known.distance) {
        best.set(other, { distance: d, first: here.first ?? l });
        open.add(other);
      }
    }
  }
  return null;
}

/** Whether a site is joined to the team's origin by links it knows: its bytes can flow home. */
export function connected(world: World, team: TeamState, siteId: string): boolean {
  return route(world, team, siteId, originId(team.id)) !== null;
}

/** The bots standing at a node (not on their way). */
export function botsAt(world: World, id: string): BotState[] {
  return world.bots.filter((b) => b.node === id && b.travel === null);
}

/**
 * The team that holds a site: the team of the Anchor that has stood there
 * longest (the first to arrive), if any Anchor stands there. A held site
 * is its team's alone: no other team takes its bytes, and another team's
 * Anchor arriving later holds nothing.
 */
export function holderOf(world: World, siteId: string): TeamId | null {
  if (node(world, siteId).kind !== 'site') return null;
  let first: BotState | null = null;
  for (const b of botsAt(world, siteId)) if (b.kind === 'anchor' && (first === null || b.since < first.since)) first = b;
  return first?.team ?? null;
}

/** Whether another team holds the site against this team. */
export function heldAgainst(world: World, team: TeamId, siteId: string): boolean {
  const holder = holderOf(world, siteId);
  return holder !== null && holder !== team;
}

/** The sites a team holds. */
export function heldBy(world: World, team: TeamId): Node[] {
  return world.nodes.filter((n) => n.kind === 'site' && holderOf(world, n.id) === team);
}

/** Whether a site has built all it can. */
export function spent(n: Node): boolean {
  return n.kind === 'site' && n.bytes >= n.capacity;
}

/** The bytes a site can still build. */
export function room(n: Node): number {
  return n.kind === 'site' ? Math.max(0, n.capacity - n.bytes) : 0;
}

export function bytesOf(world: World, team: TeamId): number {
  return teamState(world, team).bytes;
}

/** A team's progress into the mainframe, 0 to 100. */
export function hackedPct(world: World, team: TeamId): number {
  return Math.min(100, (teamState(world, team).hacked / RULES.hackCost) * 100);
}

/** Bytes for people: 1.5 MB, 320 KB, 12 B. */
export function fmtBytes(n: number): string {
  if (n >= MB) return `${(n / MB).toFixed(n >= 10 * MB ? 0 : 1)} MB`;
  if (n >= KB) return `${Math.round(n / KB)} KB`;
  return `${Math.round(n)} B`;
}

// ---- Actions: what a decision does -----------------------------------------

/** A team buys a bot of a kind: a megabyte spent, a bot at its origin. */
export function buy(world: World, teamId: TeamId, kind: BotKind): World {
  const team = teamState(world, teamId);
  if (team.bytes < RULES.botCost) throw new Error(`${teamId} cannot afford a ${kind}`);
  const serial = world.serial + 1;
  return {
    ...world,
    serial,
    bots: [...world.bots, newBot(`${teamId}-${serial}`, kind, teamId, originAt(teamId), originId(teamId), world.tick)],
    teams: world.teams.map((t) => (t.id === teamId ? { ...t, bytes: t.bytes - RULES.botCost, bought: t.bought + 1 } : t)),
  };
}

/**
 * The bot a `hack` answer would send to the mainframe: the team's nearest
 * to it of those not sent yet, an Explorer only when nothing else is
 * left (the team needs it to keep its way there); null when all are sent.
 */
export function hackerFor(world: World, teamId: TeamId): BotState | null {
  const free = world.bots.filter((b) => b.team === teamId && !b.hacker);
  const pool = free.some((b) => b.kind !== 'explorer') ? free.filter((b) => b.kind !== 'explorer') : free;
  let pick: BotState | null = null;
  for (const b of pool) if (pick === null || distance(b.at, MAP.center) < distance(pick.at, MAP.center)) pick = b;
  return pick;
}

/** A team sends a bot to the mainframe for a megabyte: from now on it goes there and builds the hack. */
export function sendHacker(world: World, teamId: TeamId): World {
  const team = teamState(world, teamId);
  if (team.bytes < RULES.botCost) throw new Error(`${teamId} has no megabyte to send a bot into the hack`);
  const sent = hackerFor(world, teamId);
  if (sent === null) throw new Error(`${teamId} has no bot left to send into the hack`);
  return {
    ...world,
    bots: world.bots.map((b) => (b === sent ? { ...b, hacker: true } : b)),
    teams: world.teams.map((t) => (t.id === teamId ? { ...t, bytes: t.bytes - RULES.botCost } : t)),
  };
}

// ---- The tick -------------------------------------------------------------

/** The world, mutable for the length of one tick. */
interface Draft {
  seed: number;
  tick: number;
  seconds: number;
  nodes: Map<string, { id: string; kind: NodeKind; at: Point; team: TeamId | null; bytes: number; richness: number; capacity: number }>;
  map: readonly Pair[];
  links: Map<string, { id: string; a: string; b: string; health: number; by: TeamId | null }>;
  bots: { uid: string; id: BotId; kind: BotKind; team: TeamId; at: Point; node: string | null; travel: Travel | null; target: string | null; since: number; hacker: boolean }[];
  teams: Map<TeamId, { id: TeamId; bytes: number; hacked: number; nodes: Set<string>; links: Set<string>; income: number; bought: number; taken: number }>;
  winner: TeamId | null;
  serial: number;
}

function draft(world: World): Draft {
  return {
    seed: world.seed,
    tick: world.tick,
    seconds: world.seconds,
    nodes: new Map(world.nodes.map((n) => [n.id, { ...n }])),
    map: world.map,
    links: new Map(world.links.map((l) => [l.id, { ...l }])),
    bots: world.bots.map((b) => ({ ...b })),
    teams: new Map(
      world.teams.map((t) => [t.id, { ...t, nodes: new Set(t.known.nodes), links: new Set(t.known.links), taken: 0 }]),
    ),
    winner: world.winner,
    serial: world.serial,
  };
}

function commit(d: Draft): World {
  return {
    seed: d.seed,
    tick: d.tick,
    seconds: d.seconds,
    nodes: [...d.nodes.values()],
    map: d.map,
    links: [...d.links.values()],
    bots: d.bots,
    teams: [...d.teams.values()].map(({ nodes, links, taken: _taken, ...t }) => ({
      ...t,
      known: { nodes: [...nodes], links: [...links] },
    })),
    winner: d.winner,
    serial: d.serial,
  };
}

/**
 * One tick: the links rot, every bot acts (the idle ones choose where to
 * go, the travelling ones advance, the ones at a site take, grow, hack or
 * combine), and a team that built the hack wins.
 */
export function step(world: World, dt: number = RULES.tickSeconds): World {
  if (world.winner !== null) return world;
  const d = draft(world);
  d.tick += 1;
  d.seconds += dt;
  rot(d, dt);
  for (const b of d.bots) {
    if (b.kind === 'explorer') explore(d, b, dt);
    else if (b.travel !== null) advance(d, b, dt);
    else act(d, b, dt);
  }
  for (const t of d.teams.values()) {
    t.income = t.income + (t.taken / dt - t.income) * Math.min(1, dt);
    if (t.hacked >= RULES.hackCost && d.winner === null) d.winner = t.id;
  }
  return commit(d);
}

/** Every link loses health; at zero it is gone, and forgotten, and whoever was on it steps back. */
function rot(d: Draft, dt: number): void {
  for (const l of d.links.values()) {
    l.health -= (100 / RULES.rotSeconds) * dt;
    if (l.health > 0) continue;
    d.links.delete(l.id);
    for (const t of d.teams.values()) t.links.delete(l.id);
    for (const b of d.bots) {
      if (b.travel?.link === l.id) {
        b.node = b.travel.from;
        b.at = d.nodes.get(b.node)!.at;
        b.travel = null;
        b.target = null;
        b.since = d.tick;
      }
    }
  }
}

/** A live link between two nodes in the draft. */
function liveBetween(d: Draft, a: string, b: string) {
  for (const l of d.links.values()) if ((l.a === a && l.b === b) || (l.a === b && l.b === a)) return l;
  return undefined;
}

/**
 * The Explorer: runs straight to the nearest node it hasn't found, and
 * finds it, with the links from it. Sent to the mainframe, it runs
 * there instead, and builds the hack.
 */
function explore(d: Draft, b: Draft['bots'][number], dt: number): void {
  const team = d.teams.get(b.team)!;
  if (b.hacker) {
    if (b.node === MAINFRAME_ID) {
      const { world, team: stateOf } = view(d);
      stay(d, b, team, d.nodes.get(MAINFRAME_ID)!, stateOf(b.team), world, dt);
      return;
    }
    b.target = MAINFRAME_ID;
    b.node = null;
  }
  if (b.target === null) {
    const candidates = [...d.nodes.values()].filter((n) => n.kind === 'site');
    const unfound = candidates.filter((n) => !team.nodes.has(n.id));
    // Sites still to find; else sites with a map link gone, to find again; else a known site far away, to keep moving.
    const missing = candidates.filter((n) => d.map.some((p) => (p.a === n.id || p.b === n.id) && liveBetween(d, p.a, p.b) === undefined));
    const pool = unfound.length ? unfound : missing.length ? missing : candidates;
    const pick = unfound.length || missing.length ? nearest(b.at, pool) : farthest(b.at, pool);
    if (pick === null) return;
    b.target = pick.id;
    b.node = null;
  }
  const to = d.nodes.get(b.target)!.at;
  const left = distance(b.at, to);
  const run = RULES.explorerSpeed * dt;
  if (left <= run) {
    b.at = to;
    b.node = b.target;
    b.target = null;
    b.since = d.tick;
    discover(d, team, b.node);
  } else {
    b.at = { x: b.at.x + ((to.x - b.at.x) / left) * run, y: b.at.y + ((to.y - b.at.y) / left) * run };
  }
}

function nearest(from: Point, nodes: DraftNode[]): DraftNode | null {
  let best: DraftNode | null = null;
  for (const n of nodes) if (best === null || distance(from, n.at) < distance(from, best.at)) best = n;
  return best;
}

function farthest(from: Point, nodes: DraftNode[]): DraftNode | null {
  let best: DraftNode | null = null;
  for (const n of nodes) if (best === null || distance(from, n.at) > distance(from, best.at)) best = n;
  return best;
}

/** A team finds a node: it, the map's links from it (live from now on, if they weren't) and every live link from it, with their far ends. */
function discover(d: Draft, team: DraftTeam, id: string): void {
  team.nodes.add(id);
  for (const p of d.map) {
    if (p.a !== id && p.b !== id) continue;
    if (liveBetween(d, p.a, p.b) === undefined) {
      const lid = `link-${++d.serial}`;
      d.links.set(lid, { id: lid, a: p.a, b: p.b, health: 100, by: null });
    }
  }
  for (const l of d.links.values()) {
    if (l.a !== id && l.b !== id) continue;
    team.links.add(l.id);
    team.nodes.add(l.a === id ? l.b : l.a);
  }
}

/** A bot on a link moves along it; at the far end, a Tester renews the link. */
function advance(d: Draft, b: Draft['bots'][number], dt: number): void {
  const travel = b.travel!;
  const from = d.nodes.get(travel.from)!.at;
  const to = d.nodes.get(travel.to)!.at;
  const length = distance(from, to) || 1;
  const t = Math.min(1, travel.t + (RULES.linkSpeed * dt) / length);
  if (t >= 1) {
    b.at = to;
    b.node = travel.to;
    b.travel = null;
    b.since = d.tick;
    if (b.kind === 'tester') {
      const l = d.links.get(travel.link);
      if (l) l.health = 100;
    }
  } else {
    b.travel = { ...travel, t };
    b.at = { x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t };
  }
}

type DraftTeam = Draft['teams'] extends Map<TeamId, infer T> ? T : never;
type DraftBot = Draft['bots'][number];
type DraftNode = Draft['nodes'] extends Map<string, infer N> ? N : never;

/** The world as the pure queries see it, for a draft: enough for `route`. */
function view(d: Draft): { world: World; team: (id: TeamId) => TeamState } {
  const world = commit(d);
  return { world, team: (id) => teamState(world, id) };
}

/**
 * A bot standing at a node: it does its part there, then decides where
 * it wants to be, and sets off along the links it knows if that is
 * elsewhere.
 */
function act(d: Draft, b: DraftBot, dt: number): void {
  const team = d.teams.get(b.team)!;
  const here = d.nodes.get(b.node!)!;
  const { world, team: stateOf } = view(d);
  const state = stateOf(b.team);
  if (b.kind === 'combinator') combine(d, b, team, state, world);
  const want = wantOf(d, b, team, state, world, here);
  if (want === here.id) {
    stay(d, b, team, here, state, world, dt);
    b.target = null;
    return;
  }
  const way = want === null ? null : route(world, state, here.id, want);
  if (way === null || way.first === null) {
    b.target = null;
    stay(d, b, team, here, state, world, dt);
    return;
  }
  b.target = want;
  const first = way.first;
  b.travel = { link: first.id, from: here.id, to: first.a === here.id ? first.b : first.a, t: 0 };
}

/**
 * How fast a bot builds where it stands, in bytes per second: at the
 * mainframe, a bot of any kind sent there, into the hack (one only
 * passing through, or stuck there, builds nothing); on a site, a Builder (twice as fast
 * with a Tester of its team there), a Combinator, or a Tester on a site
 * its team's Anchor holds with no Builder of its team there; nothing on
 * a spent site, a site another team holds, or cut off from the team's
 * origin.
 */
export function buildRate(world: World, b: BotState, here: Node): number {
  if (here.kind === 'mainframe') return b.hacker && connected(world, teamState(world, b.team), here.id) ? RULES.buildPerSecond * here.richness : 0;
  if (here.kind !== 'site' || spent(here) || heldAgainst(world, b.team, here.id)) return 0;
  const mates = botsAt(world, here.id).filter((o) => o.team === b.team);
  let rate = 0;
  if (b.kind === 'builder') rate = mates.some((o) => o.kind === 'tester') ? RULES.testerBoost : 1;
  else if (b.kind === 'combinator') rate = 1;
  else if (b.kind === 'tester') rate = !mates.some((o) => o.kind === 'builder') && holderOf(world, here.id) === b.team ? 1 : 0;
  if (rate === 0 || !connected(world, teamState(world, b.team), here.id)) return 0;
  return rate * RULES.buildPerSecond * here.richness;
}

/** What a bot does standing at a node: builds bytes on a site for its team, or at the mainframe into its team's hack. */
function stay(d: Draft, b: DraftBot, team: DraftTeam, here: DraftNode, _state: TeamState, world: World, dt: number): void {
  const rate = buildRate(world, b as BotState, here as Node) * dt;
  // A site builds up to its size: the last bytes are what is left.
  const built = here.kind === 'site' ? Math.min(rate, room(here as Node)) : rate;
  if (built <= 0) return;
  here.bytes += built;
  if (here.kind === 'mainframe') {
    team.hacked += built;
    return;
  }
  team.bytes += built;
  team.taken += built;
}

/** Where a bot wants to be, by its kind; null for nowhere in particular. */
function wantOf(d: Draft, b: DraftBot, team: DraftTeam, state: TeamState, world: World, here: DraftNode): string | null {
  const reachable = (id: string) => route(world, state, here.id, id) !== null;
  // A spent site, or one another team holds, is no use to this one: nothing to build there, nothing to hold.
  const open = (id: string) => !spent(d.nodes.get(id)! as Node) && !heldAgainst(world, b.team, id);
  const knownSites = [...team.nodes].map((id) => d.nodes.get(id)!).filter((n) => n.kind === 'site' && open(n.id) && reachable(n.id));
  /** Where the team's other bots of a kind stand or head. */
  const claimedBy = (kind: BotKind) => new Set(d.bots.filter((o) => o !== b && o.kind === kind && o.team === b.team).map((o) => o.target ?? o.node));
  const isSite = here.kind === 'site' && open(here.id);
  /** The best of some sites: the richest, then the nearest. */
  // Sent to the mainframe: there, when the team has a way; till then, its usual work.
  if (b.hacker && reachable(MAINFRAME_ID)) return MAINFRAME_ID;
  const best = (nodes: DraftNode[]): DraftNode | null => {
    let pick: { n: DraftNode; d: number } | null = null;
    for (const n of nodes) {
      const way = route(world, state, here.id, n.id);
      if (way === null) continue;
      if (pick === null || n.richness > pick.n.richness || (n.richness === pick.n.richness && way.distance < pick.d)) pick = { n, d: way.distance };
    }
    return pick?.n ?? null;
  };
  switch (b.kind) {
    case 'anchor': {
      if (isSite) return here.id;
      const claimed = claimedBy('anchor');
      const free = knownSites.filter((n) => !claimed.has(n.id));
      // Where the team builds first: hold what is worth holding.
      const builders = claimedBy('builder');
      return (best(free.filter((n) => builders.has(n.id))) ?? best(free))?.id ?? null;
    }
    case 'builder': {
      if (isSite) return here.id;
      const claimed = claimedBy('builder');
      const room = knownSites.filter((n) => !claimed.has(n.id));
      const held = new Set(heldBy(world, b.team).map((n) => n.id));
      return (best(room.filter((n) => held.has(n.id))) ?? best(room))?.id ?? null;
    }
    case 'tester': {
      // The weakest link it can get to: cross it, from the nearer end.
      let weakest: { link: Link; near: string; far: string; distance: number } | null = null;
      for (const l of world.links) {
        if (!knowsLink(state, l.id)) continue;
        for (const [near, far] of [[l.a, l.b], [l.b, l.a]] as const) {
          const way = route(world, state, here.id, near);
          if (way === null) continue;
          if (weakest === null || l.health < weakest.link.health || (l.health === weakest.link.health && way.distance < weakest.distance)) {
            weakest = { link: l, near, far, distance: way.distance };
          }
        }
      }
      const cross = weakest === null ? null : weakest.near === here.id ? weakest.far : weakest.near;
      if (weakest !== null && weakest.link.health < RULES.rottingBelow) return cross;
      // No link in danger: double a Builder, or build on a held site, where no other Tester of the team does.
      const claimed = claimedBy('tester');
      const builders = new Set(d.bots.filter((o) => o.kind === 'builder' && o.team === b.team && o.travel === null).map((o) => o.node));
      const held = new Set(heldBy(world, b.team).map((n) => n.id));
      if (isSite && (builders.has(here.id) || held.has(here.id)) && !claimed.has(here.id)) return here.id;
      const work = best(knownSites.filter((n) => builders.has(n.id) && !claimed.has(n.id))) ?? best(knownSites.filter((n) => held.has(n.id) && !claimed.has(n.id)));
      return work?.id ?? cross ?? (here.kind === 'site' ? here.id : null);
    }
    case 'combinator': {
      // Somewhere a shortcut can be made; else a site to build on.
      let shortcut: { id: string; saving: number } | null = null;
      for (const n of [...team.nodes].map((id) => d.nodes.get(id)!)) {
        if (!reachable(n.id)) continue;
        const option = shortcutAt(d, team, n.id);
        if (option !== null && (shortcut === null || option.saving > shortcut.saving)) shortcut = { id: n.id, saving: option.saving };
      }
      if (shortcut !== null) return shortcut.id;
      if (isSite) return here.id;
      const claimed = claimedBy('combinator');
      return best(knownSites.filter((n) => !claimed.has(n.id)))?.id ?? null;
    }
    default:
      return null;
  }
}

/**
 * The best shortcut a Combinator could make standing at a node: two links
 * it knows from there, whose far ends are not yet linked, that save the
 * most walking.
 */
function shortcutAt(d: Draft, team: DraftTeam, at: string): { a: string; c: string; saving: number } | null {
  let live = 0;
  for (const l of d.links.values()) if (l.by === team.id) live += 1;
  if (live >= RULES.maxShortcuts) return null;
  const ends: string[] = [];
  for (const l of d.links.values()) {
    if (!team.links.has(l.id)) continue;
    if (l.a === at) ends.push(l.b);
    else if (l.b === at) ends.push(l.a);
  }
  const here = d.nodes.get(at)!.at;
  let best: { a: string; c: string; saving: number } | null = null;
  for (let i = 0; i < ends.length; i++) {
    for (let j = i + 1; j < ends.length; j++) {
      const a = ends[i]!;
      const c = ends[j]!;
      if (a === c || liveBetween(d, a, c) !== undefined) continue;
      const pa = d.nodes.get(a)!.at;
      const pc = d.nodes.get(c)!.at;
      const saving = distance(here, pa) + distance(here, pc) - distance(pa, pc);
      if (saving >= RULES.shortcutMinSaving && (best === null || saving > best.saving)) best = { a, c, saving };
    }
  }
  return best;
}

/** A Combinator at a node makes the best shortcut there, if there is one: a new link, at full health, the team's. */
function combine(d: Draft, b: DraftBot, team: DraftTeam, _state: TeamState, _world: World): void {
  const option = shortcutAt(d, team, b.node!);
  if (option === null) return;
  const id = `shortcut-${++d.serial}`;
  d.links.set(id, { id, a: option.a, b: option.c, health: 100, by: b.team });
  team.links.add(id);
}

// ---- The situation a strategy decides on ----------------------------------

/** What a team's strategy sees when it decides what its next megabyte buys. */
export interface Situation {
  readonly seconds: number;
  readonly bytes_mb: number;
  readonly bots: number;
  readonly hackers: number;
  readonly anchors: number;
  readonly builders: number;
  readonly testers: number;
  readonly combinators: number;
  readonly explorers: number;
  readonly sites_known: number;
  readonly sites_held: number;
  readonly sites_total: number;
  readonly room_mb: number;
  readonly links_known: number;
  readonly links_rotting: number;
  readonly income_kbs: number;
  readonly mainframe_connected: boolean;
  readonly hack_pct: number;
  readonly leader_pct: number;
  readonly threat: number;
}

export function situation(world: World, teamId: TeamId): Situation {
  const team = teamState(world, teamId);
  const mine = world.bots.filter((b) => b.team === teamId);
  // By kind, the bots at their usual work: the ones sent to the mainframe count as hackers.
  const count = (kind: BotKind) => mine.filter((b) => b.kind === kind && !b.hacker).length;
  const knownLinks = world.links.filter((l) => knowsLink(team, l.id));
  const sites = world.nodes.filter((n) => n.kind === 'site');
  const knownSites = sites.filter((n) => knowsNode(team, n.id));
  const round = (n: number) => Math.round(n * 100) / 100;
  return {
    seconds: Math.round(world.seconds),
    bytes_mb: round(team.bytes / MB),
    bots: mine.length,
    hackers: mine.filter((b) => b.hacker).length,
    anchors: count('anchor'),
    builders: count('builder'),
    testers: count('tester'),
    combinators: count('combinator'),
    explorers: count('explorer'),
    sites_known: knownSites.length,
    sites_held: heldBy(world, teamId).length,
    sites_total: sites.length,
    room_mb: round(knownSites.filter((n) => !heldAgainst(world, teamId, n.id)).reduce((sum, n) => sum + room(n), 0) / MB),
    links_known: knownLinks.length,
    links_rotting: knownLinks.filter((l) => l.health < RULES.rottingBelow).length,
    income_kbs: round(team.income / KB),
    mainframe_connected: knowsNode(team, MAINFRAME_ID) && route(world, team, originId(teamId), MAINFRAME_ID) !== null,
    hack_pct: round(hackedPct(world, teamId)),
    leader_pct: round(Math.max(...TEAMS.filter((t) => t.id !== teamId).map((t) => hackedPct(world, t.id)))),
    threat: knownSites.reduce((n, s) => n + botsAt(world, s.id).filter((b) => b.team !== teamId).length, 0),
  };
}
