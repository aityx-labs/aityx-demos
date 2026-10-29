import 'dart:convert';

import 'package:http/http.dart' as http;

/// What GET /api/hello answers: the greeting kept in the database, when it
/// was written, the PostgreSQL server's version, and who the API says is
/// signed in (the greeting is addressed to them).
class Greeting {
  const Greeting({
    required this.message,
    required this.since,
    required this.postgres,
    this.user,
  });

  factory Greeting.fromJson(Map<String, Object?> json) => Greeting(
    message: json['message'] as String,
    since: DateTime.tryParse((json['since'] as String?) ?? ''),
    postgres: (json['postgres'] as String?) ?? '',
    user: json['user'] is Map ? Me.fromJson((json['user'] as Map).cast()) : null,
  );

  final String message;
  final DateTime? since;

  /// PostgreSQL's `version()`, e.g. "PostgreSQL 17.6 on x86_64-pc-linux-gnu, ...".
  final String postgres;

  /// The signed-in user the API addressed, or null.
  final Me? user;

  /// The version's first words: "PostgreSQL 17.6".
  String get postgresShort {
    final words = postgres.split(' ');
    return words.length >= 2 ? '${words[0]} ${words[1]}' : postgres;
  }
}

/// What GET /api/health answers.
class Health {
  const Health({required this.ok, required this.db, required this.aityx, this.auth = false});

  factory Health.fromJson(Map<String, Object?> json) => Health(
    ok: json['ok'] == true,
    db: json['db'] == true,
    aityx: json['aityx'] == true,
    auth: json['auth'] == true,
  );

  final bool ok;

  /// Whether the API's database answers.
  final bool db;

  /// Whether the API has its aityx key.
  final bool aityx;

  /// Whether the API wants a signed-in user.
  final bool auth;
}

/// How the API authenticates: `GET /api/auth/config`. Off until the API
/// has a client id; on, the issuer (Google) and the OpenID Connect client id
/// the app signs in with.
class AuthConfig {
  const AuthConfig({required this.enabled, required this.issuer, this.clientId});

  factory AuthConfig.fromJson(Map<String, Object?> json) => AuthConfig(
    enabled: json['enabled'] == true,
    issuer: json['issuer'] as String? ?? '',
    clientId: json['clientId'] as String?,
  );

  final bool enabled;
  final String issuer;
  final String? clientId;
}

/// Who an API says is calling: `GET /api/me` here, `GET /api/datyx/me` as
/// the datyx API sees the same token.
class Me {
  const Me({required this.authenticated, this.subject, this.email, this.name, this.picture});

  factory Me.fromJson(Map<String, Object?> json) => Me(
    // datyx answers `authenticated`; our own hello embeds the identity alone.
    authenticated: json['authenticated'] == true || json['subject'] != null,
    subject: json['subject'] as String?,
    email: json['email'] as String?,
    name: json['name'] as String?,
    picture: json['picture'] as String?,
  );

  final bool authenticated;
  final String? subject;
  final String? email;
  final String? name;
  final String? picture;

  String get label => name ?? email ?? subject ?? 'anonymous';
}

/// The API, as the app sees it.
abstract class HealthHubApi {
  Future<Health> health();
  Future<Greeting> hello();
  Future<AuthConfig> authConfig();
  Future<Me> me();

  /// What the datyx API makes of the same user: `GET /api/datyx/me`.
  Future<Me> datyxMe();

  /// How many data sources datyx keeps, through `GET /api/datyx/datasources`.
  Future<int> datyxDataSources();
}

/// Thrown when the API answers an error, with its message.
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'HTTP $status: $message';
}

/// Gives the bearer token for a call, or null for none.
typedef TokenProvider = Future<String?> Function();

/// The API over HTTP at [baseUrl]: `API_BASE_URL` (a dart-define) unless
/// given; empty means the app's own origin, where the web server proxies
/// /api/ to the API. [token] gives the signed-in user's ID token, sent as
/// `Authorization: Bearer`; after a 401, [refreshToken] is asked once for a
/// fresh one and the call is retried.
class HttpHealthHubApi implements HealthHubApi {
  HttpHealthHubApi({String? baseUrl, http.Client? client, this.token, this.refreshToken})
    : baseUrl = baseUrl ?? const String.fromEnvironment('API_BASE_URL'),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final TokenProvider? token;
  final TokenProvider? refreshToken;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<Health> health() async => Health.fromJson(await _getMap('/api/health'));

  @override
  Future<Greeting> hello() async => Greeting.fromJson(await _getMap('/api/hello'));

  @override
  Future<AuthConfig> authConfig() async => AuthConfig.fromJson(await _getMap('/api/auth/config'));

  @override
  Future<Me> me() async => Me.fromJson(await _getMap('/api/me'));

  @override
  Future<Me> datyxMe() async => Me.fromJson(await _getMap('/api/datyx/me'));

  @override
  Future<int> datyxDataSources() async {
    final json = await _get('/api/datyx/datasources');
    return json is List ? json.length : 0;
  }

  Future<Map<String, Object?>> _getMap(String path) async {
    final json = await _get(path);
    if (json is! Map<String, Object?>) throw const ApiException(200, 'unexpected answer');
    return json;
  }

  Future<Object?> _get(String path) async {
    var bearer = await token?.call();
    var retried = false;
    while (true) {
      final response = await _client
          .get(_uri(path), headers: {
            if (bearer != null && bearer.isNotEmpty) 'authorization': 'Bearer $bearer',
          })
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 401 && bearer != null && !retried && refreshToken != null) {
        retried = true;
        final fresh = await refreshToken!.call();
        if (fresh != null && fresh != bearer) {
          bearer = fresh;
          continue;
        }
      }
      final Object? json;
      try {
        json = jsonDecode(response.body);
      } on FormatException {
        throw ApiException(response.statusCode, 'not JSON: ${response.body}');
      }
      if (response.statusCode != 200) {
        throw ApiException(
          response.statusCode,
          json is Map ? (json['error'] as String?) ?? 'HTTP ${response.statusCode}' : 'HTTP ${response.statusCode}',
        );
      }
      return json;
    }
  }
}
