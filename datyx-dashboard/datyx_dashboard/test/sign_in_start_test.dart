import 'dart:async';
import 'dart:convert';

import 'package:datyx_dashboard/api/datyx_api.dart';
import 'package:datyx_dashboard/auth/auth_controller.dart';
import 'package:datyx_dashboard/dashboard/dashboard_screen.dart';
import 'package:datyx_dashboard/main.dart';
import 'package:datyx_dashboard/persist/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The paths the API answers to anybody; every other one is secured.
const open = {'/api/auth/config', '/api/health'};

/// A Google ID token as the dashboard reads one: its audience and expiry.
String idToken({Duration expiresIn = const Duration(minutes: 30)}) {
  String part(Map<String, Object?> json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return [
    part({'alg': 'RS256'}),
    part({'aud': 'client-1', 'exp': exp, 'email': 'tests@example.com', 'name': 'Tests'}),
    'signature',
  ].join('.');
}

/// The datyx API over HTTP, as the dashboard reaches it. With sign-in on
/// ([clientId] set) it refuses a secured call that doesn't carry [bearer],
/// with a 401, as the real one does. Its sign-in settings take
/// [settingsAfter] to come: the tabs are on screen before them.
class SecuredApi {
  SecuredApi({
    this.clientId,
    this.bearer,
    this.settingsAfter = const Duration(milliseconds: 50),
    this.down = false,
    this.training = false,
    this.sourcesAfter = Duration.zero,
  });

  final String? clientId;
  final String? bearer;
  final Duration settingsAfter;

  /// Whether the API is down: nothing answers until it is back.
  bool down;

  /// Whether a training run is going on: the Training tab asks again
  /// every few seconds while it is.
  final bool training;

  /// How long the data sources take to come.
  final Duration sourcesAfter;

  /// Every call, in order: its path and the `Authorization` it carried.
  final List<(String, String?)> asked = [];

  /// The secured calls refused with a 401.
  final List<String> refused = [];

  /// The secured calls made, by path.
  List<String> get secured => [
    for (final (path, _) in asked)
      if (!open.contains(path)) path,
  ];

  late final http.Client client = MockClient(_answer);

  Future<http.Response> _answer(http.Request request) async {
    final path = request.url.path;
    final authorization = request.headers['authorization'];
    asked.add((path, authorization));
    if (down) throw http.ClientException('Connection refused');
    http.Response json(Object? body, [int status = 200]) => http.Response(jsonEncode(body), status);
    if (path == '/api/auth/config') {
      await Future<void>.delayed(settingsAfter);
      return json({'enabled': clientId != null, 'issuer': 'https://accounts.google.com', 'clientId': clientId});
    }
    if (path == '/api/health') {
      return json({
        'status': 'UP',
        'checks': [
          {
            'name': 'datyx',
            'status': 'UP',
            'data': {'version': '0.1.202611101200', 'profile': 'dev', 'launchMode': 'normal', 'image': 'jvm'},
          },
          {'name': 'Database connections health check', 'status': 'UP'},
          {'name': 'OpenMetadata', 'status': 'UP', 'data': {'url': 'http://localhost:9902'}},
        ],
      });
    }
    if (path == '/api/datasources' && sourcesAfter > Duration.zero) await Future<void>.delayed(sourcesAfter);
    if (clientId != null && authorization != 'Bearer $bearer') {
      refused.add(path);
      return json({'error': 'sign in first'}, 401);
    }
    return switch (path) {
      '/api/me' => json({'authenticated': true, 'subject': 'sub-1', 'email': 'tests@example.com', 'profileId': 7}),
      '/api/profile' => json({'id': 7, 'name': 'Tests', 'dataSources': 1, 'identities': []}),
      '/api/datasources' => json([
        {
          'id': 1,
          'name': 'ward',
          'type': 'database',
          'database': {'engine': 'postgresql', 'host': 'db', 'port': 5432, 'database': 'ward'},
        },
      ]),
      '/api/datasources/1/catalog' => json({'tables': []}),
      '/api/datasources/1/timeseries' => json({'series': []}),
      '/api/training' => json({
        'models': [],
        'runs': [
          if (training) {'id': 1, 'sourceId': 1, 'name': 'patient_days', 'group': 'care', 'status': 'running'},
        ],
        'errors': [],
      }),
      '/api/catalog/events' => json({'events': []}),
      '/api/inference' => json({'totals': {}, 'lastHour': 0, 'models': [], 'hours': 24, 'perHour': [], 'calls': []}),
      '/api/aityx' => json({'days': 7, 'configured': true, 'sharesServiceCalls': true, 'calls': []}),
      _ => json({'error': 'no $path'}, 404),
    };
  }
}

/// What each tab shows once the API answered it.
final shown = <DashboardTab, Finder>{
  DashboardTab.sources: find.text('ward'),
  DashboardTab.catalog: find.byKey(const ValueKey('catalog-1')),
  DashboardTab.training: find.textContaining('No group is tagged yet'),
  DashboardTab.inference: find.text('Models'),
  DashboardTab.aityx: find.byKey(const ValueKey('aityx-services')),
  DashboardTab.audit: find.text('/api/health'),
  DashboardTab.health: find.text('datyx 0.1.202611101200'),
  DashboardTab.profile: find.textContaining('1 data source'),
};

/// The words of a view that didn't get its data.
final unanswered = [
  find.textContaining('answered 401'),
  find.textContaining('Sign in to see'),
  find.text('Loading…'),
  find.byKey(const Key('waiting-for-sign-in')),
];

void main() {
  /// Opens the app on [tab], as a reload of the page does, with [kept] in
  /// the session store, and lets the first frames go by: the tabs are on
  /// screen, the API's sign-in settings not there yet.
  Future<AuthController> reload(WidgetTester tester, SecuredApi server, DashboardTab tab, {String? kept}) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final store = SessionStore.memory();
    if (kept != null) store.write('idToken', kept);
    final auth = AuthController(store: store);
    addTearDown(auth.dispose);
    final api = HttpDatyxApi(
      baseUrl: 'http://datyx',
      client: server.client,
      token: auth.token,
      refreshToken: auth.refresh,
    );
    await tester.pumpWidget(DatyxDashApp(api: api, auth: auth, initialTab: tab));
    await tester.pump();
    await tester.pump();
    return auth;
  }

  /// Lets the sign-in settings come, and what follows them.
  Future<void> settle(WidgetTester tester, SecuredApi server) async {
    await tester.pump(server.settingsAfter * 2);
    await tester.pumpAndSettle();
  }

  group('a reload while signed in', () {
    for (final tab in DashboardTab.values) {
      testWidgets('on the ${tab.label} tab shows its data, every secured call with the kept token', (tester) async {
        final kept = idToken();
        final server = SecuredApi(clientId: 'client-1', bearer: kept);
        final auth = await reload(tester, server, tab, kept: kept);

        // The sign-in settings are still on their way: nothing secured is
        // asked, since nobody knows yet whether it needs a token.
        expect(auth.settled, isFalse);
        expect(server.secured, isEmpty, reason: 'asked before the sign-in settings came');
        expect(find.textContaining('Sign in to see'), findsNothing);

        await settle(tester, server);
        expect(auth.signedIn, isTrue);
        expect(server.refused, isEmpty, reason: 'the API refused a call: no 401 at start');
        expect(server.secured, isNotEmpty);
        for (final (path, authorization) in server.asked) {
          if (!open.contains(path)) expect(authorization, 'Bearer $kept', reason: path);
        }
        expect(shown[tab]!, findsWidgets);
        for (final words in unanswered) {
          expect(words, findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('on the Training tab asks GET /api/training once, with the token, and shows no error', (tester) async {
      final kept = idToken();
      final server = SecuredApi(clientId: 'client-1', bearer: kept);
      await reload(tester, server, DashboardTab.training, kept: kept);
      // What it shows meanwhile: that it waits, not an error.
      expect(find.byKey(const Key('waiting-for-sign-in')), findsOneWidget);
      expect(find.textContaining('401'), findsNothing);

      await settle(tester, server);
      expect([
        for (final (path, authorization) in server.asked)
          if (path == '/api/training') authorization,
      ], ['Bearer $kept']);
      expect(find.textContaining('401'), findsNothing);
      expect(find.textContaining('No group is tagged yet'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
    });

    testWidgets('then signing out locks the tab, and asks nothing more of what the API secures', (tester) async {
      final kept = idToken();
      final server = SecuredApi(clientId: 'client-1', bearer: kept);
      final auth = await reload(tester, server, DashboardTab.training, kept: kept);
      await settle(tester, server);
      final before = server.secured.length;

      unawaited(auth.signOut());
      await tester.pumpAndSettle();
      expect(find.text('Sign in to see the training.'), findsOneWidget);
      expect(find.textContaining('No group is tagged yet'), findsNothing);
      expect(server.secured.length, before);
      expect(server.refused, isEmpty);
    });
  });

  testWidgets('signing out while a run trains: the tab polls no more, and the next user sees nothing of the last', (tester) async {
    final kept = idToken();
    final server = SecuredApi(clientId: 'client-1', bearer: kept, training: true);
    final auth = await reload(tester, server, DashboardTab.training, kept: kept);
    await tester.pump(server.settingsAfter * 2);
    await tester.pump();
    await tester.pump();
    // The run going on: the tab asks again every few seconds.
    final first = server.secured.where((path) => path == '/api/training').length;
    expect(first, greaterThan(0));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(server.secured.where((path) => path == '/api/training').length, greaterThan(first));

    unawaited(auth.signOut());
    await tester.pump();
    await tester.pump();
    final before = server.asked.length;
    // Long past the tab's next look: nothing more is asked, with or
    // without a token.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(server.asked.skip(before).where((call) => !open.contains(call.$1)), isEmpty);
    expect(server.refused, isEmpty);
    expect(find.text('Sign in to see the training.'), findsOneWidget);
    // The Data sources tab holds nothing of the user who left.
    await tester.tap(find.byKey(const Key('tab-sources')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('ward'), findsNothing);
  });

  testWidgets('signing out while the data sources are on their way: their answer is dropped, nothing goes out unsigned', (tester) async {
    final kept = idToken();
    final server = SecuredApi(clientId: 'client-1', bearer: kept, sourcesAfter: const Duration(seconds: 2));
    final auth = await reload(tester, server, DashboardTab.sources, kept: kept);
    // The settings come, and the screen's round asks for the data sources,
    // which take 2 s.
    await tester.pump(server.settingsAfter * 2);
    await tester.pump(const Duration(milliseconds: 100));
    expect(server.secured, contains('/api/datasources'));

    unawaited(auth.signOut());
    await tester.pump();
    // The data sources come back, the user's who left.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(server.refused, isEmpty, reason: 'nothing secured asked without a token after the sign-out');
    expect(find.text('Sign in to see the data sources.'), findsOneWidget);
    expect(find.text('ward'), findsNothing);
  });

  testWidgets('the API back after it was down at start: the tabs load, and its error goes', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final server = SecuredApi(down: true);
    final api = HttpDatyxApi(baseUrl: 'http://datyx', client: server.client);
    final auth = AuthController(store: SessionStore.memory());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(api: api, auth: auth, initialTab: DashboardTab.sources, refreshEvery: Duration.zero),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('The API did not answer'), findsOneWidget);

    // Back, with sign-in off: the sign-in settles, and with no refresh
    // timer at all the status is asked again with the secured calls.
    server.down = false;
    await auth.start(const AuthConfig(enabled: false, issuer: ''));
    await tester.pumpAndSettle();
    expect(find.text('ward'), findsOneWidget);
    expect(find.textContaining('The API did not answer'), findsNothing);
    expect(server.asked.where((call) => call.$1 == '/api/health').length, 2);
  });

  testWidgets('signed out, with sign-in on, a tab says to sign in and asks nothing secured', (tester) async {
    final server = SecuredApi(clientId: 'client-1', bearer: idToken());
    final auth = await reload(tester, server, DashboardTab.training);
    await settle(tester, server);
    expect(auth.settled, isTrue);
    expect(auth.signedIn, isFalse);
    expect(find.text('Sign in to see the training.'), findsOneWidget);
    expect(find.byKey(const Key('waiting-for-sign-in')), findsNothing);
    expect(server.secured, isEmpty);
    expect(server.refused, isEmpty);
  });

  testWidgets('a kept token that expired is dropped: signed out, nothing secured asked', (tester) async {
    final kept = idToken(expiresIn: const Duration(seconds: 20));
    final server = SecuredApi(clientId: 'client-1', bearer: kept);
    final auth = await reload(tester, server, DashboardTab.inference, kept: kept);
    await settle(tester, server);
    expect(auth.signedIn, isFalse);
    expect(find.text('Sign in to see the inference.'), findsOneWidget);
    expect(server.secured, isEmpty);
  });

  testWidgets('with sign-in off, a tab loads with no token as soon as the API says so', (tester) async {
    final server = SecuredApi();
    final auth = await reload(tester, server, DashboardTab.training);
    expect(server.secured, isEmpty);

    await settle(tester, server);
    expect(auth.enabled, isFalse);
    expect(server.refused, isEmpty);
    expect(server.secured, containsAll(['/api/training', '/api/catalog/events', '/api/datasources', '/api/profile']));
    expect(server.asked.map((call) => call.$2), everyElement(isNull));
    expect(find.textContaining('No group is tagged yet'), findsOneWidget);
    for (final words in unanswered) {
      expect(words, findsNothing);
    }
  });

  testWidgets('while the API is down, the secured tabs wait and the Health tab shows', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final asked = <String>[];
    final api = HttpDatyxApi(
      baseUrl: 'http://datyx',
      client: MockClient((request) async {
        asked.add(request.url.path);
        throw http.ClientException('Connection refused');
      }),
    );
    final auth = AuthController(store: SessionStore.memory());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(api: api, auth: auth, initialTab: DashboardTab.training, refreshEvery: Duration.zero),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, ['/api/health']);
    expect(find.byKey(const Key('waiting-for-sign-in')), findsOneWidget);
    expect(find.textContaining('The API did not answer'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-health')));
    await tester.pumpAndSettle();
    expect(find.text('waiting for /api/auth/config'), findsOneWidget);

    // The API is back, with sign-in off: the tab loads.
    await auth.start(const AuthConfig(enabled: false, issuer: ''));
    await tester.tap(find.byKey(const Key('tab-training')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('waiting-for-sign-in')), findsNothing);
    expect(asked, contains('/api/training'));
  });

  group('a token the API refuses mid-session', () {
    test('is renewed once, silently, and the call retried with the new one', () async {
      final carried = <String?>[];
      var renewals = 0;
      final api = HttpDatyxApi(
        baseUrl: 'http://datyx',
        client: MockClient((request) async {
          carried.add(request.headers['authorization']);
          return request.headers['authorization'] == 'Bearer new'
              ? http.Response('{"models":[],"runs":[],"errors":[]}', 200)
              : http.Response('{"error":"expired"}', 401);
        }),
        token: () async => 'old',
        refreshToken: () async {
          renewals++;
          return 'new';
        },
      );
      final overview = await api.training();
      expect(overview.models, isEmpty);
      expect(carried, ['Bearer old', 'Bearer new']);
      expect(renewals, 1);
    });

    test('and can\'t be renewed is the API\'s 401, asked once', () async {
      var calls = 0;
      var renewals = 0;
      final api = HttpDatyxApi(
        baseUrl: 'http://datyx',
        client: MockClient((request) async {
          calls++;
          return http.Response('{"error":"expired"}', 401);
        }),
        token: () async => 'old',
        refreshToken: () async {
          renewals++;
          return null;
        },
      );
      await expectLater(
        api.training(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'GET /api/training answered 401: expired')),
      );
      expect(calls, 1);
      expect(renewals, 1);
    });
  });
}
