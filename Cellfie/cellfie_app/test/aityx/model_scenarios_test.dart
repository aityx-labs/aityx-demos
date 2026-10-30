/// The Life model's rules (assets/models/life.json) executed on aityx.ai:
/// every one of the 18 situations a cell can be in, against Conway's
/// rules; every shape in the pattern catalogue, recognized; shapes that
/// aren't, unknown; and an empty board. Tagged `aityx`: skipped by
/// `flutter test`, run by scripts/model-test.sh, which passes
/// AITYX_API_KEY and AITYX_URL from the repository's .env.
@Tags(['aityx'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:aityx_web/aityx_web.dart';
import 'package:cellfie_app/aityx/life.dart';
import 'package:flutter_test/flutter_test.dart';

late final Map<String, Object?> model;
late final AityxClient aityx;

/// Conway's rules, as Wikipedia states them.
bool conway({required bool alive, required int neighbours}) =>
    alive ? neighbours == 2 || neighbours == 3 : neighbours == 3;

/// The generation the app would get for [state].
Future<Map<String, Object?>> run(Map<String, Object?> state) async {
  final sent = generationRequest(model, stateFrom(state));
  final answer = await aityx.systemone(sent);
  expect(answer.status, 200, reason: answer.text);
  return toGeneration(sent, answer.json as Map<String, Object?>);
}

void main() {
  setUpAll(() {
    final env = Platform.environment;
    // The key goes only into the Authorization header; never printed.
    aityx = AityxClient(
      connection: AityxConnection.user(
        env['AITYX_API_KEY'] ?? '',
        url: env['AITYX_URL'],
      ),
    );
    model = jsonDecode(
      File('assets/models/life.json').readAsStringSync(),
    ) as Map<String, Object?>;
  });
  tearDownAll(() => aityx.close());

  test('every situation follows Conway\'s rules', () async {
    final situations = [
      for (final alive in [true, false])
        for (var n = 0; n <= 8; n++)
          {'alive': alive, 'neighbours': n, 'cells': n + 1},
    ];
    final generation = await run({
      'generation': 3,
      'situations': situations,
      'clusters': const [],
    });
    expect(generation['next_generation'], 4);
    final fates = generation['situations'] as List;
    expect(fates, hasLength(18));
    for (final fate in fates.cast<Map>()) {
      final alive = fate['alive'] as bool;
      final n = fate['neighbours'] as int;
      expect(
        fate['alive_next'],
        conway(alive: alive, neighbours: n),
        reason: 'alive $alive with $n neighbours',
      );
      expect(fate['fate'], switch ((alive, n)) {
        (true, < 2) => 'dies_lonely',
        (true, 2 || 3) => 'survives',
        (true, _) => 'dies_crowded',
        (false, 3) => 'is_born',
        _ => 'stays_empty',
      });
      expect(fate['why'], isNotEmpty);
    }
    // Live cells: 1+2+...+9 = 45; survivors have 2 or 3 neighbours (3+4),
    // born with 3 neighbours (4), dead: the other live ones.
    expect(generation['population'], 45);
    expect(generation['survivors'], 7);
    expect(generation['births'], 4);
    expect(generation['deaths'], 38);
    expect(generation['population_next'], 11);
  });

  test('every shape in the catalogue is recognized', () async {
    final functions = (model['decision'] as Map)['functions'] as Map;
    final table = (functions['identify'] as Map)['body'] as List;
    final clusters = <Map<String, Object?>>[];
    final expected = <String>[];
    for (final row in table.skip(1).cast<List>()) {
      if (row[4] == 'unknown') continue;
      // The shape cell is a comma list of JSON strings.
      final shapes = jsonDecode('[${row[3]}]') as List;
      for (final shape in shapes.cast<String>()) {
        clusters.add({
          'cells': int.parse(row[0] as String),
          'width': int.parse(row[1] as String),
          'height': int.parse(row[2] as String),
          'shape': shape,
        });
        expected.add(row[4] as String);
      }
    }
    // A generation takes 24 clusters.
    for (var at = 0; at < clusters.length; at += maxClusters) {
      final batch = clusters.sublist(
        at,
        at + maxClusters > clusters.length ? clusters.length : at + maxClusters,
      );
      final generation = await run({
        'generation': 0,
        'situations': const [],
        'clusters': batch,
      });
      final found = (generation['clusters'] as List).cast<Map>();
      for (var i = 0; i < batch.length; i++) {
        expect(
          found[i]['pattern'],
          expected[at + i],
          reason: 'shape ${batch[i]['shape']}',
        );
        expect(found[i]['kind'], isNot('unknown'));
        expect(found[i]['about'], isNotEmpty);
      }
      expect(generation['recognized'], batch.length);
    }
  });

  test(
    'HighLife also brings a dead cell with six neighbours to life',
    () async {
      final generation = await run({
        'generation': 0,
        'rules': {'highlife': true},
        'situations': [
          {'alive': false, 'neighbours': 6, 'cells': 2},
          {'alive': false, 'neighbours': 3, 'cells': 1},
          {'alive': true, 'neighbours': 4, 'cells': 1},
        ],
      });
      final fates = (generation['situations'] as List).cast<Map>();
      expect(fates.map((s) => s['fate']), [
        'is_born',
        'is_born',
        'dies_crowded',
      ]);
      expect(fates[0]['why'], startsWith('HighLife'));
      expect(generation['births'], 3);
    },
  );

  test('Life without death keeps every live cell', () async {
    final generation = await run({
      'generation': 0,
      'rules': {'no_death': true},
      'situations': [
        {'alive': true, 'neighbours': 0, 'cells': 3},
        {'alive': true, 'neighbours': 8, 'cells': 1},
        {'alive': false, 'neighbours': 3, 'cells': 2},
      ],
    });
    final fates = (generation['situations'] as List).cast<Map>();
    expect(fates.map((s) => s['fate']), ['survives', 'survives', 'is_born']);
    expect(fates[0]['why'], startsWith('Life without death'));
    expect(generation['deaths'], 0);
  });

  test('with no rule on, everything dies and nothing is born', () async {
    final generation = await run({
      'generation': 0,
      'rules': {'conway': false},
      'situations': [
        {'alive': true, 'neighbours': 2, 'cells': 3},
        {'alive': false, 'neighbours': 3, 'cells': 2},
      ],
    });
    final fates = (generation['situations'] as List).cast<Map>();
    expect(fates.map((s) => s['fate']), ['dies_no_rule', 'stays_empty']);
    expect(generation['population_next'], 0);
  });

  test('other shapes are unknown', () async {
    final generation = await run({
      'generation': 0,
      'situations': const [],
      'clusters': [
        {'cells': 1, 'width': 1, 'height': 1, 'shape': 'o'},
        {'cells': 2, 'width': 2, 'height': 1, 'shape': 'oo'},
        // A glider's cells, but not a glider.
        {'cells': 5, 'width': 3, 'height': 3, 'shape': 'o.o/.o./o.o'},
      ],
    });
    final found = (generation['clusters'] as List).cast<Map>();
    expect(found.map((c) => c['pattern']), everyElement('unknown'));
    expect(found.map((c) => c['kind']), everyElement('unknown'));
    expect(generation['recognized'], 0);
  });

  test('an empty board stays empty', () async {
    final generation = await run({
      'generation': 9,
      'situations': const [],
      'clusters': const [],
    });
    expect(generation['next_generation'], 10);
    expect(generation['population'], 0);
    expect(generation['population_next'], 0);
    expect(generation['situations'], isEmpty);
    expect(generation['clusters'], isEmpty);
  });
}
