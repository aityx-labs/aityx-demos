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

/// Robocode's sample robots, as rules, then robots of our own: some with
/// more involved tactics, some just for fun.
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
  RobotKind(
    name: 'Orbiter',
    color: Color(0xFF7FDBFF),
    description:
        'Circles the nearest enemy across its line of fire, firing harder '
        'up close; reverses its orbit off the walls and jinks when hit.',
    build: _orbiter,
  ),
  RobotKind(
    name: 'Sniper',
    color: Color(0xFFD4A373),
    description:
        'Keeps 250 px away, lies still with its gun on the target and '
        'fires steady shots; moves to a new spot when hit.',
    build: _sniper,
  ),
  RobotKind(
    name: 'Vulture',
    color: Color(0xFFB388FF),
    description:
        'Keeps out of the fight while the others wear each other down, '
        'then swoops on whoever is nearly done.',
    build: _vulture,
  ),
  RobotKind(
    name: 'Berserker',
    color: Color(0xFFFF6B6B),
    description:
        'Calm and careful at first; the more it is hurt, the angrier it '
        'gets, until it charges firing everything.',
    build: _berserker,
  ),
  RobotKind(
    name: 'Matador',
    color: Color(0xFFFFD166),
    description:
        'Stands proud facing the bull; when it charges, steps aside and '
        'strikes as it passes. Olé!',
    build: _matador,
  ),
  RobotKind(
    name: 'Chicken',
    color: Color(0xFFFFF3B0),
    description:
        'Runs from anyone who comes near, firing over its shoulder, and '
        'turns brave only when the enemy is nearly done.',
    build: _chicken,
  ),
  RobotKind(
    name: 'Tipsy',
    color: Color(0xFFFF7EB6),
    description:
        'Weaves toward the enemy as if it has had one too many, lurching '
        'left and right and hiccupping shots roughly that way.',
    build: _tipsy,
  ),
  RobotKind(
    name: 'Pacifist',
    color: Color(0xFF9CCC65),
    description:
        'Never fires a shot: keeps out of everyone\'s way and hopes the '
        'others wear each other out.',
    build: _pacifist,
  ),
  RobotKind(
    name: 'BumperCar',
    color: Color(0xFF8BD3C7),
    description:
        'Drives into everyone it can find, says sorry with the smallest '
        'shot there is, backs off and does it again.',
    build: _bumperCar,
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

List<Rule> _orbiter() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'A wall ahead: reverse the orbit.',
  ),
  Rule(
    when: {'speed': '< 0', 'wall_distance': '< 30'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Backing into a wall: orbit forward again.',
  ),
  Rule(
    when: {'was_hit': 'true', 'speed': '> 0'},
    drive: 'back',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Hit: jink backward, so the next shot misses.',
  ),
  Rule(
    when: {'enemy_distance': '> 400'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Too far to orbit: close in.',
  ),
  Rule(
    when: {
      'speed': '< 0',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 250',
    },
    drive: 'back',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 2.5,
    why: 'Orbiting backward, close: fire hard.',
  ),
  Rule(
    when: {'speed': '< 0', 'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'back',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 1,
    why: 'Orbiting backward, far: a light shot.',
  ),
  Rule(
    when: {'speed': '< 0'},
    drive: 'back',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Keep orbiting backward.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 250',
    },
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 2.5,
    why: 'Orbiting, close: fire hard.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 1,
    why: 'Orbiting, far: a light shot.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Circle the enemy, across its line of fire.',
  ),
];

List<Rule> _sniper() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'stop',
    turn: 'right',
    gun: 'aim',
    why: 'A wall ahead: turn along it.',
  ),
  Rule(
    when: {'enemy_distance': '< 250', 'wall_distance': '> 120'},
    drive: 'ahead',
    turn: 'away_from_enemy',
    gun: 'aim',
    why: 'Too close: fall back to a firing position.',
  ),
  Rule(
    when: {
      'enemy_distance': '< 250',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
    },
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 1,
    why: 'Too close, with a wall behind: slip sideways, firing.',
  ),
  Rule(
    when: {'enemy_distance': '< 250'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Too close, with a wall behind: slip sideways.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Spotted: move to a new spot.',
  ),
  Rule(
    when: {'speed': '> 2'},
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    why: 'Moving: settle down before taking a shot.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true', 'my_energy': '> 20'},
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 2,
    why: 'Steady... fire.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 0.5,
    why: 'Low on energy: cheap shots only.',
  ),
  Rule(
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    why: 'Lie still, gun on the target.',
  ),
];

List<Rule> _vulture() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'A wall ahead: back off.',
  ),
  Rule(
    when: {
      'enemy_energy': '< 20',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
    },
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 3,
    why: 'The prey is nearly done: swoop and finish it.',
  ),
  Rule(
    when: {'enemy_energy': '< 20'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'The prey is weak: swoop down on it.',
  ),
  Rule(
    when: {
      'enemies_left': '> 1',
      'enemy_distance': '< 250',
      'wall_distance': '> 120',
    },
    drive: 'ahead',
    turn: 'away_from_enemy',
    gun: 'aim',
    why: 'Let the others fight: keep away.',
  ),
  Rule(
    when: {
      'enemies_left': '> 1',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
    },
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 0.5,
    why: 'Circle at a distance, pecking with cheap shots.',
  ),
  Rule(
    when: {'enemies_left': '> 1'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Circle, waiting.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 200',
    },
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 2,
    why: 'One left: fight it, circling.',
  ),
  Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 1,
    why: 'One left, far: close in, firing.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'One left: go get it.',
  ),
];

List<Rule> _berserker() => [
  Rule(
    when: {'near_wall': 'true', 'enemy_distance': '> 100'},
    drive: 'back',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'A wall ahead: back off, turning to the enemy.',
  ),
  Rule(
    when: {'my_energy': '< 30', 'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 3,
    why: 'Nothing left to lose: charge, firing everything.',
  ),
  Rule(
    when: {'my_energy': '< 30'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'RAAAH!',
  ),
  Rule(
    when: {'my_energy': '< 60', 'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 2,
    why: 'Getting angry: close in, firing.',
  ),
  Rule(
    when: {'my_energy': '< 60'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Getting angry: close in.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Still calm: sidestep the fire.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 300',
    },
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    fire: 1,
    why: 'Calm: careful shots.',
  ),
  Rule(
    when: {'enemy_distance': '> 300'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Calm: get within range.',
  ),
  Rule(
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    why: 'Calm: wait, gun on the enemy.',
  ),
];

List<Rule> _matador() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'A wall: back into the ring.',
  ),
  Rule(
    when: {
      'enemy_distance': '< 120',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
    },
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    fire: 3,
    why: 'The bull is here: step aside and strike as it passes. Olé!',
  ),
  Rule(
    when: {'enemy_distance': '< 120'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'The bull is charging: step aside.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Stung: a step out of the line.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 350',
    },
    drive: 'stop',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 1,
    why: 'A flick of the cape, to provoke it.',
  ),
  Rule(
    when: {'enemy_distance': '> 350'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'The bull is far: strut into the ring.',
  ),
  Rule(
    drive: 'stop',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Stand proud, facing the bull.',
  ),
];

List<Rule> _chicken() => [
  Rule(
    when: {
      'enemy_energy': '< 15',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
    },
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 3,
    why: 'It is nearly done: suddenly brave! Charge!',
  ),
  Rule(
    when: {'enemy_energy': '< 15'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Brave now: after it!',
  ),
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'right',
    gun: 'aim',
    why: 'Cornered! Panic: back up, spinning.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'left',
    gun: 'sweep_right',
    why: 'Ouch! Flap about.',
  ),
  Rule(
    when: {
      'enemy_distance': '< 300',
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
    },
    drive: 'ahead',
    turn: 'away_from_enemy',
    gun: 'aim',
    fire: 0.5,
    why: 'Run away, with a shot over the shoulder.',
  ),
  Rule(
    when: {'enemy_distance': '< 300'},
    drive: 'ahead',
    turn: 'away_from_enemy',
    gun: 'aim',
    why: 'Too close! Run!',
  ),
  Rule(
    drive: 'stop',
    turn: 'none',
    gun: 'aim',
    why: 'Far enough: catch its breath, one eye on the enemy.',
  ),
];

List<Rule> _tipsy() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: 'left',
    gun: 'sweep_right',
    why: 'Bumped into a wall: stagger back.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'stop',
    turn: 'right',
    gun: 'sweep_left',
    why: 'Hit: spin round, confused.',
  ),
  Rule(
    when: {
      'enemy_in_sight': 'true',
      'gun_ready': 'true',
      'enemy_distance': '< 150',
    },
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    fire: 2,
    why: 'Close enough to hit a barn door: fire.',
  ),
  Rule(
    when: {'gun_ready': 'true', 'gun_bearing': '[-40..40]'},
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'sweep_left',
    fire: 0.5,
    why: 'Hic! A shot, roughly that way.',
  ),
  Rule(
    when: {'wall_distance': '[100..150]'},
    drive: 'ahead',
    turn: 'left',
    gun: 'aim',
    why: 'Lurch left.',
  ),
  Rule(
    when: {'wall_distance': '[190..240]'},
    drive: 'ahead',
    turn: 'right',
    gun: 'aim',
    why: 'Lurch right.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'aim',
    why: 'Stagger toward the nearest enemy.',
  ),
];

List<Rule> _pacifist() => [
  Rule(
    when: {'near_wall': 'true'},
    drive: 'stop',
    turn: 'right',
    gun: 'hold',
    why: 'A wall ahead: turn away from it.',
  ),
  Rule(
    when: {'enemy_distance': '< 150'},
    drive: 'ahead',
    turn: 'away_from_enemy',
    gun: 'hold',
    why: 'Too close for comfort: excuse me, coming through.',
  ),
  Rule(
    when: {'was_hit': 'true'},
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'hold',
    why: 'Hit: out of the line of fire, without hard feelings.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'perpendicular',
    gun: 'sweep_left',
    why: 'Circle out of the line of fire, gun idly spinning, never fired.',
  ),
];

List<Rule> _bumperCar() => [
  Rule(
    when: {'near_wall': 'true', 'enemy_distance': '> 60'},
    drive: 'back',
    turn: 'right',
    gun: 'sweep_left',
    why: 'Bonk! A wall. Back up and try again.',
  ),
  Rule(
    when: {'enemy_distance': '< 45', 'gun_ready': 'true'},
    drive: 'back',
    turn: 'left',
    gun: 'aim',
    fire: 0.1,
    why: 'Bump! Sorry! (the smallest shot there is)',
  ),
  Rule(
    when: {'enemy_distance': '< 45'},
    drive: 'back',
    turn: 'left',
    gun: 'aim',
    why: 'Bump! Back up for another go.',
  ),
  Rule(
    drive: 'ahead',
    turn: 'toward_enemy',
    gun: 'sweep_right',
    why: 'Beep beep: here I come.',
  ),
];
