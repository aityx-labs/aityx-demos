// The leaderboard's tab: the standings of the presets and the players'
// strategies over the tournaments the server played on its own key, what
// it is doing now and what waits its turn, the latest tournament's
// matches; for a signed-in player, their strategies in the tour (enter
// one, withdraw one), and for the tour's admins, a tournament now. Read
// from GET /api/leaderboard while the tab shows.

import { BadStrategy, parseStrategy } from '../game/lineup';
import { TEAMS } from '../game/teams';
import { auth } from './auth';
import { enterInTour, onEntriesChange, tourEntries, withdraw, type Entry } from './tour';

interface Standing {
  strategy: string;
  name: string;
  /** Whose it is: the owner's alias; null for a preset. */
  by: string | null;
  played: number;
  wins: number;
  progress: number;
  winSeconds: number | null;
}

interface Result {
  lineup: Record<string, string>;
  winner: string | null;
  winnerStrategy: string | null;
  seconds: number;
  progress: Record<string, number>;
  decisions: number;
}

interface View {
  enabled: boolean;
  reason: string | null;
  running: { match: number; of: number; calls: number; startedAt: string; source: string | null } | null;
  /** The tournaments waiting their turn, the oldest first. */
  queue: { source: string; at: string }[];
  error: string | null;
  next: string | null;
  everyHours: number;
  tournaments: number;
  standings: Standing[];
  latest: { number: number; startedAt: string; finishedAt: string; calls: number; names?: Record<string, string>; results: Result[] } | null;
}

// Each seat in its team's colour, from the teams' own list.
const COLORS: Record<string, string> = Object.fromEntries(TEAMS.map((t) => [t.id, t.css]));
const NAMES: Record<string, string> = { farmer: 'Farmer', sprinter: 'Sprinter', swarm: 'Swarm', doubler: 'Doubler', fortress: 'Fortress' };

const ASKERS: Record<string, string> = { schedule: 'the schedule’s', admin: 'an admin’s', strategy: 'a new strategy’s' };

const time = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
const esc = (text: string) => text.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

export function mountLeaderboard(parent: HTMLElement): { visible(on: boolean): void } {
  parent.innerHTML = `
<p class="muted small">The presets and the players’ strategies play each other on the server, on the tour’s own key: every few hours, and whenever a player enters a strategy, one tournament at a time. Five play each one, the fewest matches played first: every trio of them, each in every sector. The standings are over the latest tournaments.</p>
<div class="lb-status" id="lb-status"></div>
<button class="btn primary" type="button" id="lb-run" hidden>Play a tournament now</button>
<p class="note bad" id="lb-error" hidden></p>
<div id="lb-table"></div>
<div id="lb-mine" hidden>
  <h3>Your strategies in the tour</h3>
  <ul class="matches" id="lb-entries"></ul>
  <button class="btn" type="button" id="lb-enter">Enter a strategy</button>
  <p class="note" id="lb-entered" hidden></p>
</div>
<div id="lb-latest"></div>`;
  const status = parent.querySelector<HTMLElement>('#lb-status')!;
  const run = parent.querySelector<HTMLButtonElement>('#lb-run')!;
  const error = parent.querySelector<HTMLElement>('#lb-error')!;
  const table = parent.querySelector<HTMLElement>('#lb-table')!;
  const latest = parent.querySelector<HTMLElement>('#lb-latest')!;
  const mine = parent.querySelector<HTMLElement>('#lb-mine')!;
  const entriesList = parent.querySelector<HTMLElement>('#lb-entries')!;
  const enter = parent.querySelector<HTMLButtonElement>('#lb-enter')!;
  const entered = parent.querySelector<HTMLElement>('#lb-entered')!;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let on = false;
  let last: View | null = null;

  const render = (v: View) => {
    last = v;
    if (!v.enabled) status.textContent = `The leaderboard doesn’t play here: ${v.reason ?? 'it is off'}.`;
    else if (v.running) status.textContent = `Playing a tournament: match ${Math.min(v.running.match + 1, v.running.of)} of ${v.running.of}, ${v.running.calls} aityx calls so far.`;
    else if (v.next) status.textContent = `Next tournament at ${time(v.next)} (every ${v.everyHours} h).`;
    else status.textContent = 'Tournaments are played when an admin asks or a strategy is entered.';
    if (v.enabled && v.queue.length > 0) status.textContent += ` Waiting their turn: ${v.queue.map((q) => ASKERS[q.source] ?? q.source).join(', ')}.`;
    error.hidden = v.error === null;
    error.textContent = v.error ? `The last tournament failed: ${v.error}` : '';
    run.hidden = !(auth.player?.admin ?? false) || !v.enabled;
    // While one plays, an admin's is queued behind it; one waiting is enough.
    run.disabled = v.queue.some((q) => q.source === 'admin');
    if (v.standings.length === 0) {
      table.innerHTML = '<p class="muted">No tournament yet.</p>';
    } else {
      table.innerHTML = `<table class="standings"><thead><tr><th>#</th><th>Strategy</th><th title="Matches won">Wins</th></tr></thead><tbody>${v.standings
        .map(
          (s, i) =>
            `<tr><td>${i + 1}</td><td>${esc(s.name)}<div class="by muted small">${esc(s.by ?? 'template strategy')}</div></td><td>${s.wins}</td></tr>`,
        )
        .join('')}</tbody></table><p class="muted small">Over ${v.tournaments} tournament${v.tournaments === 1 ? '' : 's'}.</p>`;
    }
    if (v.latest === null) {
      latest.innerHTML = '';
    } else {
      const rows = v.latest.results
        .map((r) => {
          const seats = Object.entries(r.lineup)
            .map(([team, id]) => `<span class="seat${r.winner === team ? ' won' : ''}" style="color:${COLORS[team] ?? 'inherit'}">${esc(NAMES[id] ?? v.latest?.names?.[id] ?? id)}</span>`)
            .join(' · ');
          const end = r.winner === null ? 'no winner' : `${Math.floor(r.seconds / 60)}:${String(Math.round(r.seconds % 60)).padStart(2, '0')}`;
          return `<li>${seats} <span class="muted">${end} · ${r.decisions} calls</span></li>`;
        })
        .join('');
      latest.innerHTML = `<h3>Tournament ${v.latest.number}</h3><p class="muted small">Finished at ${time(v.latest.finishedAt)}, ${v.latest.calls} aityx calls. The winner of each match in bold, its seat’s colour on each strategy.</p><ul class="matches">${rows}</ul>`;
    }
  };

  const refresh = async () => {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    try {
      const answer = await fetch('/api/leaderboard', { headers: { Accept: 'application/json' } });
      if (answer.ok) render((await answer.json()) as View);
    } catch {
      status.textContent = 'The server did not answer.';
    }
    if (on) timer = setTimeout(() => void refresh(), last?.running ? 2000 : 8000);
  };

  run.addEventListener('click', async () => {
    run.disabled = true;
    try {
      const answer = await fetch('/api/leaderboard/run', { method: 'POST' });
      const body = (await answer.json().catch(() => ({}))) as { error?: string };
      error.hidden = answer.ok;
      error.textContent = answer.ok ? '' : (body.error ?? `HTTP ${answer.status}`);
    } finally {
      void refresh();
    }
  });

  // ---- The player's strategies in the tour ------------------------------
  const say = (text: string, bad: boolean) => {
    entered.hidden = false;
    entered.textContent = text;
    entered.classList.toggle('bad', bad);
  };
  const renderMine = (entries: Entry[] | null) => {
    mine.hidden = auth.player === null || entries === null;
    const own = (entries ?? []).filter((e) => e.mine);
    entriesList.innerHTML = own.length === 0 ? '<li class="muted">None yet: upload one here, or on the title.</li>' : '';
    for (const e of own) {
      const li = document.createElement('li');
      li.innerHTML = `${esc(e.name)} <button class="btn" type="button">Withdraw</button>`;
      li.querySelector('button')!.addEventListener('click', async () => {
        const problem = await withdraw(e.id);
        if (problem !== null) say(`Not withdrawn: ${problem}.`, true);
      });
      entriesList.append(li);
    }
  };
  const refreshMine = async () => renderMine(auth.player === null ? null : await tourEntries());
  enter.addEventListener('click', async () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json,.json';
    const file = await new Promise<File | null>((resolve) => {
      input.addEventListener('change', () => resolve(input.files?.[0] ?? null), { once: true });
      input.addEventListener('cancel', () => resolve(null), { once: true });
      input.click();
    });
    if (file === null) return;
    try {
      const s = parseStrategy(await file.text());
      const outcome = await enterInTour(s);
      say(outcome.ok ? `${s.name}: ${outcome.text}.` : `Not entered: ${outcome.text}.`, !outcome.ok);
    } catch (problem) {
      say(problem instanceof BadStrategy ? `Not entered: ${problem.message}.` : 'Not entered: the file could not be read.', true);
    }
  });
  onEntriesChange(() => {
    void refreshMine();
    void refresh();
  });

  auth.onChange(() => {
    if (last) render(last);
    void refreshMine();
  });

  return {
    visible(next) {
      on = next;
      if (on) {
        void refresh();
        void refreshMine();
      }
      else if (timer !== null) clearTimeout(timer);
    },
  };
}
