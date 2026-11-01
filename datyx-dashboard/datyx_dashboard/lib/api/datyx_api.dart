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

/// The algorithms that train a group, as the API names them: a group
/// without an algorithm tag is DeepAR's.
const deepArAlgorithm = 'DeepAR';
const xgBoostAlgorithm = 'XGBoost';
const algorithms = [deepArAlgorithm, xgBoostAlgorithm];

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

/// One group of a table read as a time series by the API:
/// `GET .../timeseries`, and the answer of `PUT .../timeseries`. [ready]
/// when there are no [problems].
class TimeSeriesSpec {
  const TimeSeriesSpec({
    required this.table,
    required this.name,
    this.group = defaultGroup,
    this.algorithm = deepArAlgorithm,
    this.schema,
    this.columns = const {},
    this.frequency,
    this.horizon,
    this.missing,
    this.ready = false,
    this.problems = const [],
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
      schema: json['schema'] as String?,
      columns: {
        for (final role in TimeSeriesRole.values) role: list(json[role.field]),
      },
      frequency: json['frequency'] as String?,
      horizon: json['horizon'] as String?,
      missing: json['missing'] as String?,
      ready: json['ready'] as bool? ?? false,
      problems: list(json['problems']),
    );
  }

  final String table;
  final String name;
  final String group;

  /// What trains the group: [deepArAlgorithm] (no tag, or its own) or [xgBoostAlgorithm].
  final String algorithm;
  final String? schema;
  final Map<TimeSeriesRole, List<String>> columns;
  final String? frequency;

  /// How far ahead the group predicts (the table's, as a pandas offset); required for XGBoost.
  final String? horizon;
  final String? missing;
  final bool ready;
  final List<String> problems;

  List<String> of(TimeSeriesRole role) => columns[role] ?? const [];

  String? get target => of(TimeSeriesRole.target).firstOrNull;
  List<String> get seriesKey => of(TimeSeriesRole.seriesKey);
}

/// What `PUT /api/datasources/{id}/timeseries` takes: a group's roles in a
/// table (no roles: the group is gone) and the algorithm that trains it,
/// and the table's frequency, horizon and what a missing row means, which
/// its groups share.
class TimeSeriesRoles {
  const TimeSeriesRoles({
    required this.table,
    this.group = defaultGroup,
    this.algorithm,
    this.columns = const {},
    this.frequency,
    this.horizon,
    this.missing,
  });

  final String table;
  final String group;

  /// [deepArAlgorithm] or [xgBoostAlgorithm]; null leaves the group untagged, DeepAR's.
  final String? algorithm;
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
    'algorithm': algorithm,
    'frequency': frequency,
    'horizon': horizon,
    'missing': missing,
  };
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
