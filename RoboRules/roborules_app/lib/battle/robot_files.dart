import 'dart:convert';
import 'dart:ui' show Color;

import 'model.dart';
import 'random_robots.dart';

/// Robots as files: a robot downloads as its aityx model (it runs on aityx
/// alone, given the sensors as its state) with its `color` added; several
/// download as one file, `{"robots": [...]}`. Uploading reads either, or a
/// list of robots, checking each as the rules editor does.

/// The most rules a robot may bring, and the longest name it keeps.
const maxUploadedRules = 100;
const maxRobotName = 40;

/// The file one robot downloads as: `Walls.robot.json`.
String robotFileName(String name) {
  final slug = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  return '${slug.isEmpty ? 'robot' : slug}.robot.json';
}

/// The file all the battle's robots download as.
const allRobotsFileName = 'roborules-robots.json';

const _encoder = JsonEncoder.withIndent('  ');

/// [robot] as a file: its aityx model and its color.
String robotFile(Robot robot) => _encoder.convert(_model(robot));

/// [robots] as one file.
String robotsFile(List<Robot> robots) => _encoder.convert({
  'robots': [for (final r in robots) _model(r)],
});

Map<String, Object?> _model(Robot r) => {
  ...r.toModel(),
  'color':
      '#${(r.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
};

/// The robots in [text]: one robot's model, a list of them, or
/// `{"robots": [...]}`, named and colored apart from [taken] and from each
/// other (a second Walls is "Walls 2"). Throws [FormatException], saying
/// what's wrong, when the file isn't one.
List<Robot> robotsFromFile(String text, {Iterable<Robot> taken = const []}) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('not JSON');
  }
  final models = switch (json) {
    {'robots': final List list} => list,
    List list => list,
    Map _ => [json],
    _ => throw const FormatException('not a robot, nor a list of robots'),
  };
  if (models.isEmpty) throw const FormatException('it has no robots');
  final robots = <Robot>[];
  for (final (i, model) in models.indexed) {
    final which = models.length == 1 ? '' : 'robot ${i + 1}: ';
    final Robot robot;
    try {
      robot = Robot.fromModel(model, color: robotColors.first);
    } on FormatException catch (e) {
      throw FormatException('$which${e.message}');
    }
    if (robot.rules.length > maxUploadedRules) {
      throw FormatException(
        '${which}more than $maxUploadedRules rules (${robot.rules.length})',
      );
    }
    final color = _color((model as Map)['color']);
    robots.add(_apart(robot, color, [...taken, ...robots]));
  }
  return robots;
}

/// `#rrggbb` as a color; null when it isn't one.
Color? _color(Object? hex) {
  if (hex is! String) return null;
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
  return m == null ? null : Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

/// [robot] named and colored apart from [taken], as a predefined robot is.
Robot _apart(Robot robot, Color? color, List<Robot> taken) {
  var base = robot.name.trim();
  if (base.length > maxRobotName) base = base.substring(0, maxRobotName);
  if (base.isEmpty) base = 'Robot';
  final names = {for (final r in taken) r.name};
  var name = base;
  for (var n = 2; names.contains(name); n++) {
    name = '$base $n';
  }
  final colors = {for (final r in taken) r.color.toARGB32()};
  final free = robotColors.where((c) => !colors.contains(c.toARGB32()));
  robot
    ..name = name
    ..color = color != null && !colors.contains(color.toARGB32())
        ? color
        : free.firstOrNull ?? color ?? robotColors.first;
  return robot;
}
