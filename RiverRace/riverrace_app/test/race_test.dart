import 'package:flutter_test/flutter_test.dart';
import 'package:riverrace_app/game/race.dart';
import 'package:riverrace_app/game/river.dart';
import 'package:riverrace_app/strategy/strategy.dart';

/// Whether [cell] matches [value], as aityx reads the cells the editor
/// writes: number tests, true/false, and lists of words.
bool matches(String cell, Object value) {
  cell = cell.trim();
  if (value is bool) return cell == '$value';
  if (value is String) {
    return cell.split(',').map((w) => w.trim()).contains(value);
  }
  final n = value as num;
  final range = RegExp(r'^\[(-?[\d.]+)\.\.(-?[\d.]+)\]$').firstMatch(cell);
  if (range != null) {
    return n >= num.parse(range[1]!) && n <= num.parse(range[2]!);
  }
  final test = RegExp(r'^(<=|>=|<|>|=)?\s*(-?[\d.]+)$').firstMatch(cell)!;
  final v = num.parse(test[2]!);
  return switch (test[1]) {
    '<' => n < v,
    '<=' => n <= v,
    '>' => n > v,
    '>=' => n >= v,
    _ => n == v,
  };
}

/// What a FIRST table of [strategy] decides for [sense], with the rule.
PilotAction decide(Strategy strategy, Map<String, Object> sense) {
  for (final (i, r) in strategy.rules.indexed) {
    if (r.when.entries.every((e) => matches(e.value, sense[e.key]!))) {
      return PilotAction(
        steer: r.steer,
        throttle: r.throttle,
        fire: r.fire,
        rule: i + 1,
      );
    }
  }
  return const PilotAction(steer: 'straight', rule: 0);
}

/// Plays [frames] frames, deciding every [every] frames.
Race play(
  int seed,
  List<Strategy> strategies, {
  int frames = 3600,
  int every = 6,
  int finish = 0,
}) {
  final race = Race(seed: seed, planeIds: ['p1', 'p2'], finishBridge: finish);
  for (var f = 0; f < frames && !race.over; f++) {
    race.step();
    if (race.frame % every == 0) {
      for (final (i, id) in ['p1', 'p2'].indexed) {
        final p = race.plane(id);
        if (p.flying) p.action = decide(strategies[i], race.sense(p));
      }
    }
  }
  return race;
}

void main() {
  test('the same seed is the same river', () {
    final a = River(7);
    final b = River(7);
    for (var y = 0.0; y < sectionLength * 3; y += 5) {
      expect(a.shape(y), b.shape(y));
    }
    expect(
      [for (final t in a.thingsOf(2)) '${t.kind}${t.x}'],
      [for (final t in b.thingsOf(2)) '${t.kind}${t.x}'],
    );
  });

  test('the river is mirrored, never too narrow to pass, and has bridges', () {
    final river = River(42);
    for (var y = 0.0; y < sectionLength * 12; y += 1) {
      final spans = river.spans(y);
      for (final s in spans) {
        expect(s.width, greaterThanOrEqualTo(16), reason: 'at $y');
      }
      expect(river.isWater(axis - 5, y), river.isWater(axis + 5, y));
    }
    // Every channel goes on: no dead ends, islands' sides included.
    for (var k = 0; k < sectionBlocks * 30; k++) {
      final a = river.blockAt(k);
      final b = river.blockAt(k + 1);
      expect(
        River.flowsInto((a.half, a.island), (b.half, b.island)),
        isTrue,
        reason: 'block $k (${a.half}, ${a.island}) to (${b.half}, ${b.island})',
      );
    }
    expect(river.bridgeAt(River.bridgeY(3)), 3);
    expect(river.bridgeAt(River.bridgeY(3) + 20), isNull);
  });

  test('a plane flying straight with no pilot crashes into the bank', () {
    final race = Race(seed: 3, planeIds: ['p1'], finishBridge: 0);
    final p = race.plane('p1')..action = const PilotAction(steer: 'straight');
    for (var f = 0; f < 6000 && p.lost == 0; f++) {
      race.step();
    }
    expect(p.lost, 1);
    expect(p.lastLost, anyOf('crashed into the bank', startsWith('hit')));
  });

  test('the player flies by the controls', () {
    final race = Race(seed: 3, planeIds: ['you', 'p1']);
    final you = race.plane('you');
    final x = you.x;
    race.controls
      ..left = true
      ..fast = true
      ..fire = true;
    for (var f = 0; f < 10; f++) {
      race.step();
    }
    expect(you.x, lessThan(x));
    expect(you.throttle, 'fast');
    expect(you.speed, greaterThan(speeds['normal']!));
    expect(you.missile, isNotNull);
  });

  test('a plane comes back where it can fly on', () {
    var respawns = 0;
    for (var seed = 1; seed <= 60; seed++) {
      final race = Race(seed: seed, planeIds: ['you'], finishBridge: 0);
      final you = race.plane('you');
      var back = -1;
      var was = true;
      for (var f = 0; f < 5000 && you.state != PlaneState.out; f++) {
        race.step();
        if (you.flying && !was) {
          respawns++;
          back = race.frame;
        }
        if (!you.flying && was && back >= 0) {
          expect(
            race.frame - back,
            greaterThanOrEqualTo(8),
            reason: 'seed $seed',
          );
        }
        was = you.flying;
      }
    }
    expect(respawns, greaterThan(100));
  });

  test('a plane slows down and beeps over a fuel depot', () {
    final race = Race(seed: 3, planeIds: ['p1'], finishBridge: 0);
    final p = race.plane('p1')..fuel = 50;
    race.things
      ..clear()
      ..add(Thing(ThingKind.fuel, p.x, p.y + 20));
    while (!p.refueling) {
      race.step();
    }
    // At half speed from the frame after it reaches the depot, all the way
    // over it.
    race.step();
    var over = 0;
    while (p.refueling) {
      expect(p.speed, speeds['normal']! * refuelSlow);
      over++;
      race.step();
    }
    expect(over, greaterThan(30));
    expect(race.sounds.whereType<RefuelSound>(), isNotEmpty);
    // Past it, it speeds up again.
    for (var f = 0; f < 20; f++) {
      race.step();
    }
    expect(p.speed, speeds['normal']!);
  });

  test('a missile hit explodes with a sound', () {
    final race = Race(seed: 3, planeIds: ['p1'], finishBridge: 0);
    final p = race.plane('p1')
      ..action = const PilotAction(steer: 'straight', fire: true);
    race.things
      ..clear()
      ..add(Thing(ThingKind.ship, p.x, p.y + 30));
    for (var f = 0; f < 10; f++) {
      race.step();
    }
    expect(race.things.first.exploding, greaterThan(0));
    expect(race.sounds.whereType<ExplosionSound>(), isNotEmpty);
  });

  test('fuel runs out without depots', () {
    final race = Race(seed: 3, planeIds: ['p1'], finishBridge: 0);
    final p = race.plane('p1');
    p.fuel = 0.05;
    race.step();
    expect(p.lastLost, 'ran out of fuel');
    expect(p.lives, startLives - 1);
  });

  test('the senses are what the API checks for', () {
    final race = Race(seed: 5, planeIds: ['you', 'p1', 'p2']);
    final sense = race.sense(race.plane('p1'));
    expect(sense.keys, [for (final s in sensors) s.id]);
    for (final s in sensors) {
      final v = sense[s.id];
      switch (s.kind) {
        case SensorKind.number:
          expect(v, isA<int>(), reason: s.id);
        case SensorKind.boolean:
          expect(v, isA<bool>(), reason: s.id);
        case SensorKind.words:
          expect(s.words, contains(v), reason: s.id);
      }
    }
  });

  test('the presets fly the river, and differ', () {
    var careful0 = 0, daredevil0 = 0, bridges = 0;
    for (final seed in [1, 2, 3, 4]) {
      final race = play(seed, [careful(), daredevil()]);
      final c = race.plane('p1');
      final d = race.plane('p2');
      careful0 += c.score;
      daredevil0 += d.score;
      bridges += c.bridges + d.bridges;
      // ignore: avoid_print
      print(
        'seed $seed: Careful ${c.score} pts, bridge ${c.bridges}, lost '
        '${c.lost} (${c.lastLost}); Daredevil ${d.score} pts, bridge '
        '${d.bridges}, lost ${d.lost} (${d.lastLost})',
      );
    }
    // A minute each: they get past bridges, and shoot things.
    expect(bridges, greaterThan(8));
    expect(careful0, greaterThan(0));
    expect(daredevil0, greaterThan(0));
  });

  test('a rookie flying straight does worse than a careful pilot', () {
    var rookieBridges = 0, carefulBridges = 0;
    for (final seed in [1, 2, 3]) {
      final race = play(seed, [rookie(), careful()]);
      rookieBridges += race.plane('p1').best.round();
      carefulBridges += race.plane('p2').best.round();
    }
    expect(carefulBridges, greaterThan(rookieBridges));
  });

  test('the race ends at the finish bridge, with a winner', () {
    final race = play(9, [daredevil(), daredevil()], frames: 20000, finish: 2);
    expect(race.over, isTrue);
    expect(race.winner, isNotNull);
  });
}
