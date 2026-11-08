// A stand-in for the game's runner (dist-runner/runner.mjs): tournaments
// that last as long as the test says, and count how many play at once.
export const MATCHES = 30;
export const FIELD = 5;
export const STRATEGIES = ['farmer', 'sprinter', 'swarm', 'doubler', 'fortress'].map((id) => ({ id, name: id[0].toUpperCase() + id.slice(1), tagline: '', decisions: {} }));
export class BadStrategy extends Error {}
export function parseStrategy(text) {
  const json = JSON.parse(text);
  if (typeof json.name !== 'string' || !json.decisions) throw new BadStrategy('"name" must be a text of 1 to 60 characters');
  return { id: 'own', name: json.name, tagline: json.tagline ?? '', decisions: json.decisions };
}
export function pickField(candidates, played) {
  const preset = (s) => (STRATEGIES.some((p) => p.id === s.id) ? 1 : 0);
  return [...candidates].sort((a, b) => played(a.id) - played(b.id) || preset(a) - preset(b)).slice(0, FIELD);
}
export function standings(results, named) {
  return named.map((s) => ({ strategy: s.id, name: s.name, played: results.filter((r) => Object.values(r.lineup).includes(s.id)).length, wins: 0, progress: 0, winSeconds: null }));
}
export const state = { playing: 0, most: 0, fields: [], release: [] };
export async function run(_call, onMatch, field) {
  state.playing += 1;
  state.most = Math.max(state.most, state.playing);
  state.fields.push(field.map((f) => f.id));
  await new Promise((resolve) => state.release.push(resolve));
  onMatch?.(1);
  state.playing -= 1;
  const results = [{ lineup: { cyan: field[0].id, magenta: field[1].id, green: field[2].id } }];
  return { results, standings: standings(results, field) };
}
