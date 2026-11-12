// The leaderboard's queue and entries, on a fake runner: `node --test`.
import assert from 'node:assert/strict';
import { mkdtemp, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { EntryError, createLeaderboard } from '../leaderboard.mjs';
import { fileStore } from '../store.mjs';
import * as fake from './fake-runner.mjs';

const tick = () => new Promise((resolve) => setTimeout(resolve, 20));
async function until(check) {
  for (let i = 0; i < 200 && !check(); i++) await tick();
  assert.ok(check());
}

test('tournaments queue one per source and never play at once; an entry asks for one and plays first', async () => {
  const dataDir = await mkdtemp(join(tmpdir(), 'tatyx-lb-'));
  const board = createLeaderboard({
    store: fileStore(dataDir),
    runnerPath: new URL('./fake-runner.mjs', import.meta.url).pathname,
    settings: async () => ({ leaderboardKey: 'test', leaderboardOff: false, base: new URL('https://aityx.test') }),
    ownerName: async (email) => email.split('@')[0],
    everyHours: 0,
    maxEntries: 2,
    log: () => {},
  });
  assert.deepEqual(await board.ask('admin'), { asked: 'started' });
  await until(() => fake.state.playing === 1);

  // While it plays: an entry asks for one, which is queued; a second waits in it.
  const ana = 'ana@aletyx.com';
  const first = await board.enter(ana, { name: 'Ana One', decisions: { build: {} } });
  assert.equal(first.tournament, 'queued');
  assert.equal(first.entry.by, 'ana');
  assert.equal((await board.enter(ana, { name: 'Ana Two', decisions: { build: {} } })).tournament, 'waiting');
  assert.deepEqual(await board.ask('admin'), { asked: 'queued' });
  assert.deepEqual(await board.ask('admin'), { asked: 'waiting' });
  await assert.rejects(board.enter(ana, { name: 'Ana Three', decisions: { build: {} } }), (e) => e instanceof EntryError && e.status === 409);
  await assert.rejects(board.enter(ana, { name: 'farmer', decisions: { build: {} } }), /preset's name/);
  await assert.rejects(board.enter(ana, { decisions: {} }), (e) => e instanceof EntryError && e.status === 400);
  let view = await board.view();
  assert.deepEqual(view.queue.map((q) => q.source), ['strategy', 'admin']);
  assert.ok(!JSON.stringify(view).includes(ana), 'no emails');
  const saved = JSON.parse(await readFile(join(dataDir, 'leaderboard.json'), 'utf8'));
  assert.deepEqual(saved.queue.map((q) => q.source), ['strategy', 'admin'], 'the queue is kept in the file');

  // One at a time, in the order asked; the entries, never played, sit first.
  fake.state.release.shift()();
  await until(() => fake.state.fields.length === 2);
  assert.equal(fake.state.playing, 1);
  assert.deepEqual(fake.state.fields[1].slice(0, 2).sort(), (await board.entries(ana)).map((e) => e.id).sort());
  fake.state.release.shift()();
  await until(() => fake.state.fields.length === 3);
  fake.state.release.shift()();
  await until(() => fake.state.playing === 0 && fake.state.release.length === 0);
  assert.equal(fake.state.most, 1);
  view = await board.view();
  assert.equal(view.tournaments, 3);
  assert.deepEqual(view.queue, []);
  assert.equal(view.standings.find((s) => s.name === 'Ana One')?.by, 'ana');
  // The wins, and what tells them, for an admin alone: a player sees the order only.
  assert.ok(view.standings.every((s) => !('wins' in s) && !('progress' in s) && !('winSeconds' in s)));
  assert.ok(view.latest.results.every((r) => !('winner' in r) && !('winnerStrategy' in r) && !('progress' in r)));
  const admin = await board.view({ admin: true });
  assert.ok(admin.standings.every((s) => typeof s.wins === 'number'));
  assert.ok(admin.latest.results.every((r) => 'winner' in r));
  assert.deepEqual(admin.standings.map((s) => s.strategy), view.standings.map((s) => s.strategy));

  // Withdrawn: out of the standings and the entries; only its owner can.
  const [one] = (await board.entries(ana)).filter((e) => e.name === 'Ana One');
  assert.equal(await board.withdraw('bo@aletyx.com', one.id), false);
  assert.equal(await board.withdraw(ana, one.id), true);
  assert.ok(!(await board.view()).standings.some((s) => s.name === 'Ana One'));
  board.stop();
});
