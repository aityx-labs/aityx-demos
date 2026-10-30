import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cellfie_app/calls/calls_panel.dart';
import 'package:cellfie_app/life/board.dart';
import 'package:cellfie_app/life/generation.dart';
import 'package:cellfie_app/main.dart';

/// Answers as aityx would, with Conway's rules run here and a catalogue
/// of three patterns, and keeps what it was asked.
class FakeStepper implements GenerationStepper {
  final asked = <Map<String, Object?>>[];
  Object? failWith;

  /// Fails as when there's no aityx key.
  bool noKey = false;
  Completer<void>? waitOn;
  bool killNext = false;

  static final catalogue = {
    canonicalShape(cellsOf('oo/oo')): ('block', 'still_life'),
    canonicalShape(cellsOf('ooo')): ('blinker', 'oscillator'),
    canonicalShape(cellsOf('.o./..o/ooo')): ('glider', 'spaceship'),
  };

  @override
  Future<GenerationOutcome> step(
    int generation,
    Map<String, bool> rules,
    Map<SituationKey, List<Cell>> situations,
    List<Cluster> clusters,
  ) async {
    final body = generationBody(generation, rules, situations, clusters);
    asked.add(body);
    if (failWith case final String message) {
      throw GenerationException(message, noKey: noKey);
    }
    if (waitOn case final wait?) await wait.future;
    final fates = [
      for (final key in situations.keys)
        if (killNext)
          key.alive ? 'dies_crowded' : 'stays_empty'
        else
          switch ((key.alive, key.neighbours)) {
            (true, < 2) => 'dies_lonely',
            (true, 2 || 3) => 'survives',
            (true, _) => 'dies_crowded',
            (false, 3) => 'is_born',
            _ => 'stays_empty',
          },
    ];
    int cellsWhere(bool Function(int) test) {
      var n = 0;
      var i = 0;
      for (final cells in situations.values) {
        if (test(i++)) n += cells.length;
      }
      return n;
    }

    final population = cellsWhere((i) => situations.keys.elementAt(i).alive);
    final survivors = cellsWhere((i) => fates[i] == 'survives');
    final births = cellsWhere((i) => fates[i] == 'is_born');
    return GenerationOutcome(
      Generation.fromJson({
        'generation': generation,
        'next_generation': generation + 1,
        'population': population,
        'population_next': survivors + births,
        'births': births,
        'deaths': population - survivors,
        'survivors': survivors,
        'situations': [
          for (final (i, key) in situations.keys.indexed)
            {
              'alive': key.alive,
              'neighbours': key.neighbours,
              'cells': situations[key]!.length,
              'fate': fates[i],
              'alive_next': fates[i] == 'survives' || fates[i] == 'is_born',
              'rule': 1,
              'why': 'because',
            },
        ],
        'clusters': [
          for (final c in clusters)
            {
              ...c.toJson(),
              'pattern': catalogue[c.shape]?.$1 ?? 'unknown',
              'kind': catalogue[c.shape]?.$2 ?? 'unknown',
              'about': catalogue.containsKey(c.shape)
                  ? 'A known pattern.'
                  : null,
            },
        ],
        'recognized': clusters
            .where((c) => catalogue.containsKey(c.shape))
            .length,
      }),
      aityxRequest: {
        'decision': {'name': 'Life'},
        'state': body,
      },
      aityxResponse: {'answers': {}},
      tookMs: 7,
      inputTokens: 100,
    );
  }
}

void main() {
  testWidgets('opens on the board with a sparse soup, ready to play', (
    tester,
  ) async {
    await tester.pumpWidget(CellfieApp(stepper: FakeStepper()));
    await tester.pump();

    expect(find.byType(LifeScreen), findsOneWidget);
    expect(find.text('Cellfie'), findsOneWidget);
    expect(find.byType(BoardView), findsOneWidget);
    // 800 px leaves no room for the labels: the buttons are icons.
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Acceleration'), findsOneWidget);
    expect(find.byTooltip('Zoom in'), findsOneWidget);
    expect(find.byTooltip('Zoom out'), findsOneWidget);
    expect(find.byTooltip('Back to the origin'), findsOneWidget);
    // No calls panel at 800 px: the status is over the board.
    final status = find.textContaining(RegExp(r'Generation 0 · \d+ cells'));
    expect(status, findsOneWidget);
    final cells = int.parse(
      RegExp(r'(\d+) cells').firstMatch(tester.widget<Text>(status).data!)![1]!,
    );
    expect(cells, greaterThan(0));
    expect(find.textContaining('Press Random start'), findsNothing);
    // A test build has no CELLFIE_VERSION, so no X.Y.Z shows.
    expect(find.textContaining(RegExp(r'^\d+\.\d+\.\d+$')), findsNothing);
  });

  testWidgets('a random start fills the view, and Clear empties it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: LifeScreen(
          stepper: FakeStepper(),
          random: Random(3),
          start: null,
        ),
      ),
    );

    await tester.tap(find.text('Random start'));
    await tester.pumpAndSettle();
    expect(find.text('Glider fleet'), findsOneWidget);
    await tester.tap(find.text('Soup'));
    await tester.pumpAndSettle();
    final status = find.textContaining(RegExp(r'Generation 0 · \d+ cells'));
    expect(status, findsOneWidget);
    final cells = int.parse(
      RegExp(r'(\d+) cells').firstMatch(tester.widget<Text>(status).data!)![1]!,
    );
    expect(cells, greaterThan(100));
    expect(find.textContaining('Press Random start'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.textContaining('Generation 0 · 0 cells'), findsOneWidget);
    expect(find.textContaining('Press Random start'), findsOneWidget);
  });

  testWidgets('Step asks for one generation and shows the call', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );

    // Draw a blinker at the origin by tapping three cells: the view is
    // centered on the origin at 14 px a cell.
    final view = tester.getRect(find.byType(BoardView));
    for (final x in [-1, 0, 1]) {
      await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
    }
    await tester.pump();
    expect(find.textContaining('Generation 0 · 3 cells'), findsOneWidget);

    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.pump();
    expect(stepper.asked, hasLength(1));
    final body = stepper.asked.single;
    expect(body['generation'], 0);
    expect(body['rules'], {
      'conway': true,
      'highlife': false,
      'no_death': false,
    });
    expect((body['situations'] as List), hasLength(5));
    expect((body['clusters'] as List).single, {
      'cells': 3,
      'width': 1,
      'height': 3,
      'shape': 'o/o/o',
    });
    // The blinker turned, still 3 cells, and the panel shows the call.
    expect(find.textContaining('Generation 1 · 3 cells'), findsOneWidget);
    expect(find.text('Generation 0 → 1'), findsOneWidget);
    expect(find.text('+2 born'), findsOneWidget);
    expect(find.text('−2 died'), findsOneWidget);
    expect(find.text('blinker'), findsWidgets);
    final label = tester
        .widget<BoardView>(find.byType(BoardView))
        .labels
        .single;
    expect(label.cluster.width, 1);
    expect(label.cluster.height, 3);
    // A blinker appeared: a notice on the board and in the panel.
    // Over the board, and in the panel.
    expect(
      find.textContaining('Generation 0: A blinker appeared'),
      findsNWidgets(2),
    );
    expect(find.text('Patterns noticed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('a reset discards an in-flight generation response', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper()..waitOn = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    for (final x in [-1, 0, 1]) {
      await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
    }
    await tester.pump();

    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.textContaining('Generation 0 · 0 cells'), findsOneWidget);
    expect(find.textContaining('Press Random start'), findsOneWidget);

    stepper.waitOn!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Generation 0 · 0 cells'), findsOneWidget);
    expect(find.byType(CallCard), findsNothing);
  });

  testWidgets('restarting a generation keeps call cards uniquely keyed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));

    Future<void> drawAndStep() async {
      for (final x in [-1, 0, 1]) {
        await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
      }
      await tester.pump();
      await tester.tap(find.text('Step'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Clear'));
      await tester.pump();
    }

    await drawAndStep();
    await drawAndStep();
    expect(find.text('Generation 0 → 1'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    final cards = tester.widgetList<CallCard>(find.byType(CallCard)).toList();
    expect(cards.map((card) => card.call.id).toSet(), hasLength(2));
  });

  testWidgets('patterns that die are not labeled on the next board', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper()..killNext = true;
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    for (final x in [-1, 0, 1]) {
      await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
    }
    await tester.pump();

    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<BoardView>(find.byType(BoardView)).labels, isEmpty);
  });

  testWidgets('tapping a pattern noticed opens the call that noticed it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    for (final x in [-1, 0, 1]) {
      await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
    }
    await tester.pump();
    // Three generations: the blinker is noticed at the first, and the
    // newest call is on top.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Step'));
      await tester.pump();
      await tester.pump();
    }
    expect(find.text('Generation 2 → 3'), findsOneWidget);
    expect(find.text('What aityx decided'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(CallsPanel),
        matching: find.textContaining('A blinker appeared'),
      ),
    );
    await tester.pumpAndSettle();
    // The first call's card is open, and only it.
    expect(find.text('What aityx decided'), findsOneWidget);
    final card = find.ancestor(
      of: find.text('Generation 0 → 1'),
      matching: find.byType(CallCard),
    );
    expect(tester.widget<CallCard>(card).expanded, isTrue);
    expect(tester.widget<CallCard>(card).marked, isTrue);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('Play runs generations at the acceleration until paused', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    for (final x in [-1, 0, 1]) {
      await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
    }
    await tester.pump();

    // 1 generation/s by default: one every second.
    expect(find.text('1 generation/s'), findsOneWidget);
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(stepper.asked.length, inInclusiveRange(2, 3));

    await tester.tap(find.text('Pause'));
    await tester.pump();
    final asked = stepper.asked.length;
    await tester.pump(const Duration(seconds: 2));
    expect(stepper.asked.length, asked);
    expect(find.text('Play'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('play waits for a pending manual step at maximum acceleration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper()..waitOn = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    for (final x in [-1, 0, 1]) {
      await tester.tapAt(view.center + Offset(x * 14.0 + 7, 7));
    }
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(5);
    await tester.pump();

    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    stepper.waitOn!.complete();
    await tester.pump();
    await tester.pump();
    expect(stepper.asked, hasLength(1));
  });

  testWidgets('the Rules dialog switches rules for the next generation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper();
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    await tester.tapAt(view.center + const Offset(7, 7));
    await tester.pump();

    expect(find.text('Rules (1 of 3)'), findsOneWidget);
    await tester.tap(find.text('Rules (1 of 3)'));
    await tester.pumpAndSettle();
    expect(find.text('Conway\'s rules'), findsOneWidget);
    await tester.tap(find.text('Life without death'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Rules (2 of 3)'), findsOneWidget);

    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.pump();
    expect(stepper.asked.single['rules'], {
      'conway': true,
      'highlife': false,
      'no_death': true,
    });
  });

  testWidgets('a failed generation pauses and says why', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper()
      ..failWith = 'Could not run the generation: aityx did not answer.';
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    await tester.tapAt(view.center + const Offset(7, 7));
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Could not run the generation: aityx did not answer.'),
      findsOneWidget,
    );
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Set your key'), findsNothing);
  });

  testWidgets('without a key, the notice offers to set it', (tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stepper = FakeStepper()
      ..failWith = 'aityx is not set up: set your key on the index page.'
      ..noKey = true;
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: stepper, start: null)),
    );
    final view = tester.getRect(find.byType(BoardView));
    await tester.tapAt(view.center + const Offset(7, 7));
    await tester.pump();

    await tester.tap(find.text('Step'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('aityx is not set up: set your key on the index page.'),
      findsOneWidget,
    );
    expect(find.text('Set your key'), findsOneWidget);
  });

  testWidgets('on a phone the calls open from the app bar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: LifeScreen(stepper: FakeStepper())),
    );

    expect(find.byType(CallsPanel), findsNothing);
    expect(find.byTooltip('Random start'), findsOneWidget);
    expect(find.textContaining(RegExp(r'Generation 0 · \d+ cells')), findsOneWidget);
    await tester.tap(find.byTooltip('Calls (0)'));
    await tester.pumpAndSettle();
    expect(find.byType(CallsPanel), findsOneWidget);
    expect(find.textContaining('Every generation is one call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
