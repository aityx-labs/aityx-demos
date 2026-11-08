// The leaderboard: tournaments of the preset strategies, played here on
// the leaderboard's own aityx key, which never leaves this server (no
// answer of the API holds it, no log prints it). A tournament is every
// lineup of the three strategies, one headless match each (the game's
// runner, bundled by `npm run build` into tatyx_app/dist-runner/); the
// results are kept in a JSON file, and the standings are over the
// tournaments kept. Played on a schedule (every few hours, on the hour
// in UTC) and when an admin asks.

import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

/** How many tournaments the file keeps, and the standings count. */
const KEEP = 20;
const CALL_TIMEOUT_MS = 30_000;

export function createLeaderboard({ dataDir, runnerPath, settings, ownerName, everyHours, cooldownMinutes, log }) {
  const file = join(dataDir, 'leaderboard.json');
  let data = { tournaments: [] };
  let loaded = false;
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

  async function save() {
    await mkdir(dirname(file), { recursive: true });
    const temp = `${file}.tmp`;
    await writeFile(temp, JSON.stringify(data, null, 2), { mode: 0o600 });
    await rename(temp, file);
  }

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

  /** Plays one tournament now, unless one is being played. */
  async function play(by) {
    const ready = await readiness();
    if (!ready.enabled) return { started: false, reason: ready.reason };
    if (live.running) return { started: false, reason: 'a tournament is being played' };
    await load();
    const g = await game();
    Object.assign(live, { running: true, match: 0, of: g.MATCHES, calls: 0, startedAt: new Date().toISOString(), by, error: null, lastStartedAt: Date.now() });
    const number = (data.tournaments.at(-1)?.number ?? 0) + 1;
    log(`leaderboard: tournament ${number} started${by ? ' (asked for)' : ' (scheduled)'}`);
    (async () => {
      try {
        const { results, standings } = await g.run(callerOn(ready.settings), (done) => {
          live.match = done;
        });
        data.tournaments.push({ number, startedAt: live.startedAt, finishedAt: new Date().toISOString(), calls: live.calls, results, standings });
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

  /** What GET /api/leaderboard answers: no keys, no emails. */
  async function view() {
    await load();
    const ready = await readiness();
    const tournaments = data.tournaments;
    let standings = [];
    if (tournaments.length > 0) {
      try {
        standings = (await game()).standings(tournaments.flatMap((t) => t.results));
      } catch {
        standings = tournaments.at(-1).standings ?? [];
      }
    }
    // Under each strategy, whose it is: its owner's alias; a preset has none (a template strategy).
    standings = await Promise.all(standings.map(async (s) => ({ ...s, by: s.owner ? await ownerName(s.owner) : null, owner: undefined })));
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
        results: latest.results,
      },
    };
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
  return { view, playNow, stop: () => timer && clearTimeout(timer) };
}
