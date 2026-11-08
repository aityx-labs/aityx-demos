import 'package:poker_core/table.dart';
import 'package:pokertour_api/auth.dart';
import 'package:pokertour_api/leaderboard.dart';
import 'package:pokertour_api/queue.dart';
import 'package:pokertour_api/routes.dart';
import 'package:pokertour_api/runner.dart';
import 'package:pokertour_api/schedule.dart';
import 'package:pokertour_api/store.dart';
import 'package:test/test.dart';

import 'models.dart';

const off = AuthSettings(issuer: 'https://accounts.google.com', clientId: '');
const on = AuthSettings(issuer: 'https://accounts.google.com', clientId: 'client-1');
const wide = AuthSettings(issuer: 'https://accounts.google.com', clientId: 'client-1', domains: ['aletyx.com', 'aletyx.ai', 'example.com']);
const ana = Identity(subject: '1', email: 'ana@aletyx.com', name: 'Ana');
const anaIn = Verified(ana, null);
const outsider = Verified(null, Refusal.domain);
const nobody = Verified(null, Refusal.invalid);

final mine = {
  'name': 'Ana One',
  'tagline': '',
  'decisions': {'action': {'expr': '"call"'}, 'raise_to': {'expr': 'min_raise'}},
};

void main() {
  late Models models;
  setUpAll(() async => models = await loadModels());

  test('health and config are open; config names the domains, never a key', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    final health = await route('GET', '/api/health', auth: off, boards: boards, aityx: true);
    expect(health.status, 200);
    expect((health.body as Map)['aityx'], isTrue);
    expect((health.body as Map)['auth'], isFalse);
    final config = await route('GET', '/api/config', auth: on, boards: boards);
    final body = config.body as Map;
    expect((body['auth'] as Map)['clientId'], 'client-1');
    expect(body['domains'], ['aletyx.com', 'aletyx.ai']);
    expect(body.containsKey('key'), isFalse);
  });

  test('the leaderboard is open and holds no emails', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    await boards.update((b) => b.enter(ana, mine));
    final answer = await route('GET', '/api/leaderboard', auth: on, boards: boards);
    expect(answer.status, 200);
    expect(answer.body.toString(), isNot(contains('aletyx.com')));
    expect((answer.body as Map)['standings'], hasLength(6));
  });

  test('the sign-in gates: 503 without a client id, 401, 403, then in', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    expect((await route('GET', '/api/me', auth: off, boards: boards, who: anaIn)).status, 503);
    expect((await route('GET', '/api/me', auth: on, boards: boards)).status, 401);
    expect((await route('GET', '/api/me', auth: on, boards: boards, who: nobody)).status, 401);
    expect((await route('GET', '/api/me', auth: on, boards: boards, who: outsider)).status, 403);
    final me = await route('GET', '/api/me', auth: on, boards: boards, who: anaIn);
    expect(me.status, 200);
    expect((me.body as Map)['ownerId'], ownerIdOf('ana@aletyx.com'));
    expect((await route('GET', '/api/strategies', auth: on, boards: boards, who: outsider)).status, 403);
  });

  test('an alias names the player on the leaderboard; empty for their name', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    await boards.update((b) => b.enter(ana, mine));
    Future<String?> owner() async {
      final board = await route('GET', '/api/leaderboard', auth: on, boards: boards);
      final rows = ((board.body as Map)['standings'] as List).cast<Map>();
      return rows.firstWhere((r) => r['name'] == 'Ana One')['owner'] as String?;
    }

    expect(await owner(), 'Ana', reason: 'the name by default');
    expect((await route('PUT', '/api/me', auth: on, boards: boards, body: {'alias': 'x'})).status, 401);
    final set = await route('PUT', '/api/me', auth: on, boards: boards, who: anaIn, body: {'alias': '  River Queen '});
    expect(set.status, 200);
    expect((set.body as Map)['alias'], 'River Queen');
    expect((await route('GET', '/api/me', auth: on, boards: boards, who: anaIn)).body, containsPair('alias', 'River Queen'));
    expect(await owner(), 'River Queen');
    final strategies = await route('GET', '/api/strategies', auth: on, boards: boards, who: anaIn);
    expect(((strategies.body as Map)['strategies'] as List).cast<Map>().firstWhere((r) => r['name'] == 'Ana One')['owner'], 'River Queen');

    expect((await route('PUT', '/api/me', auth: on, boards: boards, who: anaIn, body: {'alias': 'x' * 33})).status, 400);
    expect((await route('PUT', '/api/me', auth: on, boards: boards, who: anaIn, body: {'alias': 'a\nb'})).status, 400);
    expect((await route('PUT', '/api/me', auth: on, boards: boards, who: anaIn, body: {'alias': 7})).status, 400);
    await route('PUT', '/api/me', auth: on, boards: boards, who: anaIn, body: {'alias': ''});
    expect(await owner(), 'Ana', reason: 'cleared: the name again');
  });

  test('entering: checked, then aityx, then in; withdrawing', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    var checked = 0;
    Future<void> check(Object? json) async {
      checked++;
      if ((json as Map)['name'] == 'Bad') throw Exception('invalid_decision');
    }
    expect((await route('POST', '/api/strategies', auth: on, boards: boards, who: anaIn, body: {'name': 'x'}, check: check)).status, 400);
    expect(checked, 0);
    final bad = await route('POST', '/api/strategies', auth: on, boards: boards, who: anaIn, body: {...mine, 'name': 'Bad'}, check: check);
    expect(bad.status, 422);
    expect((bad.body as Map)['error'], contains('invalid_decision'));
    final ok = await route('POST', '/api/strategies', auth: on, boards: boards, who: anaIn, body: mine, check: check);
    expect(ok.status, 201);
    final id = (ok.body as Map)['id'] as String;
    expect((ok.body as Map)['owner'], 'Ana');
    expect((await boards.read()).entries[id]?.strategy.name, 'Ana One');
    final listed = await route('GET', '/api/strategies', auth: on, boards: boards, who: anaIn);
    expect(((listed.body as Map)['strategies'] as List).map((s) => (s as Map)['id']), contains(id));
    expect((await route('DELETE', '/api/strategies/nope', auth: on, boards: boards, who: anaIn)).status, 404);
    expect((await route('DELETE', '/api/strategies/$id', auth: on, boards: boards, who: anaIn)).status, 204);
    expect((await boards.read()).entries.containsKey(id), isFalse);
  });

  test('me says who is an admin: aletyx.com and aletyx.ai only; only admins start a tournament', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    const cy = Verified(Identity(subject: '3', email: 'cy@example.com'), null);
    final me = await route('GET', '/api/me', auth: wide, boards: boards, who: cy);
    expect(me.status, 200, reason: 'example.com may play here');
    expect((me.body as Map)['admin'], isFalse);
    const bo = Verified(Identity(subject: '2', email: 'bo@aletyx.ai'), null);
    expect(((await route('GET', '/api/me', auth: wide, boards: boards, who: bo)).body as Map)['admin'], isTrue);
    expect(((await route('GET', '/api/me', auth: wide, boards: boards, who: anaIn)).body as Map)['admin'], isTrue);
    final asked = <String>[];
    Future<String> start(String source, Identity by) async {
      asked.add(source);
      return 'started';
    }
    expect((await route('POST', '/api/tournaments', auth: wide, boards: boards)).status, 401);
    expect((await route('POST', '/api/tournaments', auth: wide, boards: boards, who: cy, runnerEnabled: true, start: start)).status, 403);
    expect((await route('POST', '/api/tournaments', auth: wide, boards: boards, who: bo, runnerEnabled: false, start: start)).status, 503);
    final ok = await route('POST', '/api/tournaments', auth: wide, boards: boards, who: bo, runnerEnabled: true, start: start);
    expect(ok.status, 202);
    expect((ok.body as Map)['status'], 'started');
    expect(asked, ['admin']);
  });

  test('a new strategy asks for a tournament; the leaderboard shows the queue, no owners', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    final queue = TournamentQueue(boards.db, holder: 'test');
    Future<String> start(String source, Identity by) async => (await queue.ask(source, by: by.ownerId)).name;
    var ok = await route('POST', '/api/strategies', auth: on, boards: boards, who: anaIn, body: mine, runnerEnabled: true, start: start);
    expect(ok.status, 201);
    expect((ok.body as Map)['tournament'], 'started');
    // Another upload while that one waits: it plays in it.
    ok = await route('POST', '/api/strategies', auth: on, boards: boards, who: anaIn, body: {...mine, 'name': 'Ana Two'}, runnerEnabled: true, start: start);
    expect((ok.body as Map)['tournament'], 'waiting');
    final board = await route('GET', '/api/leaderboard', auth: on, boards: boards, runnerEnabled: true, waiting: queue.waiting);
    final waiting = ((board.body as Map)['runner'] as Map)['queue'] as List;
    expect(waiting.map((r) => (r as Map)['source']), ['strategy']);
    expect((waiting.single as Map).containsKey('by'), isFalse, reason: 'who asked stays in the table');
    // With the leaderboard off nothing is asked for.
    ok = await route('POST', '/api/strategies', auth: on, boards: boards, who: anaIn, body: {...mine, 'name': 'Ana Three'}, start: start);
    expect((ok.body as Map)['tournament'], isNull);
  });

  test('the leaderboard says what the runner is doing and when the next tournament is', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    final now = DateTime.utc(2026, 11, 7, 13, 30);
    final playing = LiveState(state: 'playing', detail: 'tournament #3, 5 players', current: {'number': 3, 'hand': 7, 'calls': 40, 'seats': []}, updatedAt: now);
    var answer = await route('GET', '/api/leaderboard', auth: on, boards: boards, live: playing, schedule: Schedule.defaultSchedule, runnerEnabled: true, now: now);
    var runner = (answer.body as Map)['runner'] as Map;
    expect(runner['state'], 'playing');
    expect(runner['nextRunAt'], '2026-11-07T18:00:00.000Z');
    expect(runner['hoursUtc'], [0, 6, 12, 18]);
    expect((answer.body as Map)['current'], isNotNull);

    // A tournament nobody has heard from in a while was cut short.
    answer = await route('GET', '/api/leaderboard', auth: on, boards: boards, live: playing, runnerEnabled: true, now: now.add(const Duration(minutes: 20)));
    runner = (answer.body as Map)['runner'] as Map;
    expect(runner['state'], 'error');
    expect(runner['detail'], contains('cut short'));
    expect((answer.body as Map)['current'], isNull);
    expect(runner['nextRunAt'], isNull);
  });

  test('the schedule: four times a day, every six hours, UTC', () {
    expect(Schedule.fromEnvironment(const {}).hoursUtc, [0, 6, 12, 18]);
    expect(Schedule.fromEnvironment(const {'POKERTOUR_SCHEDULE_HOURS': 'off'}).enabled, isFalse);
    expect(Schedule.fromEnvironment(const {'POKERTOUR_SCHEDULE_HOURS': '9, 21,9,25'}).hoursUtc, [9, 21]);
    expect(Schedule.defaultSchedule.next(DateTime.utc(2026, 11, 7, 23, 59)), DateTime.utc(2026, 11, 8));
    expect(Schedule.defaultSchedule.next(DateTime.utc(2026, 11, 7, 6)), DateTime.utc(2026, 11, 7, 12));
    expect(Schedule.defaultSchedule.cron, 'cron(0 0,6,12,18 * * ? *)');
  });
}
