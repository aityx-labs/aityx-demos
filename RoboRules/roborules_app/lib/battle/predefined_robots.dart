import 'dart:ui' show Color;

import 'model.dart';
import 'random_robots.dart';

/// A robot to pick for the battle: one of Robocode's sample robots written
/// as rules, or one with random rules.
class RobotKind {
  const RobotKind({
    required this.name,
    required this.color,
    required this.description,
    required this.build,
  });

  /// Random rules from the [RobotFactory], and one of its names.
  const RobotKind.random({
    required this.name,
    required this.color,
    required this.description,
  }) : build = null;

  final String name;
  final Color color;

  /// What it does, in a sentence.
  final String description;

  /// Makes its rules, fresh each time; null for the random kind.
  final List<Rule> Function()? build;

  bool get isRandom => build == null;

  /// Fresh rules of this kind ([factory] makes the random ones).
  List<Rule> rules(RobotFactory factory) => build?.call() ?? factory.rules();

  /// A new robot of this kind, named and colored apart from [taken]: a
  /// second Walls is "Walls 2", and takes the next free color when its own
  /// is in use.
  Robot make({
    Iterable<Robot> taken = const [],
    required RobotFactory factory,
  }) {
    if (isRandom) return factory.make(taken: taken);
    final names = {for (final r in taken) r.name};
    var name = this.name;
    for (var n = 2; names.contains(name); n++) {
      name = '${this.name} $n';
    }
    final colors = {for (final r in taken) r.color.toARGB32()};
    final color = colors.contains(this.color.toARGB32())
        ? robotColors.firstWhere(
            (c) => !colors.contains(c.toARGB32()),
            orElse: () => this.color,
          )
        : this.color;
    return Robot(name: name, color: color, rules: rules(factory));
  }
}

/// A robot with random rules, as the battle starts with.
const randomRobot = RobotKind.random(
  name: 'Random robot',
  color: Color(0xFFA4C639),
  description:
      'Random rules: a mix of the classic tactics with random numbers, '
      'under a random name.',
);

/// Robocode's sample robots, as rules.
const sampleRobots = [
  RobotKind(
    name: 'SittingDuck',
    color: Color(0xFF9AA5B1),
    description: 'Sits still and does nothing: a target to practice on.',
    build: _sittingDuck,
  ),
  RobotKind(
    name: 'Fire',
    color: Color(0xFFFF9A3C),
    description:
        'Sits still spinning its gun, fires at anything it sees (hard when '
        'point blank), and moves across the line of fire when hit.',
    build: _fire,
  ),
  RobotKind(
    name: 'SpinBot',
    color: Color(0xFF5B9BF0),
    description:
        'Drives in circles and fires hard at whatever crosses its sight.',
    build: _spinBot,
  ),
  RobotKind(
    name: 'Walls',
    color: Color(0xFF4CC38A),
    description:
        'Drives along the walls, turning right at each corner, and fires '
        'at what it sees.',
    build: _walls,
  ),
  RobotKind(
    name: 'Tracker',
    color: Color(0xFFC77DDB),
    description:
        'Closes in on the nearest enemy to 150 px and fires hard; backs '
        'off when too close.',
    build: _tracker,
  ),
  RobotKind(
    name: 'RamFire',
    color: Color(0xFFE36742),
    description:
        'Drives straight at the nearest enemy to ram it, and fires once it '
        'is on it: just enough when the enemy is nearly done.',
    build: _ramFire,
  ),
  RobotKind(
    name: 'TrackFire',
    color: Color(0xFFE8B04B),
    description:
        'Sits still, keeps its gun on the nearest enemy and fires: the '
        'closer, the harder.',
    build: _trackFire,
  ),
  RobotKind(
    name: 'MyFirstRobot',
    color: Color(0xFF4FC6D1),
    description:
        'Drives ahead sweeping its gun, takes cheap shots at what it sees, '
        'turns at walls and away from fire.',
    build: _myFirstRobot,
  ),
  RobotKind(
    name: 'Crazy',
    color: Color(0xFFF0506E),
    description:
        'Loops to the left, swerves when hit, reverses off walls and keeps '
        'reversing until it bumps into something.',
    build: _crazy,
  ),
];

/// Everything a battle can be made of: a random robot, then the samples.
const robotKinds = [randomRobot, ...sampleRobots];

List<Rule> _sittingDuck() => [
  Rule(
    drive: 'stop',
    turn: 'none',
    gun: 'hold',
    why: 'Sit still, whatever happens.',
  ),
];

List<Rule> _fire() => [
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Hit: move across the line of fire.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 50',
      'my_energy': '> 50',
    },
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 3,
    why: 'Point blank, with energy to spare: fire hard.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 1,
    why: 'In sight: a cheap shot.',
  ),
  Rule(
    drive: 'stop',
    turn: 'none',
    gun: 'sweep_right',
    why: 'Sit still and spin the gun.',
  ),
];

List<Rule> _spinBot() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'stop',
    turn: 'right',
    gun: 'sweep_right',
    why: 'A wall ahead: slow down and turn in place.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'right',
    gun: 'aim',
    fire: 3,
    why: 'In sight: fire hard, still circling.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'right',
    gun: 'sweep_right',
    why: 'Drive in circles, sweeping the gun.',
  ),
];

List<Rule> _walls() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'stop',
    turn: 'right',
    gun: 'aim',
    why: 'A wall ahead: stop and turn right, along it.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'none',
    gun: 'aim',
    fire: 2,
    why: 'In sight: fire.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'none',
    gun: 'aim',
    why: 'Drive on along the wall, gun on the enemy.',
  ),
];

List<Rule> _tracker() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'A wall ahead: back off, turning to the enemy.',
  ),
  Rule(
    when: {'enemy_distance': '< 60'},
    drive: 'back',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 3,
    why: 'Too close: back off, firing.',
  ),
  Rule(
    when: {'enemy_distance': '> 150'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Far: close in to 150 px.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'stop',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 3,
    why: 'In range and in sight: fire hard.',
  ),
  Rule(
    drive: 'stop',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'In range: hold, gun on the enemy.',
  ),
];

List<Rule> _ramFire() => [
  Rule(
    when: {'near_wall': 'true', 'enemy_distance': '> 100'},
    drive: 'back',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'A wall ahead and the enemy not there: back off.',
  ),
  Rule(
    when: {'enemy_distance': '< 40', 'enemy_energy': '< 5'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 0.5,
    why: 'Rammed, and the enemy is nearly done: just enough.',
  ),
  Rule(
    when: {'enemy_distance': '< 40'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 3,
    why: 'Rammed: fire hard.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Drive straight at the enemy.',
  ),
];

List<Rule> _trackFire() => [
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 60',
      'my_energy': '> 15',
    },
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 3,
    why: 'Point blank, with energy to spare: fire hard.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 200',
      'my_energy': '> 15',
    },
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 2,
    why: 'Near: fire.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 1,
    why: 'Far, or low on energy: a cheap shot.',
  ),
  Rule(
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    why: 'Sit still, gun on the enemy.',
  ),
];

List<Rule> _myFirstRobot() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'stop',
    turn: 'left',
    gun: 'sweep_right',
    why: 'A wall ahead: turn left.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'sweep_right',
    why: 'Hit: turn across the line of fire.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'none',
    gun: 'aim',
    fire: 1,
    why: 'In sight: a cheap shot.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'none',
    gun: 'sweep_right',
    why: 'Drive ahead, sweeping the gun.',
  ),
];

List<Rule> _crazy() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'right',
    gun: 'sweep_left',
    why: 'A wall ahead: reverse, swinging right.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'left',
    gun: 'sweep_right',
    why: 'Hit: swerve left.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'left',
    gun: 'aim',
    fire: 1,
    why: 'In sight: a shot on the way past.',
  ),
  Rule(
    when: {'speed': '< 0'},
    drive: 'back',
    turn: 'right',
    gun: 'sweep_left',
    why: 'Going backward: keep going, swinging right.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'left',
    gun: 'sweep_right',
    why: 'Loop to the left, sweeping the gun.',
  ),
];
