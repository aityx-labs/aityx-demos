import 'dart:convert';
import 'dart:io';

import 'package:roborules_api/battle.dart';
import 'package:test/test.dart';

Map<String, Object?> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;

Map<String, Object?> _bot(int i) => {
  'id': robotId(i),
  'x': 100.0 + 200 * i,
  'y': 300,
  'heading': 90,
  'v': 0,
  'gun': 90,
  'energy': 100,
  'heat': 0,
  'alive': true,
  'rule': 0,
  'hit': false,
  'damage': 0,
  'fired': 0,
  'died': 0,
};

void main() {
  final world = _json('models/world.json');
  final spinner = _json('test/robots/spinner.json');
  final charger = _json('test/robots/charger.json');

  group('a robot model', () {
    test('has the sensors as its inputs', () {
      expect(spinner['inputs'], sensorInputs());
      expect(charger['inputs'], sensorInputs());
    });

    test('its table reads as rows, whichever form they take', () {
      final table = actionTable(charger, 'Charger');
      expect(table, hasLength(4));
      expect(table[2], [
        '-',
        '< 250',
        'true',
        'ahead',
        'toward_enemy',
        'aim',
        '3',
        'Close: full power.',
      ]);
    });

    test('refuses an unknown sensor', () {
      final bad = jsonDecode(jsonEncode(spinner)) as Map<String, Object?>;
      (((bad['decisions'] as Map)['action'] as Map)['table'] as List)[0][0] =
          'enemy_mood';
      expect(
        () => actionTable(bad, 'Bad'),
        throwsA(
          isA<InvalidBattle>().having(
            (e) => e.message,
            'message',
            contains('unknown sensor column "enemy_mood"'),
          ),
        ),
      );
    });

    test('refuses a missing command', () {
      final bad = jsonDecode(jsonEncode(spinner)) as Map<String, Object?>;
      final table =
          ((bad['decisions'] as Map)['action'] as Map)['table'] as List;
      for (final row in table) {
        (row as List).removeAt(5); // the gun column
      }
      expect(() => actionTable(bad, 'Bad'), throwsA(isA<InvalidBattle>()));
    });

    test('refuses a command value it does not know, and a wild power', () {
      Map<String, Object?> withCell(int column, String value) {
        final bad = jsonDecode(jsonEncode(spinner)) as Map<String, Object?>;
        (((bad['decisions'] as Map)['action'] as Map)['table']
                as List)[1][column] =
            value;
        return bad;
      }

      expect(
        () => actionTable(withCell(4, 'dance'), 'Bad'),
        throwsA(
          isA<InvalidBattle>().having(
            (e) => e.message,
            'message',
            contains('Bad, rule 1: turn must be one of'),
          ),
        ),
      );
      expect(
        () => actionTable(withCell(6, '5'), 'Bad'),
        throwsA(isA<InvalidBattle>()),
      );
    });
  });

  test('a brain function numbers its rules and keeps the commands typed', () {
    final brain = brainFunction(actionTable(spinner, 'Spinner'));
    final body = brain['body'] as List;
    expect(body.first, [
      'near_wall',
      'enemy_in_sight',
      'gun_ready',
      '=> drive: ahead|back|stop',
      '=> turn: left|right|none|toward_enemy|away_from_enemy|perpendicular',
      '=> gun: aim|sweep_left|sweep_right|hold',
      '=> fire: number [0..3]',
      '=> rule: number',
      '# why',
    ]);
    expect([for (final row in body.skip(1)) (row as List)[7]], ['1', '2', '3']);
    expect((brain['params'] as Map).keys, sensors.keys);
    expect(brain['returns'], 'Act');
  });

  group('a battle', () {
    test('adds a brain per robot, and brain_of to call them', () {
      final model = battleModel(world, [spinner, charger]);
      final functions = model['functions'] as Map;
      expect(functions.containsKey('brain_r1'), isTrue);
      expect(functions.containsKey('brain_r2'), isTrue);
      final dispatch = (functions['brain_of'] as Map)['body'] as String;
      expect(
        dispatch,
        startsWith('if s.id = "r1" then brain_r1(s.enemy_distance'),
      );
      expect(dispatch, contains('if s.id = "r2" then brain_r2('));
      // The world model itself is untouched.
      expect((world['functions'] as Map).containsKey('brain_r1'), isFalse);
    });

    test('needs two to ten robots', () {
      expect(
        () => battleModel(world, [spinner]),
        throwsA(isA<InvalidBattle>()),
      );
      expect(
        () => battleModel(world, List.filled(11, spinner)),
        throwsA(isA<InvalidBattle>()),
      );
    });

    test('sends the world and the turns as the state', () {
      final state = {
        'tick': 0,
        'bots': [_bot(0), _bot(1)],
        'bullets': [],
      };
      final sent = battleRequest(world, [spinner, charger], state, 25);
      expect(sent['state'], {'world': state, 'turns': 25});
      expect((sent['decision'] as Map)['name'], 'RoboRules · The battle');
    });

    test('checks the world matches the robots', () {
      final two = [spinner, charger];
      expect(
        () => battleRequest(world, two, {
          'bots': [_bot(0)],
          'bullets': [],
        }, 5),
        throwsA(isA<InvalidBattle>()),
      );
      expect(
        () => battleRequest(world, two, {
          'bots': [_bot(1), _bot(0)],
          'bullets': [],
        }, 5),
        throwsA(isA<InvalidBattle>()),
      );
      expect(
        () => battleRequest(world, two, {
          'bots': [_bot(0), _bot(1)],
          'bullets': [],
        }, 51),
        throwsA(isA<InvalidBattle>()),
      );
    });
  });

  test('reads the frames, and fails on a decision error', () {
    expect(
      framesOf({
        'answers': {
          'frames': {
            'value': [1, 2],
          },
        },
      }),
      [1, 2],
    );
    expect(
      () => framesOf({
        'answers': {},
        'decision_error': {'code': 'evaluation_failed'},
      }),
      throwsA(isA<InvalidBattle>()),
    );
  });
}
