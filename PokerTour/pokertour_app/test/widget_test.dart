import 'dart:math';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokertour_app/api/poker_api.dart';
import 'package:poker_core/engine/game.dart';
import 'package:pokertour_app/game/controller.dart';
import 'package:pokertour_app/main.dart';
import 'package:pokertour_app/table/chips.dart';

/// Two presets, and a decision that always calls.
class FakeApi implements PokerApi {
  int acts = 0;
  Map<String, Object?>? lastSituation;
  Object? lastStrategy;

  @override
  Future<List<Strategy>> strategies() async => const [
    Strategy(
      id: 'rock',
      name: 'The Rock',
      tagline: 'Tight.',
      decisions: {
        'action': {
          'type': 'Action',
          'table': [
            ['hand', 'can_check', '=>', '# why'],
            {
              'when': {'hand': 'premium'},
              'then': 'raise',
              'why': 'Premium.',
            },
            {'then': 'call', 'why': 'Calls.'},
          ],
        },
        'raise_to': {'type': 'number', 'expr': '3 * big_blind'},
      },
    ),
    Strategy(
      id: 'maniac',
      name: 'The Maniac',
      tagline: 'Loose.',
      decisions: {'action': {}, 'raise_to': {}},
    ),
  ];

  @override
  Future<ActResult> act(
    Strategy strategy,
    Map<String, Object?> situation,
  ) async {
    acts++;
    lastSituation = situation;
    lastStrategy = strategy.toRequest();
    return ActResult(
      kind: ActionKind.call,
      raiseTo: 0,
      rule: 2,
      why: 'Calls.',
      request: {'decision': {}, 'state': situation},
      response: {
        'answers': {
          'action': {'choice': 'call'},
        },
      },
      tookMs: 3,
    );
  }
}

void main() {
  testWidgets('seats one player per strategy and shows the table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    await tester.pumpWidget(PokerTourApp(api: api));
    await tester.pumpAndSettle();

    expect(find.text('Poker Tour'), findsOneWidget);
    expect(find.text('Rocky'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('Press play to deal.'), findsOneWidget);
    expect(find.text('aityx calls (0)'), findsOneWidget);
    // The aityx light, top right; with no key in the test (no browser
    // storage, no dev proxy), red and saying where to set one.
    expect(find.byType(AityxStatusLight), findsOneWidget);
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('aityx: no key')), findsOneWidget);
  });

  testWidgets('a step deals, the next asks aityx and plays the answer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    await tester.pumpWidget(PokerTourApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hand #1 · Preflop'), findsOneWidget);
    expect(find.byType(ChipPile), findsWidgets); // the pot, as chips
    expect(find.text('15'), findsWidgets);

    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    expect(api.acts, 1);
    expect(api.lastStrategy, isA<String>());
    expect(api.lastSituation?['street'], 'preflop');
    expect(find.text('aityx calls (1)'), findsOneWidget);
    // Heads up, the button posts the small blind and calls 5 more.
    expect(find.text('Calls 5'), findsWidgets);
    expect(find.text('Calls.'), findsOneWidget);
  });

  testWidgets('players can be added with a strategy', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(PokerTourApp(api: FakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Players (2)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-player-name')), 'Zed');
    await tester.tap(find.byKey(const Key('add-player')));
    await tester.pumpAndSettle();
    expect(find.text('Zed'), findsWidgets);
    expect(find.textContaining('Players (3)'), findsOneWidget);
  });

  testWidgets('the title starts a new tournament among random strategies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(PokerTourApp(api: FakeApi()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hand #1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('title')));
    await tester.pumpAndSettle();
    // Two strategies: both seated again, and the hand gone.
    expect(find.textContaining('Players (2)'), findsOneWidget);
    expect(find.text('Rocky'), findsOneWidget);
    expect(find.text('Max'), findsOneWidget);
    expect(find.text('Press play to deal.'), findsOneWidget);
  });

  test('a random tournament seats three to nine strategies, none twice', () async {
    final c = GameController(api: FakeApi(), random: Random(7));
    await c.load();
    for (var i = 0; i < 10; i++) {
      c.saveCustom('{"name": "Mine $i", "decisions": {"action": {}, "raise_to": {}}}');
    }
    final counts = <int>{};
    for (var i = 0; i < 40; i++) {
      c.randomTournament();
      final ids = [for (final s in c.game.seats) s.strategyId];
      expect(ids.toSet().length, ids.length);
      expect(ids.length, inInclusiveRange(3, 9));
      expect(c.game.seats.map((s) => s.name).toSet().length, ids.length);
      counts.add(ids.length);
    }
    expect(counts.length, greaterThan(1));
  });

  test('a strategy is parsed from the editor, or refused with a reason', () {
    final s = Strategy.parse(
      '{"name": "Mine", "decisions": {"action": {"expr": "\\"call\\""}, "raise_to": {"expr": "min_raise"}}}',
      id: 'custom-1',
    );
    expect(s.name, 'Mine');
    expect(s.custom, isTrue);
    expect(s.toRequest(), isA<Map>());
    expect(() => Strategy.parse('nope', id: 'x'), throwsFormatException);
    expect(
      () =>
          Strategy.parse('{"name": "x", "decisions": {"action": {}}}', id: 'x'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('raise_to'),
        ),
      ),
    );
    final c = GameController(api: FakeApi());
    final saved = c.saveCustom(s.toEditable());
    expect(saved.id, 'custom-1');
    expect(c.strategies, contains(saved));
  });

  testWidgets('tapping a seat shows its rules; a change becomes its own', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    await tester.pumpWidget(PokerTourApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('seat-1')));
    await tester.pumpAndSettle();
    expect(find.text('Rocky · The Rock'), findsOneWidget);
    // The fake preset's table: a rule and an else row.
    expect(find.byKey(const Key('remove-rule-0')), findsOneWidget);
    expect(find.byKey(const Key('remove-rule-1')), findsOneWidget);
    expect(find.byKey(const Key('remove-rule-2')), findsNothing);

    // Add a rule, remove the first, save: Rocky plays its own rules now.
    await tester.enterText(
      find.byKey(const Key('condition-value-0')),
      'premium',
    );
    await tester.enterText(find.byKey(const Key('new-rule-why')), 'Aces!');
    await tester.tap(find.byKey(const Key('add-rule')));
    await tester.pumpAndSettle();
    expect(find.text('Aces!'), findsOneWidget);
    expect(find.byKey(const Key('remove-rule-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-rule-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('remove-rule-2')), findsNothing);
    await tester.tap(find.byKey(const Key('save-rules')));
    await tester.pumpAndSettle();
    expect(find.text("Rocky's Rock"), findsWidgets);

    // The next decision is asked with the player's own rules.
    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    expect(api.lastStrategy, isA<Map>());
    final sent = api.lastStrategy as Map;
    expect(sent['name'], "Rocky's Rock");
    final table = (sent['decisions'] as Map)['action']['table'] as List;
    expect(table, hasLength(3)); // header, the new rule, the else row
    expect((table[1] as Map)['why'], 'Aces!');
  });

  testWidgets('a log entry expands into the rule and the situation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(PokerTourApp(api: FakeApi()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Hand log'));
    await tester.pumpAndSettle();
    expect(find.text('The situation'), findsNothing);
    await tester.tap(find.textContaining('calls 5.'));
    await tester.pumpAndSettle();
    expect(find.text('The situation'), findsOneWidget);
    expect(find.text('Calls.'), findsOneWidget);
    expect(find.textContaining('The Rock, rule 2'), findsOneWidget);
    expect(find.text('The whole call'), findsOneWidget);
  });

  testWidgets('the tournament ends with a winner', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeApi();
    final game = PokerGame(random: Random(1), equitySamples: 10);
    final controller = GameController(api: api, game: game);
    await tester.pumpWidget(
      MaterialApp(home: TableScreen(controller: controller)),
    );
    await tester.pumpAndSettle();
    // Everyone else is broke: the next step ends the tournament.
    for (final s in game.seats.skip(1)) {
      game.seats.first.stack += s.stack;
      s.stack = 0;
      s.status = SeatStatus.out;
      s.place = 2;
    }
    await tester.tap(find.byKey(const Key('step')));
    await tester.pumpAndSettle();
    expect(find.text('🏆 Tournament over'), findsOneWidget);
    expect(find.text('Rocky wins'), findsOneWidget);
    expect(
      find.textContaining('The winning strategy: The Rock'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('new-tournament')));
    await tester.pumpAndSettle();
    expect(game.over, isFalse);
    expect(game.seats.every((s) => s.stack == 1000), isTrue);
  });
}
