import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:roborules_app/battle/model.dart';
import 'package:roborules_app/battle/predefined_robots.dart';
import 'package:roborules_app/battle/random_robots.dart';

void main() {
  final factory = RobotFactory(Random(7));

  test('every predefined robot is a robot model the battle accepts', () {
    expect(robotKinds.first, randomRobot);
    expect(sampleRobots, hasLength(9));
    for (final kind in sampleRobots) {
      final robot = kind.make(factory: factory);
      expect(robot.name, kind.name);
      expect(robot.color, kind.color);
      expect(robot.rules, isNotEmpty, reason: kind.name);
      // The battle refuses unknown sensors, commands and fire powers: the
      // same check the editor's JSON goes through.
      final back = Robot.fromModel(robot.toModel(), color: robot.color);
      expect(back.rules, hasLength(robot.rules.length), reason: kind.name);
      for (final r in robot.rules) {
        expect(r.when.keys, everyElement(isIn(sensors.keys)));
        expect(r.fire, inInclusiveRange(0, 3));
      }
      expect(
        robot.rules.last.when,
        isEmpty,
        reason: '${kind.name}: the last rule always matches',
      );
    }
  });

  test('a second robot of a kind gets its own name and color', () {
    final walls = sampleRobots.firstWhere((k) => k.name == 'Walls');
    final first = walls.make(factory: factory);
    final second = walls.make(taken: [first], factory: factory);
    final third = walls.make(taken: [first, second], factory: factory);
    expect(second.name, 'Walls 2');
    expect(third.name, 'Walls 3');
    expect(second.color, isNot(first.color));
    expect(third.color, isNot(first.color));
    expect(third.color, isNot(second.color));
    // Its rules are its own: changing one robot leaves the other alone.
    first.rules.first.fire = 3;
    expect(second.rules.first.fire, isNot(3));
  });

  test('the random kind makes a random robot', () {
    final robot = randomRobot.make(factory: factory);
    expect(randomRobot.isRandom, isTrue);
    expect(robot.name, isNot('Random robot'));
    expect(robot.rules.length, greaterThanOrEqualTo(3));
    expect(randomRobot.rules(factory), isNotEmpty);
  });
}
