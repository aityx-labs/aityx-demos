import 'dart:convert';
import 'dart:io';

import 'package:riverrace_api/strategy.dart';
import 'package:test/test.dart';

/// What a plane senses on open water, full of fuel, nothing around.
Map<String, Object?> calm([Map<String, Object?> overrides = const {}]) => {
  'fuel': 100,
  'speed': 'normal',
  'land_ahead': false,
  'land_distance': 999,
  'channel': 'ahead',
  'room_left': 40,
  'room_right': 40,
  'enemy_ahead': false,
  'enemy_distance': 999,
  'threat': 'none',
  'fuel_ahead': false,
  'fuel_side': 'none',
  'bridge_ahead': false,
  'leading': true,
  'missile_ready': true,
  ...overrides,
};

final careful = [
  {
    'when': {'land_distance': '< 40'},
    'then': {'steer': 'to_channel', 'throttle': 'slow', 'fire': false},
    'why': 'Land ahead: brake and turn for the open water.',
  },
  {
    'when': {'threat': 'left, right, ahead'},
    'then': {'steer': 'dodge', 'throttle': 'slow', 'fire': true},
    'why': 'Something is about to hit: dodge it and shoot.',
  },
  {
    'when': {'fuel': '< 40', 'fuel_side': 'left, right, ahead'},
    'then': {'steer': 'to_fuel', 'throttle': 'slow', 'fire': false},
    'why': 'Low on fuel: fly slowly over the depot.',
  },
];

Map<String, Object?> body(List<Object?> pilots) => {
  'tick': 12,
  'pilots': pilots,
};

void main() {
  final base = jsonDecode(
    File('models/river.json').readAsStringSync(),
  ) as Map<String, Object?>;

  group('requestFrom', () {
    test('reads the pilots, their rules and senses', () {
      final asked = requestFrom(
        body([
          {'id': 'p1', 'name': 'Careful', 'rules': careful, 'sense': calm()},
        ]),
      );
      expect(asked.tick, 12);
      expect(asked.pilots.single.name, 'Careful');
      expect(asked.pilots.single.rules, hasLength(3));
      expect(asked.pilots.single.rules[2].when, {
        'fuel': '< 40',
        'fuel_side': 'left, right, ahead',
      });
    });

    test('refuses what aityx could not run', () {
      Map<String, Object?> pilot(Map<String, Object?> changes) => {
        'id': 'p1',
        'rules': careful,
        'sense': calm(),
        ...changes,
      };
      for (final (bad, why) in [
        (body([]), 'no pilots'),
        (body([pilot({}), pilot({})]), 'a repeated pilot'),
        (
          body([
            pilot({'id': 'p3'}),
          ]),
          'the player is not a pilot',
        ),
        (
          body([
            pilot({
              'rules': [
                {
                  'when': {'altitude': '> 3'},
                },
              ],
            }),
          ]),
          'an unknown sensor',
        ),
        (
          body([
            pilot({
              'rules': [
                {
                  'then': {'steer': 'loop'},
                },
              ],
            }),
          ]),
          'an unknown command value',
        ),
        (
          body([
            pilot({
              'sense': calm({'threat': 'above'}),
            }),
          ]),
          'a sense of the wrong kind',
        ),
        (
          body([
            pilot({'sense': calm()..remove('fuel')}),
          ]),
          'a missing sense',
        ),
        ({'pilots': []}, 'no tick'),
      ]) {
        expect(
          () => requestFrom(bad),
          throwsA(isA<InvalidRequest>()),
          reason: why,
        );
      }
    });
  });

  group('the table', () {
    test('has a column per sensor tested, the commands and why', () {
      final pilot = Pilot('p1', 'Careful', [
        for (final r in careful) Rule.from(r, 'r'),
      ], {});
      final table = pilot.table;
      expect(table.first, [
        'fuel',
        'land_distance',
        'threat',
        'fuel_side',
        '=> steer: left|right|straight|to_channel|to_fuel|dodge',
        '=> throttle: slow|normal|fast',
        '=> fire: boolean',
        '# why',
      ]);
      expect(table[3], [
        '< 40',
        '-',
        '-',
        'left, right, ahead',
        'to_fuel',
        'slow',
        'false',
        'Low on fuel: fly slowly over the depot.',
      ]);
      // aityx wants a FIRST table to end with an else row.
      expect(table.last.take(4), everyElement('-'));
      expect(table.last.skip(4).take(3), ['straight', 'normal', 'false']);
    });

    test('ends with the strategy\'s own else row when it has one', () {
      final pilot = Pilot('p1', 'Straight', [
        Rule.from({
          'then': {'steer': 'to_channel', 'throttle': 'fast', 'fire': true},
          'why': 'Always.',
        }, 'r'),
      ], {});
      expect(pilot.table, hasLength(2));
      final blank = Pilot('p1', 'Blank', [Rule.from(const {}, 'r')], {});
      expect(blank.table[1].last, 'Rule 1.');
      expect(pilot.table.first.first, 'fuel');
    });
  });

  test('the request has an input, a function and a decision per pilot', () {
    final asked = requestFrom(
      body([
        {'id': 'p1', 'rules': careful, 'sense': calm()},
        {
          'id': 'p2',
          'rules': const [],
          'sense': calm({'fuel': 12}),
        },
      ]),
    );
    final sent = decisionRequest(base, asked.pilots);
    final decision = sent['decision'] as Map;
    expect((decision['inputs'] as Map).keys, ['p1', 'p2']);
    expect((decision['functions'] as Map).keys, ['strategy_p1', 'strategy_p2']);
    expect(
      ((decision['decisions'] as Map)['p2_action'] as Map)['expr'],
      startsWith('strategy_p2(p2.fuel, p2.speed, '),
    );
    expect((sent['state'] as Map)['p2'], containsPair('fuel', 12));
    expect(decision['types'], (base['decision'] as Map)['types']);
  });

  test('the actions are read from the answer, with the rule that fired', () {
    final asked = requestFrom(
      body([
        {'id': 'p1', 'rules': careful, 'sense': calm()},
        {'id': 'p2', 'rules': careful, 'sense': calm()},
      ]),
    );
    final actions = toActions(12, asked.pilots, {
      'answers': {
        'p1_action': {
          'value': {'steer': 'dodge', 'throttle': 'slow', 'fire': true},
        },
        'p2_action': {
          'value': {'steer': 'straight', 'throttle': 'normal', 'fire': false},
        },
      },
      'receipt': {
        'functions': {
          'strategy_p1': [
            {'rule': 2},
          ],
          'strategy_p2': [
            {'rule': 4},
          ],
        },
      },
    });
    expect(actions['tick'], 12);
    final byPilot = actions['actions'] as Map;
    expect(byPilot['p1'], {
      'steer': 'dodge',
      'throttle': 'slow',
      'fire': true,
      'rule': 2,
      'why': 'Something is about to hit: dodge it and shoot.',
    });
    // Rule 4 is the else row the API added.
    expect((byPilot['p2'] as Map)['rule'], 0);
  });

  test('an answer without the actions fails', () {
    final asked = requestFrom(
      body([
        {'id': 'p1', 'rules': careful, 'sense': calm()},
      ]),
    );
    expect(
      () => toActions(1, asked.pilots, {'answers': {}}),
      throwsA(isA<DecisionFailed>()),
    );
    expect(
      () => toActions(1, asked.pilots, {
        'decision_error': {'code': 'x'},
      }),
      throwsA(isA<DecisionFailed>()),
    );
  });

  test('the call is left out when the answer holds the key', () {
    final out = withAityx(
      {'tick': 1},
      {},
      {},
      'has sk-1 in it',
      'sk-1',
      tookMs: 3,
    );
    expect(out.containsKey('aityx'), isFalse);
    final kept = withAityx({'tick': 1}, {}, {}, 'clean', 'sk-1', tookMs: 3);
    expect((kept['aityx'] as Map)['took_ms'], 3);
  });
}
