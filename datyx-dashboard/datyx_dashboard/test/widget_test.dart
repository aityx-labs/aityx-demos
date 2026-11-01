import 'dart:convert';

import 'package:datyx_dashboard/api/datyx_api.dart';
import 'package:datyx_dashboard/auth/auth_controller.dart';
import 'package:datyx_dashboard/dashboard/catalog_tab.dart' show groupColors, groupPalette, otherGroupColor;
import 'package:datyx_dashboard/dashboard/dashboard_screen.dart';
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
        // Each group's algorithm as a tag on the table, as the API answers it.
        tags: [
          for (final g in groups.values)
            g.group == defaultGroup ? 'TimeSeries.${g.algorithm}' : 'TimeSeries.${g.group}.${g.algorithm}',
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
    expect(sent['horizon'], isNull);
    expect(find.text('DeepAR · default'), findsOneWidget);
    expect(find.text('default: DeepAR'), findsOneWidget);
    expect(find.text('time series: ready'), findsOneWidget);
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
    await tester.tap(find.text('XGBoost'));
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
    expect(chip(const ValueKey('algorithm-tag-care')), chip(const ValueKey('tag-care-Target')),
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

  test('colors groups by name, the default first, gray past the palette', () {
    final colors = groupColors(['zeta', 'chronic', 'default', 'acute', 'chronic']);
    expect(colors.keys, ['default', 'acute', 'chronic', 'zeta']);
    expect(colors.values, [...groupPalette, otherGroupColor]);
    expect(groupColors(['chronic', 'acute']).values, groupPalette.take(2));
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
