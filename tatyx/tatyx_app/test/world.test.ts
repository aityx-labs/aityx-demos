import { describe, expect, it } from 'vitest';
import { BOTS, bot, botOfKind } from '../src/game/bots';
import { Match } from '../src/game/play';
import { STRATEGIES, TEAM_MODEL, buildRequest, decideLocally, readDecision, strategy } from '../src/game/strategy';
import { SYSTEM, TEAMS, tag, team } from '../src/game/teams';
import {
  MAINFRAME_ID,
  MAP,
  MB,
  RULES,
  SECTOR_ANGLES,
  SITE_DRAW,
  buildMap,
  buy,
  bytesOf,
  connected,
  fmtBytes,
  hackedPct,
  hackerFor,
  buildRate,
  heldAgainst,
  holderOf,
  newWorld,
  node,
  originAt,
  originId,
  room,
  seeded,
  route,
  sendHacker,
  situation,
  spent,
  step,
  teamState,
  type BotState,
  type World,
} from '../src/game/world';

describe('the bots', () => {
  it('are the five letters of aityx, Anchor, Builder, Tester, Combinator and Explorer, each with a portrait', () => {
    expect(BOTS.map((b) => b.id).join('')).toBe('AITYX');
    expect(BOTS.map((b) => b.name)).toEqual(['Anchor', 'Builder', 'Tester', 'Combinator', 'Explorer']);
    for (const b of BOTS) expect(b.portrait).toBe(`bots/${b.id.toLowerCase()}-${b.kind}.png`);
    expect(bot('A').kind).toBe('anchor');
    expect(botOfKind('explorer').id).toBe('X');
    expect(() => bot('Z' as never)).toThrow();
  });
});

describe('the teams', () => {
  it('are three, each with a colour tag of its own, and none of them orange', () => {
    expect(TEAMS).toHaveLength(3);
    const colors = new Set(TEAMS.map((t) => t.color));
    expect(colors.size).toBe(3);
    expect(colors.has(SYSTEM.color)).toBe(false);
    expect(SYSTEM.css).toBe('#E36742');
    expect(tag('system')).toBe(SYSTEM);
    expect(team('cyan').css).toBe('#00F0FF');
  });
  it('sit in a triangle around the mainframe, 120 degrees apart, all three as far from it', () => {
    const angles = TEAMS.map((t) => SECTOR_ANGLES[t.id]).sort((a, b) => a - b);
    expect(angles[1]! - angles[0]!).toBe(120);
    expect(angles[2]! - angles[1]!).toBe(120);
    for (const t of TEAMS) {
      const at = originAt(t.id);
      expect(at.x).toBeGreaterThan(0);
      expect(at.x).toBeLessThan(MAP.width);
      expect(at.y).toBeGreaterThan(0);
      expect(at.y).toBeLessThan(MAP.height);
      expect(Math.hypot(at.x - MAP.center.x, at.y - MAP.center.y)).toBeCloseTo(MAP.radius, 6);
    }
  });
});

/** The map most tests play on: a new one every game, this one here, so the tests see the same. */
const SEED = 7;
/** Seeds enough to try the drawing of the map on many. */
const SEEDS = Array.from({ length: 200 }, (_, i) => i * 7919 + 1);

/** Runs the world for some seconds, without decisions. */
function run(world: World, seconds: number): World {
  for (let i = 0; i < Math.round(seconds / RULES.tickSeconds); i++) world = step(world);
  return world;
}

const explorerOf = (world: World, t: 'cyan' | 'magenta' | 'green') => world.bots.find((b) => b.team === t && b.kind === 'explorer')!;
const only = (world: World, kinds: readonly string[]): World => ({ ...world, bots: world.bots.filter((b) => kinds.includes(b.kind)) });

describe('the map', () => {
  const world = newWorld(SEED);
  it('has the mainframe in the middle, an origin and five bots per team, twenty-one sites, and no link found yet', () => {
    expect(world.tick).toBe(0);
    expect(world.winner).toBeNull();
    expect(node(world, MAINFRAME_ID).at).toEqual(MAP.center);
    expect(world.bots).toHaveLength(15);
    for (const t of TEAMS) {
      expect(world.bots.filter((b) => b.team === t.id).map((b) => b.id).join('')).toBe('AITYX');
      expect(bytesOf(world, t.id)).toBe(0);
      expect(teamState(world, t.id).known).toEqual({ nodes: [originId(t.id)], links: [] });
      expect(node(world, originId(t.id)).team).toBe(t.id);
    }
    const perSector = SITE_DRAW.perSector.core + SITE_DRAW.perSector.relay + SITE_DRAW.perSector.outer;
    expect(world.nodes.filter((n) => n.kind === 'site')).toHaveLength(3 * perSector);
    expect(world.links).toEqual([]);
    expect(world.map.length).toBeGreaterThan(3 * perSector);
  });
  it('builds faster near the mainframe than farther out, starts with nothing built, and keeps the sites apart and on the board, on every map', () => {
    /** How far out a point is: 0 at the mainframe, 1 on the origins' ring. */
    const reach = (p: { x: number; y: number }) => Math.hypot(p.x - MAP.center.x, p.y - MAP.center.y) / MAP.radius;
    for (const seed of SEEDS) {
      const { nodes } = buildMap(seed);
      const sites = nodes.filter((n) => n.kind === 'site');
      for (const s of sites) {
        const kind = s.id.startsWith('core-') ? 'core' : s.id.startsWith('outer-') ? 'outer' : 'relay';
        const core = kind === 'core';
        expect(s.richness).toBe(core ? RULES.richness.core : RULES.richness.relay);
        const [near, far] = SITE_DRAW.reach[kind];
        expect(reach(s.at)).toBeGreaterThanOrEqual(near - 1e-9);
        expect(reach(s.at)).toBeLessThanOrEqual(far + 1e-9);
        const [lo, hi] = SITE_DRAW.size[kind];
        expect(s.capacity).toBeGreaterThanOrEqual(lo);
        expect(s.capacity).toBeLessThanOrEqual(hi);
        expect(s.capacity % (MB / 2)).toBe(0);
        expect(s.bytes).toBe(0);
        expect(s.at.x).toBeGreaterThanOrEqual(SITE_DRAW.bounds.left);
        expect(s.at.x).toBeLessThanOrEqual(SITE_DRAW.bounds.right);
        expect(s.at.y).toBeGreaterThanOrEqual(SITE_DRAW.bounds.top);
        expect(s.at.y).toBeLessThanOrEqual(SITE_DRAW.bounds.bottom);
      }
      expect(sites.filter((s) => s.richness === RULES.richness.core)).toHaveLength(3 * SITE_DRAW.perSector.core);
      expect(sites.filter((s) => s.id.startsWith('outer-'))).toHaveLength(3 * SITE_DRAW.perSector.outer);
      // Beyond the origins: past their ring.
      for (const s of sites.filter((o) => o.id.startsWith('outer-'))) expect(reach(s.at)).toBeGreaterThan(1);
      const all = nodes.map((n) => n.at);
      for (let i = 0; i < all.length; i++) {
        for (let j = i + 1; j < all.length; j++) expect(Math.hypot(all[i]!.x - all[j]!.x, all[i]!.y - all[j]!.y)).toBeGreaterThanOrEqual(SITE_DRAW.apart);
      }
    }
  });
  it('is drawn anew every game: the same seed the same map, another seed other places, sizes and links', () => {
    expect(buildMap(SEED)).toEqual(buildMap(SEED));
    expect(newWorld(SEED).seed).toBe(SEED);
    const other = buildMap(SEED + 1);
    const sites = (seed: number) => buildMap(seed).nodes.filter((n) => n.kind === 'site');
    expect(sites(SEED).map((n) => n.at)).not.toEqual(sites(SEED + 1).map((n) => n.at));
    expect(new Set(SEEDS.flatMap((seed) => sites(seed).map((n) => n.capacity))).size).toBeGreaterThanOrEqual(8);
    expect(other.map).not.toEqual(buildMap(SEED).map);
    expect(newWorld().seed).not.toBe(newWorld().seed);
  });
  it('joins every node to the mainframe, and every origin by two ways out at least, never an origin straight to another or to the mainframe, on every map', () => {
    for (const seed of SEEDS) {
      const { nodes, map } = buildMap(seed);
      const reached = (from: string) => {
        const seen = new Set([from]);
        const queue = [from];
        while (queue.length) {
          const id = queue.shift()!;
          for (const p of map) {
            const other = p.a === id ? p.b : p.b === id ? p.a : null;
            if (other !== null && !seen.has(other)) {
              seen.add(other);
              queue.push(other);
            }
          }
        }
        return seen;
      };
      expect(reached(MAINFRAME_ID).size).toBe(nodes.length);
      for (const p of map) {
        const kinds = [p.a, p.b].map((id) => nodes.find((n) => n.id === id)!.kind);
        expect(kinds).toContain('site');
      }
      for (const t of TEAMS) expect(map.filter((p) => p.a === originId(t.id) || p.b === originId(t.id)).length).toBeGreaterThanOrEqual(SITE_DRAW.originLinks);
    }
  });
  it('formats bytes for people', () => {
    expect(fmtBytes(12)).toBe('12 B');
    expect(fmtBytes(320 * 1024)).toBe('320 KB');
    expect(fmtBytes(1.5 * MB)).toBe('1.5 MB');
    expect(fmtBytes(12 * MB)).toBe('12 MB');
  });
});

describe('the Explorer', () => {
  it('runs free to the nearest site and finds it, with the links from it and their far ends', () => {
    let world = only(newWorld(SEED), ['explorer']);
    world = { ...world, bots: world.bots.filter((b) => b.team === 'cyan') };
    const before = explorerOf(world, 'cyan');
    world = run(world, 0.5);
    const moved = explorerOf(world, 'cyan');
    expect(moved.node).toBeNull();
    expect(moved.target).toMatch(/^(relay|core)-/);
    expect(Math.hypot(moved.at.x - before.at.x, moved.at.y - before.at.y)).toBeCloseTo(RULES.explorerSpeed * 0.5, 0);
    world = run(world, 6);
    const cyan = teamState(world, 'cyan');
    expect(cyan.known.links.length).toBeGreaterThanOrEqual(3);
    expect(cyan.known.nodes).toContain(moved.target);
    expect(world.links.every((l) => l.health > 0 && l.health <= 100)).toBe(true);
    // The other teams know nothing of it.
    expect(teamState(world, 'magenta').known.links).toEqual([]);
    // Everything is found in time, the mainframe included.
    world = run(world, 60);
    expect(teamState(world, 'cyan').known.nodes).toContain(MAINFRAME_ID);
    expect(teamState(world, 'cyan').known.nodes.length).toBe(world.nodes.length);
  });
  it('never touches the input', () => {
    const world = newWorld(SEED);
    const later = step(world);
    expect(world.tick).toBe(0);
    expect(world.bots[0]!.at).toEqual(originAt('cyan'));
    expect(later.tick).toBe(1);
  });
});

describe('the links', () => {
  it('rot away in RULES.rotSeconds, and are forgotten when gone', () => {
    let world = run(only(newWorld(SEED), ['explorer']), 3);
    const first = world.links[0]!;
    expect(first.health).toBeLessThan(100);
    expect(first.health).toBeGreaterThanOrEqual(100 - (100 / RULES.rotSeconds) * 3);
    const frozen = { ...world, bots: [] };
    const gone = run(frozen, RULES.rotSeconds);
    expect(gone.links).toEqual([]);
    for (const t of gone.teams) expect(t.known.links).toEqual([]);
  });
  it('are renewed by a Tester crossing them', () => {
    let world = run(only(newWorld(SEED), ['explorer', 'tester']), 4);
    const cyan = teamState(world, 'cyan');
    expect(cyan.known.links.length).toBeGreaterThan(0);
    // Without Testers a link only loses health; one Tester's crossing brings it back to 100.
    const testers = new Set(world.bots.filter((b) => b.kind === 'tester').map((b) => b.uid));
    let renewed = 0;
    for (let i = 0; i < 100; i++) {
      const later = step(world);
      for (const l of later.links) {
        const before = world.links.find((o) => o.id === l.id);
        if (before && l.health > before.health) renewed += 1;
      }
      world = later;
    }
    expect(testers.size).toBeGreaterThan(0);
    expect(renewed).toBeGreaterThan(0);
    expect(world.links.every((l) => l.health <= 100)).toBe(true);
    const tester = world.bots.find((b) => b.team === 'cyan' && b.kind === 'tester')!;
    expect(tester.node ?? tester.travel).not.toBeNull();
  });
});

describe('building bytes', () => {
  /** Cyan knowing its corner of the map, no bots, and a relay of cyan's connected to its origin. */
  function ground(): { world: World; site: string } {
    // Explore until cyan knows two sites joined to its origin (links rot, so stop there).
    const joined = (w: World) => w.nodes.filter((n) => n.kind === 'site' && teamState(w, 'cyan').known.nodes.includes(n.id) && connected(w, teamState(w, 'cyan'), n.id));
    let explored = only(newWorld(SEED), ['explorer']);
    for (let i = 0; i < 60 && joined(explored).length < 2; i++) explored = run(explored, 0.5);
    const site = joined(explored)[0]!;
    expect(site).toBeDefined();
    return { world: { ...explored, bots: [] }, site: site.id };
  }
  const put = (world: World, site: string, kind: BotState['kind'], team: 'cyan' | 'magenta', since = 0): BotState => ({
    uid: `${team}-${kind}-${since}-${world.bots.length}`,
    id: ({ anchor: 'A', builder: 'I', tester: 'T', combinator: 'Y', explorer: 'X' } as const)[kind],
    kind,
    team,
    at: node(world, site).at,
    node: site,
    travel: null,
    target: null,
    since,
    hacker: false,
  });
  const withBots = (world: World, bots: BotState[]): World => ({ ...world, bots });
  const rate = (world: World, b: BotState, site: string) => buildRate(world, b, node(world, site));
  const base = (world: World, site: string) => RULES.buildPerSecond * node(world, site).richness;

  it('is a Builder\'s: bytes for its team, on the site, at the rate times the site\'s richness', () => {
    const { world, site } = ground();
    const b = put(world, site, 'builder', 'cyan');
    const w = withBots(world, [b]);
    expect(rate(w, b, site)).toBe(base(w, site));
    const later = step(w);
    expect(bytesOf(later, 'cyan') - bytesOf(w, 'cyan')).toBeCloseTo(base(w, site) * RULES.tickSeconds, 3);
    expect(node(later, site).bytes - node(w, site).bytes).toBeCloseTo(base(w, site) * RULES.tickSeconds, 3);
    expect(teamState(run(w, 2), 'cyan').income).toBeGreaterThan(0);
  });
  it('goes twice as fast for a Builder with a Tester of its team, and the Tester then builds nothing itself', () => {
    const { world, site } = ground();
    const b = put(world, site, 'builder', 'cyan');
    const t = put(world, site, 'tester', 'cyan');
    const w = withBots(world, [b, t]);
    expect(rate(w, b, site)).toBe(RULES.testerBoost * base(w, site));
    expect(rate(w, t, site)).toBe(0);
    // Another team's Tester doubles nobody.
    const other = withBots(world, [b, put(world, site, 'tester', 'magenta')]);
    expect(rate(other, b, site)).toBe(base(w, site));
  });
  it('is a Combinator\'s too, which no Tester doubles', () => {
    const { world, site } = ground();
    const y = put(world, site, 'combinator', 'cyan');
    const w = withBots(world, [y, put(world, site, 'tester', 'cyan')]);
    expect(rate(w, y, site)).toBe(base(w, site));
  });
  it('is the holding Anchor\'s, and a Tester\'s on a site its team\'s Anchor holds, and nowhere else', () => {
    const { world, site } = ground();
    const t = put(world, site, 'tester', 'cyan');
    expect(rate(withBots(world, [t]), t, site)).toBe(0);
    const held = withBots(world, [put(world, site, 'anchor', 'cyan'), t]);
    expect(rate(held, t, site)).toBe(base(held, site));
    const anchor = held.bots[0]!;
    expect(rate(held, anchor, site)).toBe(base(held, site));
    expect(rate(withBots(world, [anchor, put(world, site, 'anchor', 'magenta', 5)]), put(world, site, 'anchor', 'magenta', 5), site)).toBe(0);
  });
  it('stops when the site is cut off from the origin', () => {
    const { world, site } = ground();
    const b = put(world, site, 'builder', 'cyan');
    const cut = { ...withBots(world, [b]), links: [], teams: world.teams.map((t) => ({ ...t, known: { ...t.known, links: [] } })) };
    expect(rate(cut, b, site)).toBe(0);
    expect(bytesOf(step(cut), 'cyan')).toBe(bytesOf(cut, 'cyan'));
  });
  it('is the holding team\'s alone: the first Anchor holds the site, another team\'s arriving later holds nothing', () => {
    const { world, site } = ground();
    const cyanAnchor = put(world, site, 'anchor', 'cyan', 0);
    const magentaAnchor = put(world, site, 'anchor', 'magenta', 5);
    const magentaBuilder = put(world, site, 'builder', 'magenta');
    const cyanBuilder = put(world, site, 'builder', 'cyan');
    const w = withBots(world, [cyanAnchor, magentaAnchor, magentaBuilder, cyanBuilder]);
    expect(holderOf(w, site)).toBe('cyan');
    expect(heldAgainst(w, 'magenta', site)).toBe(true);
    expect(heldAgainst(w, 'cyan', site)).toBe(false);
    expect(rate(w, magentaBuilder, site)).toBe(0);
    expect(rate(w, cyanBuilder, site)).toBe(base(w, site));
  });
  it('is held for RULES.holdSeconds only: then the Anchor holds and builds nothing, the next Anchor there holds it, and the first moves on', () => {
    const { world, site } = ground();
    const hold = RULES.holdSeconds / RULES.tickSeconds;
    const now = { ...world, tick: world.tick + hold * 2 };
    const done = put(now, site, 'anchor', 'cyan', now.tick - hold);
    const fresh = put(now, site, 'anchor', 'magenta', now.tick - hold + 1);
    const both = withBots(now, [done, fresh]);
    expect(holderOf(both, site)).toBe('magenta');
    expect(rate(both, done, site)).toBe(0);
    // The next Anchor builds there, as the holder (one of the team's own: another team may have no way to the site).
    const next = { ...fresh, team: 'cyan' as const, uid: 'cyan-next' };
    expect(rate(withBots(now, [done, next]), next, site)).toBe(base(both, site));
    // A tick before its time is up, the first still held it.
    expect(holderOf(withBots(now, [{ ...done, since: now.tick - hold + 1 }, { ...fresh, since: now.tick - hold + 2 }]), site)).toBe('cyan');
    // Alone and out of time, it sets off for another site it knows, to hold that one.
    const alone = run(withBots(now, [done]), 0.5).bots[0]!;
    expect(alone.travel === null && alone.node === site).toBe(false);
  });
  it('stops at the site\'s size: the last bytes are what is left, then the site is spent, and its bots move on', () => {
    const { world, site } = ground();
    const b = put(world, site, 'builder', 'cyan');
    const capacity = node(world, site).capacity;
    const almost = { ...withBots(world, [b]), nodes: world.nodes.map((n) => (n.id === site ? { ...n, bytes: capacity - 1000 } : n)) };
    expect(room(node(almost, site))).toBe(1000);
    const later = step(almost);
    expect(node(later, site).bytes).toBe(capacity);
    expect(bytesOf(later, 'cyan') - bytesOf(almost, 'cyan')).toBe(1000);
    expect(spent(node(later, site))).toBe(true);
    expect(rate(later, b, site)).toBe(0);
    expect(room(node(later, site))).toBe(0);
    // The Builder leaves for a site with room, when it knows one.
    const moved = run(later, 1).bots.find((o) => o.uid === b.uid)!;
    expect(moved.node === site && moved.travel === null).toBe(false);
  });
  it('is open to any number of bots of any team while nobody holds the site, each at the rate', () => {
    const { world, site } = ground();
    const cyan = teamState(world, 'cyan');
    const builders = [put(world, site, 'builder', 'cyan'), put(world, site, 'builder', 'cyan'), put(world, site, 'builder', 'cyan')];
    const w = withBots(world, builders);
    expect(holderOf(w, site)).toBeNull();
    for (const b of builders) expect(rate(w, b, site)).toBe(base(w, site));
    expect(bytesOf(step(w), 'cyan') - bytesOf(w, 'cyan')).toBeCloseTo(3 * base(w, site) * RULES.tickSeconds, 3);
    expect(cyan.known.nodes).toContain(site);
  });
});

describe('the Combinator', () => {
  it('makes a shortcut where two links it knows meet, and the team walks it', () => {
    let world = run(only(newWorld(SEED), ['explorer', 'combinator']), 60);
    const shortcuts = world.links.filter((l) => l.by === 'cyan');
    expect(shortcuts.length).toBeGreaterThan(0);
    const cyan = teamState(world, 'cyan');
    for (const s of shortcuts) expect(cyan.known.links).toContain(s.id);
    // The shortcut is a way: its ends are joined by it.
    const s = shortcuts[0]!;
    expect(route(world, cyan, s.a, s.b)!.distance).toBeLessThanOrEqual(Math.hypot(node(world, s.a).at.x - node(world, s.b).at.x, node(world, s.a).at.y - node(world, s.b).at.y) + 1);
  });
});

describe('buying and hacking', () => {
  it('buys a bot for a megabyte, at the origin; sends the nearest bot to the mainframe for a megabyte, an Explorer last', () => {
    const start = newWorld(SEED);
    expect(() => buy(start, 'cyan', 'anchor')).toThrow();
    const rich = { ...start, teams: start.teams.map((t) => (t.id === 'cyan' ? { ...t, bytes: 2 * MB } : t)) };
    const bought = buy(rich, 'cyan', 'tester');
    expect(bytesOf(bought, 'cyan')).toBe(MB);
    expect(bought.bots).toHaveLength(16);
    const added = bought.bots[15]!;
    expect(added).toMatchObject({ kind: 'tester', id: 'T', team: 'cyan', node: originId('cyan'), hacker: false });
    expect(teamState(bought, 'cyan').bought).toBe(1);
    const sent = sendHacker(bought, 'cyan');
    expect(bytesOf(sent, 'cyan')).toBe(0);
    expect(sent.bots.filter((b) => b.hacker)).toHaveLength(1);
    expect(sent.bots.find((b) => b.hacker)).toMatchObject({ team: 'cyan' });
    expect(sent.bots.find((b) => b.hacker)!.kind).not.toBe('explorer');
    expect(situation(sent, 'cyan')).toMatchObject({ hackers: 1, bots: 6 });
    expect(() => sendHacker(sent, 'cyan')).toThrow();
    // Every other bot first; the Explorer last; then nobody.
    let all: World = { ...bought, teams: bought.teams.map((t) => (t.id === 'cyan' ? { ...t, bytes: 10 * MB } : t)) };
    const kinds: string[] = [];
    while (hackerFor(all, 'cyan') !== null) {
      kinds.push(hackerFor(all, 'cyan')!.kind);
      all = sendHacker(all, 'cyan');
    }
    expect(kinds).toHaveLength(6);
    expect(kinds[5]).toBe('explorer');
    expect(() => sendHacker(all, 'cyan')).toThrow(/no bot/);
  });
  it('is built at the mainframe by the bots sent there, any kind, and ends the game', () => {
    // Explore until cyan's origin reaches the mainframe over links it knows (they rot, so not forever).
    let world = only(newWorld(SEED), ['explorer']);
    for (let i = 0; i < 120 && !situation(world, 'cyan').mainframe_connected; i++) world = run(world, 1);
    expect(teamState(world, 'cyan').known.nodes).toContain(MAINFRAME_ID);
    // Cyan's Anchor and Builder, sent in; Testers to keep the way open.
    const sent = newWorld(SEED).bots.filter((b) => b.team === 'cyan' && (b.kind === 'anchor' || b.kind === 'builder')).map((b) => ({ ...b, hacker: true }));
    const testers = newWorld(SEED).bots.filter((b) => b.kind === 'tester');
    world = { ...world, bots: [...world.bots, ...sent, ...testers] };
    expect(situation(world, 'cyan')).toMatchObject({ mainframe_connected: true, hackers: 2 });
    // Until they build there: the way rots too, so look while it holds.
    for (let i = 0; i < 120 && hackedPct(world, 'cyan') === 0; i++) world = run(world, 0.5);
    expect(hackedPct(world, 'cyan')).toBeGreaterThan(0);
    expect(node(world, MAINFRAME_ID).bytes).toBe(teamState(world, 'cyan').hacked);
    for (const b of world.bots.filter((o) => o.hacker)) expect(b.node === MAINFRAME_ID || b.target === MAINFRAME_ID || world.winner !== null).toBe(true);
    // At the mainframe, a bot sent there builds, whatever its kind, at its richness; one not sent builds nothing.
    const at = world.bots.find((b) => b.hacker && b.node === MAINFRAME_ID && b.travel === null)!;
    expect(buildRate(world, at, node(world, MAINFRAME_ID))).toBe(RULES.buildPerSecond * RULES.richness.mainframe);
    expect(buildRate(world, { ...at, hacker: false }, node(world, MAINFRAME_ID))).toBe(0);
    world = run(world, 120);
    expect(world.winner).toBe('cyan');
    expect(hackedPct(world, 'cyan')).toBe(100);
    expect(step(world)).toBe(world);
  });
});

describe('the strategies', () => {
  it('are three presets, each a build table on the team model, and decide every situation', () => {
    expect(STRATEGIES.map((s) => s.id)).toEqual(['farmer', 'sprinter', 'swarm', 'doubler', 'fortress']);
    const state = situation(newWorld(SEED), 'cyan');
    for (const s of STRATEGIES) {
      const request = buildRequest(s, state);
      expect(request).toMatchObject({ decision: { name: expect.stringContaining(s.name), decisions: s.decisions }, state });
      const decision = decideLocally(s, state);
      expect(decision.rule).toBeGreaterThan(0);
      expect(decision.why).toBeTruthy();
    }
    expect(() => strategy('none')).toThrow();
  });
  it('see exactly the team model\'s inputs, which aityx checks the state against', () => {
    expect(Object.keys(situation(newWorld(SEED), 'cyan')).sort()).toEqual(Object.keys(TEAM_MODEL.inputs).sort());
  });
  it('reads aityx\'s answer: the build, the row that fired and its why', () => {
    const s = strategy('farmer');
    const sent = buildRequest(s, situation(newWorld(SEED), 'cyan'));
    const decision = readDecision(sent, { answers: { build: { choice: 'anchor' } }, receipt: { decisions: { build: { rule: 2 } } } });
    expect(decision).toEqual({ build: 'anchor', rule: 2, why: expect.stringContaining('second Builder') });
    expect(() => readDecision(sent, { answers: {}, receipt: {} })).toThrow(/no build/);
    expect(() => readDecision(sent, { decision_error: { code: 'x', detail: 'y' } })).toThrow(/x, y/);
    expect(() => readDecision(sent, 'nope')).toThrow(/unexpected/);
  });
});

describe('a match', () => {
  it('plays itself from the strategies, every megabyte decided, until a team hacks the mainframe', async () => {
    const asked: string[] = [];
    const match = new Match(async (team, s, state) => {
      asked.push(team);
      return decideLocally(s, state);
    });
    let seconds = 0;
    while (match.world.winner === null && seconds < 600) {
      match.advance(1);
      await Promise.resolve();
      seconds += 1;
    }
    expect(match.world.winner).not.toBeNull();
    expect(asked.length).toBeGreaterThan(5);
    expect(match.made.every((m) => m.error === null)).toBe(true);
    expect(match.world.bots.length).toBeGreaterThan(15);
    const line = TEAMS.map((t) => `${t.id} ${match.strategyOf(t.id).id}: ${match.world.bots.filter((b) => b.team === t.id).length} bots, ${Math.round(hackedPct(match.world, t.id))}% in`);
    console.log(`winner ${match.world.winner} at ${Math.round(match.world.seconds)} s, ${asked.length} decisions; ${line.join('; ')}`);
  });
});

describe('a tournament', () => {
  it('plays every lineup once, and ranks the strategies', async () => {
    const { lineups, playTournament } = await import('../src/game/tournament');
    // Every trio of the five, each turned through the three seats.
    expect(lineups()).toHaveLength(30);
    for (const t of TEAMS) {
      for (const s of STRATEGIES) expect(lineups().filter((l) => l[t.id] === s.id)).toHaveLength(6);
    }
    for (const l of lineups()) expect(new Set(Object.values(l)).size).toBe(3);
    expect(lineups(['farmer', 'sprinter', 'swarm'])).toHaveLength(3);
    const done: number[] = [];
    const { results, standings } = await playTournament(async (_team, s, state) => decideLocally(s, state), (n) => done.push(n));
    expect(done).toHaveLength(30);
    expect(results.every((r) => r.decisions > 0)).toBe(true);
    expect(standings.map((s) => s.played)).toEqual([18, 18, 18, 18, 18]);
    expect(standings.reduce((n, s) => n + s.wins, 0)).toBe(results.filter((r) => r.winner !== null).length);
    console.log(standings.map((s) => `${s.name} ${s.wins}/${s.played} ${s.progress}%`).join('; '));
    const seats = TEAMS.map((t) => `${t.id} ${results.filter((r) => r.winner === t.id).length}`);
    console.log(`wins by seat: ${seats.join(', ')}`);
  }, 240_000);
  it('stops when aityx refuses every question', async () => {
    const { playMatch, AityxFailing } = await import('../src/game/tournament');
    await expect(playMatch(async () => { throw new Error('aityx rejected the key'); }, { cyan: 'farmer', magenta: 'sprinter', green: 'swarm' })).rejects.toBeInstanceOf(AityxFailing);
  });
});

describe('a team\'s own strategy', () => {
  it('round-trips through a file, and a bad one says what to fix', async () => {
    const { parseStrategy, strategyFile } = await import('../src/game/lineup');
    const own = parseStrategy(strategyFile(strategy('farmer')));
    expect(own.name).toBe('The Farmer');
    expect(own.decisions).toEqual(strategy('farmer').decisions);
    expect(decideLocally(own, situation(newWorld(SEED), 'cyan')).build).toBe(decideLocally(strategy('farmer'), situation(newWorld(SEED), 'cyan')).build);
    expect(() => parseStrategy('nope')).toThrow(/not JSON/);
    expect(() => parseStrategy('{"name": "x"}')).toThrow(/decisions.build.table/);
    const looks = { name: 'x', decisions: { build: { table: [['=>'], { when: { mood: 'happy' }, then: 'hack' }] } } };
    expect(() => parseStrategy(JSON.stringify(looks))).toThrow(/mood/);
    const answers = { name: 'x', decisions: { build: { table: [['=>'], { then: 'dance' }] } } };
    expect(() => parseStrategy(JSON.stringify(answers))).toThrow(/then/);
  });
});

describe('the lineup', () => {
  it('is drawn at random from the presets, no two teams the same', async () => {
    const { lineup, shuffleLineup } = await import('../src/game/lineup');
    const seen = new Set<string>();
    const random = seeded(SEED);
    for (let i = 0; i < 50; i++) {
      const drawn = shuffleLineup(random);
      const ids = TEAMS.map((t) => drawn[t.id].id);
      expect(new Set(ids).size).toBe(TEAMS.length);
      for (const id of ids) expect(STRATEGIES.map((s) => s.id)).toContain(id);
      expect(lineup()).toBe(drawn);
      seen.add(ids.join(','));
    }
    expect(seen.size).toBeGreaterThan(10);
  });
});
