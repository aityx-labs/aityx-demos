import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:roborules_app/battle/model.dart';
import 'package:roborules_app/battle/predefined_robots.dart';
import 'package:roborules_app/battle/random_robots.dart';
import 'package:roborules_app/battle/robot_files.dart';

void main() {
  final factory = RobotFactory(Random(3));
  Robot kind(String name) =>
      sampleRobots.firstWhere((k) => k.name == name).make(factory: factory);

  test('a robot downloads as its aityx model, with its color', () {
    final matador = kind('Matador');
    final file = jsonDecode(robotFile(matador)) as Map;
    expect(file['name'], 'Matador');
    expect(file['color'], '#ffd166');
    expect(file['decisions'], matador.toModel()['decisions']);
    expect(file['inputs'], matador.toModel()['inputs']);
    expect(robotFileName('Walls 2'), 'Walls-2.robot.json');
    expect(robotFileName('  '), 'robot.robot.json');
  });

  test('uploads what it downloaded: the same rules, name and color', () {
    final orbiter = kind('Orbiter');
    final back = robotsFromFile(robotFile(orbiter)).single;
    expect(back.name, 'Orbiter');
    expect(back.color, orbiter.color);
    expect(jsonEncode(back.toModel()), jsonEncode(orbiter.toModel()));
  });

  test('several robots: all of a battle, or a list', () {
    final robots = [kind('Walls'), kind('Chicken'), kind('Tipsy')];
    final all = robotsFromFile(robotsFile(robots));
    expect(all.map((r) => r.name), ['Walls', 'Chicken', 'Tipsy']);
    final list = jsonEncode([for (final r in robots) r.toModel()]);
    expect(robotsFromFile(list), hasLength(3));
  });

  test('named and colored apart from the battle and from each other', () {
    final walls = kind('Walls');
    final twice = robotsFile([walls, walls]);
    final robots = robotsFromFile(twice, taken: [walls]);
    expect(robots.map((r) => r.name), ['Walls 2', 'Walls 3']);
    final colors = {walls.color, ...robots.map((r) => r.color)};
    expect(colors, hasLength(3));
  });

  test('a model without a color, or a bad one, gets a free color', () {
    final model = kind('Sniper').toModel()..['color'] = 'teal';
    final robot = robotsFromFile(jsonEncode(model)).single;
    expect(
      robotColors.map((c) => c.toARGB32()),
      contains(robot.color.toARGB32()),
    );
    expect(robot.color, isNot(const Color(0x00000000)));
  });

  test('a long name is cut, and an empty one is "Robot"', () {
    final model = kind('Pacifist').toModel()..['name'] = 'x' * 300;
    expect(robotsFromFile(jsonEncode(model)).single.name, 'x' * maxRobotName);
    model['name'] = '   ';
    expect(robotsFromFile(jsonEncode(model)).single.name, 'Robot');
  });

  test('refuses what is not a robot, saying why', () {
    Matcher says(String what) => throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains(what),
      ),
    );
    expect(() => robotsFromFile('not json'), says('not JSON'));
    expect(() => robotsFromFile('42'), says('not a robot'));
    expect(() => robotsFromFile('[]'), says('no robots'));
    expect(() => robotsFromFile('{"robots": []}'), says('no robots'));
    final bad = jsonDecode(jsonEncode(kind('Walls').toModel())) as Map;
    // Walls' first rule, driving a way no robot can.
    final table = ((bad['decisions'] as Map)['action'] as Map)['table'] as List;
    final drive = (table[0] as List).indexWhere(
      (h) => '$h'.startsWith('=> drive'),
    );
    table[1] = [...(table[1] as List)]..[drive] = 'fly';
    expect(() => robotsFromFile(jsonEncode(bad)), says('drive must be one of'));
    expect(
      () => robotsFromFile(jsonEncode([kind('Walls').toModel(), bad])),
      says('robot 2: '),
    );
    final big = kind('Walls')
      ..rules = [for (var i = 0; i <= maxUploadedRules; i++) Rule(why: '$i')];
    expect(
      () => robotsFromFile(robotFile(big)),
      says('more than $maxUploadedRules rules'),
    );
  });
}
