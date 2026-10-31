import 'dart:convert';

import 'package:datyx_dashboard/api/datyx_api.dart';
import 'package:datyx_dashboard/auth/auth_controller.dart';
import 'package:datyx_dashboard/dashboard/dashboard_screen.dart';
import 'package:datyx_dashboard/main.dart';
import 'package:datyx_dashboard/persist/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// An API that answers from memory, and logs its calls as the real one does.
class FakeDatyxApi implements DatyxApi {
  @override
  final CallLog log = CallLog();
  final List<DataSource> _sources = [];

  @override
  Future<AuthConfig> authConfig() async {
    final call = log.start('GET', '/api/auth/config');
    log.finish(call, status: 200, body: '{"enabled":false}');
    return const AuthConfig(enabled: false, issuer: 'https://accounts.google.com');
  }

  @override
  Future<Me> me() async => const Me(authenticated: false, profileId: 1);

  @override
  Future<Profile> profile() async {
    final call = log.start('GET', '/api/profile');
    log.finish(call, status: 200, body: '{"id":1}');
    return Profile(
      id: 1,
      name: 'Local',
      createdAt: DateTime(2026),
      dataSources: _sources.length,
      identities: const [
        ProfileIdentity(issuer: 'local', subject: 'anonymous'),
        ProfileIdentity(
          issuer: 'https://accounts.google.com',
          subject: 'sub-1',
          email: 'tests@example.com',
          name: 'Tests',
        ),
      ],
    );
  }

  @override
  Future<List<DataSource>> dataSources({int limit = 100}) async {
    final call = log.start('GET', '/api/datasources');
    log.finish(call, status: 200, body: '[]');
    return _sources.reversed.toList();
  }

  @override
  Future<DataSource> addDataSource(NewDataSource source) async {
    final call = log.start('POST', '/api/datasources');
    log.finish(call, status: 201, body: '{}');
    final s = DataSource(
      id: _sources.length + 1,
      name: source.name,
      type: source.type,
      description: source.description,
      createdAt: DateTime(2026),
      createdBy: 'tests@example.com',
      details: source.details,
    );
    _sources.add(s);
    return s;
  }

  @override
  Future<void> removeDataSource(int id) async {
    _sources.removeWhere((s) => s.id == id);
  }

  @override
  Future<SystemStatus> status() async {
    final call = log.start('GET', '/api/health');
    log.finish(call, status: 503, body: '{"status":"DOWN"}');
    return SystemStatus(
      name: 'datyx',
      version: '0.1.202601011200',
      profile: 'dev',
      launchMode: 'development',
      image: 'jvm',
      startedAt: DateTime(2026),
      database: const Dependency(ok: true),
      openMetadata: const Dependency(
        ok: false,
        error: 'Connection refused',
        url: 'http://localhost:9902',
      ),
    );
  }
}

void main() {
  testWidgets('shows the health, with the version', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();

    // The data sources come first; the health is a tab away.
    expect(find.text('None yet. Add a database, an S3 bucket or a folder.'), findsOneWidget);
    expect(find.text('dev profile, development, jvm'), findsNothing);
    await tester.tap(find.byKey(const Key('tab-health')));
    await tester.pumpAndSettle();
    expect(find.text('datyx 0.1.202601011200'), findsOneWidget);
    expect(find.text('dev profile, development, jvm'), findsOneWidget);
    expect(find.text('Connection refused'), findsOneWidget);
    expect(find.text('off: no OIDC_CLIENT_ID on the API'), findsOneWidget);
    // A test build has no version compiled in.
    expect(find.text('no version: not built by the scripts'), findsOneWidget);
  });

  testWidgets('audits every call', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();

    // The tab counts the calls made so far: the sign-in config, the status,
    // the data sources and the profile.
    expect(find.text('Audit (4)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-audit')));
    await tester.pumpAndSettle();
    expect(find.text('/api/auth/config'), findsOneWidget);
    expect(find.text('/api/health'), findsOneWidget);
    expect(find.text('/api/datasources'), findsOneWidget);
    expect(find.text('/api/profile'), findsOneWidget);
    expect(find.text('4 of the latest 100 kept'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No calls yet.'), findsOneWidget);
    expect(find.text('Audit (0)'), findsOneWidget);
  });

  testWidgets('shows the profile and its identities', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('tab-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('profile 1 · since 2026-01-01 · 0 data sources'), findsOneWidget);
    // Both identities, the local one and a Google account.
    expect(find.text('anonymous'), findsOneWidget);
    expect(find.text('tests@example.com'), findsOneWidget);
    expect(find.text('Tests · accounts.google.com'), findsOneWidget);
  });

  testWidgets('adds and removes a data source', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    expect(find.text('None yet. Add a database, an S3 bucket or a folder.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ds-add')));
    await tester.pumpAndSettle();
    expect(find.text('Add a data source'), findsOneWidget);
    await tester.tap(find.text('Filesystem'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ds-name')), 'exports');
    await tester.enterText(find.byKey(const Key('ds-path')), '/data/exports');
    await tester.tap(find.byKey(const Key('ds-submit')));
    await tester.pumpAndSettle();

    expect(find.text('exports'), findsOneWidget);
    expect(find.text('/data/exports'), findsOneWidget);
    expect(find.text('by tests@example.com'), findsOneWidget);
    // The audit saw the POST.
    await tester.tap(find.byKey(const Key('tab-audit')));
    await tester.pumpAndSettle();
    expect(find.text('POST'), findsOneWidget);
    expect(find.text('/api/datasources'), findsWidgets);

    await tester.tap(find.byKey(const Key('tab-sources')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ds-remove-1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove exports?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ds-remove-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('/data/exports'), findsNothing);
  });

  testWidgets('has the tabs in order, and the catalog lists the sources', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();

    final xs = [
      for (final tab in DashboardTab.values)
        tester.getTopLeft(find.byKey(Key('tab-${tab.name}'))).dx,
    ];
    expect(xs, [...xs]..sort());
    expect(DashboardTab.values.map((t) => t.label), [
      'Data sources',
      'Catalog',
      'Audit',
      'Health',
      'Profile',
    ]);

    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    expect(find.text('No data sources yet: add one on the Data sources tab.'), findsOneWidget);
    await api.addDataSource(
      NewDataSource(
        name: 'exports',
        type: DataSourceType.filesystem,
        details: const {'path': '/data/exports'},
      ),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('exports'), findsOneWidget);
    expect(find.text('not catalogued yet'), findsOneWidget);
  });

  testWidgets('opens the tab the address names', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    expect(DashboardTab.named('health'), DashboardTab.health);
    expect(DashboardTab.named('nonsense'), DashboardTab.sources);
    expect(DashboardTab.named(null), DashboardTab.sources);

    final auth = AuthController(store: SessionStore.memory());
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          api: FakeDatyxApi(),
          auth: auth,
          initialTab: DashboardTab.named('health'),
          refreshEvery: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('dev profile, development, jvm'), findsOneWidget);
  });

  test('reads the health checks by name', () {
    final status = SystemStatus.fromHealth({
      'status': 'DOWN',
      'checks': [
        {
          'name': 'datyx',
          'status': 'UP',
          'data': {
            'version': '0.1.202610301200',
            'profile': 'dev',
            'launchMode': 'normal',
            'image': 'jvm',
            'startedAt': '2026-10-30T12:00:00Z',
          },
        },
        {
          'name': 'Database connections health check',
          'status': 'UP',
          'data': {'<default>': 'UP'},
        },
        {
          'name': 'OpenMetadata',
          'status': 'DOWN',
          'data': {'url': 'http://localhost:9902', 'error': 'Connection refused'},
        },
      ],
    });
    expect(status.name, 'datyx');
    expect(status.version, '0.1.202610301200');
    expect(status.profile, 'dev');
    expect(status.launchMode, 'normal');
    expect(status.startedAt, DateTime.utc(2026, 10, 30, 12));
    expect(status.database.ok, isTrue);
    expect(status.database.error, isNull);
    expect(status.openMetadata.ok, isFalse);
    expect(status.openMetadata.error, 'Connection refused');
    expect(status.openMetadata.url, 'http://localhost:9902');
  });

  test('the audit outlives a reload', () {
    final store = SessionStore.memory();
    final log = CallLog(store: store);
    log.finish(log.start('GET', '/api/health'), status: 200, body: '{}');
    log.start('POST', '/api/datasources', requestBody: '{"name":"x"}');

    final again = CallLog(store: store);
    expect(again.calls.map((c) => c.path), ['/api/datasources', '/api/health']);
    expect(again.calls.last.status, 200);
    // The one still waiting at the reload never got its answer.
    expect(again.calls.first.pending, isFalse);
    expect(again.calls.first.error, 'the page was reloaded before the answer');

    again.clear();
    expect(CallLog(store: store).calls, isEmpty);
  });

  group('sign-in outlives a reload', () {
    const config = AuthConfig(
      enabled: true,
      issuer: 'https://accounts.google.com',
      clientId: 'client-1',
    );

    String token({required Duration expiresIn, String aud = 'client-1'}) {
      String part(Map<String, Object?> json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
      return [
        part({'alg': 'RS256'}),
        part({'aud': aud, 'exp': exp, 'email': 'tests@example.com', 'name': 'Tests'}),
        'signature',
      ].join('.');
    }

    test('a fresh token signs in without asking Google', () async {
      final kept = token(expiresIn: const Duration(minutes: 30));
      final store = SessionStore.memory()..write('idToken', kept);
      final auth = AuthController(store: store);
      await auth.start(config);
      expect(auth.signedIn, isTrue);
      expect(auth.user?.email, 'tests@example.com');
      expect(auth.user?.name, 'Tests');
      expect(await auth.token(), kept);
    });

    test('an expired token, or another client\'s, is dropped', () async {
      for (final kept in [
        token(expiresIn: const Duration(seconds: 30)),
        token(expiresIn: const Duration(minutes: 30), aud: 'client-2'),
        'not a token',
      ]) {
        final store = SessionStore.memory()..write('idToken', kept);
        final auth = AuthController(store: store);
        await auth.start(config);
        expect(auth.signedIn, isFalse);
        expect(store.read('idToken'), isNull);
      }
    });

    test('a token refused, and not renewed, signs out', () async {
      final store = SessionStore.memory()
        ..write('idToken', token(expiresIn: const Duration(minutes: 30)));
      final auth = AuthController(store: store);
      await auth.start(config);
      // What the API client does after a 401; Google can't renew here.
      expect(await auth.refresh(), isNull);
      expect(auth.signedIn, isFalse);
      expect(store.read('idToken'), isNull);
    });

    test('signing out forgets the token', () async {
      final store = SessionStore.memory()
        ..write('idToken', token(expiresIn: const Duration(minutes: 30)));
      final auth = AuthController(store: store);
      await auth.start(config);
      await auth.signOut();
      expect(auth.signedIn, isFalse);
      expect(store.read('idToken'), isNull);
    });
  });
}
