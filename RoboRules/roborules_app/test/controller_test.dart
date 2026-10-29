import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roborules_app/battle/api.dart';
import 'package:roborules_app/battle/controller.dart';
import 'package:roborules_app/battle/model.dart';
import 'package:roborules_app/battle/predefined_robots.dart';
import 'package:roborules_app/battle/random_robots.dart';
import 'package:roborules_app/main.dart';

/// Plays turns where r2 loses 10 energy a turn, so it dies on turn 10,
/// and scores r1 the winner.
class FakeApi implements BattleApi {
  int turnCalls = 0;
  int scoreCalls = 0;
  Object? failNext;
  Object? failScore;

  /// When set, the next turns call waits for it.
  Completer<void>? hold;

  @override
  Future<Turns> turns(List<Robot> robots, World world, int turns) async {
    turnCalls++;
    final wait = hold;
    hold = null;
    if (wait != null) await wait.future;
    if (failNext case final e?) {
      failNext = null;
      throw e;
    }
    final frames = <World>[];
    var w = world;
    for (var i = 0; i < turns; i++) {
      final tick = w.tick + 1;
      w = World(
        tick: tick,
        bullets: const [],
        bots: [
          for (final b in w.bots)
            b.id == 'r2'
                ? _with(b, energy: max(0, 100 - tick * 10), tick: tick)
                : _with(b, energy: b.energy, tick: tick),
        ],
      );
      frames.add(w);
    }
    return Turns(frames, request: {'decision': {}}, response: {'answers': {}});
  }

  Bot _with(Bot b, {required double energy, required int tick}) => Bot(
    id: b.id,
    x: b.x + 1,
    y: b.y,
    heading: b.heading,
    v: 1,
    gun: b.gun,
    energy: energy,
    heat: 0,
    alive: energy > 0,
    rule: 1,
    hit: energy < b.energy,
    damage: b.damage,
    fired: 0,
    died: energy <= 0 && b.alive ? tick : b.died,
  );

  @override
  Future<RoundScore> score(World last) async {
    scoreCalls++;
    if (failScore case final e?) {
      failScore = null;
      throw e;
    }
    return const RoundScore([
      Score(
        id: 'r1',
        survival: 50,
        lastSurvivor: 10,
        bulletDamage: 100,
        total: 160,
      ),
      Score(id: 'r2', survival: 0, lastSurvivor: 0, bulletDamage: 0, total: 0),
    ], 'r1');
  }
}

class DeferredApi extends FakeApi {
  final requests = <Completer<Turns>>[];

  @override
  Future<Turns> turns(List<Robot> robots, World world, int turns) {
    final request = Completer<Turns>();
    requests.add(request);
    return request.future;
  }
}

void main() {
  BattleController battle(FakeApi api) =>
      BattleController(api: api, factory: RobotFactory(Random(1)))
        ..randomRobots(2)
        ..rounds = 2
        ..turnsPerSecond = 0; // as fast as the turns arrive

  testWidgets('plays every round to the end, scored on aityx', (tester) async {
    final api = FakeApi();
    final c = battle(api);
    c.start();
    expect(c.state, BattleState.running);

    for (var i = 0; i < 400 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.state, BattleState.over);
    expect(api.scoreCalls, 2);
    expect(c.totals['r1']!.total, 320);
    expect(c.totals['r1']!.firsts, 2);
    expect(c.ranking.first, 0);
    // r2 died on turn 10 each round: the round stopped there.
    expect(c.world!.tick, 10);
    expect(c.world!.bots[1].alive, isFalse);
    final turnCalls = api.turnCalls;
    c.start();
    expect(c.state, BattleState.running);
    expect(api.turnCalls, greaterThan(turnCalls));
    c.dispose();
  });

  testWidgets('a response from before restart cannot fill the new battle', (
    tester,
  ) async {
    final api = DeferredApi();
    final c = battle(api);
    c.start();
    final oldWorld = c.world!;
    expect(api.requests, hasLength(1));

    c.stop();
    c.start();
    api.requests.first.complete(await FakeApi().turns(c.robots, oldWorld, 1));
    await tester.pump();
    expect(c.world!.tick, 0);
    expect(c.buffered, 0);

    await tester.pump(const Duration(milliseconds: 20));
    expect(api.requests, hasLength(2));
    api.requests.last.complete(await FakeApi().turns(c.robots, c.world!, 1));
    await tester.pump(const Duration(milliseconds: 20));
    expect(c.world!.tick, 1);
    c.dispose();
  });

  testWidgets('every event and every aityx call go in the log', (tester) async {
    final api = FakeApi();
    final c = battle(api)..keptCalls = 2;
    c.start();
    for (var i = 0; i < 400 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.state, BattleState.over);
    final lines = c.events.map((e) => e.text).toList();
    final r2 = c.robots[1].name;
    expect(lines.first, startsWith('Battle: '));
    expect(lines, contains('Round 1 begins'));
    expect(lines, contains('Turn 10 · $r2 is lost'));
    expect(lines.where((l) => l.contains('$r2 is hit')), isNotEmpty);
    expect(
      lines.where((l) => l.startsWith('aityx played turns 1–')),
      hasLength(2),
    );
    expect(
      lines.where((l) => l.startsWith('aityx scored round')),
      hasLength(2),
    );
    expect(lines, contains('Round 2 begins'));
    expect(lines.last, startsWith('Battle over: ${c.robots[0].name} wins'));
    expect(lines.join(), isNot(contains('dead')));
    // Two turn calls and two score calls; only the last two keep payloads.
    expect(c.calls, hasLength(4));
    expect(c.calls.map((k) => k.kept), [false, false, true, true]);
    expect(c.events.where((e) => e.call != null), hasLength(4));
    expect(c.lastCall!.what, 'the score of round 2');
    c.dispose();
  });

  testWidgets('the window lists the events, and opens a kept call', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi())..rounds = 1;
    await tester.pumpWidget(RoboRulesApp(controller: c));
    expect(find.text('Events'), findsOneWidget);
    c.start();
    for (var i = 0; i < 400 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('is lost'), findsOneWidget);
    expect(find.text('Results for 1 round'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('aityx scored round 1'));
    await tester.pumpAndSettle();
    expect(find.text('aityx call 2: the score of round 1'), findsOneWidget);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a battle after a finished one plays again', (tester) async {
    final api = FakeApi();
    final c = battle(api)..rounds = 1;
    c.start();
    for (var i = 0; i < 200 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.state, BattleState.over);
    c.start();
    for (var i = 0; i < 50 && c.world!.tick == 0; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.world!.tick, greaterThan(0));
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets("a restarted battle drops the old battle's late reply", (
    tester,
  ) async {
    final api = FakeApi()..hold = Completer<void>();
    // Slow, so what arrives stays in the buffer to be counted.
    final c = battle(api)..turnsPerSecond = 1;
    final held = api.hold!;
    c.start(); // the first call waits
    await tester.pump(const Duration(milliseconds: 20));
    c.start(); // restart: a new battle, a new call
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    held.complete(); // the old battle's 20 frames arrive late
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Dropped: the turns shown and buffered are the new battle's round
    // alone, which ends on turn 10 (an old reply would add 10 more).
    expect(c.world!.tick + c.buffered, 10);
    expect(api.turnCalls, 2);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a round aityx fails to score waits for a retry', (tester) async {
    final api = FakeApi()
      ..failScore = const BattleException('aityx answered HTTP 503');
    final c = battle(api);
    c.start();
    for (var i = 0; i < 200 && !c.canRetryScore; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.canRetryScore, isTrue);
    expect(c.error, contains('Scoring failed'));
    await tester.pump(const Duration(seconds: 3));
    expect(c.round, 1, reason: 'it does not move on unscored');
    expect(c.roundScores, isEmpty);

    c.retryScore();
    for (var i = 0; i < 200 && c.round == 1; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.roundScores, hasLength(1));
    expect(c.round, 2);
    expect(c.error, isNull);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('robots can be added and removed between battles', (
    tester,
  ) async {
    final c = battle(FakeApi());
    final walls = sampleRobots.firstWhere((k) => k.name == 'Walls');
    c.addRobot(walls.make(taken: c.robots, factory: c.factory));
    expect(c.robots, hasLength(3));
    expect(c.robots.last.name, 'Walls');
    expect(c.world!.bots, hasLength(3));
    expect(c.totals.keys, ['r1', 'r2', 'r3']);

    c.removeRobot(0);
    expect(c.robots, hasLength(2));
    expect(c.robots.last.name, 'Walls');
    expect(c.world!.bots, hasLength(2));
    expect(c.totals.keys, ['r1', 'r2']);

    for (var i = 0; i < 20; i++) {
      c.addRobot(randomRobot.make(taken: c.robots, factory: c.factory));
    }
    expect(c.robots, hasLength(maxRobots));
    expect(c.robots.map((r) => r.name).toSet(), hasLength(maxRobots));

    c.setRobots([c.robots[0], c.robots[1]]);
    expect(c.robots, hasLength(2));
    expect(c.state, BattleState.setup);
    c.dispose();
  });

  testWidgets('New Battle picks robots from the predefined ones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi());
    await tester.pumpWidget(RoboRulesApp(controller: c));
    await tester.tap(find.text('New battle…'));
    await tester.pumpAndSettle();
    expect(find.text('Available robots'), findsOneWidget);
    expect(find.text('Selected robots (2 of $maxRobots)'), findsOneWidget);

    await tester.tap(find.text('Walls'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Drives along the walls'), findsOneWidget);
    await tester.tap(find.text('Add →'));
    await tester.pumpAndSettle();
    expect(find.text('Selected robots (3 of $maxRobots)'), findsOneWidget);
    expect(find.text('Walls'), findsNWidgets(2));

    await tester.tap(find.text(c.robots[0].name).last);
    await tester.pump();
    await tester.tap(find.text('← Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Selected robots (2 of $maxRobots)'), findsOneWidget);

    await tester.tap(find.text('Start Battle'));
    await tester.pumpAndSettle();
    expect(c.robots.map((r) => r.name), [c.robots[0].name, 'Walls']);
    expect(c.round, 1);
    expect(c.state, isNot(BattleState.setup));
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the robots panel adds and removes robots', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi());
    await tester.pumpWidget(RoboRulesApp(controller: c));
    await tester.tap(find.text('Add robot…'));
    await tester.pumpAndSettle();
    expect(find.text('Add a robot'), findsOneWidget);
    await tester.tap(find.text('SpinBot'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(c.robots, hasLength(3));
    expect(c.robots.last.name, 'SpinBot');
    expect(find.text('SpinBot'), findsWidgets);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    expect(c.robots, hasLength(2));
    expect(find.text('SpinBot'), findsNothing);

    // During a battle the roster is fixed.
    c.start();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Add robot…'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a death makes a big explosion', (tester) async {
    final c = battle(FakeApi());
    c.start();
    var big = false;
    for (var i = 0; i < 200 && !big; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      big = c.explosions.any((e) => e.big);
    }
    expect(big, isTrue);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a failed call pauses the battle and says why', (tester) async {
    final api = FakeApi()
      ..failNext = const BattleException('aityx answered HTTP 422');
    final c = battle(api);
    c.start();
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.state, BattleState.paused);
    expect(c.error, contains('422'));
    c.resume();
    for (var i = 0; i < 50 && c.world!.tick == 0; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.world!.tick, greaterThan(0));
    expect(c.error, isNull);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the window shows the robots, and opens one\'s rules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi());
    await tester.pumpWidget(RoboRulesApp(controller: c));
    expect(find.text(c.robots[0].name), findsWidgets);
    expect(find.text(c.robots[1].name), findsWidgets);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text(c.robots[0].name).last);
    await tester.pumpAndSettle();
    expect(find.text('Rules of ${c.robots[0].name}'), findsOneWidget);
    expect(find.text('Rule 1'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    c.dispose();
  });
}
