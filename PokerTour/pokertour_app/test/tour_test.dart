import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:poker_core/table.dart';
import 'package:pokertour_app/auth/auth_controller.dart';
import 'package:pokertour_app/main.dart';
import 'package:pokertour_app/tour/enter.dart';
import 'package:pokertour_app/tour/leaderboard_panel.dart' show timeLeft;
import 'package:pokertour_app/tour/tour_api.dart';

const _config = {
  'auth': {'enabled': false, 'issuer': 'https://accounts.google.com', 'clientId': null},
  'domains': ['aletyx.com', 'aletyx.ai'],
  'aityxUrl': 'https://api.aityx.ai',
};

const _board = {
  'standings': [
    {'id': 'u-1', 'name': 'Ana One', 'tagline': 'Mine', 'owner': 'Ana', 'ownerId': 'abc', 'preset': false, 'tournaments': 3, 'wins': 2, 'points': 9, 'best': 1, 'last': 1},
    {'id': 'rock', 'name': 'The Rock', 'tagline': 'Tight', 'owner': 'the house', 'ownerId': 'house', 'preset': true, 'tournaments': 3, 'wins': 0, 'points': 4, 'best': 2, 'last': 3, 'broken': null},
  ],
  'current': {
    'number': 4,
    'hand': 12,
    'calls': 88,
    'seats': [
      {'name': 'Ana One', 'strategyId': 'u-1', 'stack': 3200, 'place': null},
      {'name': 'The Rock', 'strategyId': 'rock', 'stack': 0, 'place': 2},
    ],
  },
  'history': [
    {'number': 3, 'finished': '2026-11-06T10:00:00Z', 'places': [{'id': 'u-1', 'name': 'Ana One', 'place': 1}, {'id': 'rock', 'name': 'The Rock', 'place': 2}]},
  ],
  'runner': {'enabled': true, 'state': 'playing', 'detail': 'tournament #4, 2 players', 'hoursUtc': [0, 6, 12, 18], 'nextRunAt': '2026-11-07T18:00:00.000Z', 'queue': [{'source': 'strategy', 'at': '2026-11-07T13:00:00Z'}]},
};

void main() {
  test('the server\'s answers are read', () async {
    final api = HttpTourApi(
      base: Uri.parse('http://tour.test/pokertour/'),
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer tok');
        return switch (request.url.path) {
          '/api/config' => http.Response(jsonEncode(_config), 200),
          '/api/leaderboard' => http.Response(jsonEncode(_board), 200),
          '/api/me' => http.Response(jsonEncode({'email': 'ana@aletyx.com', 'ownerId': 'abc', 'name': 'Ana', 'admin': true}), 200),
          '/api/tournaments' when request.method == 'POST' => http.Response('{"status":"queued"}', 202),
          '/api/strategies' => http.Response(jsonEncode({'strategies': [
            {'id': 'u-1', 'name': 'Ana One', 'tagline': 'Mine', 'decisions': {'action': {'expr': '"call"'}, 'raise_to': {'expr': 'min_raise'}}, 'owner': 'Ana', 'ownerId': 'abc', 'preset': false},
            {'id': 'rock', 'name': 'The Rock', 'tagline': 'Tight', 'decisions': {'action': {'expr': '"fold"'}, 'raise_to': {'expr': 'min_raise'}}, 'owner': 'the house', 'ownerId': 'house', 'preset': true},
          ]}), 200),
          _ => http.Response('{"error":"nope"}', 404),
        };
      }),
      token: () async => 'tok',
    );
    final config = await api.config();
    expect(config.auth.enabled, isFalse);
    expect(config.domains, ['aletyx.com', 'aletyx.ai']);
    final board = await api.leaderboard();
    expect(board.standings.first.name, 'Ana One');
    expect(board.standings.first.points, 9);
    expect(board.current?.hand, 12);
    expect(board.current?.seats.last.place, 2);
    expect(board.history.single.places.first.name, 'Ana One');
    expect(board.runnerState, 'playing');
    expect(board.nextRunAt, DateTime.utc(2026, 11, 7, 18));
    expect(board.hoursUtc, [0, 6, 12, 18]);
    expect(board.queue, ['strategy']);
    final strategies = await api.strategies();
    expect(strategies.map((t) => t.strategy.id), ['tour-u-1', 'tour-rock']);
    expect(strategies.first.strategy.custom, isTrue);
    expect(strategies.map((t) => t.preset), [false, true]);
    // The table takes the players' entries, not a second copy of a preset.
    final table = tableStrategies(strategies);
    expect(table.map((s) => s.id), ['tour-u-1']);
    expect(table.single.tagline, 'In the tour, by Ana. Mine');
    expect((await api.me()).admin, isTrue);
    expect(await api.startTournament(), 'queued');
    expect(() => api.withdraw('x'), throwsA(isA<TourException>().having((e) => e.message, 'message', 'nope')));
  });

  test('the time to the next tournament, for people', () {
    expect(timeLeft(const Duration(hours: 5, minutes: 2, seconds: 9)), '5 h 02 min');
    expect(timeLeft(const Duration(minutes: 12, seconds: 5)), '12 min 05 s');
    expect(timeLeft(const Duration(seconds: 45)), '45 s');
  });

  test('a strategy\'s file name', () {
    expect(strategyFileName(const Strategy(id: 'x', name: "Ana's Shark 2", tagline: '', decisions: {})), 'ana-s-shark-2.json');
    expect(strategyFileName(const Strategy(id: 'x', name: '!!', tagline: '', decisions: {})), 'strategy.json');
  });

  testWidgets('without a sign-in set up, the page says so and shows the standings', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = HttpTourApi(
      base: Uri.parse('http://tour.test/pokertour/'),
      client: MockClient((request) async => switch (request.url.path) {
        '/api/config' => http.Response(jsonEncode(_config), 200),
        '/api/leaderboard' => http.Response(jsonEncode(_board), 200),
        _ => http.Response('{"error":"nope"}', 404),
      }),
    );
    await tester.pumpWidget(PokerTourApp(tour: api, auth: AuthController()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Welcome to the Poker Tour'), findsOneWidget);
    expect(find.byKey(const Key('not-configured')), findsOneWidget);
    expect(find.byKey(const Key('standings')), findsOneWidget);
    expect(find.text('Ana One'), findsWidgets);
    expect(find.textContaining('tournament #4'), findsOneWidget);
    // The time to the next scheduled tournament (the fixture's is past).
    expect(find.byKey(const Key('countdown')), findsOneWidget);
    expect(find.textContaining('Next tournament any moment now'), findsOneWidget);
    // Wins, no points; no "latest tournaments"; a preset is a template strategy.
    expect(find.text('Points'), findsNothing);
    expect(find.textContaining('#3: 1. Ana One'), findsNothing);
    // The welcome page's leaderboard has the wins alone, and the welcome
    // with the sign-in is beside it, on the right.
    expect(find.text('Wins'), findsOneWidget);
    expect(find.text('Played'), findsNothing);
    expect(find.text('Best'), findsNothing);
    final board = tester.getRect(find.byKey(const Key('leaderboard-card')));
    final welcome = tester.getRect(find.byKey(const Key('welcome')));
    expect(welcome.left, greaterThan(board.right));
    expect(board.width, greaterThan(welcome.width));
    expect(find.byKey(const Key('owner-u-1')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('owner-rock'))).data, 'template strategy');
    expect(tester.widget<Text>(find.byKey(const Key('owner-u-1'))).data, 'Ana');
    // Nobody is signed in: no upload, no "now"; the table and its
    // controls show, seated with the presets, under a veil that takes
    // every click.
    expect(find.byKey(const Key('upload-strategy')), findsNothing);
    expect(find.byKey(const Key('run-now')), findsNothing);
    expect(find.byKey(const Key('table-preview')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-veil')), findsOneWidget);
    expect(find.text('Rocky'), findsOneWidget);
    expect(find.byKey(const Key('play')), findsOneWidget);
    expect(find.byKey(const Key('play')).hitTestable(), findsNothing);
    expect(find.byKey(const Key('step')).hitTestable(), findsNothing);
  });
}
