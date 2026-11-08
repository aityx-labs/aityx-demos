import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokertour_app/aityx/player_keys.dart';
import 'package:pokertour_app/auth/auth_controller.dart';
import 'package:pokertour_app/main.dart';
import 'package:pokertour_app/persist/session_store.dart';
import 'package:pokertour_app/persist/storage_area.dart';
import 'package:pokertour_app/tour/files.dart' show filesSupported;
import 'package:pokertour_app/tour/tour_api.dart';
import 'package:pokertour_app/tour/tour_session.dart';

const staging = 'https://api-stage.aityx.ai';
const production = 'https://api.aityx.ai';

/// Signed in as [email], without Google.
class FakeAuth extends AuthController {
  FakeAuth(this.email) : super(store: SessionStore.memory());

  String? email;

  @override
  SignedInUser? get user => email == null ? null : SignedInUser(email: email!, name: 'Ana');

  @override
  bool get ready => true;

  @override
  Future<void> start(AuthConfig config) async {}

  @override
  Future<String?> token() async => email == null ? null : 'id-token';

  @override
  Future<void> signOut() async {
    email = null;
    notifyListeners();
  }
}

PlayerKeys memoryKeys() => PlayerKeys(local: memoryArea(), session: memoryArea());

/// The server ([aityxUrl] as this environment's aityx; Ana's alias, her
/// strategy and Bo's, which she can remove and set) and aityx, which
/// takes "good" and rejects anything else.
http.Client world({String aityxUrl = staging}) {
  String? alias;
  final strategies = [
    {'id': 'u-1', 'name': 'Ana One', 'tagline': 'Mine', 'decisions': {'action': {'expr': '"call"'}, 'raise_to': {'expr': 'min_raise'}}, 'owner': 'Ana', 'ownerId': 'abc', 'preset': false},
    {'id': 'u-2', 'name': 'Bo One', 'tagline': 'His', 'decisions': {'action': {'expr': '"fold"'}, 'raise_to': {'expr': 'min_raise'}}, 'owner': 'Bo', 'ownerId': 'bo', 'preset': false},
  ];
  Map<String, Object?> me() => {'email': 'ana@aletyx.com', 'ownerId': 'abc', 'name': 'Ana', 'alias': alias, 'admin': true};
  return MockClient((request) async {
  final path = request.url.path;
  if (request.method == 'PUT' && path == '/api/me') {
    final given = (jsonDecode(request.body) as Map)['alias'] as String;
    alias = given.trim().isEmpty ? null : given.trim();
    return http.Response(jsonEncode(me()), 200);
  }
  if (request.method == 'DELETE' && path.startsWith('/api/strategies/')) {
    strategies.removeWhere((x) => x['id'] == path.split('/').last);
    return http.Response('', 204);
  }
  if (path.endsWith('/v1/systemone')) {
    final good = request.headers['Authorization'] == 'Bearer good';
    return good
        ? http.Response('{"code":"invalid_request","detail":"state is required"}', 400)
        : http.Response('{"code":"unauthorized","detail":"invalid or revoked API key"}', 401);
  }
  return switch (path) {
    '/api/config' => http.Response(jsonEncode({
      'auth': {'enabled': true, 'issuer': 'https://accounts.google.com', 'clientId': 'client-1'},
      'domains': ['aletyx.com', 'aletyx.ai'],
      'aityxUrl': aityxUrl,
    }), 200),
    '/api/me' => http.Response(jsonEncode(me()), 200),
    '/api/leaderboard' => http.Response(jsonEncode({'standings': [
      for (final x in strategies)
        {'id': x['id'], 'name': x['name'], 'tagline': x['tagline'], 'owner': x['ownerId'] == 'abc' ? alias ?? 'Ana' : x['owner'], 'ownerId': x['ownerId'], 'preset': false, 'tournaments': 0, 'wins': 0, 'points': 0},
    ], 'current': null, 'history': [], 'runner': {'enabled': true, 'state': 'idle', 'detail': 'no tournament yet'}}), 200),
    '/api/strategies' => http.Response(jsonEncode({'strategies': strategies}), 200),
    _ => http.Response('{"error":"not found"}', 404),
  };
  });
}

TourSession session(http.Client client, {PlayerKeys? keys, String email = 'ana@aletyx.com'}) => TourSession(
  api: HttpTourApi(base: Uri.parse('http://tour.test/pokertour/'), client: client, token: () async => 'id-token'),
  auth: FakeAuth(email),
  keys: keys ?? memoryKeys(),
  client: client,
);

void main() {
  group('the player\'s key', () {
    test('theirs, else none; on this environment\'s aityx', () {
      final keys = memoryKeys()..defaultUrl = staging;
      expect(keys.source, KeySource.none);
      expect(keys.key, isNull);
      expect(keys.url, isNull);
      expect(keys.connection.source, AityxSource.none);

      keys.save('mine');
      expect(keys.source, KeySource.own);
      expect((keys.key, keys.url), ('mine', staging), reason: 'no URL given: this environment\'s');
      expect(keys.connection.systemone.toString(), '$staging/v1/systemone');

      keys.forget();
      expect(keys.key, isNull, reason: 'no other key: never the host\'s');
      expect(keys.source, KeySource.none);
    });

    test('on a laptop, staging calls go through the server\'s relay; others go direct', () {
      final keys = memoryKeys()
        ..defaultUrl = staging
        ..relay = Uri.parse('http://localhost:9810/aityx/');
      keys.save('mine');
      expect(keys.connection.systemone.toString(), 'http://localhost:9810/aityx/v1/systemone');
      expect(keys.connection.headers()['Authorization'], 'Bearer mine', reason: 'the browser\'s key, passed on');
      expect(keys.connection.url, staging, reason: 'shown as staging');
      keys.save('mine', url: production);
      expect(keys.connection.systemone.toString(), '$production/v1/systemone', reason: 'production takes browser calls');
    });

    test('a URL is kept, production\'s too on a laptop; the session or the device', () {
      final local = memoryArea();
      final session = memoryArea();
      final keys = PlayerKeys(local: local, session: session)..defaultUrl = staging;
      keys.save(' mine ', url: '$production/');
      expect(keys.url, production, reason: 'not dropped as "the default"');
      expect(local.read(PlayerKeys.keyName), 'mine');
      expect(keys.sessionOnly, isFalse);

      keys.save('other', url: staging, sessionOnly: true);
      expect(keys.sessionOnly, isTrue);
      expect(local.read(PlayerKeys.keyName), isNull, reason: 'one place at a time');
      expect(session.read(PlayerKeys.urlName), staging, reason: 'this environment\'s URL is kept too');

      // Saved without a URL: this environment's now, kept when the server's changes.
      final drift = memoryKeys()..defaultUrl = staging;
      drift.save('third');
      drift.defaultUrl = production;
      expect(drift.url, staging, reason: 'a staging key never drifts to production');

      final deployed = memoryKeys()..defaultUrl = production;
      deployed.save('mine');
      expect(deployed.url, production);
      expect(deployed.staging, isFalse);
      expect(keys.staging, isTrue);
    });
  });

  group('the session', () {
    test('signed in with no key anywhere: Profile is needed until a key works', () async {
      final s = session(world());
      await s.start();
      await pumpEventQueue();
      expect(s.stage, TourStage.ready, reason: 'straight to the table');
      expect(s.keys.defaultUrl, staging, reason: 'the server\'s environment');
      expect(s.needsKey, isTrue);
      expect(s.canPlay, isFalse);

      s.keys.save('bad');
      await pumpEventQueue();
      expect(s.aityxState?.kind, AityxStateKind.rejected);
      expect(s.needsKey, isTrue, reason: 'a rejected key is no key');
      expect(s.canPlay, isFalse);

      s.keys.save('good');
      await pumpEventQueue();
      expect(s.aityxState?.kind, AityxStateKind.ready);
      expect(s.aityxState?.whose, 'your key');
      expect(s.needsKey, isFalse);
      expect(s.canPlay, isTrue);
      s.dispose();
    });

    test('deployed, the default is production\'s aityx', () async {
      final s = session(world(aityxUrl: production));
      await s.start();
      await pumpEventQueue();
      s.keys.save('good');
      expect(s.keys.url, production);
      s.dispose();
    });
  });

  testWidgets('the table with the sidebar beside it opens on Profile, where the key is set', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final s = session(world());
    await tester.runAsync(() async {
      await s.start();
      await pumpEventQueue();
    });
    await tester.pumpWidget(PokerTourApp(session: s));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Title and table on the left; the sidebar's three tabs on the right.
    expect(find.text('Poker Tour'), findsOneWidget);
    expect(find.byKey(const Key('tab-leaderboard')), findsOneWidget);
    expect(find.byKey(const Key('tab-calls')), findsOneWidget);
    expect(find.byKey(const Key('tab-profile')), findsOneWidget);
    expect(find.byKey(const Key('play')), findsOneWidget);
    // No key: Profile, saying so.
    expect(find.byKey(const Key('needs-key')), findsOneWidget);
    expect(find.byKey(const Key('demo-key-note')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('own-url'))).controller!.text, staging,
        reason: "the field shows the server's aityx");
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('play'))).onPressed, isNull,
        reason: 'no key: no play');

    await tester.enterText(find.byKey(const Key('own-key')), 'good');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(s.keys.ownKey, 'good');
    expect(find.byKey(const Key('needs-key')), findsNothing);
    // The saved key fills its field, masked, and is said to work.
    TextField keyField() => tester.widget<TextField>(find.byKey(const Key('own-key')));
    expect(keyField().controller!.text, 'good', reason: 'the field shows the saved key');
    expect(keyField().obscureText, isTrue, reason: 'masked until Show');
    expect(find.descendant(of: find.byKey(const Key('key-status')), matching: find.textContaining('set and works')), findsOneWidget);
    // Typing another: not saved yet; then a rejected one says so.
    await tester.enterText(find.byKey(const Key('own-key')), 'bad');
    await tester.pump();
    expect(find.textContaining('Not saved yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(find.descendant(of: find.byKey(const Key('key-status')), matching: find.textContaining('rejected')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('own-key')), 'good');
    await tester.tap(find.byKey(const Key('save-profile')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
    expect(find.textContaining('set and works'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('play'))).onPressed, isNotNull,
        reason: 'a working key: play');

    // The other tabs.
    await tester.tap(find.descendant(of: find.byKey(const Key('tab-calls')), matching: find.textContaining('aityx calls')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calls-or-log')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const Key('tab-leaderboard')), matching: find.text('Leaderboard')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pumpAndSettle();
    expect(find.textContaining('The leaderboard is idle'), findsOneWidget);
    expect(find.byKey(const Key('run-now')), findsOneWidget, reason: 'an admin');

    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });

  testWidgets('Profile saves the alias the leaderboard shows with one button, and lists and removes your strategies', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final s = session(world(), keys: memoryKeys()..save('good'));
    await tester.runAsync(() async {
      await s.start();
      await pumpEventQueue();
    });
    await tester.pumpWidget(PokerTourApp(session: s));
    await tester.pump();
    await tester.tap(find.byKey(const Key('tab-profile')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    TextField alias() => tester.widget<TextField>(find.byKey(const Key('alias')));
    expect(alias().controller!.text, 'Ana', reason: 'the name by default');
    expect(find.textContaining('Empty:'), findsNothing);
    expect(find.byKey(const Key('save-alias')), findsNothing, reason: 'one button saves the profile');
    expect(find.byKey(const Key('save-key')), findsNothing, reason: 'one button saves the profile');
    expect(find.byKey(const Key('upload-strategy')), filesSupported ? findsOneWidget : findsNothing, reason: 'where files can be picked');
    expect(find.byKey(const Key('my-strategy-u-1')), findsOneWidget, reason: 'hers');
    expect(find.byKey(const Key('my-strategy-u-2')), findsNothing, reason: 'not his');

    Future<void> saveProfile() async {
      await tester.tap(find.byKey(const Key('save-profile')));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.enterText(find.byKey(const Key('alias')), 'River Queen');
    await saveProfile();
    expect(s.me?.alias, 'River Queen');
    expect(s.keys.ownKey, 'good', reason: 'the key, untouched, stays');
    expect(s.leaderboard?.standings.firstWhere((r) => r.id == 'u-1').owner, 'River Queen');
    expect(alias().controller!.text, 'River Queen');

    // Her name again: no alias, the name.
    await tester.enterText(find.byKey(const Key('alias')), 'Ana');
    await saveProfile();
    expect(s.me?.alias, isNull);
    expect(alias().controller!.text, 'Ana');

    // The name and a new key, under the one button.
    await tester.enterText(find.byKey(const Key('alias')), 'Ana B');
    await tester.enterText(find.byKey(const Key('own-key')), 'newer');
    await saveProfile();
    expect(s.me?.alias, 'Ana B');
    expect(s.keys.ownKey, 'newer');

    await tester.tap(find.byKey(const Key('remove-u-1')));
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('my-strategy-u-1')), findsNothing);
    expect(s.tourStrategies.map((t) => t.id), ['u-2']);

    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
