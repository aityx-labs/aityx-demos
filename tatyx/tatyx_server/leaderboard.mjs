// The leaderboard: tournaments among the preset strategies and the ones
// players enter, played here on the leaderboard's own aityx key, which
// never leaves this server (no answer of the API holds it, no log prints
// it). A tournament is a field of five of them, the fewest matches played
// first, so a new entry plays at once: every lineup of the field, one
// headless match each (the game's runner, bundled by `npm run build` into
// tatyx_app/dist-runner/). The results are kept in a JSON file, and the
// standings are over the tournaments kept. Asked for on a schedule (every
// few hours, on the hour in UTC), by an admin, and by every strategy a
// player enters; never two at once: a tournament asked for while one is
// played is queued (one waiting per source, kept in the file) and played
// when it ends. The entries are in their own file, strategies.json.

import { randomBytes } from 'node:crypto';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

/** How many tournaments the file keeps, and the standings count. */
const KEEP = 20;
const CALL_TIMEOUT_MS = 30_000;
/** Who asks for a tournament. */
export const SOURCES = ['schedule', 'admin', 'strategy'];

export class EntryError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = 'EntryError';
    this.status = status;
  }
}

/** Writes `data` as `file`, through a temporary file, mode 600. */
async function writeJson(file, data) {
  await mkdir(dirname(file), { recursive: true });
  const temp = `${file}.tmp`;
  await writeFile(temp, JSON.stringify(data, null, 2), { mode: 0o600 });
  await rename(temp, file);
}

export function createLeaderboard({ dataDir, runnerPath, settings, ownerName, everyHours, maxEntries = 3, log }) {
  const file = join(dataDir, 'leaderboard.json');
  const entriesFile = join(dataDir, 'strategies.json');
  let data = { tournaments: [], queue: [] };
  let entries = [];
  let loading = null;
  let runner = null;
  /** What it is doing now. */
  const live = { running: false, match: 0, of: 0, calls: 0, startedAt: null, source: null, error: null };
  let timer = null;
  let nextAt = null;

  /** Reads the files once; every caller waits for the same read. */
  function load() {
    loading ??= readFiles();
    return loading;
  }

  async function readFiles() {
    try {
      const parsed = JSON.parse(await readFile(file, 'utf8'));
      if (Array.isArray(parsed.tournaments)) data = { ...parsed, queue: Array.isArray(parsed.queue) ? parsed.queue : [] };
    } catch {
      // No file yet: no tournaments.
    }
    try {
      const parsed = JSON.parse(await readFile(entriesFile, 'utf8'));
      if (Array.isArray(parsed.entries)) entries = parsed.entries;
    } catch {
      // No entries yet.
    }
  }

  const save = () => writeJson(file, data);
  const saveEntries = () => writeJson(entriesFile, { entries });

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

  /** One systemone call on the leaderboard's key. */
  function callerOn(s) {
    return async (body) => {
      live.calls += 1;
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

  /** An entry as the game plays it. */
  const asStrategy = (e) => ({ id: e.id, name: e.name, tagline: e.tagline, decisions: e.decisions });

  /** How many matches each strategy played in the tournaments kept. */
  function playedCounts() {
    const counts = new Map();
    for (const t of data.tournaments) {
      for (const r of t.results ?? []) {
        for (const id of Object.values(r.lineup ?? {})) counts.set(id, (counts.get(id) ?? 0) + 1);
      }
    }
    return counts;
  }

  /** Plays one tournament, to its end; never throws (a failure is in live.error). */
  async function playOne(source, s) {
    const g = await game();
    const counts = playedCounts();
    const field = g.pickField([...g.STRATEGIES, ...entries.map(asStrategy)], (id) => counts.get(id) ?? 0);
    const number = (data.tournaments.at(-1)?.number ?? 0) + 1;
    Object.assign(live, { running: true, match: 0, of: g.MATCHES, calls: 0, startedAt: new Date().toISOString(), source, error: null });
    log(`leaderboard: tournament ${number} started (asked for by the ${source}): ${field.map((f) => f.name).join(', ')}`);
    try {
      const { results, standings } = await g.run(callerOn(s), (done) => {
        live.match = done;
      }, field);
      const owners = new Map(entries.map((e) => [e.id, e.owner]));
      data.tournaments.push({
        number,
        source,
        startedAt: live.startedAt,
        finishedAt: new Date().toISOString(),
        calls: live.calls,
        field: field.map((f) => ({ id: f.id, name: f.name, owner: owners.get(f.id) ?? null })),
        results,
        standings,
      });
      data.tournaments = data.tournaments.slice(-KEEP);
      await save();
      log(`leaderboard: tournament ${number} done, ${live.calls} calls; first: ${standings[0]?.name ?? 'nobody'}`);
    } catch (error) {
      live.error = error instanceof Error ? error.message : String(error);
      log(`leaderboard: tournament ${number} failed: ${live.error}`);
    }
  }

  /** Plays the queue, the oldest first, one at a time, until it is empty; one drain at a time. */
  async function drain() {
    // Taken before the first await: two drains never both pass.
    if (live.running) return;
    live.running = true;
    try {
      const ready = await readiness();
      if (!ready.enabled) return;
      for (;;) {
        await load();
        const next = data.queue[0];
        if (next === undefined) break;
        data.queue = data.queue.slice(1);
        await save();
        await playOne(next.source, ready.settings);
      }
    } finally {
      live.running = false;
    }
  }

  /**
   * Asks for a tournament from `source`: queued, unless one from it is
   * waiting already; played when the one being played ends. What asking
   * did: "started", "queued" or "waiting"; or { off: reason }.
   */
  async function ask(source) {
    const ready = await readiness();
    if (!ready.enabled) return { off: ready.reason };
    await load();
    let asked;
    if (data.queue.some((q) => q.source === source)) asked = 'waiting';
    else {
      data.queue = [...data.queue, { source, at: new Date().toISOString() }];
      await save();
      asked = live.running ? 'queued' : 'started';
    }
    void drain();
    return { asked };
  }

  /** What GET /api/leaderboard answers: no keys, no emails. */
  async function view() {
    await load();
    const ready = await readiness();
    const tournaments = data.tournaments;
    const g = tournaments.length > 0 || entries.length > 0 ? await game().catch(() => null) : null;
    // The presets and the entries in the tour: a withdrawn entry leaves the standings.
    const named = [...(g?.STRATEGIES ?? []), ...entries];
    const owners = new Map(entries.map((e) => [e.id, e.owner]));
    let standings = [];
    if (tournaments.length > 0) {
      try {
        standings = g.standings(tournaments.flatMap((t) => t.results), named).filter((s) => named.some((n) => n.id === s.strategy));
      } catch {
        standings = tournaments.at(-1).standings ?? [];
      }
    }
    // Under each strategy, whose it is: its owner's alias; a preset has none (a template strategy).
    standings = await Promise.all(standings.map(async (s) => ({ ...s, by: owners.has(s.strategy) ? await ownerName(owners.get(s.strategy)) : null })));
    const latest = tournaments.at(-1) ?? null;
    return {
      enabled: ready.enabled,
      reason: ready.reason,
      running: live.running && live.startedAt !== null ? { match: live.match, of: live.of, calls: live.calls, startedAt: live.startedAt, source: live.source } : null,
      queue: data.queue.map((q) => ({ source: q.source, at: q.at })),
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
        names: Object.fromEntries((latest.field ?? []).map((f) => [f.id, f.name])),
        results: latest.results,
      },
    };
  }

  /** The entries in the tour, each with its owner's alias and whether it is `email`'s; the rules too. */
  async function listEntries(email) {
    await load();
    return Promise.all(
      entries.map(async (e) => ({ id: e.id, name: e.name, tagline: e.tagline, decisions: e.decisions, by: await ownerName(e.owner), mine: e.owner === email, enteredAt: e.enteredAt })),
    );
  }

  /**
   * Enters `json` (a strategy file's object) for `email`: checked as the
   * game checks an upload, replacing the player's entry of the same name;
   * then a tournament is asked for. The entry and what asking did.
   */
  async function enter(email, json) {
    await load();
    const g = await game();
    let s;
    try {
      s = g.parseStrategy(JSON.stringify(json));
    } catch (error) {
      if (error instanceof g.BadStrategy) throw new EntryError(error.message);
      throw error;
    }
    if (g.STRATEGIES.some((p) => p.name.toLowerCase() === s.name.toLowerCase())) throw new EntryError(`"${s.name}" is a preset's name: give yours another`);
    const same = entries.find((e) => e.owner === email && e.name.toLowerCase() === s.name.toLowerCase());
    if (!same && entries.filter((e) => e.owner === email).length >= maxEntries) {
      throw new EntryError(`you have ${maxEntries} strategies in the tour: withdraw one first`, 409);
    }
    const entry = { id: `u-${randomBytes(5).toString('hex')}`, owner: email, name: s.name, tagline: s.tagline, decisions: s.decisions, enteredAt: new Date().toISOString() };
    // A replacement is a new strategy, with a fresh record.
    entries = [...entries.filter((e) => e !== same), entry];
    await saveEntries();
    log(`leaderboard: a strategy was entered (${entries.length} in the tour)`);
    const asked = await ask('strategy');
    return { entry: { id: entry.id, name: entry.name, tagline: entry.tagline, by: await ownerName(email), mine: true }, tournament: asked.asked ?? null };
  }

  /** Withdraws `email`'s entry `id`; false when there is no such entry of theirs. */
  async function withdraw(email, id) {
    await load();
    const gone = entries.find((e) => e.id === id && e.owner === email);
    if (!gone) return false;
    entries = entries.filter((e) => e !== gone);
    await saveEntries();
    return true;
  }

  /** The next start on the schedule: the next whole multiple of `everyHours` hours, UTC. */
  function scheduleNext() {
    if (!(everyHours > 0)) return;
    const step = everyHours * 3_600_000;
    nextAt = Math.floor(Date.now() / step) * step + step;
    timer = setTimeout(async () => {
      try {
        await ask('schedule');
      } catch (error) {
        log(`leaderboard: the scheduled tournament could not be asked for: ${error?.message ?? error}`);
      } finally {
        scheduleNext();
      }
    }, nextAt - Date.now());
    timer.unref?.();
  }

  scheduleNext();
  // What the last process left in the queue.
  load()
    .then(() => (data.queue.length > 0 ? drain() : undefined))
    .catch((error) => log(`leaderboard: the queue could not be read: ${error?.message ?? error}`));
  return { view, ask, enter, withdraw, entries: listEntries, stop: () => timer && clearTimeout(timer) };
}
