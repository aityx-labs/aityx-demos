import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:riverrace_app/game/race.dart';
import 'package:riverrace_app/main.dart';
import 'package:riverrace_app/strategy/decide.dart';

/// Stands in for aityx: every pilot does [action]; remembers the asks.
class FakeDecider implements Decider {
  FakeDecider({this.action = const PilotAction(rule: 1, why: 'Because.')});

  final PilotAction action;
  final asks = <List<PilotAsk>>[];
  String? fail;

  @override
  Future<Decision> decide(int tick, List<PilotAsk> pilots) async {
    asks.add(pilots);
    if (fail case final message?) throw DecideException(message);
    return Decision(
      tick,
      {for (final p in pilots) p.id: action},
      aityxRequest: {'state': {}},
      aityxResponse: {'answers': {}},
      tookMs: 42,
    );
  }
}

Future<void> pumpApp(WidgetTester tester, Decider decider) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RiverRaceApp(decider: decider, seed: 11));
}

/// Lets the race run for [frames] frames.
Future<void> run(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('starts paused, with both pilots and the player', (tester) async {
    await pumpApp(tester, FakeDecider());
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Press any key to play'), findsOneWidget);
    expect(find.text('Careful'), findsWidgets);
    expect(find.text('Daredevil'), findsWidgets);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('playing asks aityx for both pilots and shows the calls', (
    tester,
  ) async {
    final decider = FakeDecider();
    await pumpApp(tester, decider);
    await tester.tap(find.text('Start'));
    await run(tester, 30);
    expect(decider.asks, isNotEmpty);
    expect(decider.asks.first.map((p) => p.id), ['p1', 'p2']);
    expect(decider.asks.first.first.strategy.name, 'Careful');
    expect(decider.asks.first.first.sense.keys, contains('land_distance'));
    expect(find.text('Decision 1'), findsOneWidget);
    expect(find.textContaining('42 ms'), findsWidgets);
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });

  testWidgets('any key starts the race, and pauses with P', (tester) async {
    final decider = FakeDecider();
    await pumpApp(tester, decider);
    expect(find.text('Press any key to play'), findsOneWidget);
    // Even with a control focused (a chip just clicked), a key plays.
    await tester.tap(find.text('Fair race'));
    await tester.pump();
    // A shortcut's modifier alone doesn't start it.
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('Start'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await run(tester, 20);
    expect(find.text('Pause'), findsOneWidget);
    expect(decider.asks, isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(find.text('Press any key to go on.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });

  testWidgets('an aityx error is shown, and the race goes on', (tester) async {
    final decider = FakeDecider()..fail = 'aityx could not decide: no key.';
    await pumpApp(tester, decider);
    await tester.tap(find.text('Start'));
    await run(tester, 30);
    expect(find.text('aityx could not decide: no key.'), findsWidgets);
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });

  testWidgets('a rule can be removed and added', (tester) async {
    await pumpApp(tester, FakeDecider());
    final rules = find.byTooltip('Remove the rule');
    final before = tester.widgetList(rules).length;
    await tester.tap(rules.first);
    await tester.pump();
    expect(tester.widgetList(rules).length, before - 1);
    await tester.tap(find.text('Add rule').first);
    await tester.pumpAndSettle();
    expect(find.text('New rule'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.widgetList(rules).length, before);
  });

  testWidgets('a strategy can be swapped for another', (tester) async {
    await pumpApp(tester, FakeDecider());
    await tester.tap(find.text('Strategy').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rookie').last);
    await tester.pumpAndSettle();
    expect(find.text('Rookie'), findsWidgets);
    expect(find.text('Fly straight and keep firing.'), findsOneWidget);
  });

  testWidgets('a key held into a dialog stops counting', (tester) async {
    await pumpApp(tester, FakeDecider());
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await run(tester, 2);
    final race =
        (tester.state(find.byType(RaceScreen)) as dynamic).race as Race;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await run(tester, 3);
    expect(race.controls.left, isTrue);
    // A dialog opens over the race: the key, still held, stops counting,
    // and stays off once let go there.
    await tester.ensureVisible(find.text('Add rule').first);
    await tester.pump();
    await tester.tap(find.text('Add rule').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('New rule'), findsOneWidget);
    await run(tester, 3);
    expect(race.controls.left, isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await run(tester, 3);
    expect(race.controls.left, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
  });

  testWidgets('starts at half speed and speeds up every 30 seconds', (
    tester,
  ) async {
    await pumpApp(tester, FakeDecider());
    final screen = tester.state(find.byType(RaceScreen)) as dynamic;
    expect(screen.pace, 50);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await run(tester, 2);
    // Each pump is one long frame of play: the game time it makes is
    // capped, but every second counts towards the speed.
    await tester.pump(const Duration(seconds: 31));
    expect(screen.pace, 60);
    expect(find.text('now 0.6×'), findsOneWidget);
    await tester.pump(const Duration(seconds: 300));
    expect(screen.pace, 100);
    await tester.tap(find.byTooltip('Restart'));
    await tester.pump();
    expect(screen.pace, 50);
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });

  testWidgets('a late answer is dropped for a plane lost since', (
    tester,
  ) async {
    final decider = SlowDecider();
    await pumpApp(tester, decider);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    // At ½× speed, 16 frames reach the first aityx decision.
    await run(tester, 16);
    expect(decider.pending, isNotNull);
    final race =
        (tester.state(find.byType(RaceScreen)) as dynamic).race as Race;
    // Pilot 1 crashes and comes back before aityx answers.
    race.plane('p1').lost++;
    decider.answer(const PilotAction(steer: 'left', rule: 3));
    await tester.pump();
    expect(race.plane('p1').action.rule, isNot(3));
    expect(race.plane('p2').action.rule, 3);
    await tester.tap(find.text('Pause'));
    await tester.pump();
  });
}

/// Answers only when told to.
class SlowDecider implements Decider {
  Completer<Decision>? pending;
  int tick = 0;
  List<String> ids = const [];

  @override
  Future<Decision> decide(int tick, List<PilotAsk> pilots) {
    this.tick = tick;
    ids = [for (final p in pilots) p.id];
    return (pending = Completer<Decision>()).future;
  }

  void answer(PilotAction action) =>
      pending!.complete(Decision(tick, {for (final id in ids) id: action}));
}
