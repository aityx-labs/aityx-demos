import 'dart:math';
import 'dart:ui' show Color;

import 'model.dart';

const _names = [
  'Spinner', 'Charger', 'Sniper', 'Dodger', 'Rammer', 'Sweeper', //
  'Circler', 'Hunter', 'Coward', 'Jitter', 'Turret', 'Wallflower',
  'Stalker', 'Brawler', 'Drifter', 'Gunner', 'Ghost', 'Tornado',
  'Bulldog', 'Hornet', 'Viper', 'Mantis', 'Rhino', 'Falcon',
];

/// Tank colors, bright enough on the dark battlefield.
const robotColors = [
  Color(0xFFE36742), Color(0xFF4CC38A), Color(0xFF5B9BF0), //
  Color(0xFFE8B04B), Color(0xFFC77DDB), Color(0xFF4FC6D1),
  Color(0xFFF0506E), Color(0xFFA4C639), Color(0xFFFF9A3C),
  Color(0xFF9AA5B1),
];

/// Makes robots with random rules: a mix of the classic tactics, each
/// with random numbers, and a last rule that always matches.
class RobotFactory {
  RobotFactory([Random? random]) : _random = random ?? Random();

  final Random _random;

  T _pick<T>(List<T> xs) => xs[_random.nextInt(xs.length)];
  int _between(int lo, int hi) => lo + _random.nextInt(hi - lo + 1);
  num _power() => _pick([0.5, 1, 1.5, 2, 2.5, 3]);

  /// A new robot named and colored differently from [taken].
  Robot make({Iterable<Robot> taken = const []}) {
    final usedNames = {for (final r in taken) r.name};
    final usedColors = {for (final r in taken) r.color.toARGB32()};
    final names = _names.where((n) => !usedNames.contains(n)).toList();
    final colors = robotColors
        .where((c) => !usedColors.contains(c.toARGB32()))
        .toList();
    return Robot(
      name: names.isEmpty ? 'Robot ${taken.length + 1}' : _pick(names),
      color: colors.isEmpty ? _pick(robotColors) : _pick(colors),
      rules: rules(),
    );
  }

  /// Two to five tactics in random order, usually after "off the wall",
  /// then a fallback.
  List<Rule> rules() {
    final tactics = <Rule Function()>[
      _fireInSight,
      _closeIn,
      _dodge,
      _flee,
      _finishOff,
      _ram,
      _snipe,
    ]..shuffle(_random);
    return [
      if (_random.nextDouble() < 0.8) _offTheWall(),
      for (final t in tactics.take(_between(2, 5))) t(),
      _fallback(),
    ];
  }

  Rule _offTheWall() => Rule(
    when: {'near_wall': 'true'},
    drive: 'back',
    turn: _pick(['left', 'right', 'toward_enemy']),
    gun: _pick(['aim', 'sweep_left', 'sweep_right']),
    why: 'A wall ahead: back off and turn.',
  );

  Rule _fireInSight() => Rule(
    when: {'enemy_in_sight': 'true', 'gun_ready': 'true'},
    drive: _pick(['ahead', 'stop', 'back']),
    turn: _pick(['perpendicular', 'none', 'toward_enemy']),
    gun: 'aim',
    fire: _power(),
    why: 'The enemy is in the gun sight: fire.',
  );

  Rule _closeIn() {
    final d = _between(15, 35) * 10;
    return Rule(
      when: {'enemy_distance': '< $d', 'gun_ready': 'true'},
      drive: 'stop',
      turn: 'perpendicular',
      gun: 'aim',
      fire: _pick([2, 2.5, 3]),
      why: 'Closer than $d px: stand and fire hard.',
    );
  }

  Rule _dodge() => Rule(
    when: {'was_hit': 'true'},
    drive: _pick(['ahead', 'back']),
    turn: 'perpendicular',
    gun: 'aim',
    why: 'Hit: move across the line of fire.',
  );

  Rule _flee() {
    final e = _between(2, 5) * 10;
    return Rule(
      when: {'my_energy': '< $e'},
      drive: 'ahead',
      turn: 'away_from_enemy',
      gun: 'aim',
      fire: _pick([0, 0.5, 1]),
      why: 'Under $e energy: run.',
    );
  }

  Rule _finishOff() {
    final e = _between(1, 3) * 10;
    return Rule(
      when: {'enemy_energy': '< $e', 'gun_ready': 'true'},
      drive: 'ahead',
      turn: 'toward_enemy',
      gun: 'aim',
      fire: 3,
      why: 'The enemy is under $e: finish it.',
    );
  }

  Rule _ram() {
    final d = _between(8, 15) * 10;
    return Rule(
      when: {'enemy_distance': '< $d'},
      drive: 'ahead',
      turn: 'toward_enemy',
      gun: 'aim',
      fire: _pick([1, 2, 3]),
      why: 'Closer than $d px: ram it.',
    );
  }

  Rule _snipe() {
    final d = _between(30, 50) * 10;
    return Rule(
      when: {'enemy_distance': '> $d', 'gun_ready': 'true'},
      drive: 'stop',
      turn: 'none',
      gun: 'aim',
      fire: _pick([0.5, 1]),
      why: 'Farther than $d px: cheap long shots.',
    );
  }

  Rule _fallback() => _pick([
    Rule(
      drive: 'ahead',
      turn: _pick(['left', 'right']),
      gun: _pick(['sweep_left', 'sweep_right']),
      why: 'Nothing else: circle and sweep the gun.',
    ),
    Rule(
      drive: 'ahead',
      turn: 'toward_enemy',
      gun: 'aim',
      fire: _pick([0, 0.5, 1]),
      why: 'Nothing else: head for the enemy, gun on it.',
    ),
    Rule(
      drive: 'ahead',
      turn: 'perpendicular',
      gun: 'aim',
      why: 'Nothing else: circle the enemy, gun on it.',
    ),
  ]);

  /// Starting places for [n] robots: apart from each other and the walls,
  /// facing anywhere.
  List<({double x, double y, double heading})> places(int n) {
    final out = <({double x, double y, double heading})>[];
    var tries = 0;
    while (out.length < n) {
      final x = 60 + _random.nextDouble() * (arenaWidth - 120);
      final y = 60 + _random.nextDouble() * (arenaHeight - 120);
      final apart = out.every(
        (p) => (p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) > 120 * 120,
      );
      if (apart || ++tries > 500) {
        out.add((
          x: x.roundToDouble(),
          y: y.roundToDouble(),
          heading: (_random.nextInt(36) * 10).toDouble(),
        ));
      }
    }
    return out;
  }
}
