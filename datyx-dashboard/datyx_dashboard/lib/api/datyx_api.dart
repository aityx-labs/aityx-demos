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
  filesystem('filesystem', 'Filesystem');

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
    }
  }
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
          '$method $path answered ${response.statusCode}',
          status: response.statusCode,
        );
      }
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }
  }

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
