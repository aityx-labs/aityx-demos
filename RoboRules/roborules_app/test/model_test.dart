import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:roborules_app/battle/model.dart';
import 'package:roborules_app/battle/random_robots.dart';

void main() {
  final spinner = Robot(
    name: 'Spinner',
    color: const Color(0xFFE36742),
    rules: [
      Rule(
        when: {'near_wall': 'true'},
        drive: 'back',
        turn: 'right',
        gun: 'sweep_right',
        why: 'Back off the wall.',
      ),
      Rule(
        when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
        drive: 'ahead',
        turn: 'perpendicular',
        gun: 'aim',
        fire: 2.5,
        why: 'In sight: fire.',
      ),
      Rule(drive: 'ahead', turn: 'right', gun: 'sweep_right', why: 'Circle.'),
    ],
  );

  test('a robot is an aityx model: sensors in, a FIRST table of commands', () {
    final model = spinner.toModel();
    expect(model['name'], 'Spinner');
    expect((model['inputs'] as Map).keys, sensors.keys);
    final table =
        ((model['decisions'] as Map)['action'] as Map)['table'] as List;
    expect(table.first, [
      'enemy_in_sight',
      'near_wall',
      'gun_ready',
      '=> drive: ahead|back|stop',
      '=> turn: left|right|none|toward_enemy|away_from_enemy|perpendicular',
      '=> gun: aim|sweep_left|sweep_right|hold',
      '=> fire: number [0..3]',
      '# why',
    ]);
    expect(table[1], [
      '-',
      'true',
      '-',
      'back',
      'right',
      'sweep_right',
      '0',
      'Back off the wall.',
    ]);
    expect(table[2][6], '2.5');
    expect(table[3].take(3), ['-', '-', '-']);
  });

  test('a model reads back into the same robot', () {
    final back = Robot.fromModel(spinner.toModel(), color: spinner.color);
    expect(back.name, 'Spinner');
    expect(back.rules, hasLength(3));
    expect(back.rules[1].when, {'enemy_in_sight': 'true', 'gun_ready': 'true'});
    expect(back.rules[1].fire, 2.5);
    expect(back.rules[2].when, isEmpty);
    expect(back.toModel(), spinner.toModel());
  });

  test('a model with {when, then, why} rules reads too', () {
    final robot = Robot.fromModel({
      'name': 'Charger',
      'decisions': {
        'action': {
          'table': [
            [
              'enemy_distance',
              '=> drive',
              '=> turn',
              '=> gun',
              '=> fire',
              '# why',
            ],
            {
              'when': {'enemy_distance': '< 250'},
              'then': {
                'drive': 'ahead',
                'turn': 'toward_enemy',
                'gun': 'aim',
                'fire': 3,
              },
              'why': 'Close.',
            },
          ],
        },
      },
    }, color: spinner.color);
    expect(robot.rules.single.when, {'enemy_distance': '< 250'});
    expect(robot.rules.single.fire, 3);
  });

  test('a model that is not a robot is refused', () {
    expect(
      () => Robot.fromModel({'decisions': {}}, color: spinner.color),
      throwsFormatException,
    );
    expect(
      () => Robot.fromModel({
        'decisions': {
          'action': {
            'table': [
              ['enemy_mood', '=> drive'],
              ['happy', 'ahead'],
            ],
          },
        },
      }, color: spinner.color),
      throwsFormatException,
    );
  });

  test('malformed nested values and commands are refused', () {
    final header = ['=> drive', '=> turn', '=> gun', '=> fire'];
    Map<String, Object?> modelFor(Object row) => {
      'decisions': {
        'action': {
          'table': [header, row],
        },
      },
    };

    for (final model in [
      {'decisions': 'junk'},
      modelFor({'when': 'junk', 'then': {}}),
      modelFor({'when': {}, 'then': 'junk'}),
      modelFor(['fly', 'none', 'hold', '0']),
      modelFor(['ahead', 'none', 'hold', 'not a number']),
      modelFor(['ahead', 'none', 'hold', '4']),
      modelFor(['ahead', 'none', 'hold', 'NaN']),
    ]) {
      expect(
        () => Robot.fromModel(model, color: spinner.color),
        throwsFormatException,
      );
    }
  });

  test('a broken model says what is wrong instead of crashing', () {
    Map<String, Object?> withRow(List<Object?> row) => {
      'decisions': {
        'action': {
          'table': [
            ['=> drive', '=> turn', '=> gun', '=> fire', '# why'],
            row,
          ],
        },
      },
    };
    expect(
      () => Robot.fromModel({'decisions': []}, color: spinner.color),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Robot.fromModel(
        withRow(['sideways', 'none', 'aim', '0', 'x']),
        color: spinner.color,
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('rule 1: drive must be one of'),
        ),
      ),
    );
    expect(
      () => Robot.fromModel(
        withRow(['ahead', 'none', 'aim', '5', 'x']),
        color: spinner.color,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => Robot.fromModel({
        'decisions': {
          'action': {
            'table': [
              ['=> drive', '=> turn', '=> fire'],
              ['ahead', 'none', '0'],
            ],
          },
        },
      }, color: spinner.color),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('no "=> gun" column'),
        ),
      ),
    );
  });

  group('random robots', () {
    final factory = RobotFactory(Random(42));

    test('only ever give the commands a battle accepts', () {
      for (var i = 0; i < 200; i++) {
        final robot = factory.make();
        expect(robot.rules.length, inInclusiveRange(3, 7));
        expect(robot.rules.last.when, isEmpty, reason: 'a fallback rule');
        for (final r in robot.rules) {
          expect(commandValues['drive'], contains(r.drive));
          expect(commandValues['turn'], contains(r.turn));
          expect(commandValues['gun'], contains(r.gun));
          expect(r.fire, inInclusiveRange(0, 3));
          for (final s in r.when.keys) {
            expect(sensors, contains(s));
          }
        }
      }
    });

    test('get different names and colors', () {
      final robots = <Robot>[];
      for (var i = 0; i < 10; i++) {
        robots.add(factory.make(taken: robots));
      }
      expect({for (final r in robots) r.name}, hasLength(10));
      expect({for (final r in robots) r.color.toARGB32()}, hasLength(10));
    });

    test('start apart from each other and the walls', () {
      final places = factory.places(6);
      for (final p in places) {
        expect(p.x, inInclusiveRange(60, arenaWidth - 60));
        expect(p.y, inInclusiveRange(60, arenaHeight - 60));
      }
      for (var i = 0; i < places.length; i++) {
        for (var j = i + 1; j < places.length; j++) {
          final d = sqrt(
            pow(places[i].x - places[j].x, 2) +
                pow(places[i].y - places[j].y, 2),
          );
          expect(d, greaterThan(120));
        }
      }
    });
  });
}
