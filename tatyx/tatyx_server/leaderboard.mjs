// The leaderboard: tournaments of the preset strategies and the players'
// entries, played here on the leaderboard's own aityx key, which never
// leaves this server (no answer of the API holds it, no log prints it).
// A tournament is every lineup of three of its strategies, one headless
// match each (the game's runner, bundled by `npm run build` into
// tatyx_app/dist-runner/); the results are kept in a JSON file, and the
// standings are over the tournaments kept. Played on a schedule (every
// few hours, on the hour in UTC) and when an admin asks. The entries are
// kept in another file, with their owners' emails, which no answer
// holds.

import { randomBytes } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

/** How many tournaments the file keeps, and the standings count. */
const KEEP = 20;
const CALL_TIMEOUT_MS = 30_000;
/** The most entries a player may have in the tour. */
export const MAX_ENTRIES = 3;
/** The entries a tournament seats besides the presets: seven strategies, 105 matches. */
const ENTRIES_PER_TOURNAMENT = 2;

export class EntryError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function createLeaderboard({ dataDir, runnerPath, settings, ownerName, everyHours, cooldownMinutes, log }) {
  const file = join(dataDir, 'leaderboard.json');
  const entriesFile = join(dataDir, 'entries.json');
  let data = { tournaments: [] };
  let loaded = false;
  /** The players' entries: {id, name, tagline, decisions, owner (the email), enteredAt}. */
  let entries = null;
  let runner = null;
  /** What it is doing now. */
  const live = { running: false, match: 0, of: 0, calls: 0, startedAt: null, by: null, error: null, lastStartedAt: 0 };
  let timer = null;
  let nextAt = null;

  async function load() {
    if (loaded) return;
    loaded = true;
    try {
      const text = await readFile(file, 'utf8');
      const parsed = JSON.parse(text);
      if (Array.isArray(parsed.tournaments)) data = parsed;
    } catch {
      // No file yet: no tournaments.
    }
  }

  async function writeJson(path, value) {
    await mkdir(dirname(path), { recursive: true });
    const temp = `${path}.tmp`;
    await writeFile(temp, JSON.stringify(value, null, 2), { mode: 0o600 });
    await rename(temp, path);
  }

  const save = () => writeJson(file, data);

  async function loadEntries() {
    if (entries !== null) return entries;
    try {
      const parsed = JSON.parse(await readFile(entriesFile, 'utf8'));
      entries = Array.isArray(parsed.entries) ? parsed.entries : [];
    } catch {
      entries = [];
    }
    return entries;
  }

  /** Writes the entries as they are when its turn comes, one write at a time, so the last one holds the latest. */
  let writing = Promise.resolve();
  function saveEntries() {
    writing = writing.catch(() => {}).then(() => writeJson(entriesFile, { entries }));
    return writing;
  }

  /** An entry as the game plays it. */
  const strategyOf = (e) => ({ id: e.id, name: e.name, tagline: e.tagline, decisions: e.decisions });

  async function game() {
    runner ??= await import(pathToFileURL(runnerPath).href);
    return runner;
  }

  /** Whether it can play, and why not. */
  async function readiness() {
    const s = await settings();
    if (s.leaderboardOff) return { enabled: false, reason: 'the leaderboard is off (TATYX_LEADERBOARD=off)' };
    if (!s.leaderboardKey) return { enabled: false, reason: 'the server has no leaderboard key (TATYX_LEADERBOARD_KEY)' };
    if (s.base === null) return { enabled: false, reason: 'AITYX_URL must be an https URL' };
    return { enabled: true, reason: null, settings: s };
  }

  /** One systemone call on the leaderboard's key; a tournament's counted. */
  function callerOn(s, counted = true) {
    return async (body) => {
      if (counted) live.calls += 1;
      let answer;
      try {
        answer = await fetch(`${s.base.href.replace(/\/+$/, '')}/v1/systemone`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${s.leaderboardKey}`, 'Content-Type': 'application/json', 'User-Agent': 'aityx-demos-tatyx-leaderboard' },
          body: JSON.stringify(body),
          redirect: 'manual',
          signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
        });
      } catch (error) {
        throw new Error(`aityx did not answer (${error?.name ?? 'error'})`);
      }
      const text = await answer.text();
      let json = null;
      try {
        json = JSON.parse(text);
      } catch {
        json = null;
      }
      return { status: answer.status, json };
    };
  }

  /** Plays one tournament now, unless one is being played. */
  async function play(by) {
    const ready = await readiness();
    if (!ready.enabled) return { started: false, reason: ready.reason };
    if (live.running) return { started: false, reason: 'a tournament is being played' };
    await load();
    const g = await game();
    const seated = await seat();
    Object.assign(live, { running: true, match: 0, of: g.matches(seated.length), calls: 0, startedAt: new Date().toISOString(), by, error: null, lastStartedAt: Date.now() });
    const number = (data.tournaments.at(-1)?.number ?? 0) + 1;
    log(`leaderboard: tournament ${number} started${by ? ' (asked for)' : ' (scheduled)'}, ${seated.length} entr${seated.length === 1 ? 'y' : 'ies'} seated`);
    (async () => {
      try {
        const { results, standings } = await g.run(
          callerOn(ready.settings),
          (done) => {
            live.match = done;
          },
          seated.map(strategyOf),
        );
        const names = Object.fromEntries(seated.map((e) => [e.id, e.name]));
        data.tournaments.push({ number, startedAt: live.startedAt, finishedAt: new Date().toISOString(), calls: live.calls, names, results, standings });
        data.tournaments = data.tournaments.slice(-KEEP);
        await save();
        log(`leaderboard: tournament ${number} done, ${live.calls} calls; first: ${standings[0]?.name ?? 'nobody'}`);
      } catch (error) {
        live.error = error instanceof Error ? error.message : String(error);
        log(`leaderboard: tournament ${number} failed: ${live.error}`);
      } finally {
        live.running = false;
      }
    })();
    return { started: true };
  }

  /** The entries a tournament seats: those that have played the fewest matches in the tournaments kept, ties at random. */
  async function seat() {
    const played = new Map();
    for (const r of data.tournaments.flatMap((t) => t.results)) {
      for (const id of Object.values(r.lineup)) played.set(id, (played.get(id) ?? 0) + 1);
    }
    return (await loadEntries())
      .map((e) => ({ e, n: played.get(e.id) ?? 0, tie: Math.random() }))
      .sort((a, b) => a.n - b.n || a.tie - b.tie)
      .slice(0, ENTRIES_PER_TOURNAMENT)
      .map(({ e }) => e);
  }

  /** What GET /api/leaderboard answers: no keys, no emails. */
  async function view() {
    await load();
    const ready = await readiness();
    const tournaments = data.tournaments;
    const all = await loadEntries();
    let standings = [];
    if (tournaments.length > 0) {
      try {
        const g = await game();
        // The presets, and every entry in the tour: one that hasn't played yet shows with none played.
        standings = g.standings(
          tournaments.flatMap((t) => t.results),
          [...g.STRATEGIES, ...all.map(strategyOf)],
        );
      } catch {
        standings = tournaments.at(-1).standings ?? [];
      }
    }
    // Under each strategy, whose it is: its owner's alias; a preset has none (a template strategy).
    const owners = new Map(all.map((e) => [e.id, e.owner]));
    standings = await Promise.all(
      standings.map(async (s) => {
        const owner = owners.get(s.strategy);
        return { ...s, by: owner ? await ownerName(owner) : null, owner: undefined };
      }),
    );
    const latest = tournaments.at(-1) ?? null;
    return {
      enabled: ready.enabled,
      reason: ready.reason,
      running: live.running ? { match: live.match, of: live.of, calls: live.calls, startedAt: live.startedAt } : null,
      error: live.error,
      next: ready.enabled && nextAt !== null ? new Date(nextAt).toISOString() : null,
      everyHours,
      tournaments: tournaments.length,
      standings,
      latest: latest && {
        number: latest.number,
        startedAt: latest.startedAt,
        finishedAt: latest.finishedAt,
        calls: latest.calls,
        // The entries' names, for the matches' lineups (the presets' the app knows).
        names: latest.names ?? {},
        results: latest.results,
      },
    };
  }

  /** `email`'s entries, as they would download them. */
  async function entriesOf(email) {
    return (await loadEntries()).filter((e) => e.owner === email).map(({ id, name, tagline, decisions, enteredAt }) => ({ id, name, tagline, decisions, enteredAt }));
  }

  /**
   * Enters a strategy file's text for `email`: checked as the title checks
   * an upload, its name not a preset's, then asked once on aityx on the
   * leaderboard's key; an entry of the same name is replaced (a new id, a
   * fresh record), and a player has MAX_ENTRIES at most. Plays from the
   * next tournament. Throws EntryError with the status to answer.
   */
  async function enter(email, text) {
    const g = await game();
    let s;
    try {
      s = g.parseStrategy(text);
    } catch (error) {
      if (error instanceof g.BadStrategy) throw new EntryError(400, error.message);
      throw error;
    }
    if (g.STRATEGIES.some((p) => p.name.toLowerCase() === s.name.toLowerCase())) throw new EntryError(400, `"${s.name}" is a preset's name; call yours something else`);
    // The limit, before aityx is asked and again after, when another entry may have gone in meanwhile.
    const fits = (all) => {
      const mine = all.filter((e) => e.owner === email);
      const same = mine.find((e) => e.name.toLowerCase() === s.name.toLowerCase());
      if (!same && mine.length >= MAX_ENTRIES) throw new EntryError(409, `you already have ${MAX_ENTRIES} strategies in the tour; withdraw one first`);
      return same;
    };
    fits(await loadEntries());
    const ready = await readiness();
    if (!ready.enabled) throw new EntryError(503, `the strategy can't be checked: ${ready.reason}`);
    try {
      await g.check(callerOn(ready.settings, false), s);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (message === 'aityx rejected the key' || message.startsWith('aityx did not answer')) throw new EntryError(503, `the strategy can't be checked now: ${message}`);
      throw new EntryError(422, `aityx refused the rules: ${message}`);
    }
    const entry = { id: `e-${randomBytes(6).toString('hex')}`, name: s.name, tagline: s.tagline, decisions: s.decisions, owner: email, enteredAt: new Date().toISOString() };
    const all = await loadEntries();
    const same = fits(all);
    entries = [...all.filter((e) => e !== same), entry];
    await saveEntries();
    log(`leaderboard: an entry ${same ? 'replaced' : 'entered'} (${entry.id})`);
    const { owner, ...shown } = entry;
    return shown;
  }

  /** Withdraws `email`'s entry `id`: false when they have none by that id. */
  async function withdraw(email, id) {
    const all = await loadEntries();
    if (!all.some((e) => e.id === id && e.owner === email)) return false;
    entries = all.filter((e) => e.id !== id);
    await saveEntries();
    return true;
  }

  /** An admin's "play one now": not while one is played, nor within the cooldown of the last start. */
  async function playNow() {
    const wait = live.lastStartedAt + cooldownMinutes * 60_000 - Date.now();
    if (!live.running && wait > 0) return { started: false, reason: `the last tournament started less than ${cooldownMinutes} minutes ago: try again in ${Math.ceil(wait / 60_000)} min` };
    return play(true);
  }

  /** The next start on the schedule: the next whole multiple of `everyHours` hours, UTC. */
  function scheduleNext() {
    if (!(everyHours > 0)) return;
    const step = everyHours * 3_600_000;
    nextAt = Math.floor(Date.now() / step) * step + step;
    timer = setTimeout(async () => {
      try {
        await play(false);
      } finally {
        scheduleNext();
      }
    }, nextAt - Date.now());
    timer.unref?.();
  }

  scheduleNext();
  return { view, playNow, entriesOf, enter, withdraw, stop: () => timer && clearTimeout(timer) };
}
