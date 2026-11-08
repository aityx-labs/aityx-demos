// The leaderboard's tab: the standings of the preset strategies and the
// players' entries over the tournaments the server played on its own key, what it is doing now, the
// latest tournament's matches, and, for the tour's admins, a tournament
// now. Read from GET /api/leaderboard while the tab shows.

import { auth } from './auth';

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
  running: { match: number; of: number; calls: number; startedAt: string } | null;
  error: string | null;
  next: string | null;
  everyHours: number;
  tournaments: number;
  standings: Standing[];
  /** `names`: the entries' names by id, for the lineups (the presets' are below). */
  latest: { number: number; startedAt: string; finishedAt: string; calls: number; names?: Record<string, string>; results: Result[] } | null;
}

const COLORS: Record<string, string> = { cyan: '#00E5FF', magenta: '#FF2BD6', green: '#39FF7A' };
const NAMES: Record<string, string> = { farmer: 'Farmer', sprinter: 'Sprinter', swarm: 'Swarm', doubler: 'Doubler', fortress: 'Fortress' };

const time = (iso: string) => new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
const esc = (text: string) => text.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]!);

export function mountLeaderboard(parent: HTMLElement): { visible(on: boolean): void } {
  parent.innerHTML = `
<p class="muted small">The preset strategies and the players’ entries play each other on the server, on the tour’s own key, every few hours: every trio of them, each in every sector. The standings are over the latest tournaments.</p>
<div class="lb-status" id="lb-status"></div>
<button class="btn primary" type="button" id="lb-run" hidden>Play a tournament now</button>
<p class="note bad" id="lb-error" hidden></p>
<div id="lb-table"></div>
<div id="lb-latest"></div>`;
  const status = parent.querySelector<HTMLElement>('#lb-status')!;
  const run = parent.querySelector<HTMLButtonElement>('#lb-run')!;
  const error = parent.querySelector<HTMLElement>('#lb-error')!;
  const table = parent.querySelector<HTMLElement>('#lb-table')!;
  const latest = parent.querySelector<HTMLElement>('#lb-latest')!;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let on = false;
  let last: View | null = null;

  const render = (v: View) => {
    last = v;
    if (!v.enabled) status.textContent = `The leaderboard doesn’t play here: ${v.reason ?? 'it is off'}.`;
    else if (v.running) status.textContent = `Playing a tournament: match ${Math.min(v.running.match + 1, v.running.of)} of ${v.running.of}, ${v.running.calls} aityx calls so far.`;
    else if (v.next) status.textContent = `Next tournament at ${time(v.next)} (every ${v.everyHours} h).`;
    else status.textContent = 'Tournaments are played on demand.';
    error.hidden = v.error === null;
    error.textContent = v.error ? `The last tournament failed: ${v.error}` : '';
    run.hidden = !(auth.player?.admin ?? false) || !v.enabled;
    run.disabled = v.running !== null;
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
      const names = { ...v.latest.names, ...NAMES };
      const rows = v.latest.results
        .map((r) => {
          const seats = Object.entries(r.lineup)
            .map(([team, id]) => `<span class="seat${r.winner === team ? ' won' : ''}" style="color:${COLORS[team] ?? 'inherit'}">${esc(names[id] ?? id)}</span>`)
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
      const body = (await answer.json().catch(() => ({}))) as { reason?: string; error?: string };
      error.hidden = answer.ok;
      error.textContent = answer.ok ? '' : (body.reason ?? body.error ?? `HTTP ${answer.status}`);
    } finally {
      void refresh();
    }
  });
  auth.onChange(() => last && render(last));

  return {
    visible(next) {
      on = next;
      if (on) void refresh();
      else if (timer !== null) clearTimeout(timer);
    },
  };
}
