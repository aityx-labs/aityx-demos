// The decider on aityx: one systemone call per decision, through the
// shared aityx-js package (the player's own key, through the server's
// relay to its aityx), each shown in the calls
// panel as a line, with the request's body and the answer behind it,
// never the headers.

import { AityxClient, AityxNoKey, AityxUnreachable } from 'aityx-js';

import type { ShownCall } from '../ui/shell';
import { team, type TeamId } from './teams';
import { buildRequest, DecisionFailed, readDecision, type Decision, type Strategy } from './strategy';
import type { Situation } from './world';

/** How long a decision waits for aityx. */
export const DEADLINE_MS = 30_000;

const clock = (seconds: number) => `${Math.floor(seconds / 60)}:${String(Math.floor(seconds % 60)).padStart(2, '0')}`;

export function aityxDecider(client: AityxClient, show: (call: ShownCall) => void) {
  return async (teamId: TeamId, s: Strategy, state: Situation): Promise<Decision> => {
    const sent = buildRequest(s, state);
    const t = team(teamId);
    const base = { team: { name: t.name, css: t.css }, at: clock(state.seconds), request: sent };
    const who = `${t.name} · ${s.name.replace(/^The /, '')}`;
    let answer;
    try {
      answer = await client.systemone(sent, { timeoutMs: DEADLINE_MS });
    } catch (error) {
      const message = error instanceof AityxNoKey ? AityxNoKey.message : error instanceof AityxUnreachable ? AityxUnreachable.message : String(error);
      show({ ...base, title: `${who} · ${message}`, detail: message, response: message, tookMs: 0, ok: false });
      throw new Error(message);
    }
    if (!answer.ok) {
      const problem = answer.problem ?? `aityx answered HTTP ${answer.status}`;
      show({ ...base, title: `${who} · ${problem}`, detail: problem, response: answer.json ?? answer.text, tookMs: answer.tookMs, ok: false });
      throw new Error(problem);
    }
    try {
      const decision = readDecision(sent, answer.json);
      show({
        ...base,
        title: `${who} → ${decision.build}`,
        detail: decision.why === null ? null : `Rule ${decision.rule}: ${decision.why}`,
        response: answer.json,
        tookMs: answer.tookMs,
        ok: true,
      });
      return decision;
    } catch (error) {
      const message = error instanceof DecisionFailed ? `aityx could not decide it: ${error.message}` : 'unexpected answer from aityx';
      show({ ...base, title: `${who} · ${message}`, detail: message, response: answer.json ?? answer.text, tookMs: answer.tookMs, ok: false });
      throw new Error(message);
    }
  };
}
