import 'dart:convert';

import 'package:datyx_dashboard/api/datyx_api.dart';
import 'package:datyx_dashboard/auth/auth_controller.dart';
import 'package:datyx_dashboard/dashboard/catalog_tab.dart'
    show cleanupHelp, groupColors, groupPalette, otherGroupColor, tableKind, tagHelp;
import 'package:datyx_dashboard/dashboard/dashboard_screen.dart';
import 'package:datyx_dashboard/dashboard/inference_tab.dart' show ms;
import 'package:datyx_dashboard/dashboard/training_tab.dart' show FeatureWeights;
import 'package:datyx_dashboard/main.dart';
import 'package:datyx_dashboard/persist/address.dart';
import 'package:datyx_dashboard/persist/address_memory.dart' as address;
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

  /// The catalogue: empty until a sync, then HealthHub's hourly table.
  List<CatalogTable> catalogued = [];
  TimeSeriesRoles? lastRoles;

  /// The groups tagged so far, by name; a group sent with no roles is gone.
  final Map<String, TimeSeriesSpec> groups = {};

  /// The table's custom properties, as the last roles set them.
  Map<String, Object?> properties = {};

  /// The trainer, as the API answers it, and what was asked of it.
  TrainingOverview trainingOverview = const TrainingOverview();
  final Map<int, TrainingRunDetail> runDetails = {};
  final List<String> trainCalls = [];
  final List<String?> retrainCalls = [];

  @override
  Future<TrainingOverview> training() async => trainingOverview;

  @override
  Future<TrainingRunDetail> trainingRun(int id) async => runDetails[id]!;

  @override
  Future<TrainingRunInfo> trainNow(int sourceId, String table, String group, {String? algorithm}) async {
    trainCalls.add('$sourceId $table $group ${algorithm ?? '(the API\'s choice)'}');
    return TrainingRunInfo(id: 99, sourceId: sourceId, table: table, name: 'patient_days', group: group);
  }

  /// The groups switched on or off, newest first; enabling one through the
  /// fake adds one, with a run queued per algorithm, as the API does.
  List<GroupEvent> events = [];

  /// Set to have `GET /api/catalog/events` fail, as an API without it would.
  ApiException? eventsError;

  @override
  Future<List<GroupEvent>> groupEvents({int limit = 50}) async {
    if (eventsError != null) throw eventsError!;
    return events.take(limit).toList();
  }

  @override
  Future<void> setRetrain(int sourceId, String table, String? retrain) async => retrainCalls.add(retrain);

  /// Inference, as the API answers it, and the calls made.
  InferenceAccount inferenceAccount = const InferenceAccount();
  final List<List<Map<String, String>>?> scoreCalls = [];

  @override
  Future<InferenceAccount> inference() async => inferenceAccount;

  @override
  Future<InferenceAnswer> score(
    int sourceId,
    String table,
    String group, {
    List<Map<String, String>>? series,
    int limit = 25,
  }) async {
    scoreCalls.add(series);
    return InferenceAnswer(
      callId: 40 + scoreCalls.length,
      runId: 7,
      requested: series?.length ?? 0,
      scored: 1,
      millis: 12,
      predictions: [
        series == null
            ? const Prediction({'run_id': 'adf5309c', 'person_id': 'reus-4'}, 4.7, 8, null)
            : Prediction(series.first, 3.25, 2, null),
      ],
    );
  }

  static const hourly = CatalogTable(
    fqn: 'datyx-ds-1.healthhub.public.admissions_hourly',
    schema: 'public',
    name: 'admissions_hourly',
    type: 'Regular',
    primaryKey: ['run_id', 'hospital_id', 'hour_start'],
    columns: [
      CatalogColumn(name: 'run_id', dataType: 'TEXT'),
      CatalogColumn(name: 'hospital_id', dataType: 'INT'),
      CatalogColumn(name: 'hour_start', dataType: 'TIMESTAMP'),
      CatalogColumn(name: 'admissions', dataType: 'INT'),
      CatalogColumn(name: 'acute_admissions', dataType: 'INT'),
    ],
  );

  /// A Kafka source's topics: empty until a sync, then HealthHub's hourly topic and an empty one.
  List<CatalogTopic> topicsCatalogued = [];

  static const hourlyTopic = CatalogTopic(
    fqn: 'datyx-ds-2."healthhub.admissions.hourly"',
    name: 'healthhub.admissions.hourly',
    partitions: 1,
    replicationFactor: 1,
    cleanupPolicies: ['compact', 'delete'],
    retentionTime: 86400000,
    schemaType: 'JSON',
    fields: [
      CatalogField(name: 'hospital_id', dataType: 'INT', tags: ['PII.None']),
      CatalogField(name: 'hour_start', dataType: 'STRING'),
      CatalogField(name: 'where', dataType: 'RECORD', children: [CatalogField(name: 'city', dataType: 'STRING')]),
    ],
  );

  @override
  Future<CatalogSync> syncCatalog(int sourceId) async {
    if (_sources.firstWhere((s) => s.id == sourceId).type == DataSourceType.kafka) {
      topicsCatalogued = [hourlyTopic, const CatalogTopic(fqn: 'datyx-ds-2.quiet', name: 'quiet', partitions: 3)];
      return const CatalogSync(topics: 2, fields: 3, sampled: 1);
    }
    catalogued = [hourly];
    return const CatalogSync(tables: 1, columns: 4);
  }

  @override
  Future<List<CatalogTopic>> topics(int sourceId) async => topicsCatalogued;

  @override
  Future<List<CatalogTable>> catalog(int sourceId) async => [
    for (final t in catalogued)
      CatalogTable(
        fqn: t.fqn,
        schema: t.schema,
        name: t.name,
        type: t.type,
        primaryKey: t.primaryKey,
        properties: properties,
        // Each group's algorithm as a tag on the table, and a disabled
        // group's Disabled tag, as the API answers them.
        tags: [
          for (final g in groups.values)
            for (final a in g.algorithms)
              g.group == defaultGroup ? 'TimeSeries.$a' : 'TimeSeries.${g.group}.$a',
          for (final g in groups.values)
            if (!g.enabled) disabledTag(g.group),
        ],
        columns: [
          // Each group's roles as OpenMetadata's tags, as the API answers them.
          for (final c in t.columns)
            CatalogColumn(
              name: c.name,
              dataType: c.dataType,
              tags: [
                for (final g in groups.values)
                  for (final role in TimeSeriesRole.values)
                    if (g.of(role).contains(c.name))
                      g.group == defaultGroup ? 'TimeSeries.${role.tag}' : 'TimeSeries.${g.group}.${role.tag}',
              ],
            ),
        ],
      ),
  ];

  @override
  Future<List<TimeSeriesSpec>> timeSeries(int sourceId) async => groups.values.toList();

  @override
  Future<TimeSeriesSpec> setTimeSeries(int sourceId, TimeSeriesRoles roles) async {
    lastRoles = roles;
    properties = {
      'timeSeriesFrequency': ?roles.frequency,
      'timeSeriesHorizon': ?roles.horizon,
      'timeSeriesMissing': ?roles.missing,
    };
    final ready = roles.columns[TimeSeriesRole.target]?.isNotEmpty ?? false;
    final spec = TimeSeriesSpec(
      table: roles.table,
      name: 'admissions_hourly',
      group: roles.group,
      algorithm: roles.algorithm ?? deepArAlgorithm,
      algorithms: roles.algorithms == null ? null : inAlgorithmOrder(roles.algorithms!),
      columns: {for (final e in roles.columns.entries) e.key: List.of(e.value)},
      frequency: roles.frequency,
      horizon: roles.horizon,
      missing: roles.missing,
      ready: ready,
      problems: ready ? const [] : const ['no column is tagged TimeSeries.Target, the value to forecast'],
    );
    if (roles.columns.values.every((c) => c.isEmpty)) {
      groups.remove(roles.group);
    } else {
      groups[roles.group] = spec;
    }
    return spec;
  }

  /// The groups enabled or disabled, as `table group enabled`.
  final List<String> enabledCalls = [];

  @override
  Future<TimeSeriesSpec> setGroupEnabled(int sourceId, String table, String group, bool enabled) async {
    enabledCalls.add('$table $group $enabled');
    final g = groups[group];
    if (g == null) throw ApiException('PUT /api/datasources/$sourceId/timeseries/enabled answered 404', status: 404);
    if (enabled && !g.enabled) {
      final first = 20 + events.length * 10;
      events.insert(
        0,
        GroupEvent(
          id: events.length + 1,
          sourceId: sourceId,
          source: 'HealthHub',
          table: table,
          name: g.name,
          group: group,
          enabled: true,
          via: 'datyx-api',
          version: '0.${events.length + 2}',
          by: 'tests@example.com',
          at: DateTime(2026, 11, 1, 12),
          runIds: [for (var i = 0; i < g.algorithms.length; i++) first + i],
        ),
      );
    }
    return groups[group] = TimeSeriesSpec(
      table: g.table,
      name: g.name,
      group: g.group,
      algorithm: g.algorithm,
      algorithms: g.algorithms,
      columns: g.columns,
      frequency: g.frequency,
      horizon: g.horizon,
      missing: g.missing,
      ready: g.ready,
      problems: g.problems,
      enabled: enabled,
    );
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

/// The tooltips whose message contains [text].
Finder tip(String text) => find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').contains(text));

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

    // OpenMetadata, the API's health check and the dashboard are links.
    expect(find.text('http://localhost:9902'), findsOneWidget);
    address.opened.clear();
    await tester.tap(find.byKey(const ValueKey('link-OpenMetadata')));
    await tester.tap(find.byKey(const ValueKey('link-API')));
    await tester.tap(find.byKey(const ValueKey('link-Dashboard')));
    expect(address.opened, ['http://localhost:9902', Uri.base.resolve('/api/health').toString(), Address.page.toString()]);
  });

  testWidgets('audits every call', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();

    // The calls made so far: the sign-in config, the status, the data
    // sources and the profile. Neither the tab's label nor the panel's
    // title counts them.
    expect(find.text('Audit'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-audit')));
    await tester.pumpAndSettle();
    expect(find.text('/api/auth/config'), findsOneWidget);
    expect(find.text('/api/health'), findsOneWidget);
    expect(find.text('/api/datasources'), findsOneWidget);
    expect(find.text('/api/profile'), findsOneWidget);
    expect(find.text('API calls'), findsOneWidget);
    expect(find.textContaining('of the latest'), findsNothing);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No calls yet.'), findsOneWidget);
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
      'Training',
      'Inference',
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
    expect(find.text('not read yet: only databases and Kafka so far'), findsOneWidget);
    expect(find.text('Not read yet'), findsOneWidget);
  });

  testWidgets('adds a Kafka source and reads its topics in the Streams section', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await api.addDataSource(
      const NewDataSource(
        name: 'HealthHub',
        type: DataSourceType.database,
        details: {'engine': 'postgresql', 'host': 'localhost', 'port': 9803, 'database': 'healthhub'},
      ),
    );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ds-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kafka'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ds-name')), 'HealthHub Kafka');
    await tester.enterText(find.byKey(const Key('ds-bootstrap')), ' localhost:9804 ');
    await tester.tap(find.byKey(const Key('ds-submit')));
    await tester.pumpAndSettle();
    final added = api._sources.last;
    expect(added.type, DataSourceType.kafka);
    expect(added.details, {'bootstrapServers': 'localhost:9804', 'securityProtocol': 'PLAINTEXT'});
    expect(find.text('kafka://localhost:9804'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    // Databases above Streams, each source a card of its own, apart.
    expect(tester.getTopLeft(find.text('Databases')).dy, lessThan(tester.getTopLeft(find.text('Streams')).dy));
    final database = tester.getRect(find.byKey(const ValueKey('catalog-1')));
    final stream = tester.getRect(find.byKey(const ValueKey('catalog-2')));
    expect(stream.top - database.bottom, greaterThanOrEqualTo(28));
    expect(find.textContaining('Read topics reads its topics'), findsOneWidget);

    await tester.tap(find.text('Read topics'));
    await tester.pumpAndSettle();
    expect(find.text('Read 2 topics, 3 fields from the 1 with records.'), findsOneWidget);
    expect(find.text('3 fields'), findsOneWidget);
    expect(find.text('no fields read'), findsOneWidget);
    await tester.tap(find.text('healthhub.admissions.hourly'));
    await tester.pumpAndSettle();
    expect(find.text('1 partition · replication 1 · kept 1 day'), findsOneWidget);
    expect(find.text('hospital_id'), findsOneWidget);
    expect(find.text('PII.None'), findsOneWidget);
    expect(find.text('city'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('city')).dx,
      greaterThan(tester.getTopLeft(find.text('hour_start')).dx),
    );
    expect(find.byTooltip('Kafka source'), findsOneWidget);
    expect(tip('Kafka topic healthhub.admissions.hourly\nIn OpenMetadata: datyx-ds-2."healthhub.admissions.hourly"'), findsOneWidget);
    expect(tip('Cleanup policy compact'), findsOneWidget);
    expect(tip('Tag None of the PII classification'), findsOneWidget);
    expect(tip('Field where of the records, holding the fields under it'), findsOneWidget);
    await tester.tap(find.text('quiet'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No record to learn the fields from'), findsOneWidget);
  });

  testWidgets('reads a database\'s schema and tags a table for DeepAR', (tester) async {
    tester.view.physicalSize = const Size(1600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await api.addDataSource(
      const NewDataSource(
        name: 'HealthHub',
        type: DataSourceType.database,
        details: {'engine': 'postgresql', 'host': 'localhost', 'port': 9803, 'database': 'healthhub'},
      ),
    );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not catalogued yet'), findsOneWidget);

    await tester.tap(find.text('Read schema'));
    await tester.pumpAndSettle();
    expect(find.text('Read 1 tables, 4 columns.'), findsOneWidget);
    await tester.tap(find.text('public.admissions_hourly'));
    await tester.pumpAndSettle();
    expect(find.text('hour_start'), findsOneWidget);
    // Each part says what it is on hover: the source, the table, its columns.
    expect(find.byTooltip('Database source'), findsOneWidget);
    expect(tip('No rows are read'), findsOneWidget);
    expect(
      tip('Table public.admissions_hourly, with no description in the source\n'
          'In OpenMetadata: datyx-ds-1.healthhub.public.admissions_hourly'),
      findsOneWidget,
    );
    expect(tip('Column run_id: part of the primary key, not tagged'), findsOneWidget);
    expect(tip('Primary key'), findsNWidgets(3));
    expect(tip('as OpenMetadata names it: TIMESTAMP'), findsOneWidget);
    await tester.longPress(find.text('public.admissions_hourly'));
    await tester.pumpAndSettle();
    expect(find.textContaining('In OpenMetadata: datyx-ds-1.healthhub.public.admissions_hourly'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tag for training'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('Timestamp-hour_start')));
    await tester.tap(find.byKey(const ValueKey('SeriesKey-run_id')));
    await tester.tap(find.byKey(const ValueKey('SeriesKey-hospital_id')));
    await tester.tap(find.byKey(const ValueKey('frequency-1h')));
    await tester.tap(find.text('counts as 0'));
    await tester.pump();
    // No target yet: the API's problem is shown and the dialog stays.
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no column is tagged TimeSeries.Target'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('Target-admissions')));
    await tester.pump();
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();
    expect(find.text('Save tags'), findsNothing);
    final sent = api.lastRoles!.toJson();
    expect(sent['table'], 'datyx-ds-1.healthhub.public.admissions_hourly');
    expect(sent['timestamp'], 'hour_start');
    expect(sent['target'], 'admissions');
    expect(sent['seriesKey'], ['run_id', 'hospital_id']);
    expect(sent['frequency'], '1h');
    expect(sent['missing'], 'zero');
    expect(sent['group'], 'default');
    expect(sent['algorithm'], 'DeepAR', reason: 'DeepAR unless XGBoost is picked, said explicitly');
    expect(sent['algorithms'], ['DeepAR']);
    expect(sent['horizon'], isNull);
    expect(find.text('DeepAR · default'), findsOneWidget);
    expect(find.text('default: DeepAR'), findsOneWidget);
    expect(find.text('time series: ready'), findsOneWidget);
    // The roles' tags, the group and its readiness say what they are too.
    expect(tip('The time index: a date or timestamp, one per table, in the default group.\nDeepAR takes it as start. Tag TimeSeries.Timestamp in OpenMetadata'), findsOneWidget);
    expect(tip('forecasting admissions'), findsOneWidget);
    expect(tip('datyx can train it as tagged'), findsOneWidget);
    expect(tip('Ready to train'), findsOneWidget);
  });

  testWidgets('tags a group for XGBoost, with its horizon, and shows what XGBoost makes of it', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await api.addDataSource(
      const NewDataSource(
        name: 'HealthHub',
        type: DataSourceType.database,
        details: {'engine': 'postgresql', 'host': 'localhost', 'port': 9803, 'database': 'healthhub'},
      ),
    );
    await api.syncCatalog(1);
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('public.admissions_hourly'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tag for training'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group')), 'care');
    // Several can be picked: XGBoost added, then DeepAR taken off.
    await tester.tap(find.text('XGBoost'));
    await tester.pump();
    expect(find.text('Tag public.admissions_hourly for XGBoost + DeepAR'), findsOneWidget);
    await tester.tap(find.text('DeepAR'));
    await tester.pump();
    expect(find.text('Tag public.admissions_hourly for XGBoost'), findsOneWidget);
    expect(find.text('Horizon (required)'), findsOneWidget);
    expect(find.text('label: sum over the horizon, one'), findsOneWidget, reason: 'the roles in XGBoost\'s terms');
    await tester.tap(find.byKey(const ValueKey('Timestamp-hour_start')));
    await tester.tap(find.byKey(const ValueKey('Target-admissions')));
    await tester.tap(find.byKey(const ValueKey('SeriesKey-run_id')));
    await tester.tap(find.byKey(const ValueKey('SeriesKey-hospital_id')));
    await tester.tap(find.byKey(const ValueKey('frequency-1h')));
    await tester.tap(find.byKey(const ValueKey('horizon-30D')));
    await tester.tap(find.text('counts as 0'));
    await tester.pump();
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();

    final sent = api.lastRoles!.toJson();
    expect(sent['group'], 'care');
    expect(sent['algorithm'], 'XGBoost');
    expect(sent['algorithms'], ['XGBoost']);
    expect(sent['horizon'], '30D');
    expect(sent['target'], 'admissions');
    // The table says who trains the group, collapsed and open.
    expect(find.text('care: XGBoost, 30D ahead'), findsOneWidget);
    expect(find.text('care: trained by XGBoost'), findsOneWidget);
    expect(find.text('XGBoost · care'), findsOneWidget);
    expect(find.text('scores admissions summed over the next 30D, per run_id + hospital_id'), findsOneWidget);
    expect(find.text('label: sum over the horizon = admissions'), findsOneWidget);
    expect(find.text('horizon = 30D'), findsOneWidget);
    expect(find.text('care: Target · label: sum over the horizon'), findsOneWidget);
    Color chip(Key key) => (tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration).border!.top.color;
    expect(chip(const ValueKey('algorithm-tag-care-XGBoost')), chip(const ValueKey('tag-care-Target')),
        reason: 'the algorithm in its group\'s color');

    // Editing it starts from XGBoost and the table's horizon.
    await tester.tap(find.byKey(const ValueKey('edit-group-datyx-ds-1.healthhub.public.admissions_hourly-care')));
    await tester.pumpAndSettle();
    expect(find.text('Tag public.admissions_hourly for XGBoost: care'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('horizon'))).controller!.text, '30D');
  });

  testWidgets('adds a group of tags to a tagged table, and removes it', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi();
    await api.addDataSource(
      const NewDataSource(
        name: 'HealthHub',
        type: DataSourceType.database,
        details: {'engine': 'postgresql', 'host': 'localhost', 'port': 9803, 'database': 'healthhub'},
      ),
    );
    await api.syncCatalog(1);
    await api.setTimeSeries(
      1,
      const TimeSeriesRoles(
        table: 'datyx-ds-1.healthhub.public.admissions_hourly',
        columns: {
          TimeSeriesRole.timestamp: ['hour_start'],
          TimeSeriesRole.target: ['admissions'],
          TimeSeriesRole.seriesKey: ['run_id', 'hospital_id'],
        },
        frequency: '1h',
        missing: 'zero',
      ),
    );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('public.admissions_hourly'));
    await tester.pumpAndSettle();

    // A new group starts from the default's roles but its target.
    await tester.tap(find.text('Add a group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group')), 'acute');
    await tester.tap(find.byKey(const ValueKey('Target-acute_admissions')));
    await tester.pump();
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();
    final sent = api.lastRoles!.toJson();
    expect(sent['group'], 'acute');
    expect(sent['timestamp'], 'hour_start');
    expect(sent['target'], 'acute_admissions');
    expect(sent['seriesKey'], ['run_id', 'hospital_id']);
    expect(find.text('DeepAR · default'), findsOneWidget);
    expect(find.text('DeepAR · acute'), findsOneWidget);
    expect(find.text('2 time series: all ready'), findsOneWidget);
    // Each group has a color of its own, on its box and on its tags.
    Color dot(String group) =>
        (tester.widget<Container>(find.byKey(ValueKey('group-color-$group'))).decoration! as BoxDecoration).color!;
    Color chip(String group, String role) =>
        (tester.widget<Container>(find.byKey(ValueKey('tag-$group-$role'))).decoration! as BoxDecoration).border!.top.color;
    expect(dot('default'), groupPalette[0]);
    expect(dot('acute'), groupPalette[1]);
    expect(chip('default', 'Target'), groupPalette[0]);
    expect(chip('acute', 'Target'), groupPalette[1]);

    // A group's name is taken once.
    await tester.tap(find.text('Add a group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group')), 'acute');
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();
    expect(find.textContaining('has a group named acute already'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Removing sends the group with no roles, after a second press.
    await tester.tap(find.byKey(const ValueKey('edit-group-datyx-ds-1.healthhub.public.admissions_hourly-acute')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group')), findsNothing);
    await tester.tap(find.text('Remove group'));
    await tester.pump();
    await tester.tap(find.text('Remove its tags: sure?'));
    await tester.pumpAndSettle();
    expect(api.lastRoles!.group, 'acute');
    expect(api.lastRoles!.columns, isEmpty);
    expect(find.text('DeepAR · acute'), findsNothing);
    expect(find.text('time series: ready'), findsOneWidget);
  });

  testWidgets('disables and enables a group, its Disabled tag in OpenMetadata', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.admissions_hourly';
    final api = FakeDatyxApi();
    await api.addDataSource(
      const NewDataSource(
        name: 'HealthHub',
        type: DataSourceType.database,
        details: {'engine': 'postgresql', 'host': 'localhost', 'port': 9803, 'database': 'healthhub'},
      ),
    );
    await api.syncCatalog(1);
    for (final (group, target) in [(defaultGroup, 'admissions'), ('chronic', 'acute_admissions')]) {
      await api.setTimeSeries(
        1,
        TimeSeriesRoles(
          table: fqn,
          group: group,
          columns: {
            TimeSeriesRole.timestamp: const ['hour_start'],
            TimeSeriesRole.target: [target],
            TimeSeriesRole.seriesKey: const ['run_id', 'hospital_id'],
          },
          frequency: '1h',
          missing: 'zero',
        ),
      );
    }
    // chronic comes disabled, as the API answers it.
    await api.setGroupEnabled(1, fqn, 'chronic', false);
    api.enabledCalls.clear();
    // An API that doesn't say is read as enabled.
    expect(TimeSeriesSpec.fromJson(const {'table': fqn, 'group': 'acute'}).enabled, isTrue);
    expect(TimeSeriesSpec.fromJson(const {'table': fqn, 'group': 'acute', 'enabled': false}).enabled, isFalse);

    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    expect(find.text('2 time series: all ready, 1 disabled'), findsOneWidget);
    expect(find.text('chronic: DeepAR, disabled'), findsOneWidget);
    await tester.tap(find.text('public.admissions_hourly'));
    await tester.pumpAndSettle();

    // Disabled: switched off, muted, its tag shown on the box and on the table.
    Switch toggle(String group) => tester.widget<Switch>(find.byKey(ValueKey('enabled-$fqn-$group')));
    expect(toggle('chronic').value, isFalse);
    expect(toggle('default').value, isTrue);
    expect(find.text('Disabled'), findsOneWidget);
    expect(find.text('Enabled'), findsOneWidget);
    expect(find.byKey(const ValueKey('disabled-chip-chronic')), findsOneWidget);
    expect(find.text('TimeSeries.chronic.Disabled'), findsOneWidget);
    expect(find.text('chronic: disabled, not trained'), findsOneWidget);
    expect(find.byKey(const ValueKey('disabled-chip-default')), findsNothing);
    expect(
      find.byTooltip(
        'Disabled: datyx doesn\'t train this group. Enabling removes its TimeSeries.chronic.Disabled tag in '
        'OpenMetadata, and datyx queues a training run of it (DeepAR); removing the tag in OpenMetadata itself '
        'does the same.',
      ),
      findsOneWidget,
    );
    // Still editable.
    await tester.tap(find.byKey(const ValueKey('edit-group-$fqn-chronic')));
    await tester.pumpAndSettle();
    expect(find.text('Save tags'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Enabling removes the tag, and datyx queues a training run.
    await tester.tap(find.byKey(ValueKey('enabled-$fqn-chronic')));
    await tester.pumpAndSettle();
    expect(api.enabledCalls, ['$fqn chronic true']);
    expect(find.text('chronic enabled: datyx queues a training run of it (DeepAR); see the Training tab.'), findsOneWidget);
    expect(toggle('chronic').value, isTrue);
    expect(find.text('Disabled'), findsNothing);
    expect(find.text('TimeSeries.chronic.Disabled'), findsNothing);
    expect(find.text('chronic: disabled, not trained'), findsNothing);
    expect(find.text('chronic: DeepAR'), findsOneWidget);
    expect(find.text('2 time series: all ready'), findsOneWidget);

    // Disabling the default group tags the table TimeSeries.Disabled.
    await tester.tap(find.byKey(ValueKey('enabled-$fqn-default')));
    await tester.pumpAndSettle();
    expect(api.enabledCalls.last, '$fqn default false');
    expect(toggle('default').value, isFalse);
    expect(find.text('TimeSeries.Disabled'), findsOneWidget);
    expect(find.text('disabled, not trained'), findsOneWidget);

    // An error shows the API's words, and the group stays as it was.
    api.groups.remove('chronic');
    await tester.tap(find.byKey(ValueKey('enabled-$fqn-chronic')));
    await tester.pumpAndSettle();
    expect(find.textContaining('timeseries/enabled answered 404'), findsOneWidget);
    expect(toggle('chronic').value, isTrue);
  });

  testWidgets('shows the models datyx trains, what they found and their runs, and trains one now', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.patient_days';
    final now = DateTime.now();
    final done = TrainingRunInfo(
      id: 7,
      sourceId: 1,
      table: fqn,
      name: 'patient_days',
      group: 'care',
      trigger: 'initial',
      status: 'succeeded',
      queuedAt: now.subtract(const Duration(hours: 5)),
      finishedAt: now.subtract(const Duration(hours: 5)),
      seconds: 2.5,
      examples: 9000,
      test: const TestMetrics(examples: 1800, mae: 3.1, naiveMae: 5.2, meanMae: 6, improvement: 0.404, meanLabel: 7.5),
    );
    final failed = TrainingRunInfo(
      id: 8,
      sourceId: 1,
      table: fqn,
      name: 'patient_days',
      group: 'care',
      trigger: 'schedule',
      status: 'failed',
      queuedAt: now.subtract(const Duration(minutes: 30)),
      error: 'the data source can\'t be read: refused',
    );
    final api = FakeDatyxApi()
      ..trainingOverview = TrainingOverview(
        models: [
          TrainingModel(
            sourceId: 1,
            source: 'HealthHub',
            table: fqn,
            schema: 'public',
            name: 'patient_days',
            group: 'care',
            target: 'stay_hours',
            seriesKey: const ['run_id', 'person_id'],
            ready: true,
            frequency: '1D',
            horizon: '30D',
            retrain: '6h',
            retrainEvery: '6h',
            nextAt: now.add(const Duration(minutes: 30)),
            latest: failed,
            lastSucceeded: done,
          ),
        ],
        runs: [failed, done],
      );
    api.runDetails[7] = TrainingRunDetail(
      run: done,
      importance: const [FeatureWeight('stay_hours, last 30D', 0.42), FeatureWeight('age', 0.1)],
      scores: const [
        SeriesScore({'run_id': 'adf5309c', 'person_id': 'reus-3'}, 41.5, 12),
      ],
    );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-training')));
    await tester.pumpAndSettle();

    expect(find.text('XGBoost · care'), findsOneWidget);
    expect(find.text('Scores stay_hours summed over the next 30D, per run_id + person_id, from steps of 1D.'), findsOneWidget);
    expect(find.textContaining('Next in 2'), findsOneWidget);
    expect(find.textContaining('The latest run failed: the data source can\'t be read'), findsOneWidget);
    // The latest success's metrics as tiles, its weights as bars, its scores as a table.
    expect(find.descendant(of: find.byKey(const ValueKey('tile-mae')), matching: find.text('3.10')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tile-naive')), matching: find.text('5.20')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tile-better')), matching: find.text('40%')), findsOneWidget);
    expect(find.text('42.0%'), findsOneWidget);
    double bar(String feature) => tester.getSize(find.byKey(ValueKey('weight-$feature'))).width;
    expect(bar('age'), lessThan(bar('stay_hours, last 30D') / 3));
    expect(find.text('reus-3'), findsOneWidget);
    expect(find.text('41.5'), findsOneWidget);
    // Every run, newest first.
    expect(find.byKey(const ValueKey('run-8')), findsOneWidget);
    expect(find.text('MAE 3.10 vs naive 5.20, 9000 examples'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('run-8'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('run-7'))).dy),
    );

    await tester.tap(find.byKey(const ValueKey('train-now-$fqn-care')));
    await tester.pumpAndSettle();
    expect(api.trainCalls, ['1 $fqn care XGBoost'], reason: 'the model\'s algorithm, said explicitly');
    expect(find.text('Queued: training now.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('retrain-never')));
    await tester.tap(find.byKey(const ValueKey('save-retrain-$fqn-care')));
    await tester.pumpAndSettle();
    expect(api.retrainCalls, ['never']);
    expect(find.text('Saved in OpenMetadata: retrain never.'), findsOneWidget);
  });

  testWidgets('shows a DeepAR group: forecasts step by step, its errors a step, its band, no weights', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.admissions_hourly';
    final now = DateTime.now();
    final done = TrainingRunInfo(
      id: 11,
      sourceId: 1,
      table: fqn,
      name: 'admissions_hourly',
      group: 'default',
      algorithm: deepArAlgorithm,
      trigger: 'initial',
      status: 'succeeded',
      queuedAt: now.subtract(const Duration(minutes: 10)),
      finishedAt: now.subtract(const Duration(minutes: 9)),
      seconds: 47.2,
      examples: 48000,
      test: const TestMetrics(examples: 6648, mae: 0.005, naiveMae: 0.008, meanMae: 0.009, improvement: 0.375, meanLabel: 0.006),
    );
    final api = FakeDatyxApi()
      ..trainingOverview = TrainingOverview(
        models: [
          TrainingModel(
            sourceId: 1,
            source: 'HealthHub',
            table: fqn,
            schema: 'public',
            name: 'admissions_hourly',
            group: 'default',
            algorithm: deepArAlgorithm,
            target: 'admissions',
            seriesKey: const ['run_id', 'hospital_id'],
            ready: true,
            frequency: '1h',
            horizon: '1D',
            retrainEvery: '1D',
            nextAt: now.add(const Duration(hours: 23)),
            latest: done,
            lastSucceeded: done,
          ),
        ],
        runs: [done],
      );
    api.runDetails[11] = TrainingRunDetail(
      run: done,
      coverage: 0.994,
      scores: const [
        SeriesScore({'run_id': 'adf5309c', 'hospital_id': '376'}, 0.17, 0),
      ],
    );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-training')));
    await tester.pumpAndSettle();

    expect(find.text('DeepAR · default'), findsOneWidget);
    expect(find.text('Forecasts admissions step by step over the next 1D, per run_id + hospital_id, from steps of 1h.'),
        findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tile-mae')), matching: find.text('0.005')), findsOneWidget);
    expect(find.text("admissions a step, the forecast's median"), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('tile-coverage')), matching: find.text('99%')), findsOneWidget);
    expect(find.byType(FeatureWeights), findsNothing);
    expect(find.text('376'), findsOneWidget);
  });

  testWidgets('shows a run triggered by enabling a group, with its note, and a disabled group', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.admissions_hourly';
    const note = 'TimeSeries.chronic.Disabled removed in OpenMetadata (table version 0.9, by admin, 2026-11-01 12:00 UTC)';
    final run = TrainingRunInfo.fromJson(const {
      'id': 12,
      'sourceId': 1,
      'table': fqn,
      'name': 'admissions_hourly',
      'group': 'chronic',
      'algorithm': 'DeepAR',
      'trigger': 'enabled',
      'triggerNote': note,
      'status': 'failed',
      'error': 'the data source can\'t be read: connection refused',
    });
    expect(run.triggerNote, note);
    final api = FakeDatyxApi()
      ..trainingOverview = TrainingOverview(
        models: [
          TrainingModel(
            sourceId: 1,
            source: 'HealthHub',
            table: fqn,
            schema: 'public',
            name: 'admissions_hourly',
            group: 'chronic',
            algorithm: deepArAlgorithm,
            ready: true,
            latest: run,
          ),
          TrainingModel.fromJson(const {
            'sourceId': 1,
            'source': 'HealthHub',
            'table': fqn,
            'schema': 'public',
            'name': 'admissions_hourly',
            'group': 'acute',
            'algorithm': 'DeepAR',
            'ready': true,
            'enabled': false,
            'nextAt': null,
          }),
        ],
        runs: [run],
      );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-training')));
    await tester.pumpAndSettle();

    // The run says why it ran: the tag removed, in which version of the table.
    expect(find.descendant(of: find.byKey(const ValueKey('run-12')), matching: find.text('enabled')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('run-note-12')), matching: find.text(note)), findsOneWidget);
    expect(find.text('The latest run (enabled): $note'), findsOneWidget);
    // A disabled group: never next, and not trained now.
    expect(find.text('disabled'), findsOneWidget);
    expect(find.textContaining('Disabled: not trained until enabled on the Catalog tab'), findsOneWidget);
    expect(find.textContaining('TimeSeries.acute.Disabled tag'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const ValueKey('train-now-$fqn-acute'))).onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const ValueKey('train-now-$fqn-chronic'))).onPressed,
      isNotNull,
    );
  });

  test('reads a group\'s algorithms, and sends them', () {
    const fqn = 'datyx-ds-1.healthhub.public.patient_days';
    final both = TimeSeriesSpec.fromJson(const {
      'table': fqn,
      'group': 'care',
      'algorithm': 'XGBoost',
      'algorithms': ['XGBoost', 'DeepAR'],
    });
    expect(both.algorithms, ['XGBoost', 'DeepAR']);
    expect(both.algorithm, 'XGBoost');
    expect(both.xgBoost, isTrue);
    // An API that only says algorithm: that one; one that says neither: DeepAR.
    expect(TimeSeriesSpec.fromJson(const {'table': fqn, 'algorithm': 'XGBoost'}).algorithms, ['XGBoost']);
    final none = TimeSeriesSpec.fromJson(const {'table': fqn});
    expect(none.algorithms, ['DeepAR']);
    expect(none.xgBoost, isFalse);
    expect(TimeSeriesRole.target.toEach(both.algorithms), 'label: sum over the horizon / target');
    expect(TimeSeriesRole.target.toEach(const ['DeepAR']), 'target');
    expect(inAlgorithmOrder({'DeepAR', 'XGBoost'}), ['XGBoost', 'DeepAR']);

    // Roles send algorithms, the first as algorithm for an API that takes one.
    final sent = const TimeSeriesRoles(table: fqn, group: 'care', algorithms: ['XGBoost', 'DeepAR']).toJson();
    expect(sent['algorithms'], ['XGBoost', 'DeepAR']);
    expect(sent['algorithm'], 'XGBoost');
    final untagged = const TimeSeriesRoles(table: fqn, algorithms: []).toJson();
    expect(untagged['algorithms'], isEmpty);
    expect(untagged['algorithm'], isNull);
    final old = const TimeSeriesRoles(table: fqn, algorithm: 'DeepAR').toJson();
    expect(old.containsKey('algorithms'), isFalse);
    expect(old['algorithm'], 'DeepAR');

    // A switch, and a run it queued.
    final event = GroupEvent.fromJson(const {
      'id': 5,
      'sourceId': 1,
      'source': 'HealthHub',
      'table': 'datyx-ds-1.healthhub.public.admissions_hourly',
      'name': 'admissions_hourly',
      'group': 'chronic',
      'enabled': true,
      'via': 'openmetadata-webhook',
      'version': 0.9,
      'by': 'admin',
      'at': '2026-11-01T12:00:00Z',
      'receivedAt': '2026-11-01T12:00:01Z',
      'runIds': [12, 13],
    });
    expect(event.version, '0.9');
    expect(event.runIds, [12, 13]);
    expect(event.viaWords, 'OpenMetadata\'s webhook');
    expect(event.at, DateTime.utc(2026, 11, 1, 12));
    expect(GroupEvent.fromJson(const {'id': 6, 'group': 'acute', 'enabled': false}).runIds, isEmpty);
    expect(TrainingRunInfo.fromJson(const {'id': 12, 'eventId': 5}).eventId, 5);
    expect(TrainingRunInfo.fromJson(const {'id': 11}).eventId, isNull);
  });

  testWidgets('tags a group for XGBoost and DeepAR, and enabling it queues a run of each', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.admissions_hourly';
    final api = FakeDatyxApi();
    await api.addDataSource(
      const NewDataSource(
        name: 'HealthHub',
        type: DataSourceType.database,
        details: {'engine': 'postgresql', 'host': 'localhost', 'port': 9803, 'database': 'healthhub'},
      ),
    );
    await api.syncCatalog(1);
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-catalog')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('public.admissions_hourly'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tag for training'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('group')), 'care');
    await tester.tap(find.text('XGBoost'));
    await tester.pump();
    expect(find.text('Tag public.admissions_hourly for XGBoost + DeepAR'), findsOneWidget);
    expect(find.text('Horizon (required)'), findsOneWidget, reason: 'XGBoost is among them');
    expect(find.text('label: sum over the horizon / target, one'), findsOneWidget, reason: 'the roles in both\'s terms');
    // One at least: the last one picked stays.
    await tester.tap(find.text('XGBoost'));
    await tester.pump();
    await tester.tap(find.text('DeepAR'));
    await tester.pump();
    expect(find.text('Tag public.admissions_hourly for DeepAR'), findsOneWidget);
    await tester.tap(find.text('XGBoost'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('Timestamp-hour_start')));
    await tester.tap(find.byKey(const ValueKey('Target-admissions')));
    await tester.tap(find.byKey(const ValueKey('SeriesKey-hospital_id')));
    await tester.tap(find.byKey(const ValueKey('frequency-1h')));
    await tester.tap(find.byKey(const ValueKey('horizon-30D')));
    await tester.tap(find.text('Save tags'));
    await tester.pumpAndSettle();

    final sent = api.lastRoles!.toJson();
    expect(sent['algorithms'], ['XGBoost', 'DeepAR'], reason: 'in the API\'s order, XGBoost first');
    expect(sent['algorithm'], 'XGBoost');
    // Every algorithm of the group shows: closed, on its box and as its tags.
    expect(find.text('care: XGBoost + DeepAR, 30D ahead'), findsOneWidget);
    expect(find.text('XGBoost + DeepAR · care'), findsOneWidget);
    expect(find.text('care: trained by XGBoost'), findsOneWidget);
    expect(find.text('care: trained by DeepAR'), findsOneWidget);
    expect(find.byKey(const ValueKey('algorithm-tag-care-DeepAR')), findsOneWidget);
    expect(find.text('care: Target · label: sum over the horizon / target'), findsOneWidget);
    expect(find.text('label: sum over the horizon / target = admissions'), findsOneWidget);
    expect(find.text('scores admissions summed over the next 30D, per hospital_id'), findsOneWidget);
    expect(
      find.byTooltip(
        'Enabled: datyx trains this group with each of its algorithms (XGBoost, DeepAR). Disabling adds the tag '
        'TimeSeries.care.Disabled to the table in OpenMetadata, and datyx stops training it.',
      ),
      findsOneWidget,
    );

    // Off, then on: the switch says a run is queued for each algorithm.
    await tester.tap(find.byKey(const ValueKey('enabled-$fqn-care')));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip(
        'Disabled: datyx doesn\'t train this group. Enabling removes its TimeSeries.care.Disabled tag in '
        'OpenMetadata, and datyx queues a run for each of its algorithms: XGBoost, DeepAR; removing the tag in '
        'OpenMetadata itself does the same.',
      ),
      findsOneWidget,
    );
    // The disabling's snack bar goes first.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('enabled-$fqn-care')));
    await tester.pumpAndSettle();
    expect(api.enabledCalls, ['$fqn care false', '$fqn care true']);
    expect(
      find.text('care enabled: datyx queues a run for each of its algorithms: XGBoost, DeepAR; see the Training tab.'),
      findsOneWidget,
    );
    expect(api.events.single.runIds, hasLength(2));

    // Editing starts from both.
    await tester.tap(find.byKey(const ValueKey('edit-group-$fqn-care')));
    await tester.pumpAndSettle();
    expect(find.text('Tag public.admissions_hourly for XGBoost + DeepAR: care'), findsOneWidget);
  });

  testWidgets('lists the group switches, and links each run to the switch that queued it', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.patient_days';
    const note = 'TimeSeries.care.Disabled removed in OpenMetadata (table version 0.9, by admin, 2026-11-01 12:00 UTC; webhook)';
    TrainingRunInfo run(int id, String algorithm, String status) => TrainingRunInfo.fromJson({
      'id': id,
      'sourceId': 1,
      'table': fqn,
      'name': 'patient_days',
      'group': 'care',
      'algorithm': algorithm,
      'trigger': 'enabled',
      'triggerNote': note,
      'eventId': 5,
      'status': status,
      if (algorithm == 'DeepAR') 'error': 'the data source can\'t be read: connection refused',
    });
    final xgb = run(12, 'XGBoost', 'queued');
    final deepAr = run(13, 'DeepAR', 'failed');
    final api = FakeDatyxApi()
      ..trainingOverview = TrainingOverview(
        models: [
          TrainingModel(
            sourceId: 1,
            source: 'HealthHub',
            table: fqn,
            schema: 'public',
            name: 'patient_days',
            group: 'care',
            ready: true,
            latest: xgb,
          ),
        ],
        runs: [deepAr, xgb],
      )
      ..events = [
        GroupEvent(
          id: 5,
          sourceId: 1,
          source: 'HealthHub',
          table: fqn,
          name: 'patient_days',
          group: 'care',
          enabled: true,
          via: 'openmetadata-webhook',
          version: '0.9',
          by: 'admin',
          at: DateTime(2026, 11, 1, 12),
          runIds: const [12, 13],
        ),
        GroupEvent(
          id: 4,
          sourceId: 1,
          source: 'HealthHub',
          table: fqn,
          name: 'patient_days',
          group: 'care',
          enabled: false,
          via: 'datyx-api',
          version: '0.8',
          by: 'tests@example.com',
          at: DateTime(2026, 11, 1, 11),
        ),
      ];
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-training')));
    // A run is queued: the tab asks again every 3 s, so it never settles.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Each run says its algorithm, and links to the switch that queued it.
    expect(find.descendant(of: find.byKey(const ValueKey('run-12')), matching: find.text('XGBoost')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('run-13')), matching: find.text('DeepAR')), findsOneWidget);
    expect(find.textContaining('the data source can\'t be read'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('run-event-12')), matching: find.text('switch #5')), findsOneWidget);

    // The switches, newest first: on and off, how datyx heard, by whom, the version and the runs.
    final on = find.byKey(const ValueKey('event-5'));
    final off = find.byKey(const ValueKey('event-4'));
    expect(find.descendant(of: on, matching: find.text('switched on')), findsOneWidget);
    expect(find.descendant(of: on, matching: find.text('via OpenMetadata\'s webhook')), findsOneWidget);
    expect(find.descendant(of: on, matching: find.text('by admin')), findsOneWidget);
    expect(find.descendant(of: on, matching: find.text('table version 0.9')), findsOneWidget);
    expect(find.descendant(of: on, matching: find.text('queued runs 12, 13')), findsOneWidget);
    expect(find.descendant(of: off, matching: find.text('switched off')), findsOneWidget);
    expect(find.descendant(of: off, matching: find.text('via the datyx API')), findsOneWidget);
    expect(find.descendant(of: off, matching: find.text('not trained while off')), findsOneWidget);
    expect(tester.getTopLeft(on).dy, lessThan(tester.getTopLeft(off).dy));

    // Following a run's link highlights its switch.
    Color border(Finder f) => (tester.widget<Container>(f).decoration! as BoxDecoration).border!.top.color;
    expect(border(on), Colors.transparent);
    await tester.tap(find.byKey(const ValueKey('run-event-13')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(border(on), isNot(Colors.transparent));
    expect(border(off), Colors.transparent);
    // Leave no timer behind.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows the training when the group switches can\'t be read', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final api = FakeDatyxApi()
      ..eventsError = ApiException('GET /api/catalog/events answered 404', status: 404);
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-training')));
    await tester.pumpAndSettle();
    expect(find.text('GET /api/catalog/events answered 404'), findsOneWidget);
    expect(find.textContaining('No group is tagged yet'), findsOneWidget);

    api
      ..eventsError = null
      ..events = const [GroupEvent(id: 1, group: 'chronic', enabled: true, name: 'admissions_hourly', via: 'poll')];
    await tester.tap(find.byKey(const ValueKey('training-reload')));
    await tester.pumpAndSettle();
    expect(find.text('via datyx\'s minute check'), findsOneWidget);
    expect(find.text('no run queued'), findsOneWidget);
  });

  testWidgets('accounts for inference calls, and scores a series by its key or all still observed', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    const fqn = 'datyx-ds-1.healthhub.public.patient_days';
    final now = DateTime.now().toUtc();
    final top = DateTime.utc(now.year, now.month, now.day, now.hour);
    final api = FakeDatyxApi()
      ..inferenceAccount = InferenceAccount(
        totals: const InferenceStats(calls: 12, failed: 1, scored: 40, avgMillis: 18.5, p50Millis: 14, p95Millis: 61),
        lastHour: 5,
        models: [
          InferenceModel(
            sourceId: 1,
            source: 'HealthHub',
            table: fqn,
            name: 'patient_days',
            group: 'care',
            runId: 7,
            trainedAt: now,
            target: 'stay_hours',
            horizon: '30D',
            seriesKey: const ['run_id', 'person_id'],
            stats: InferenceStats(calls: 12, failed: 1, scored: 40, avgMillis: 18.5, p50Millis: 14, p95Millis: 61, lastCalledAt: now),
          ),
        ],
        perHour: [
          for (var h = 23; h >= 0; h--) InferenceHour(top.subtract(Duration(hours: h)), h == 0 ? 5 : (h == 3 ? 10 : 0), h == 3 ? 1 : 0),
        ],
        calls: [
          InferenceCallInfo(id: 31, name: 'patient_days', group: 'care', runId: 7, calledAt: now, millis: 14, requested: 2, scored: 1, caller: 'ana@example.com'),
          InferenceCallInfo(
            id: 30,
            name: 'patient_days',
            group: 'care',
            runId: 7,
            calledAt: now,
            millis: 3,
            requested: 1,
            status: 'failed',
            error: 'a series names its key: run_id, person_id',
          ),
        ],
      );
    await tester.pumpWidget(DatyxDashApp(api: api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab-inference')));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byKey(const ValueKey('total-calls')), matching: find.text('12')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('total-last-hour')), matching: find.text('5')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('total-p95')), matching: find.text('61 ms')), findsOneWidget);
    expect(find.text('the last 24 hours; the tallest is 10'), findsOneWidget);
    double column(int hoursAgo) => tester
        .getSize(find.byKey(ValueKey('hour-${top.subtract(Duration(hours: hoursAgo)).toIso8601String()}')))
        .height;
    expect(column(3), 90);
    expect(column(0), 45, reason: 'half the tallest');
    expect(column(1), 0);
    expect(find.text('XGBoost · care'), findsOneWidget);
    expect(find.textContaining('Predicts stay_hours over the next 30D, per run_id + person_id.'), findsOneWidget);
    expect(find.text('2 asked, 1 scored'), findsOneWidget);
    expect(find.text('a series names its key: run_id, person_id'), findsOneWidget);

    // Score is on once the whole key is typed.
    final score = find.byKey(const ValueKey('score-$fqn-care'));
    expect(tester.widget<FilledButton>(score).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('key-run_id')), 'adf5309c');
    await tester.enterText(find.byKey(const ValueKey('key-person_id')), 'reus-3');
    await tester.pump();
    await tester.tap(score);
    await tester.pumpAndSettle();
    expect(api.scoreCalls.last, [
      {'run_id': 'adf5309c', 'person_id': 'reus-3'},
    ]);
    expect(find.text('Call 41: 1 scored in 12 ms by run 7'), findsOneWidget);
    expect(find.text('3.3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('score-all-$fqn-care')));
    await tester.pumpAndSettle();
    expect(api.scoreCalls.last, isNull, reason: 'none named: all still observed');
    expect(find.text('reus-4'), findsOneWidget);
  });

  test('says milliseconds without a decimal when they are whole', () {
    expect(ms(36), '36 ms');
    expect(ms(36.0), '36 ms');
    expect(ms(18.5), '18.5 ms');
    expect(ms(null), '–');
  });

  test('colors groups by name, the default first, gray past the palette', () {
    final colors = groupColors(['zeta', 'chronic', 'default', 'acute', 'chronic']);
    expect(colors.keys, ['default', 'acute', 'chronic', 'zeta']);
    expect(colors.values, [...groupPalette, otherGroupColor]);
    expect(groupColors(['chronic', 'acute']).values, groupPalette.take(2));
  });

  test('names a table\'s kind, a tag\'s classification and a cleanup policy', () {
    expect(tableKind('Regular'), 'Table');
    expect(tableKind('View'), 'View');
    expect(tableKind('MaterializedView'), 'Materialized view');
    expect(tableKind('Partitioned'), 'Partitioned table');
    expect(tableKind(null), 'Table');
    expect(tagHelp('PII.Sensitive'), startsWith('Tag Sensitive of the PII classification'));
    expect(tagHelp('Tier.Tier1'), startsWith('Tag Tier1 of the Tier classification'));
    expect(tagHelp('loose'), 'Tag loose in OpenMetadata');
    expect(cleanupHelp('delete'), contains('older than the retention'));
    expect(cleanupHelp('compact'), contains('latest record of each key'));
    expect(cleanupHelp('other'), startsWith('Cleanup policy other'));
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
