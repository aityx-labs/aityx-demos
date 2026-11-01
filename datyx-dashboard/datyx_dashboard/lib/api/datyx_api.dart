import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../persist/session_store.dart';

/// The system as the API sees it: `GET /api/health`, its checks by name.
/// `datyx` is the API itself (its version, configuration profile, launch
/// mode, jvm or native, and when it started), `Database connections health
/// check` is PostgreSQL's, `OpenMetadata` the catalogue's.
class SystemStatus {
  const SystemStatus({
    required this.name,
    required this.version,
    required this.startedAt,
    required this.database,
    required this.openMetadata,
    this.profile,
    this.launchMode,
    this.image,
  });

  factory SystemStatus.fromHealth(Map<String, Object?> json) {
    final checks = {
      for (final check in (json['checks'] as List? ?? const []))
        if (check is Map) check['name'] as String? ?? '': check.cast<String, Object?>(),
    };
    final api = (checks[apiCheck]?['data'] as Map?)?.cast<String, Object?>() ?? const {};
    return SystemStatus(
      name: checks.containsKey(apiCheck) ? apiCheck : '',
      version: api['version'] as String? ?? '',
      profile: api['profile'] as String?,
      launchMode: api['launchMode'] as String?,
      image: api['image'] as String?,
      startedAt: DateTime.tryParse(api['startedAt'] as String? ?? ''),
      database: Dependency.fromCheck(checks['Database connections health check']),
      openMetadata: Dependency.fromCheck(checks['OpenMetadata']),
    );
  }

  /// The API's own check in `/api/health`.
  static const apiCheck = 'datyx';

  final String name;
  final String version;
  final String? profile;
  final String? launchMode;
  final String? image;
  final DateTime? startedAt;
  final Dependency database;
  final Dependency openMetadata;

  Duration get uptime =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);
}

/// A dependency's check in the health: ok, its version, or the error.
class Dependency {
  const Dependency({required this.ok, this.version, this.url, this.error});

  /// A check of `/api/health`: `{"name":..., "status":"UP"|"DOWN",
  /// "data":{...}}`. The error is `data.error`, else the first other value
  /// (the database check puts it under the datasource's name).
  factory Dependency.fromCheck(Map<String, Object?>? check) {
    if (check == null) return const Dependency(ok: false, error: 'no check');
    final data = (check['data'] as Map?)?.cast<String, Object?>() ?? const {};
    final ok = check['status'] == 'UP';
    final other = data.entries
        .where((e) => e.key != 'version' && e.key != 'url')
        .map((e) => e.value?.toString())
        .firstOrNull;
    return Dependency(
      ok: ok,
      version: data['version'] as String?,
      url: data['url'] as String?,
      error: ok ? null : (data['error'] as String? ?? other),
    );
  }

  final bool ok;
  final String? version;
  final String? url;
  final String? error;
}

/// How the API authenticates: `GET /api/auth/config`. Off until the API
/// has a client id; on, the issuer (Google) and the OpenID Connect client id
/// the app signs in with.
class AuthConfig {
  const AuthConfig({
    required this.enabled,
    required this.issuer,
    this.clientId,
  });

  factory AuthConfig.fromJson(Map<String, Object?> json) => AuthConfig(
    enabled: json['enabled'] == true,
    issuer: json['issuer'] as String? ?? '',
    clientId: json['clientId'] as String?,
  );

  final bool enabled;
  final String issuer;
  final String? clientId;
}

/// Who the API says is calling, and their profile: `GET /api/me`.
class Me {
  const Me({
    required this.authenticated,
    this.subject,
    this.email,
    this.name,
    this.picture,
    this.profileId,
  });

  factory Me.fromJson(Map<String, Object?> json) => Me(
    authenticated: json['authenticated'] == true,
    subject: json['subject'] as String?,
    email: json['email'] as String?,
    name: json['name'] as String?,
    picture: json['picture'] as String?,
    profileId: (json['profileId'] as num?)?.toInt(),
  );

  final bool authenticated;
  final String? subject;
  final String? email;
  final String? name;
  final String? picture;
  final int? profileId;
}

/// The caller's profile: `GET /api/profile`. Made by the API on the first
/// call of an identity; its identities, and how many data sources it owns.
class Profile {
  const Profile({
    required this.id,
    this.name,
    this.createdAt,
    this.dataSources = 0,
    this.identities = const [],
  });

  factory Profile.fromJson(Map<String, Object?> json) => Profile(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
    dataSources: (json['dataSources'] as num?)?.toInt() ?? 0,
    identities: [
      for (final item in json['identities'] as List? ?? const [])
        ProfileIdentity.fromJson((item as Map).cast<String, Object?>()),
    ],
  );

  final int id;
  final String? name;
  final DateTime? createdAt;
  final int dataSources;
  final List<ProfileIdentity> identities;
}

/// One sign-in a profile answers to: an issuer's subject, with the claims
/// the API last saw.
class ProfileIdentity {
  const ProfileIdentity({
    required this.issuer,
    required this.subject,
    this.email,
    this.name,
    this.picture,
    this.addedAt,
    this.lastSeenAt,
  });

  factory ProfileIdentity.fromJson(Map<String, Object?> json) =>
      ProfileIdentity(
        issuer: json['issuer'] as String? ?? '',
        subject: json['subject'] as String? ?? '',
        email: json['email'] as String?,
        name: json['name'] as String?,
        picture: json['picture'] as String?,
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
        lastSeenAt: DateTime.tryParse(json['lastSeenAt'] as String? ?? ''),
      );

  final String issuer;
  final String subject;
  final String? email;
  final String? name;
  final String? picture;
  final DateTime? addedAt;
  final DateTime? lastSeenAt;

  /// The issuer as a host (`accounts.google.com`), or as given (`local`).
  String get provider => Uri.tryParse(issuer)?.host.isNotEmpty == true
      ? Uri.parse(issuer).host
      : issuer;

  /// What to call it: the email, else the name, else the subject.
  String get label => email ?? name ?? subject;
}

/// The kinds of data source the API keeps, as its JSON names them.
enum DataSourceType {
  database('database', 'Database'),
  s3('s3', 'S3 bucket'),
  filesystem('filesystem', 'Filesystem'),
  kafka('kafka', 'Kafka');

  const DataSourceType(this.json, this.label);
  final String json;
  final String label;

  static DataSourceType parse(String? json) =>
      values.firstWhere((t) => t.json == json, orElse: () => filesystem);
}

/// A data source on record: `GET /api/datasources`. The access details come
/// under a key named after the type, without their secrets (the API answers
/// `passwordSet` and `secretAccessKeySet` instead).
class DataSource {
  const DataSource({
    required this.id,
    required this.name,
    required this.type,
    this.description,
    this.createdAt,
    this.createdBy,
    this.createdByName,
    this.details = const {},
  });

  factory DataSource.fromJson(Map<String, Object?> json) {
    final type = DataSourceType.parse(json['type'] as String?);
    return DataSource(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      type: type,
      description: json['description'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      createdBy: json['createdBy'] as String?,
      createdByName: json['createdByName'] as String?,
      details: (json[type.json] as Map?)?.cast<String, Object?>() ?? const {},
    );
  }

  final int id;
  final String name;
  final DataSourceType type;
  final String? description;
  final DateTime? createdAt;
  final String? createdBy;
  final String? createdByName;
  final Map<String, Object?> details;

  /// One line saying where it points, as the API describes it.
  String get summary {
    switch (type) {
      case DataSourceType.database:
        final user = details['username'];
        return '${details['engine']}://${details['host']}:${details['port']}/${details['database']}'
            '${user == null ? '' : ' as $user'}';
      case DataSourceType.s3:
        final region = details['region'];
        final endpoint = details['endpoint'];
        return 's3://${details['bucket']}/${details['prefix'] ?? ''}'
            '${region == null ? '' : ' ($region)'}${endpoint == null ? '' : ' at $endpoint'}';
      case DataSourceType.filesystem:
        return '${details['path']}';
      case DataSourceType.kafka:
        final protocol = details['securityProtocol'];
        final user = details['username'];
        return 'kafka://${details['bootstrapServers']}'
            '${protocol == null || protocol == 'PLAINTEXT' ? '' : ' ($protocol${details['saslMechanism'] == null ? '' : ', ${details['saslMechanism']}'})'}'
            '${user == null ? '' : ' as $user'}';
    }
  }
}

/// A topic of a Kafka source as the catalogue (OpenMetadata) has it:
/// `GET /api/datasources/{id}/catalog`, under `topics`.
class CatalogTopic {
  const CatalogTopic({
    required this.fqn,
    required this.name,
    this.description,
    this.partitions = 0,
    this.replicationFactor,
    this.cleanupPolicies = const [],
    this.retentionTime,
    this.retentionSize,
    this.schemaType,
    this.fields = const [],
    this.tags = const [],
  });

  factory CatalogTopic.fromJson(Map<String, Object?> json) => CatalogTopic(
    fqn: json['fqn'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    partitions: (json['partitions'] as num?)?.toInt() ?? 0,
    replicationFactor: (json['replicationFactor'] as num?)?.toInt(),
    cleanupPolicies: [for (final p in (json['cleanupPolicies'] as List?) ?? const []) '$p'],
    retentionTime: (json['retentionTime'] as num?)?.toInt(),
    retentionSize: (json['retentionSize'] as num?)?.toInt(),
    schemaType: json['schemaType'] as String?,
    fields: [
      for (final f in (json['fields'] as List?) ?? const [])
        CatalogField.fromJson((f as Map).cast<String, Object?>()),
    ],
    tags: [for (final t in (json['tags'] as List?) ?? const []) '$t'],
  );

  final String fqn;
  final String name;
  final String? description;
  final int partitions;
  final int? replicationFactor;
  final List<String> cleanupPolicies;

  /// How long records are kept, in ms; null when for ever.
  final int? retentionTime;

  /// How many bytes a partition keeps; null when unlimited.
  final int? retentionSize;
  final String? schemaType;
  final List<CatalogField> fields;
  final List<String> tags;
}

/// A field of a topic's records, with a record's own fields as [children].
class CatalogField {
  const CatalogField({required this.name, this.dataType, this.tags = const [], this.children = const []});

  factory CatalogField.fromJson(Map<String, Object?> json) => CatalogField(
    name: json['name'] as String? ?? '',
    dataType: json['dataType'] as String?,
    tags: [for (final t in (json['tags'] as List?) ?? const []) '$t'],
    children: [
      for (final c in (json['children'] as List?) ?? const [])
        CatalogField.fromJson((c as Map).cast<String, Object?>()),
    ],
  );

  final String name;
  final String? dataType;
  final List<String> tags;
  final List<CatalogField> children;
}

/// A table of a data source as the catalogue (OpenMetadata) has it:
/// `GET /api/datasources/{id}/catalog`.
class CatalogTable {
  const CatalogTable({
    required this.fqn,
    required this.name,
    this.schema,
    this.type,
    this.description,
    this.columns = const [],
    this.primaryKey = const [],
    this.properties = const {},
    this.tags = const [],
  });

  factory CatalogTable.fromJson(Map<String, Object?> json) => CatalogTable(
    fqn: json['fqn'] as String? ?? '',
    name: json['name'] as String? ?? '',
    schema: json['schema'] as String?,
    type: json['type'] as String?,
    description: json['description'] as String?,
    columns: [
      for (final c in (json['columns'] as List?) ?? const [])
        CatalogColumn.fromJson((c as Map).cast<String, Object?>()),
    ],
    primaryKey: [
      for (final c in ((json['constraints'] as Map?)?['PRIMARY_KEY'] as List?) ?? const [])
        '$c',
    ],
    properties: (json['properties'] as Map?)?.cast<String, Object?>() ?? const {},
    tags: [for (final t in (json['tags'] as List?) ?? const []) '$t'],
  );

  final String fqn;
  final String name;
  final String? schema;
  final String? type;
  final String? description;
  final List<CatalogColumn> columns;
  final List<String> primaryKey;
  final Map<String, Object?> properties;

  /// The table's own tags (a column's are its column's), among them the
  /// algorithm that trains a group: `TimeSeries.care.XGBoost`.
  final List<String> tags;

  String get qualifiedName => schema == null ? name : '$schema.$name';
}

class CatalogColumn {
  const CatalogColumn({
    required this.name,
    this.dataType,
    this.constraint,
    this.tags = const [],
  });

  factory CatalogColumn.fromJson(Map<String, Object?> json) => CatalogColumn(
    name: json['name'] as String? ?? '',
    dataType: json['dataType'] as String?,
    constraint: json['constraint'] as String?,
    tags: [for (final t in (json['tags'] as List?) ?? const []) '$t'],
  );

  final String name;
  final String? dataType;
  final String? constraint;
  final List<String> tags;
}

/// The group of the TimeSeries roles tagged without one (`TimeSeries.Target`).
const defaultGroup = 'default';

/// The algorithms that train a group, as the API names them and in its
/// order (XGBoost first): a group can have several, each a tag on the
/// table; a group without one is DeepAR's.
const deepArAlgorithm = 'DeepAR';
const xgBoostAlgorithm = 'XGBoost';
const algorithms = [xgBoostAlgorithm, deepArAlgorithm];

/// [names] in the API's order of [algorithms], once each.
List<String> inAlgorithmOrder(Iterable<String> names) => [
  for (final a in algorithms)
    if (names.contains(a)) a,
];

/// The roles a column can have in a forecast, as the API names them: the
/// tags of OpenMetadata's TimeSeries classification, the field each is in
/// `PUT /api/datasources/{id}/timeseries`, the DeepAR input it becomes and
/// what it is to XGBoost.
enum TimeSeriesRole {
  timestamp('Timestamp', 'timestamp', 'start', 'cutoffs', 'The time index: a date or timestamp, one per table'),
  target('Target', 'target', 'target', 'label: sum over the horizon', 'The value to forecast: a number, one per table'),
  seriesKey('SeriesKey', 'seriesKey', 'item_id', 'one score each', 'Which series a row belongs to; none: one series'),
  staticCategorical('StaticCategorical', 'staticCategorical', 'feat_static_cat', 'categorical feature', 'A category that holds for a whole series'),
  staticReal('StaticReal', 'staticReal', 'feat_static_real', 'numeric feature', 'A number that holds for a whole series'),
  knownCovariate('KnownCovariate', 'knownCovariates', 'feat_dynamic_real', 'features ahead', 'A number over time, known ahead for the hours to forecast'),
  pastCovariate('PastCovariate', 'pastCovariates', 'past_feat_dynamic_real', 'features: past sums', 'A number over time, known only once observed');

  const TimeSeriesRole(this.tag, this.field, this.deepAr, this.xgBoost, this.help);
  final String tag;
  final String field;
  final String deepAr;
  final String xgBoost;
  final String help;

  /// What the role becomes to [algorithm]: DeepAR's input, or its part in XGBoost's dataset.
  String to(String algorithm) => algorithm == xgBoostAlgorithm ? xgBoost : deepAr;

  /// What the role is to each of a group's [algorithms], once each, `/` between.
  String toEach(List<String> algorithms) => {for (final a in algorithms) to(a)}.join(' / ');

  String get fqn => 'TimeSeries.$tag';

  /// One column at most: the others take several.
  bool get single => this == timestamp || this == target;

  static TimeSeriesRole? ofName(String tag) {
    for (final role in values) {
      if (role.tag == tag) return role;
    }
    return null;
  }
}

/// A column's TimeSeries tag, as a role in a group: `TimeSeries.Target` is
/// the default group's Target, `TimeSeries.acute.Target` the acute group's.
class TimeSeriesTag {
  const TimeSeriesTag(this.group, this.role);

  final String group;
  final TimeSeriesRole role;

  /// The tag an FQN names, or null for one that isn't a TimeSeries role.
  static TimeSeriesTag? parse(String fqn) {
    final parts = fqn.split('.');
    if (parts.length < 2 || parts.length > 3 || parts.first != 'TimeSeries') return null;
    final role = TimeSeriesRole.ofName(parts.last);
    if (role == null) return null;
    return TimeSeriesTag(parts.length == 2 ? defaultGroup : parts[1], role);
  }
}

/// A table's tag naming the algorithm that trains a group:
/// `TimeSeries.XGBoost` for the default group, `TimeSeries.care.XGBoost`
/// for care.
class AlgorithmTag {
  const AlgorithmTag(this.group, this.algorithm);

  final String group;
  final String algorithm;

  /// The tag an FQN names, or null for one that isn't a TimeSeries algorithm.
  static AlgorithmTag? parse(String fqn) {
    final parts = fqn.split('.');
    if (parts.length < 2 || parts.length > 3 || parts.first != 'TimeSeries') return null;
    if (!algorithms.contains(parts.last)) return null;
    return AlgorithmTag(parts.length == 2 ? defaultGroup : parts[1], parts.last);
  }
}

/// The table tag that disables a group, so that datyx doesn't train it:
/// `TimeSeries.Disabled` for the default group, `TimeSeries.chronic.Disabled`
/// for chronic. Removing it enables the group again.
String disabledTag(String group) =>
    group == defaultGroup ? 'TimeSeries.Disabled' : 'TimeSeries.$group.Disabled';

/// The group a table's Disabled tag disables, or null for another tag.
String? disabledGroup(String fqn) {
  final parts = fqn.split('.');
  if (parts.length < 2 || parts.length > 3 || parts.first != 'TimeSeries' || parts.last != 'Disabled') return null;
  return parts.length == 2 ? defaultGroup : parts[1];
}

/// One group of a table read as a time series by the API:
/// `GET .../timeseries`, and the answer of `PUT .../timeseries` and of
/// `PUT .../timeseries/enabled`. [ready] when there are no [problems];
/// [enabled] unless the table carries the group's [disabledTag] (an API
/// that doesn't say: enabled). [algorithms] are all that train it, the
/// API's `algorithms` (an API that only says `algorithm`: that one).
class TimeSeriesSpec {
  const TimeSeriesSpec({
    required this.table,
    required this.name,
    this.group = defaultGroup,
    this._algorithm = deepArAlgorithm,
    this._algorithms,
    this.schema,
    this.columns = const {},
    this.frequency,
    this.horizon,
    this.missing,
    this.ready = false,
    this.problems = const [],
    this.enabled = true,
  });

  factory TimeSeriesSpec.fromJson(Map<String, Object?> json) {
    List<String> list(Object? value) => [
      if (value is String) value,
      if (value is List) for (final v in value) '$v',
    ];
    return TimeSeriesSpec(
      table: json['table'] as String? ?? '',
      name: json['name'] as String? ?? '',
      group: json['group'] as String? ?? defaultGroup,
      algorithm: json['algorithm'] as String? ?? deepArAlgorithm,
      algorithms: list(json['algorithms']),
      schema: json['schema'] as String?,
      columns: {
        for (final role in TimeSeriesRole.values) role: list(json[role.field]),
      },
      frequency: json['frequency'] as String?,
      horizon: json['horizon'] as String?,
      missing: json['missing'] as String?,
      ready: json['ready'] as bool? ?? false,
      problems: list(json['problems']),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  final String table;
  final String name;
  final String group;

  final String _algorithm;
  final List<String>? _algorithms;

  /// What trains the group, one model each: [xgBoostAlgorithm],
  /// [deepArAlgorithm] or both, in the API's order; [deepArAlgorithm]
  /// when the table has no tag for it.
  List<String> get algorithms => _algorithms == null || _algorithms.isEmpty ? [_algorithm] : _algorithms;

  /// The first of [algorithms], as the API's `algorithm` says.
  String get algorithm => algorithms.first;

  /// Whether XGBoost is among its [algorithms], which needs a horizon.
  bool get xgBoost => algorithms.contains(xgBoostAlgorithm);
  final String? schema;
  final Map<TimeSeriesRole, List<String>> columns;
  final String? frequency;

  /// How far ahead the group predicts (the table's, as a pandas offset); required for XGBoost.
  final String? horizon;
  final String? missing;
  final bool ready;
  final List<String> problems;

  /// Whether datyx trains the group: false while the table has its [disabledTag].
  final bool enabled;

  /// The tag in OpenMetadata that disables the group.
  String get disabledTagFqn => disabledTag(group);

  List<String> of(TimeSeriesRole role) => columns[role] ?? const [];

  String? get target => of(TimeSeriesRole.target).firstOrNull;
  List<String> get seriesKey => of(TimeSeriesRole.seriesKey);
}

/// What `PUT /api/datasources/{id}/timeseries` takes: a group's roles in a
/// table (no roles: the group is gone) and the algorithms that train it,
/// and the table's frequency, horizon and what a missing row means, which
/// its groups share.
class TimeSeriesRoles {
  const TimeSeriesRoles({
    required this.table,
    this.group = defaultGroup,
    this.algorithm,
    this.algorithms,
    this.columns = const {},
    this.frequency,
    this.horizon,
    this.missing,
  });

  final String table;
  final String group;

  /// One algorithm, [deepArAlgorithm] or [xgBoostAlgorithm], for an API
  /// that only takes one; null leaves the group untagged, DeepAR's.
  final String? algorithm;

  /// Every algorithm that trains the group, its tags exactly: sent as
  /// `algorithms`, which the API takes over [algorithm]; empty leaves the
  /// group untagged, DeepAR's.
  final List<String>? algorithms;
  final Map<TimeSeriesRole, List<String>> columns;
  final String? frequency;
  final String? horizon;
  final String? missing;

  Map<String, Object?> toJson() => {
    'table': table,
    'group': group,
    for (final role in TimeSeriesRole.values)
      role.field: role.single
          ? (columns[role]?.isNotEmpty ?? false ? columns[role]!.first : null)
          : columns[role] ?? const <String>[],
    'algorithm': algorithms == null ? algorithm : algorithms!.firstOrNull,
    'algorithms': ?algorithms,
    'frequency': frequency,
    'horizon': horizon,
    'missing': missing,
  };
}

/// The test metrics of a training run, as the API measured them: the mean
/// absolute error ([mae]) against the naive forecast's (the next horizon
/// like the last) and the training mean's, and [improvement], the share of
/// the naive error saved.
class TestMetrics {
  const TestMetrics({
    this.examples = 0,
    this.mae = 0,
    this.rmse = 0,
    this.naiveMae = 0,
    this.meanMae = 0,
    this.improvement = 0,
    this.meanLabel = 0,
  });

  factory TestMetrics.fromJson(Map<String, Object?> json) {
    double n(String k) => (json[k] as num?)?.toDouble() ?? 0;
    return TestMetrics(
      examples: (json['examples'] as num?)?.toInt() ?? 0,
      mae: n('mae'),
      rmse: n('rmse'),
      naiveMae: n('naiveMae'),
      meanMae: n('meanMae'),
      improvement: n('improvement'),
      meanLabel: n('meanLabel'),
    );
  }

  final int examples;
  final double mae;
  final double rmse;
  final double naiveMae;
  final double meanMae;
  final double improvement;
  final double meanLabel;
}

DateTime? _time(Object? value) => value is String ? DateTime.tryParse(value) : null;

/// A training run at a glance: why it ran ([trigger]: initial, schedule,
/// manual, or enabled, when the group's Disabled tag was removed in
/// OpenMetadata, with [triggerNote] saying which version of the table, by
/// whom and when), how it went ([status]: queued, running, succeeded,
/// failed) and, once it succeeded, its [test] metrics. A run queued by a
/// group switched on has its [GroupEvent]'s id, [eventId].
class TrainingRunInfo {
  const TrainingRunInfo({
    required this.id,
    required this.sourceId,
    required this.table,
    required this.name,
    required this.group,
    this.source = '',
    this.algorithm = xgBoostAlgorithm,
    this.trigger = 'manual',
    this.triggerNote,
    this.eventId,
    this.status = 'queued',
    this.queuedAt,
    this.startedAt,
    this.finishedAt,
    this.seconds,
    this.error,
    this.examples,
    this.test,
  });

  factory TrainingRunInfo.fromJson(Map<String, Object?> json) => TrainingRunInfo(
    id: (json['id'] as num).toInt(),
    sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? '',
    table: json['table'] as String? ?? '',
    name: json['name'] as String? ?? '',
    group: json['group'] as String? ?? defaultGroup,
    algorithm: json['algorithm'] as String? ?? xgBoostAlgorithm,
    trigger: json['trigger'] as String? ?? '',
    triggerNote: json['triggerNote'] as String?,
    eventId: (json['eventId'] as num?)?.toInt(),
    status: json['status'] as String? ?? '',
    queuedAt: _time(json['queuedAt']),
    startedAt: _time(json['startedAt']),
    finishedAt: _time(json['finishedAt']),
    seconds: (json['seconds'] as num?)?.toDouble(),
    error: json['error'] as String?,
    examples: (json['examples'] as num?)?.toInt(),
    test: json['test'] is Map ? TestMetrics.fromJson((json['test'] as Map).cast()) : null,
  );

  final int id;
  final int sourceId;
  final String source;
  final String table;
  final String name;
  final String group;
  final String algorithm;
  final String trigger;

  /// More on why it ran, when the API says: for `enabled`, the tag removed and the table's version.
  final String? triggerNote;

  /// The [GroupEvent] that queued it, when one did.
  final int? eventId;
  final String status;
  final DateTime? queuedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final double? seconds;
  final String? error;
  final int? examples;
  final TestMetrics? test;

  /// Queued or running: not done yet.
  bool get active => status == 'queued' || status == 'running';
}

/// A group tagged for XGBoost, as `GET /api/training` answers it: what it
/// scores, how often it is trained again ([retrainEvery], the table's
/// timeSeriesRetrain or 1D; [retrain] as set, null when not), when next
/// ([nextAt], null when never, while a run is on or while not [enabled]),
/// its latest run and its latest success. A group not [enabled] has its
/// Disabled tag in OpenMetadata, and isn't trained.
class TrainingModel {
  const TrainingModel({
    required this.sourceId,
    required this.table,
    required this.name,
    required this.group,
    this.source = '',
    this.schema,
    this.algorithm = xgBoostAlgorithm,
    this.target,
    this.seriesKey = const [],
    this.ready = false,
    this.problems = const [],
    this.frequency,
    this.horizon,
    this.retrain,
    this.retrainEvery = '1D',
    this.nextAt,
    this.enabled = true,
    this.latest,
    this.lastSucceeded,
  });

  factory TrainingModel.fromJson(Map<String, Object?> json) => TrainingModel(
    sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? '',
    table: json['table'] as String? ?? '',
    schema: json['schema'] as String?,
    name: json['name'] as String? ?? '',
    group: json['group'] as String? ?? defaultGroup,
    algorithm: json['algorithm'] as String? ?? xgBoostAlgorithm,
    target: json['target'] as String?,
    seriesKey: [for (final k in (json['seriesKey'] as List?) ?? const []) '$k'],
    ready: json['ready'] as bool? ?? false,
    problems: [for (final p in (json['problems'] as List?) ?? const []) '$p'],
    frequency: json['frequency'] as String?,
    horizon: json['horizon'] as String?,
    retrain: json['retrain'] as String?,
    retrainEvery: json['retrainEvery'] as String? ?? '1D',
    nextAt: _time(json['nextAt']),
    enabled: json['enabled'] as bool? ?? true,
    latest: json['latest'] is Map ? TrainingRunInfo.fromJson((json['latest'] as Map).cast()) : null,
    lastSucceeded: json['lastSucceeded'] is Map
        ? TrainingRunInfo.fromJson((json['lastSucceeded'] as Map).cast())
        : null,
  );

  final int sourceId;
  final String source;
  final String table;
  final String? schema;
  final String name;
  final String group;
  final String algorithm;
  final String? target;
  final List<String> seriesKey;
  final bool ready;
  final List<String> problems;
  final String? frequency;
  final String? horizon;
  final String? retrain;
  final String retrainEvery;
  final DateTime? nextAt;
  final bool enabled;
  final TrainingRunInfo? latest;
  final TrainingRunInfo? lastSucceeded;

  String get qualifiedName => schema == null ? name : '$schema.$name';
}

/// `GET /api/training`: the groups tagged for XGBoost, the latest runs of
/// them all, and the sources whose catalogue couldn't be read.
class TrainingOverview {
  const TrainingOverview({this.models = const [], this.runs = const [], this.errors = const []});

  factory TrainingOverview.fromJson(Map<String, Object?> json) => TrainingOverview(
    models: [
      for (final m in (json['models'] as List?) ?? const [])
        TrainingModel.fromJson((m as Map).cast()),
    ],
    runs: [
      for (final r in (json['runs'] as List?) ?? const [])
        TrainingRunInfo.fromJson((r as Map).cast()),
    ],
    errors: [for (final e in (json['errors'] as List?) ?? const []) '$e'],
  );

  final List<TrainingModel> models;
  final List<TrainingRunInfo> runs;
  final List<String> errors;

  /// Whether a run is queued or running: worth asking again soon.
  bool get busy => runs.any((r) => r.active) || models.any((m) => m.latest?.active ?? false);
}

/// A group switched on or off, as `GET /api/catalog/events` answers it:
/// its table's Disabled tag removed ([enabled]) or added, [via] how datyx
/// heard of it (`openmetadata-webhook`, OpenMetadata telling it;
/// `datyx-api`, switched through datyx; `poll`, its minute check), the
/// table's [version] in OpenMetadata, who changed it ([by]) and when
/// ([at]), when datyx heard ([receivedAt]), and the training runs it
/// queued ([runIds], one per algorithm of a group switched on).
class GroupEvent {
  const GroupEvent({
    required this.id,
    required this.group,
    required this.enabled,
    this.sourceId = 0,
    this.source = '',
    this.table = '',
    this.name = '',
    this.via = '',
    this.version,
    this.by,
    this.at,
    this.receivedAt,
    this.runIds = const [],
  });

  factory GroupEvent.fromJson(Map<String, Object?> json) => GroupEvent(
    id: (json['id'] as num).toInt(),
    sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? '',
    table: json['table'] as String? ?? '',
    name: json['name'] as String? ?? '',
    group: json['group'] as String? ?? defaultGroup,
    enabled: json['enabled'] as bool? ?? false,
    via: json['via'] as String? ?? '',
    version: json['version'] == null ? null : '${json['version']}',
    by: json['by'] as String?,
    at: _time(json['at']),
    receivedAt: _time(json['receivedAt']),
    runIds: [for (final r in (json['runIds'] as List?) ?? const []) (r as num).toInt()],
  );

  final int id;
  final int sourceId;
  final String source;
  final String table;
  final String name;
  final String group;
  final bool enabled;
  final String via;
  final String? version;
  final String? by;
  final DateTime? at;
  final DateTime? receivedAt;
  final List<int> runIds;

  /// How datyx heard of it, in words.
  String get viaWords => switch (via) {
    'openmetadata-webhook' => 'OpenMetadata\'s webhook',
    'datyx-api' => 'the datyx API',
    'poll' => 'datyx\'s minute check',
    _ => via,
  };
}

/// A feature's weight in a model: its [share] of the mean absolute SHAP contribution.
class FeatureWeight {
  const FeatureWeight(this.feature, this.share);
  final String feature;
  final double share;
}

/// A series scored at its end: its key's values, the [predicted] Target
/// over the horizon ahead, and its Target over the [last] horizon.
class SeriesScore {
  const SeriesScore(this.series, this.predicted, this.last);
  final Map<String, String> series;
  final double predicted;
  final double last;
}

/// `GET /api/training/runs/{id}`: a run and what it found, once it succeeded.
class TrainingRunDetail {
  const TrainingRunDetail({
    required this.run,
    this.importance = const [],
    this.scores = const [],
    this.dataset = const {},
    this.params = const {},
    this.bestIteration,
    this.coverage,
  });

  factory TrainingRunDetail.fromJson(Map<String, Object?> json) {
    final results = (json['results'] as Map?)?.cast<String, Object?>() ?? const {};
    return TrainingRunDetail(
      run: TrainingRunInfo.fromJson((json['run'] as Map).cast()),
      importance: [
        for (final i in (results['importance'] as List?) ?? const [])
          FeatureWeight('${(i as Map)['feature']}', (i['share'] as num?)?.toDouble() ?? 0),
      ],
      scores: [
        for (final sc in (results['scores'] as List?) ?? const [])
          SeriesScore(
            {
              for (final e in (((sc as Map)['series'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
            },
            (sc['predicted'] as num?)?.toDouble() ?? 0,
            (sc['last'] as num?)?.toDouble() ?? 0,
          ),
      ],
      dataset: (results['dataset'] as Map?)?.cast<String, Object?>() ?? const {},
      params: (results['params'] as Map?)?.cast<String, Object?>() ?? const {},
      bestIteration: (results['bestIteration'] as num?)?.toInt(),
      coverage: (results['coverage'] as num?)?.toDouble(),
    );
  }

  final TrainingRunInfo run;
  final List<FeatureWeight> importance;
  final List<SeriesScore> scores;
  final Map<String, Object?> dataset;
  final Map<String, Object?> params;
  final int? bestIteration;

  /// DeepAR's: the share of held-out steps inside the forecast's 10th to 90th percentiles.
  final double? coverage;
}

/// Inference calls' account: how many, how many failed, series scored,
/// and latency in milliseconds (mean, median, 95th percentile).
class InferenceStats {
  const InferenceStats({
    this.calls = 0,
    this.failed = 0,
    this.scored = 0,
    this.avgMillis,
    this.p50Millis,
    this.p95Millis,
    this.lastCalledAt,
  });

  factory InferenceStats.fromJson(Map<String, Object?> json) => InferenceStats(
    calls: (json['calls'] as num?)?.toInt() ?? 0,
    failed: (json['failed'] as num?)?.toInt() ?? 0,
    scored: (json['scored'] as num?)?.toInt() ?? 0,
    avgMillis: (json['avgMillis'] as num?)?.toDouble(),
    p50Millis: (json['p50Millis'] as num?)?.toInt(),
    p95Millis: (json['p95Millis'] as num?)?.toInt(),
    lastCalledAt: _time(json['lastCalledAt']),
  );

  final int calls;
  final int failed;
  final int scored;
  final double? avgMillis;
  final int? p50Millis;
  final int? p95Millis;
  final DateTime? lastCalledAt;
}

/// A model that answers inference (a group with a trained model) and its calls' account.
class InferenceModel {
  const InferenceModel({
    required this.sourceId,
    required this.table,
    required this.name,
    required this.group,
    this.source = '',
    this.runId,
    this.trainedAt,
    this.target,
    this.horizon,
    this.seriesKey = const [],
    this.stats = const InferenceStats(),
  });

  factory InferenceModel.fromJson(Map<String, Object?> json) => InferenceModel(
    sourceId: (json['sourceId'] as num?)?.toInt() ?? 0,
    source: json['source'] as String? ?? '',
    table: json['table'] as String? ?? '',
    name: json['name'] as String? ?? '',
    group: json['group'] as String? ?? defaultGroup,
    runId: (json['runId'] as num?)?.toInt(),
    trainedAt: _time(json['trainedAt']),
    target: json['target'] as String?,
    horizon: json['horizon'] as String?,
    seriesKey: [for (final k in (json['seriesKey'] as List?) ?? const []) '$k'],
    stats: json['stats'] is Map ? InferenceStats.fromJson((json['stats'] as Map).cast()) : const InferenceStats(),
  );

  final int sourceId;
  final String source;
  final String table;
  final String name;
  final String group;
  final int? runId;
  final DateTime? trainedAt;
  final String? target;
  final String? horizon;
  final List<String> seriesKey;
  final InferenceStats stats;
}

/// One inference call, as accounted: which model, how many series asked
/// ([requested], 0 for all those still observed) and scored, how long,
/// whether it failed, and who asked.
class InferenceCallInfo {
  const InferenceCallInfo({
    required this.id,
    required this.name,
    required this.group,
    this.runId = 0,
    this.calledAt,
    this.millis = 0,
    this.requested = 0,
    this.scored = 0,
    this.status = 'ok',
    this.error,
    this.caller,
  });

  factory InferenceCallInfo.fromJson(Map<String, Object?> json) => InferenceCallInfo(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String? ?? '',
    group: json['group'] as String? ?? defaultGroup,
    runId: (json['runId'] as num?)?.toInt() ?? 0,
    calledAt: _time(json['calledAt']),
    millis: (json['millis'] as num?)?.toInt() ?? 0,
    requested: (json['requested'] as num?)?.toInt() ?? 0,
    scored: (json['scored'] as num?)?.toInt() ?? 0,
    status: json['status'] as String? ?? '',
    error: json['error'] as String?,
    caller: json['caller'] as String?,
  );

  final int id;
  final String name;
  final String group;
  final int runId;
  final DateTime? calledAt;
  final int millis;
  final int requested;
  final int scored;
  final String status;
  final String? error;
  final String? caller;
}

/// One hour's calls.
class InferenceHour {
  const InferenceHour(this.hour, this.calls, this.failed);
  final DateTime hour;
  final int calls;
  final int failed;
}

/// `GET /api/inference`: the account of the last 7 days' calls: totals,
/// the last hour's, each model's, the last 24 hours hour by hour, and the
/// latest calls.
class InferenceAccount {
  const InferenceAccount({
    this.totals = const InferenceStats(),
    this.lastHour = 0,
    this.models = const [],
    this.perHour = const [],
    this.calls = const [],
  });

  factory InferenceAccount.fromJson(Map<String, Object?> json) => InferenceAccount(
    totals: json['totals'] is Map ? InferenceStats.fromJson((json['totals'] as Map).cast()) : const InferenceStats(),
    lastHour: (json['lastHour'] as num?)?.toInt() ?? 0,
    models: [
      for (final m in (json['models'] as List?) ?? const [])
        InferenceModel.fromJson((m as Map).cast()),
    ],
    perHour: [
      for (final h in (json['perHour'] as List?) ?? const [])
        InferenceHour(
          _time((h as Map)['hour']) ?? DateTime.fromMillisecondsSinceEpoch(0),
          (h['calls'] as num?)?.toInt() ?? 0,
          (h['failed'] as num?)?.toInt() ?? 0,
        ),
    ],
    calls: [
      for (final c in (json['calls'] as List?) ?? const [])
        InferenceCallInfo.fromJson((c as Map).cast()),
    ],
  );

  final InferenceStats totals;
  final int lastHour;
  final List<InferenceModel> models;
  final List<InferenceHour> perHour;
  final List<InferenceCallInfo> calls;
}

/// A series scored by a call: its key, the prediction and its Target over
/// the last horizon; or, with neither, why ([note]).
class Prediction {
  const Prediction(this.series, this.predicted, this.last, this.note);
  final Map<String, String> series;
  final double? predicted;
  final double? last;
  final String? note;
}

/// What `POST /api/datasources/{id}/inference` answers.
class InferenceAnswer {
  const InferenceAnswer({
    required this.callId,
    required this.runId,
    this.requested = 0,
    this.scored = 0,
    this.millis = 0,
    this.predictions = const [],
  });

  factory InferenceAnswer.fromJson(Map<String, Object?> json) => InferenceAnswer(
    callId: (json['callId'] as num).toInt(),
    runId: (json['runId'] as num).toInt(),
    requested: (json['requested'] as num?)?.toInt() ?? 0,
    scored: (json['scored'] as num?)?.toInt() ?? 0,
    millis: (json['millis'] as num?)?.toInt() ?? 0,
    predictions: [
      for (final p in (json['predictions'] as List?) ?? const [])
        Prediction(
          {for (final e in (((p as Map)['series'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
          (p['predicted'] as num?)?.toDouble(),
          (p['last'] as num?)?.toDouble(),
          p['note'] as String?,
        ),
    ],
  );

  final int callId;
  final int runId;
  final int requested;
  final int scored;
  final int millis;
  final List<Prediction> predictions;
}

/// What `POST /api/datasources/{id}/catalog` answers: what it wrote. A
/// database's tables and columns, or a Kafka cluster's topics, their
/// top-level fields and how many had a record to learn them from.
class CatalogSync {
  const CatalogSync({
    this.tables = 0,
    this.columns = 0,
    this.topics = 0,
    this.fields = 0,
    this.sampled = 0,
    this.removed = const [],
  });

  factory CatalogSync.fromJson(Map<String, Object?> json) => CatalogSync(
    tables: (json['tables'] as num?)?.toInt() ?? 0,
    columns: (json['columns'] as num?)?.toInt() ?? 0,
    topics: (json['topics'] as num?)?.toInt() ?? 0,
    fields: (json['fields'] as num?)?.toInt() ?? 0,
    sampled: (json['sampled'] as num?)?.toInt() ?? 0,
    removed: [for (final r in (json['removed'] as List?) ?? const []) '$r'],
  );

  final int tables;
  final int columns;
  final int topics;
  final int fields;
  final int sampled;
  final List<String> removed;
}

/// What `POST /api/datasources` takes: the name, the type, a description and
/// the access details of that type, which the body carries under the type's
/// own key.
class NewDataSource {
  const NewDataSource({
    required this.name,
    required this.type,
    this.description,
    required this.details,
  });

  final String name;
  final DataSourceType type;
  final String? description;
  final Map<String, Object?> details;

  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.json,
    if (description != null && description!.isNotEmpty)
      'description': description,
    type.json: details,
  };
}

/// One call to the API, as the calls panel shows it.
class ApiCall {
  ApiCall({
    required this.method,
    required this.path,
    required this.startedAt,
    this.requestBody,
  });

  final String method;
  final String path;
  final DateTime startedAt;
  final String? requestBody;
  int? status;
  String? responseBody;
  String? error;
  Duration? elapsed;

  bool get ok =>
      error == null && status != null && status! >= 200 && status! < 300;
  bool get pending => elapsed == null;

  Map<String, Object?> toJson() => {
    'method': method,
    'path': path,
    'startedAt': startedAt.toIso8601String(),
    'requestBody': requestBody,
    'status': status,
    'responseBody': responseBody,
    'error': error,
    'elapsedMs': elapsed?.inMilliseconds,
  };

  /// A call kept from before a reload; one that was still waiting then
  /// never got its answer.
  static ApiCall fromJson(Map<String, Object?> json) {
    final call = ApiCall(
      method: json['method'] as String? ?? '?',
      path: json['path'] as String? ?? '?',
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.now(),
      requestBody: json['requestBody'] as String?,
    );
    call.status = (json['status'] as num?)?.toInt();
    call.responseBody = json['responseBody'] as String?;
    call.error = json['error'] as String?;
    final ms = (json['elapsedMs'] as num?)?.toInt();
    if (ms != null) {
      call.elapsed = Duration(milliseconds: ms);
    } else {
      call.error ??= 'the page was reloaded before the answer';
      call.elapsed = Duration.zero;
    }
    return call;
  }
}

/// Every call made, newest first; the calls panel listens. Kept in the
/// [store] as it changes, and read back from it when made, so the audit
/// outlives a reload of the page.
class CallLog extends ChangeNotifier {
  CallLog({this.store}) {
    try {
      final kept = store?.read(_key);
      if (kept != null) {
        _calls.addAll(
          [
            for (final item in jsonDecode(kept) as List)
              ApiCall.fromJson((item as Map).cast<String, Object?>()),
          ].take(keep),
        );
      }
    } catch (_) {
      // Unreadable: start empty.
    }
  }

  static const int keep = 100;
  static const _key = 'calls';
  /// Where the calls are kept across reloads; none in tests.
  final SessionStore? store;
  final List<ApiCall> _calls = [];

  void _save() {
    final store = this.store;
    if (store == null) return;
    if (_calls.isEmpty) {
      store.remove(_key);
    } else {
      store.write(_key, jsonEncode([for (final call in _calls) call.toJson()]));
    }
  }

  @override
  void notifyListeners() {
    _save();
    super.notifyListeners();
  }

  List<ApiCall> get calls => List.unmodifiable(_calls);

  ApiCall start(String method, String path, {String? requestBody}) {
    final call = ApiCall(
      method: method,
      path: path,
      startedAt: DateTime.now(),
      requestBody: requestBody,
    );
    _calls.insert(0, call);
    if (_calls.length > keep) _calls.removeRange(keep, _calls.length);
    notifyListeners();
    return call;
  }

  void finish(ApiCall call, {int? status, String? body, String? error}) {
    call.status = status;
    call.responseBody = body;
    call.error = error;
    call.elapsed = DateTime.now().difference(call.startedAt);
    notifyListeners();
  }

  void clear() {
    _calls.clear();
    notifyListeners();
  }
}

/// Thrown when the API answers outside 2xx, or can't be reached.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// What the dashboard asks the API. [HttpDatyxApi] is the real one; tests
/// pass a fake.
abstract class DatyxApi {
  CallLog get log;
  Future<AuthConfig> authConfig();
  Future<Me> me();
  Future<Profile> profile();
  Future<SystemStatus> status();
  Future<List<DataSource>> dataSources({int limit = 100});
  Future<DataSource> addDataSource(NewDataSource source);
  Future<void> removeDataSource(int id);
  Future<CatalogSync> syncCatalog(int sourceId);
  Future<List<CatalogTable>> catalog(int sourceId);
  Future<List<CatalogTopic>> topics(int sourceId);
  Future<List<TimeSeriesSpec>> timeSeries(int sourceId);
  Future<TimeSeriesSpec> setTimeSeries(int sourceId, TimeSeriesRoles roles);

  /// Enables or disables a group of [table]: removes or adds its [disabledTag]
  /// in OpenMetadata. Enabling has datyx queue a training run for each of
  /// the group's algorithms.
  Future<TimeSeriesSpec> setGroupEnabled(int sourceId, String table, String group, bool enabled);
  Future<TrainingOverview> training();
  Future<TrainingRunDetail> trainingRun(int id);

  /// Queues a run of a group with one of its algorithms: [algorithm], or
  /// the API's choice (XGBoost, when the group has it) when null.
  Future<TrainingRunInfo> trainNow(int sourceId, String table, String group, {String? algorithm});

  /// The latest groups switched on or off, newest first, and the runs each queued.
  Future<List<GroupEvent>> groupEvents({int limit = 50});

  /// Sets how often a table's groups are trained again: a span, `never`, or null for the default (1D).
  Future<void> setRetrain(int sourceId, String table, String? retrain);
  Future<InferenceAccount> inference();

  /// Scores [series] (each its key's values by column) with a group's latest
  /// model; none: every series still observed, the highest [limit].
  Future<InferenceAnswer> score(
    int sourceId,
    String table,
    String group, {
    List<Map<String, String>>? series,
    int limit = 25,
  });
}

/// Gives the bearer token for a call, or null for none.
typedef TokenProvider = Future<String?> Function();

/// The keys whose values never reach the calls panel.
const secretKeys = {'password', 'secretAccessKey'};

/// A copy of a request body with its secrets replaced, for the log.
Object? redacted(Object? body) {
  if (body is Map) {
    return {
      for (final entry in body.entries)
        entry.key: secretKeys.contains(entry.key) && entry.value != null
            ? '••••••'
            : redacted(entry.value),
    };
  }
  if (body is List) return [for (final item in body) redacted(item)];
  return body;
}

/// Where the API answers [path], as a link for the browser: the app's own
/// origin, as the calls go, unless API_BASE_URL was set at build time.
Uri apiAddress(String path) {
  const base = String.fromEnvironment('API_BASE_URL');
  return Uri.base.resolve('${base.endsWith('/') ? base.substring(0, base.length - 1) : base}$path');
}

/// The API over HTTP. [baseUrl] is API_BASE_URL at build time: empty, the
/// app's own origin (the dev server and the web server proxy /api/ there).
/// [token] gives the signed-in user's ID token, sent as `Authorization:
/// Bearer` when there is one; after a 401, [refreshToken] is asked once for
/// a fresh one and the call is retried. A call that takes longer than
/// [timeout] fails. The log gets request bodies with their secrets
/// replaced ([redacted]).
class HttpDatyxApi implements DatyxApi {
  HttpDatyxApi({
    String? baseUrl,
    http.Client? client,
    CallLog? log,
    this.token,
    this.refreshToken,
    this.timeout = const Duration(seconds: 20),
  }) : baseUrl = baseUrl ?? const String.fromEnvironment('API_BASE_URL'),
       _client = client ?? http.Client(),
       log = log ?? CallLog();

  final String baseUrl;
  final http.Client _client;
  final TokenProvider? token;
  final TokenProvider? refreshToken;
  final Duration timeout;
  @override
  final CallLog log;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Set<int> alsoOk = const {},
  }) async {
    final uri = _uri(path, query);
    final requestBody = body == null ? null : jsonEncode(body);
    final loggedBody = body == null ? null : jsonEncode(redacted(body));
    final shown = query == null || query.isEmpty
        ? path
        : '$path?${Uri(queryParameters: query).query}';
    var bearer = await token?.call();
    var retried = false;
    while (true) {
      final call = log.start(method, shown, requestBody: loggedBody);
      http.Response response;
      try {
        final request = http.Request(method, uri);
        if (requestBody != null) {
          request.headers['content-type'] = 'application/json';
          request.body = requestBody;
        }
        if (bearer != null && bearer.isNotEmpty) {
          request.headers['authorization'] = 'Bearer $bearer';
        }
        response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout),
        ).timeout(timeout);
      } catch (e) {
        log.finish(call, error: e.toString());
        throw ApiException('$method $path failed: $e');
      }
      log.finish(call, status: response.statusCode, body: response.body);
      if (response.statusCode == 401 &&
          bearer != null &&
          !retried &&
          refreshToken != null) {
        // An expired token: a fresh one, once.
        retried = true;
        final fresh = await refreshToken!.call();
        if (fresh != null && fresh != bearer) {
          bearer = fresh;
          continue;
        }
      }
      if ((response.statusCode < 200 || response.statusCode >= 300) &&
          !alsoOk.contains(response.statusCode)) {
        throw ApiException(
          '$method $path answered ${response.statusCode}${_said(response.body)}',
          status: response.statusCode,
        );
      }
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }
  }

  /// The API's own words for an error, `{"error":"..."}`, when it gives some.
  static String _said(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] is String) return ': ${json['error']}';
    } on FormatException {
      // Not JSON: the status says enough.
    }
    return '';
  }

  @override
  Future<CatalogSync> syncCatalog(int sourceId) async => CatalogSync.fromJson(
    (await _send('POST', '/api/datasources/$sourceId/catalog') as Map).cast(),
  );

  @override
  Future<List<CatalogTable>> catalog(int sourceId) async {
    final json = await _send('GET', '/api/datasources/$sourceId/catalog') as Map;
    return [
      for (final t in (json['tables'] as List?) ?? const [])
        CatalogTable.fromJson((t as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<List<CatalogTopic>> topics(int sourceId) async {
    final json = await _send('GET', '/api/datasources/$sourceId/catalog') as Map;
    return [
      for (final t in (json['topics'] as List?) ?? const [])
        CatalogTopic.fromJson((t as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<List<TimeSeriesSpec>> timeSeries(int sourceId) async {
    final json = await _send('GET', '/api/datasources/$sourceId/timeseries') as Map;
    return [
      for (final s in (json['series'] as List?) ?? const [])
        TimeSeriesSpec.fromJson((s as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<TimeSeriesSpec> setTimeSeries(int sourceId, TimeSeriesRoles roles) async =>
      TimeSeriesSpec.fromJson(
        (await _send('PUT', '/api/datasources/$sourceId/timeseries', body: roles.toJson()) as Map).cast(),
      );

  @override
  Future<TimeSeriesSpec> setGroupEnabled(int sourceId, String table, String group, bool enabled) async =>
      TimeSeriesSpec.fromJson(
        (await _send(
                  'PUT',
                  '/api/datasources/$sourceId/timeseries/enabled',
                  body: {'table': table, 'group': group, 'enabled': enabled},
                )
                as Map)
            .cast(),
      );

  @override
  Future<TrainingOverview> training() async =>
      TrainingOverview.fromJson((await _send('GET', '/api/training') as Map).cast());

  @override
  Future<TrainingRunDetail> trainingRun(int id) async =>
      TrainingRunDetail.fromJson((await _send('GET', '/api/training/runs/$id') as Map).cast());

  @override
  Future<TrainingRunInfo> trainNow(int sourceId, String table, String group, {String? algorithm}) async =>
      TrainingRunInfo.fromJson(
        (await _send(
                  'POST',
                  '/api/datasources/$sourceId/training',
                  body: {'table': table, 'group': group, 'algorithm': ?algorithm},
                )
                as Map)
            .cast(),
      );

  @override
  Future<List<GroupEvent>> groupEvents({int limit = 50}) async {
    final json = await _send('GET', '/api/catalog/events', query: {'limit': '$limit'}) as Map;
    return [
      for (final e in (json['events'] as List?) ?? const [])
        GroupEvent.fromJson((e as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<void> setRetrain(int sourceId, String table, String? retrain) async {
    await _send('PUT', '/api/datasources/$sourceId/training', body: {'table': table, 'retrain': retrain});
  }

  @override
  Future<InferenceAccount> inference() async =>
      InferenceAccount.fromJson((await _send('GET', '/api/inference') as Map).cast());

  @override
  Future<InferenceAnswer> score(
    int sourceId,
    String table,
    String group, {
    List<Map<String, String>>? series,
    int limit = 25,
  }) async => InferenceAnswer.fromJson(
    (await _send(
              'POST',
              '/api/datasources/$sourceId/inference',
              body: {'table': table, 'group': group, 'series': ?series, 'limit': limit},
            )
            as Map)
        .cast(),
  );

  @override
  Future<AuthConfig> authConfig() async => AuthConfig.fromJson(
    (await _send('GET', '/api/auth/config') as Map).cast(),
  );

  @override
  Future<Me> me() async =>
      Me.fromJson((await _send('GET', '/api/me') as Map).cast());

  @override
  Future<Profile> profile() async =>
      Profile.fromJson((await _send('GET', '/api/profile') as Map).cast());

  @override
  Future<List<DataSource>> dataSources({int limit = 100}) async {
    final json = await _send(
      'GET',
      '/api/datasources',
      query: {'limit': '$limit'},
    );
    return [
      for (final item in json as List)
        DataSource.fromJson((item as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<DataSource> addDataSource(NewDataSource source) async {
    final json = await _send('POST', '/api/datasources', body: source.toJson());
    return DataSource.fromJson((json as Map).cast<String, Object?>());
  }

  @override
  Future<void> removeDataSource(int id) async {
    await _send('DELETE', '/api/datasources/$id');
  }

  /// A 503 is a check down, with the checks still in the body.
  @override
  Future<SystemStatus> status() async => SystemStatus.fromHealth(
    (await _send('GET', '/api/health', alsoOk: {503}) as Map).cast(),
  );
}
