import 'dart:convert';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roborules_app/aityx/aityx_call_view.dart';
import 'package:roborules_app/battle/api.dart';
import 'package:roborules_app/battle/controller.dart';
import 'package:roborules_app/battle/model.dart';
import 'package:roborules_app/battle/predefined_robots.dart';
import 'package:roborules_app/battle/random_robots.dart';
import 'package:roborules_app/battle/robot_files.dart';
import 'package:roborules_app/files/files.dart';
import 'package:roborules_app/main.dart';
import 'package:roborules_app/sound/sounds.dart';
import 'package:roborules_app/ui/battle_screen.dart'
    show eventStripes, shotBackground, shotText;

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

/// Plays the same few turns, whatever it's asked: [frames], from the turn
/// after the one it plays from.
class ScriptedApi extends FakeApi {
  ScriptedApi(this.frames);

  final List<World> frames;

  @override
  Future<Turns> turns(List<Robot> robots, World world, int turns) async {
    turnCalls++;
    return Turns(
      frames.where((f) => f.tick > world.tick).take(turns).toList(),
      request: {'decision': {}},
      response: {'answers': {}},
    );
  }
}

/// Records the sounds the battle plays, and what it saves.
class FakeSounds implements Sounds {
  FakeSounds({this.saved});

  final played = <BattleSound>[];

  @override
  bool? saved;

  @override
  void play(BattleSound sound) => played.add(sound);

  @override
  void save(bool on) => saved = on;
}

Bot bot(
  String id,
  double x,
  double y, {
  double v = 0,
  double energy = 100,
  bool hit = false,
  int died = 0,
  double fired = 0,
}) => Bot(
  id: id,
  x: x,
  y: y,
  heading: 90,
  v: v,
  gun: 90,
  energy: energy,
  heat: 0,
  alive: energy > 0,
  rule: 1,
  hit: hit,
  damage: 0,
  fired: fired,
  died: died,
);

World turn(int tick, List<Bot> bots) =>
    World(tick: tick, bots: bots, bullets: const []);

/// r1 drives into the left wall, is hit, rams r2, and r2 is lost.
final collisions = [
  turn(1, [bot('r1', 100, 300, v: 8), bot('r2', 300, 300, v: -8)]),
  // r1 runs into the wall, and stops 18 px from it.
  turn(2, [bot('r1', 18, 300), bot('r2', 292, 300, v: -8)]),
  // Stuck at the wall: no second thud.
  turn(3, [bot('r1', 18, 300), bot('r2', 284, 300, v: -8)]),
  turn(4, [bot('r1', 18, 300, energy: 90, hit: true), bot('r2', 276, 300)]),
  turn(5, [bot('r1', 26, 300, v: 8, energy: 90), bot('r2', 60, 300, v: -8)]),
  // A ram: both stay where they were, and stop.
  turn(6, [bot('r1', 26, 300, energy: 89.4), bot('r2', 60, 300, energy: 9.4)]),
  turn(7, [
    bot('r1', 26, 300, energy: 89.4),
    bot('r2', 60, 300, v: -1, energy: 9.4),
  ]),
  turn(8, [
    bot('r1', 26, 300, energy: 89.4),
    bot('r2', 60, 300, energy: 0, hit: true, died: 8),
  ]),
];

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

  testWidgets('every event goes in the log, and every aityx call is kept', (
    tester,
  ) async {
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
    // The calls aren't events: the latest shows below the log.
    expect(lines.where((l) => l.startsWith('aityx ')), isEmpty);
    expect(lines, contains('Round 2 begins'));
    expect(lines.last, startsWith('Battle over: ${c.robots[0].name} wins'));
    expect(lines.join(), isNot(contains('dead')));
    // Two turn calls and two score calls; only the last two keep payloads.
    expect(c.calls, hasLength(4));
    expect(c.calls.map((k) => k.kept), [false, false, true, true]);
    expect(c.calls.map((k) => k.what), [
      'turns 1–20 of round 1',
      'the score of round 1',
      'turns 1–20 of round 2',
      'the score of round 2',
    ]);
    expect(c.calls.map((k) => k.millis), everyElement(isNotNull));
    expect(c.lastCall!.what, 'the score of round 2');
    expect(c.lastCall!.result, '${c.robots[0].name} 160, $r2 0');
    // Every line keeps the call behind it: a turn's events the call that
    // played the turn, a round's end its last turn's, the battle's end the
    // last score; the app's own lines none.
    BattleEvent line(String text) => c.events.firstWhere((e) => e.text == text);
    expect(line('Turn 10 · $r2 is lost').call, c.calls[0]);
    expect(
      c.events.firstWhere((e) => e.text.startsWith('Round 1 is over')).call,
      c.calls[0],
    );
    expect(c.events.last.call, c.calls[3]);
    expect(line('Round 1 begins').call, isNull);
    expect(line('Round 2 begins').call, isNull);
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
    // The way back to the index page, at the right end of the menu bar.
    expect(find.text('aityx demos'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('aityx demos')).dx,
      greaterThan(tester.getTopRight(find.text('Help')).dx),
    );
    expect(
      tester.getCenter(find.text('aityx demos')).dy,
      moreOrLessEquals(tester.getCenter(find.text('Help')).dy, epsilon: 2),
    );
    c.start();
    for (var i = 0; i < 400 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('is lost'), findsOneWidget);
    expect(find.text('Results for 1 round'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // The last call, always below the log, opens in the viewer.
    expect(find.text('Last aityx call'), findsOneWidget);
    await tester.tap(find.textContaining('Call 2: the score of round 1, in '));
    await tester.pumpAndSettle();
    expect(find.text('aityx call 2: the score of round 1'), findsOneWidget);
    c.dispose();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a scored round announces its winner, and the log is striped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi());
    await tester.pumpWidget(RoboRulesApp(controller: c));
    c.start();
    for (var i = 0; i < 100 && c.roundWinner == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // The fake scores r1 the winner, with 160 points.
    final winner = c.roundWinner!;
    expect(winner.round, 1);
    expect(winner.robot, 0);
    expect(winner.points, 160);
    final name = c.robots[0].name;
    await tester.pump();
    expect(find.text('$name wins round 1!'), findsOneWidget);
    expect(find.text('160 points'), findsOneWidget);
    expect(
      c.events.map((e) => e.text),
      contains('$name wins round 1, with 160 points'),
    );
    // Announced for a while, then the next round begins without it.
    expect(c.state, BattleState.scoring);
    await tester.pump(c.announceFor + const Duration(milliseconds: 100));
    expect(c.round, 2);
    expect(c.roundWinner, isNull);
    await tester.pump();
    expect(find.text('$name wins round 1!'), findsNothing);

    // Each line of the log on the other shade from the next.
    Color? stripe(String text) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Material))
              .first,
        )
        .color;
    final lines = c.events.map((e) => e.text).toList();
    // The two newest lines, in view at the bottom.
    final a = lines.length - 2;
    expect(stripe(lines[a]), eventStripes[a % 2]);
    expect(stripe(lines[a + 1]), eventStripes[(a + 1) % 2]);
    expect(stripe(lines[a]), isNot(stripe(lines[a + 1])));
    c.dispose();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a robot downloads from its rules, and uploads back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final files = FakeFiles();
    final c = battle(FakeApi());
    await tester.pumpWidget(RoboRulesApp(controller: c, files: files));
    final first = c.robots[0];

    Future<void> menu(String item) async {
      await tester.tap(find.text('Robot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    // The Robot menu holds only what is about the whole battle.
    await tester.tap(find.text('Robot'));
    await tester.pumpAndSettle();
    expect(find.text('Download ${first.name}'), findsNothing);
    expect(find.textContaining('Remove ${first.name}'), findsNothing);
    await tester.tapAt(const Offset(700, 600));
    await tester.pumpAndSettle();

    // A robot's rules download it.
    await tester.tap(find.text(first.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(files.saved.keys, [robotFileName(first.name)]);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await menu('Download all robots');
    expect(files.saved[allRobotsFileName], robotsFile(c.robots));

    // Upload them back, with a file that isn't a robot.
    files.toPick = [
      PickedFile('mine.json', text: files.saved[robotFileName(first.name)]),
      const PickedFile('notes.json', text: 'hello'),
      const PickedFile('huge.json', error: 'larger than 1 MB'),
    ];
    await menu('Upload robots…');
    expect(c.robots, hasLength(3));
    expect(c.robots.last.name, '${first.name} 2');
    expect(
      jsonEncode(c.robots.last.rules.map((r) => r.why).toList()),
      jsonEncode(first.rules.map((r) => r.why).toList()),
    );
    expect(find.text('Uploaded ${first.name} 2'), findsOneWidget);
    expect(
      find.textContaining('notes.json: not a robot: not JSON'),
      findsOneWidget,
    );
    expect(find.textContaining('huge.json: larger than 1 MB'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // The panel's Upload button: the whole battle file, up to ten robots.
    files.toPick = [
      PickedFile(
        'all.json',
        text: robotsFile([...c.robots, ...c.robots, ...c.robots]),
      ),
    ];
    await tester.tap(find.text('Upload robots…').last);
    await tester.pumpAndSettle();
    expect(c.robots, hasLength(maxRobots));
    expect(
      find.textContaining('at most $maxRobots robots; 2 left out'),
      findsOneWidget,
    );
    c.dispose();
  });

  testWidgets("a robot's rules remove it, between battles only", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi())
      ..addRobot(
        Robot(name: 'Extra', color: const Color(0xFF123456), rules: [Rule()]),
      );
    await tester.pumpWidget(RoboRulesApp(controller: c, files: FakeFiles()));
    await tester.tap(find.text('Extra').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(c.robots.map((r) => r.name), isNot(contains('Extra')));
    expect(find.text('Rules of Extra'), findsNothing);

    // During a battle, the rules have no Remove.
    c.start();
    await tester.pump();
    await tester.tap(find.text(c.robots.first.name).last);
    await tester.pumpAndSettle();
    expect(find.text('Rules of ${c.robots.first.name}'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    c.dispose();
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a battle starts slow and speeds up as it plays', (tester) async {
    // aityx never answers: the battle plays on, waiting for turns.
    final api = FakeApi()..hold = Completer<void>();
    final c = battle(api)
      ..turnsPerSecond = 10
      ..speedUpEvery = const Duration(seconds: 1);
    expect(c.pace, 10);
    c.start();
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.pace, 10);
    await tester.pump(const Duration(milliseconds: 600));
    expect(c.pace, 15);
    // Paused, it doesn't speed up.
    c.pause();
    await tester.pump(const Duration(seconds: 3));
    expect(c.pace, 15);
    c.resume();
    await tester.pump(const Duration(seconds: 10));
    expect(c.pace, 40, reason: 'no faster than speedUpTo');
    // Choosing a speed starts again from it; Max stays Max.
    c.setSpeed(20);
    expect(c.pace, 20);
    c.setSpeed(0);
    await tester.pump(const Duration(seconds: 2));
    expect(c.pace, 0);
    // A new battle starts again from the choice.
    c.setSpeed(5);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(c.pace, 10);
    api.hold = Completer<void>();
    c.start();
    expect(c.pace, 5);
    c.dispose();
    expect(BattleController().turnsPerSecond, 10);
  });

  testWidgets('a shot is its own event, in a red tone', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c =
        BattleController(
            api: ScriptedApi([
              turn(1, [bot('r1', 100, 300), bot('r2', 300, 300)]),
              turn(2, [bot('r1', 100, 300, fired: 2.5), bot('r2', 300, 300)]),
              turn(3, [bot('r1', 100, 300), bot('r2', 300, 300, fired: 3)]),
              turn(4, [bot('r1', 100, 300), bot('r2', 300, 300, energy: 0)]),
            ]),
            factory: RobotFactory(Random(1)),
          )
          ..randomRobots(2)
          ..rounds = 1
          ..turnsPerSecond = 0;
    await tester.pumpWidget(RoboRulesApp(controller: c, files: FakeFiles()));
    c.start();
    for (var i = 0; i < 200 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final shots = c.events.where((e) => e.isShot).map((e) => e.text).toList();
    expect(shots, [
      'Turn 2 · ${c.robots[0].name} fires a shot of power 2.5',
      'Turn 3 · ${c.robots[1].name} fires a shot of power 3',
    ]);
    Material row(String text) => tester.widget<Material>(
      find.ancestor(of: find.text(text), matching: find.byType(Material)).first,
    );
    expect(row(shots.last).color, shotBackground);
    expect(tester.widget<Text>(find.text(shots.last)).style?.color, shotText);
    // Every other line keeps its stripe.
    final lost = c.events.lastWhere((e) => e.text.endsWith('is lost')).text;
    expect(row(lost).color, isIn(eventStripes));
    c.dispose();
  });

  testWidgets('any event opens like the aityx call button, with its call', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = battle(FakeApi())..rounds = 1;
    await tester.pumpWidget(RoboRulesApp(controller: c));
    c.start();
    for (var i = 0; i < 400 && c.state != BattleState.over; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    Future<void> close() async {
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    }

    // The last aityx call (the aityx call button, Help): in the viewer.
    await tester.tap(find.text('Help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View the last aityx call…'));
    await tester.pumpAndSettle();
    expect(find.text('The last aityx call'), findsOneWidget);
    expect(find.byType(AityxCallView), findsOneWidget);
    await close();

    // A turn's event: the same viewer, with the call that played the turn.
    final lost = 'Turn 10 · ${c.robots[1].name} is lost';
    final line = find.text(lost);
    expect(
      tester
          .widget<InkWell>(
            find.ancestor(of: line, matching: find.byType(InkWell)),
          )
          .onTap,
      isNotNull,
    );
    await tester.tap(line);
    await tester.pumpAndSettle();
    expect(find.text('aityx call 1: turns 1–20 of round 1'), findsOneWidget);
    expect(
      find.text(lost),
      findsNWidgets(2),
    ); // the log's line and the dialog's
    expect(find.byType(AityxCallView), findsOneWidget);
    await close();

    // The app's own lines open too, and say no call is behind them.
    // The oldest lines, scrolled up to in the log.
    await tester.scrollUntilVisible(
      find.text('Round 1 begins'),
      50,
      scrollable: find.descendant(
        of: find.byWidgetPredicate((w) => w is ListView && w.reverse),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Round 1 begins'));
    await tester.pumpAndSettle();
    expect(find.text('A battle event'), findsOneWidget);
    expect(find.textContaining('no aityx call is behind it'), findsOneWidget);
    expect(find.byType(AityxCallView), findsNothing);
    await close();
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

  group('sounds', () {
    Future<BattleController> play(FakeSounds sounds, {bool fast = true}) async {
      final c =
          BattleController(
              api: ScriptedApi(collisions),
              factory: RobotFactory(Random(1)),
              sounds: sounds,
            )
            ..randomRobots(2)
            ..rounds = 1
            ..turnsPerSecond = 0;
      if (fast) c.soundGap = Duration.zero;
      return c;
    }

    Future<void> finish(WidgetTester tester, BattleController c) async {
      c.start();
      for (var i = 0; i < 200 && c.state != BattleState.over; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(c.state, BattleState.over);
      c.dispose();
    }

    testWidgets('a wall, a hit, a ram and a robot lost each sound', (
      tester,
    ) async {
      final sounds = FakeSounds();
      final c = await play(sounds);
      expect(c.soundOn, isTrue);
      await finish(tester, c);
      // The robot lost drowns out its own hit.
      expect(sounds.played, [
        BattleSound.collision,
        BattleSound.hit,
        BattleSound.collision,
        BattleSound.loss,
      ]);
    });

    testWidgets('a kind sounds at most once in a short while', (tester) async {
      final sounds = FakeSounds();
      final c = await play(sounds, fast: false);
      await finish(tester, c);
      // Turns shown faster than 100 ms apart: one thud for two collisions.
      expect(sounds.played, [
        BattleSound.collision,
        BattleSound.hit,
        BattleSound.loss,
      ]);
    });

    testWidgets('turned off, the battle is silent, and stays off', (
      tester,
    ) async {
      final sounds = FakeSounds();
      final c = await play(sounds);
      c.setSound(false);
      expect(c.soundOn, isFalse);
      expect(sounds.saved, isFalse);
      await finish(tester, c);
      expect(sounds.played, isEmpty);

      // The next visit starts as the user left it.
      final again = await play(sounds);
      expect(again.soundOn, isFalse);
      again.setSound(true);
      expect(sounds.saved, isTrue);
      await finish(tester, again);
      expect(sounds.played, hasLength(4));
    });

    testWidgets('the Options menu and the Sound button turn it off', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await play(FakeSounds());
      await tester.pumpWidget(RoboRulesApp(controller: c));
      await tester.tap(find.text('Sound on'));
      await tester.pump();
      expect(c.soundOn, isFalse);
      expect(find.text('Sound off'), findsOneWidget);

      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sound: off (turn it on)'));
      await tester.pumpAndSettle();
      expect(c.soundOn, isTrue);
      expect(find.text('Sound on'), findsOneWidget);
      c.dispose();
    });
  });
}

/// Downloads kept by name; uploads from [toPick].
class FakeFiles extends Files {
  final saved = <String, String>{};
  List<PickedFile> toPick = const [];

  @override
  void save(String name, String text) => saved[name] = text;

  @override
  Future<List<PickedFile>> pick() async => toPick;
}
