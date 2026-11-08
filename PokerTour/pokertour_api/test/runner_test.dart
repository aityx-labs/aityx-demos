import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poker_core/table.dart';
import 'package:pokertour_api/aityx.dart';
import 'package:pokertour_api/auth.dart';
import 'package:pokertour_api/leaderboard.dart';
import 'package:pokertour_api/runner.dart';
import 'package:pokertour_api/store.dart';
import 'package:test/test.dart';

import 'models.dart';

/// An aityx that answers every decision the same way: a call (a check
/// when free), from rule 1; or, for a strategy named "Broken", a 422.
AityxDecider fake(Models models, {int Function()? status, Duration delay = Duration.zero}) => AityxDecider(
  AityxSettings(key: 'test-key', url: Uri.parse('https://aityx.test')),
  models,
  client: MockClient((request) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final body = request.body;
    if (body.contains('Broken')) {
      return http.Response('{"code":"invalid_decision","detail":"no such input"}', 422);
    }
    final code = status?.call() ?? 200;
    if (code != 200) return http.Response('{"code":"down"}', code);
    return http.Response(
      '{"answers":{"action":{"choice":"call"},"raise_to":{"number":0}},"receipt":{"decisions":{"action":{"rule":1}}}}',
      200,
    );
  }),
);

void main() {
  late Models models;
  setUpAll(() async => models = await loadModels());

  test('a tournament is played to the end and recorded, and the store hears of it', () async {
    final store = MemoryStore();
    final boards = Boards(store: store, models: models);
    final runner = Runner(boards: boards, decider: fake(models), maxHands: 20, random: Random(3), log: false);
    final result = await runner.play();
    expect(result, isNotNull);
    expect(result!.places.length, 5);
    expect(result.places.map((p) => p.place).toSet(), {1, 2, 3, 4, 5});
    expect(result.calls, greaterThan(0));
    final board = await boards.read();
    expect(board.tournamentsPlayed, 1);
    expect(board.recordOf(result.places.first.id).wins, 1);
    expect(runner.current, isNull);
    expect(runner.playing, isFalse);
    final live = await readLive(store);
    expect(live?.state, 'waiting');
    expect(live?.detail, contains('tournament #1 over'));
    expect(live?.current, isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the fewest tournaments sit first, up to nine', () async {
    final boards = Boards(store: MemoryStore(), models: models, random: Random(4));
    for (var i = 0; i < 6; i++) {
      await boards.update((b) => b.enter(Identity(subject: '$i', email: 'p$i@aletyx.com'), {
        'name': 'Player $i',
        'decisions': {'action': {'expr': '"call"'}, 'raise_to': {'expr': 'min_raise'}},
      }));
    }
    await boards.update((b) {
      b.recordOf('rock').tournaments = 5;
      b.recordOf('shark').tournaments = 5;
    });
    final board = await boards.read();
    final runner = Runner(boards: boards, decider: fake(models), random: Random(5), log: false);
    final picked = runner.pick(board, board.playable);
    expect(picked.length, 9);
    expect(picked.map((e) => e.id), isNot(contains('rock')));
    expect(picked.map((e) => e.id), isNot(contains('shark')));
  });

  test('a strategy aityx refuses is marked broken and folds on', () async {
    final boards = Boards(store: MemoryStore(), models: models);
    final broken = await boards.update((b) => b.enter(const Identity(subject: '9', email: 'x@aletyx.ai'), {
      'name': 'Broken',
      'decisions': {'action': {'expr': 'nope'}, 'raise_to': {'expr': 'min_raise'}},
    }));
    final runner = Runner(boards: boards, decider: fake(models), maxHands: 10, random: Random(6), log: false);
    final result = await runner.play();
    expect(result, isNotNull);
    final board = await boards.read();
    expect(board.entries[broken.id]?.broken, contains('aityx answered HTTP 422'));
    expect(board.playable.map((e) => e.id), isNot(contains(broken.id)));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('out of time, the chips decide; a rejected key ends it at once', () async {
    final store = MemoryStore();
    final boards = Boards(store: store, models: models);
    final slow = Runner(boards: boards, decider: fake(models, delay: const Duration(milliseconds: 20)), maxHands: 300, random: Random(7), log: false);
    final result = await slow.play(deadline: DateTime.now().add(const Duration(milliseconds: 600)));
    expect(result, isNotNull);
    expect(result!.hands, lessThan(300));
    expect(result.places.map((p) => p.place).toSet(), {1, 2, 3, 4, 5});
    expect((await readLive(store))?.detail, contains('out of time'));

    final rejected = Runner(boards: boards, decider: fake(models, status: () => 401), maxHands: 10, random: Random(8), log: false);
    expect(await rejected.play(), isNull);
    final live = await readLive(store);
    expect(live?.state, 'error');
    expect(live?.detail, contains('rejected the key'));
    expect(live?.current, isNull, reason: 'an abandoned tournament leaves no seats behind');
    expect((await boards.read()).tournamentsPlayed, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
