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
// when it ends. The entries are in their own file, strategies.json; with
// none yet, the ones kept in the repository (tatyx/strategies/) start it.
// The files are in a store (store.mjs): a folder, or a bucket deployed.
// Deployed, a tournament is played by the runner function, one at a time
// (`dispatch` hands it there; `runNow` is what it runs), and its progress
// is in live.json for every instance of the API to show.

import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';

/** How many tournaments the file keeps, and the standings count. */
const KEEP = 20;
const CALL_TIMEOUT_MS = 30_000;
/** How long a tournament asked for waits, deployed, before another from the same source is asked for: Lambda's queue keeps it six hours. */
const WAITING_MS = 6 * 3_600_000;
/** Who asks for a tournament. */
export const SOURCES = ['schedule', 'admin', 'strategy'];

export class EntryError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.name = 'EntryError';
    this.status = status;
  }
}

const json = (value) => JSON.stringify(value, null, 2);

/** `text` as JSON, or null. */
function parsed(text) {
  if (text === null) return null;
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export function createLeaderboard({ store, seeds = [], runnerPath, settings, ownerName, everyHours, maxEntries = 3, log, dispatch = null }) {
  let data = { tournaments: [], queue: [] };
  let entries = [];
  let loading = null;
  let runner = null;
  /** What it is doing now. */
  const live = { running: false, match: 0, of: 0, calls: 0, startedAt: null, source: null, error: null };
  let timer = null;
  let nextAt = null;

  /** Reads the files: once from a folder (every caller waits for the same read), every time from a shared bucket. */
  function load() {
    if (store.shared) return readFiles();
    loading ??= readFiles();
    return loading;
  }

  async function readFiles() {
    const board = parsed(await store.read('leaderboard.json'));
    if (Array.isArray(board?.tournaments)) data = { ...board, queue: Array.isArray(board.queue) ? board.queue : [] };
    // The entries; before strategies.json, they were in entries.json; with neither, the repository's start them.
    const kept = parsed(await store.read('strategies.json')) ?? parsed(await store.read('entries.json'));
    if (Array.isArray(kept?.entries)) entries = kept.entries;
    else if (kept === null && seeds.length > 0) {
      entries = [...seeds];
      await saveEntries();
      log(`leaderboard: ${seeds.length} strategies from the repository entered the tour`);
    }
  }

  const save = () => store.write('leaderboard.json', json(data));
  const saveEntries = () => store.write('strategies.json', json({ entries }));
  /** What the runner is doing, for the API's instances (deployed). */
  const saveLive = () => (dispatch !== null || store.shared ? store.write('live.json', json({ ...live, at: new Date().toISOString() })) : Promise.resolve());

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
      await saveLive();
      const { results, standings } = await g.run(callerOn(s), (done) => {
        live.match = done;
        void saveLive().catch(() => {});
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

  /** One tournament now, from `source`, to its end: the runner function's work, deployed. */
  async function runNow(source) {
    const ready = await readiness();
    if (!ready.enabled) {
      log(`leaderboard: no tournament: ${ready.reason}`);
      return;
    }
    await load();
    live.running = true;
    // Its run starts: the next ask from the same source asks for another.
    const asked = parsed(await store.read('asked.json')) ?? {};
    if (asked[source] !== undefined) {
      delete asked[source];
      await store.write('asked.json', json(asked));
    }
    try {
      await playOne(source, ready.settings);
    } finally {
      live.running = false;
      await saveLive().catch(() => {});
    }
  }

  /** What the runner is doing: this process's own, or, deployed, the runner function's (live.json; a run older than its 15 minutes is over). */
  async function liveNow() {
    if (dispatch === null) return live;
    const kept = parsed(await store.read('live.json'));
    if (kept === null) return { ...live, running: false };
    const stale = kept.running && Date.now() - Date.parse(kept.at ?? 0) > 15 * 60_000;
    return stale ? { ...kept, running: false } : kept;
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
    // Deployed: the runner function plays it, one at a time; the others wait their turn there.
    // One waiting per source, as here: asked.json says when each was asked for, until its run starts.
    if (dispatch !== null) {
      const asked = parsed(await store.read('asked.json')) ?? {};
      const at = Date.parse(asked[source] ?? '');
      if (Number.isFinite(at) && Date.now() - at < WAITING_MS) return { asked: 'waiting' };
      await store.write('asked.json', json({ ...asked, [source]: new Date().toISOString() }));
      const running = (await liveNow()).running;
      await dispatch(source);
      return { asked: running ? 'queued' : 'started' };
    }
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

  /**
   * What GET /api/leaderboard answers: no keys, no emails. The wins (and
   * what tells them: the progress, the winning times, each match's
   * winner) for an admin alone, so they don't steer the players.
   */
  async function view({ admin = false } = {}) {
    await load();
    const ready = await readiness();
    const live = await liveNow();
    if (dispatch !== null) scheduleNext();
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
    if (!admin) standings = standings.map(({ wins, progress, winSeconds, ...rest }) => rest);
    const results = (latest?.results ?? []).map((r) => (admin ? r : (({ winner, winnerStrategy, progress, ...rest }) => rest)(r)));
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
        results,
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

  /** The next start on the schedule: the next whole multiple of `everyHours` hours, UTC (deployed, the schedule's own; only shown here). */
  function scheduleNext() {
    if (!(everyHours > 0)) return;
    const step = everyHours * 3_600_000;
    nextAt = Math.floor(Date.now() / step) * step + step;
    if (dispatch !== null) return;
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
  // What the last process left in the queue (a folder's; deployed, the runner function keeps none).
  if (dispatch === null) {
    load()
      .then(() => (data.queue.length > 0 ? drain() : undefined))
      .catch((error) => log(`leaderboard: the queue could not be read: ${error?.message ?? error}`));
  }
  return {
    view,
    ask,
    enter,
    withdraw,
    entries: listEntries,
    runNow,
    stop: () => timer && clearTimeout(timer),
  };
}
