import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:poker_core/table.dart';
import 'package:pokertour_api/auth.dart';
import 'package:pokertour_api/leaderboard.dart';
import 'package:pokertour_api/store.dart';
import 'package:pokertour_api/tour_db.dart';
import 'package:test/test.dart';

import 'models.dart';

const ana = Identity(subject: '1', email: 'ana@aletyx.com', name: 'Ana');
const bo = Identity(subject: '2', email: 'bo@aletyx.ai');

Map<String, Object?> rules(String name) => {
  'name': name,
  'tagline': 'Mine.',
  'decisions': {
    'action': {'type': 'Action', 'expr': '"call"'},
    'raise_to': {'type': 'number', 'expr': 'min_raise'},
  },
};

void main() {
  late Models models;
  setUpAll(() async => models = await loadModels());

  test('the presets are in as the house\'s, and standings start even', () {
    final board = Leaderboard(models: models);
    expect(board.entries.length, 5);
    expect(board.entries.values.every((e) => e.preset && e.owner == 'the house'), isTrue);
    final rows = board.standings();
    expect(rows.map((r) => r['points']), everyElement(0));
    expect(rows.first['name'], 'The Calling Station'); // by name when even
    expect(rows.first.containsKey('ownerEmail'), isFalse);
  });

  test('a player enters, replaces by name, is limited, and withdraws', () {
    final board = Leaderboard(models: models, maxPerPlayer: 2, random: Random(1));
    final one = board.enter(ana, rules('Ana One'));
    expect(one.owner, 'Ana');
    expect(one.ownerId, ownerIdOf('ana@aletyx.com'));
    expect(one.strategy.custom, isTrue);
    board.enter(ana, rules('Ana Two'));
    expect(() => board.enter(ana, rules('Ana Three')), throwsA(isA<EntryException>().having((e) => e.message, 'message', contains('withdraw one first'))));
    board.recordOf(one.id).tournaments = 4;
    final again = board.enter(ana, rules('ana one'));
    expect(again.id, isNot(one.id), reason: 'the same name replaces, under a new id');
    expect(board.entries.containsKey(one.id), isFalse);
    expect(board.records.containsKey(one.id), isFalse, reason: 'the old rules\' record goes with them');
    expect(board.recordOf(again.id).tournaments, 0);
    expect(board.entries.values.where((e) => !e.preset).length, 2);
    expect(() => board.enter(bo, rules('The Rock')), throwsA(isA<EntryException>()));
    expect(() => board.enter(bo, {'name': 'x'}), throwsA(isA<EntryException>()));
    expect(board.withdraw(bo, again.id), isFalse, reason: 'not Bo\'s');
    expect(board.withdraw(ana, again.id), isTrue);
    expect(board.withdraw(ana, 'rock'), isFalse, reason: 'a preset');
    expect(board.entries.containsKey(again.id), isFalse);
  });

  test('a tournament\'s places become points, wins, best and last', () {
    final board = Leaderboard(models: models);
    board.finish([
      (id: 'rock', name: 'The Rock', place: 1),
      (id: 'shark', name: 'The Shark', place: 2),
      (id: 'maniac', name: 'The Maniac', place: 3),
    ], hands: 40, calls: 300);
    board.finish([
      (id: 'shark', name: 'The Shark', place: 1),
      (id: 'rock', name: 'The Rock', place: 2),
      (id: 'gone', name: 'Gone', place: 3),
    ], hands: 10, calls: 50);
    expect(board.recordOf('rock').points, 3);
    expect(board.recordOf('shark').points, 3);
    expect(board.recordOf('rock').wins, 1);
    expect(board.recordOf('rock').best, 1);
    expect(board.recordOf('rock').last, 2);
    expect(board.recordOf('maniac').points, 0);
    expect(board.records.containsKey('gone'), isFalse);
    final rows = board.standings();
    expect(rows.take(2).map((r) => r['name']), ['The Rock', 'The Shark']);
    expect(board.history.length, 2);
    expect(board.history.first.number, 2);
  });

  test('what is saved is read back, and a lost race is run again', () async {
    final dir = await Directory.systemTemp.createTemp('pokertour-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/leaderboard.json');
    final db = MemoryTourDb();
    final boards = Boards(store: FileStore(dir), db: db, models: models, random: Random(2));
    final mine = await boards.update((b) => b.enter(ana, rules('Ana One')));
    await boards.update((b) => b.finish([(id: mine.id, name: 'Ana One', place: 1), (id: 'rock', name: 'The Rock', place: 2)], hands: 5, calls: 20));
    await boards.update((b) => b.markBroken('maniac', 'aityx refused it'));
    expect(jsonDecode(await file.readAsString()), isA<Map>());

    expect(jsonDecode(await file.readAsString()), isNot(contains('entries')), reason: 'the strategies are in the table');
    final later = await Boards(store: FileStore(dir), db: db, models: models).read();
    expect(later.entries[mine.id]?.strategy.name, 'Ana One');
    expect(later.entries[mine.id]?.ownerEmail, 'ana@aletyx.com');
    expect(later.recordOf(mine.id).wins, 1);
    expect(later.tournamentsPlayed, 1);
    expect(later.history.single.places.first.name, 'Ana One');
    expect(later.entries['maniac']?.broken, isNull, reason: 'a preset plays again after a restart');

    // Another writer gets in between the read and the write: the change
    // is applied again on what they wrote.
    final store = MemoryStore();
    final shared = MemoryTourDb();
    final a = Boards(store: store, db: shared, models: models, random: Random(3));
    final b = Boards(store: store, db: shared, models: models, random: Random(4));
    var first = true;
    await a.update((board) {
      if (first) {
        first = false;
        b.update((other) => other.enter(bo, rules('Bo One'))); // not awaited: a later write
      }
      return board.enter(ana, rules('Ana Two'));
    });
    await Future<void>.delayed(Duration.zero);
    final both = await a.read();
    expect(both.entries.values.where((e) => !e.preset).map((e) => e.strategy.name), containsAll(['Ana Two', 'Bo One']));
  });

  test('a conditional write refuses another version', () async {
    final store = MemoryStore();
    final v1 = await store.write('x.json', '{}', ifVersion: '');
    expect(() => store.write('x.json', '{"a":1}', ifVersion: ''), throwsA(isA<StoreConflict>()));
    expect(() => store.write('x.json', '{"a":1}', ifVersion: 'nope'), throwsA(isA<StoreConflict>()));
    final v2 = await store.write('x.json', '{"a":1}', ifVersion: v1);
    expect(v2, isNot(v1));
    expect((await store.read('x.json'))?.text, '{"a":1}');
  });

  test('an entry is within the limits, and its name plain text', () {
    final ok = {'name': 'Fine', 'decisions': {'action': {'expr': '"call"'}, 'raise_to': {'expr': 'min_raise'}}};
    Leaderboard.check(ok);
    String why(Map<String, Object?> json) {
      try {
        Leaderboard.check(json);
        return 'ok';
      } on EntryException catch (e) {
        return e.message;
      }
    }

    expect(why({...ok, 'tagline': 'x' * 201}), contains('tagline'));
    expect(why({...ok, 'name': 'Shark\u202e'}), contains('plain text'));
    expect(why({...ok, 'name': 'Sh\u200bark'}), contains('plain text'));
    expect(why({...ok, 'decisions': {...ok['decisions'] as Map<String, Object?>, 'pad': {'desc': 'x' * (17 * 1024)}}}), contains('KB'));
    expect(why({...ok, 'decisions': {for (var i = 0; i < 25; i++) 'd$i': {'expr': '1'}, 'action': {'expr': '"call"'}, 'raise_to': {'expr': '1'}}}), contains('decisions'));
    expect(why({...ok, 'name': 'Café Zürich'}), 'ok', reason: 'accents are plain text');
  });

  test('the same rules again are spotted; different ones are not', () {
    final board = Leaderboard(models: models, random: Random(2));
    board.enter(ana, rules('Ana One'));
    expect(board.unchanged(ana, rules('ana one')), isNotNull);
    expect(board.unchanged(bo, rules('Ana One')), isNull, reason: 'not Bo\'s');
    expect(board.unchanged(ana, {...rules('Ana One'), 'tagline': 'new'}), isNull);
  });
}
