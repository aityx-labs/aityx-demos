/// HealthHub's API. Holds the aityx.ai key, which must never reach the
/// app, talks to PostgreSQL (lib/db.dart), and answers:
///
///   GET  /              302 to /app/, so a forwarded port's bare URL
///                       opens the app (the web server proxies the root
///                       here)
///   GET  /api/health    {"ok": true, "db": true when the database
///                       answers, "aityx": true when the key is set,
///                       "auth": true when authentication is on}
///   GET  /api/hello     {"message": "Hello, world", "since": when the
///                       row was written, "postgres": the server's
///                       version(), "user": who is signed in, or null},
///                       read from the database, addressed to the
///                       signed-in user; 503 when the database doesn't
///                       answer
///   GET  /api/auth/config  how to sign in: {"enabled", "issuer", "clientId"}
///   GET  /api/me        who the bearer token says is calling (lib/auth.dart);
///                       401 without a valid one once authentication is on
///   GET  /api/datyx/me, /api/datyx/datasources
///                       the datyx API's /api/me and /api/datasources, asked
///                       with the user's own token, so datyx sees the same
///                       person; 401 without a user, 502 when datyx is down
///
/// Settings, from the environment (scripts/api.sh loads .env):
///   AITYX_API_KEY         the key (secret); nothing calls aityx yet
///   AITYX_URL             aityx's base URL (default https://api.aityx.ai)
///   API_PORT              the port (default 9802)
///   HEALTHHUB_BIND_HOST   the address to bind (default 127.0.0.1)
///   ALLOWED_ORIGINS       comma-separated origins allowed by CORS
///                         (default http://localhost:9801)
///   HEALTHHUB_DB_*        the database (see lib/db.dart)
///   OIDC_ISSUER, OIDC_CLIENT_ID  authentication (see lib/auth.dart)
///   DATYX_API_URL         the datyx API (default http://127.0.0.1:9900)
///
/// `server healthcheck` instead asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:healthhub_api/auth.dart';
import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/routes.dart';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'healthcheck') exit(await _healthcheck());
  final env = Platform.environment;
  final key = env['AITYX_API_KEY'] ?? '';
  final url = Uri.parse(
    (env['AITYX_URL'] ?? '').isEmpty
        ? 'https://api.aityx.ai'
        : env['AITYX_URL']!,
  );
  if (url.scheme != 'https') {
    stderr.writeln('error: AITYX_URL must be https');
    exit(1);
  }
  final port = int.parse(env['API_PORT'] ?? '9802');
  final host = env['HEALTHHUB_BIND_HOST'] ?? '127.0.0.1';
  final origins = (env['ALLOWED_ORIGINS'] ?? 'http://localhost:9801')
      .split(',')
      .map((origin) => origin.trim())
      .where((origin) => origin.isNotEmpty)
      .toSet();
  if (key.isEmpty) stderr.writeln('warning: AITYX_API_KEY is not set');

  final db = Db(DbSettings.fromEnvironment());
  final auth = AuthSettings.fromEnvironment();
  final verifier = TokenVerifier(auth);
  final datyx = Uri.parse(
    (env['DATYX_API_URL'] ?? '').isEmpty ? 'http://127.0.0.1:9900' : env['DATYX_API_URL']!,
  );
  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'healthhub_api on http://$host:$port (aityx: ${url.host}; '
    'database: ${db.settings}; '
    'auth: ${auth.enabled ? 'on, ${auth.issuer}' : 'off'}; datyx: $datyx)',
  );
  // The tables, once the database answers: retried in the background, so
  // the server is up (and /api/health says db: false) meanwhile.
  unawaited(_migrate(db));

  await for (final request in server) {
    unawaited(_handle(request, origins, db, verifier, datyx, aityx: key.isNotEmpty));
  }
}

Future<void> _migrate(Db db) async {
  for (var attempt = 1; ; attempt++) {
    try {
      await db.migrate();
      stdout.writeln('database ready: ${db.settings}');
      return;
    } catch (error) {
      if (attempt == 1 || attempt % 10 == 0) {
        stderr.writeln('database not ready (attempt $attempt): $error');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
}

/// 0 when the server on this machine answers /api/health with ok, else 1.
Future<int> _healthcheck() async {
  final port = int.parse(Platform.environment['API_PORT'] ?? '9802');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/health'),
    );
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    return response.statusCode == 200 && json is Map && json['ok'] == true
        ? 0
        : 1;
  } catch (error) {
    stderr.writeln('healthcheck: $error');
    return 1;
  } finally {
    client.close(force: true);
  }
}

Future<void> _handle(
  HttpRequest request,
  Set<String> origins,
  Db db,
  TokenVerifier verifier,
  Uri datyx, {
  required bool aityx,
}) async {
  final response = request.response;
  final origin = request.headers.value('origin');
  if (origin != null && origins.contains(origin)) {
    response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Vary', 'Origin')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  }
  try {
    final method = request.method;
    final path = request.uri.path;
    final auth = verifier.settings;
    final token = _bearer(request);
    final identity = await verifier.verify(token);
    // Only the routes that need the database, or datyx, ask them.
    final answer = switch ((method, path)) {
      ('GET', '/api/health') => route(
        method,
        path,
        db: await db.ping(),
        aityx: aityx,
        auth: auth,
      ),
      ('GET', '/api/hello') => route(
        method,
        path,
        greeting: await _greeting(db),
        auth: auth,
        identity: identity,
      ),
      ('GET', _) when datyxPath(path) != null => route(
        method,
        path,
        auth: auth,
        identity: identity,
        datyx: auth.enabled && identity == null
            ? null
            : await _forward(datyx, datyxPath(path)!, token),
      ),
      _ => route(method, path, aityx: aityx, auth: auth, identity: identity),
    };
    response.statusCode = answer.status;
    if (answer.location case final location?) {
      response.headers.set(HttpHeaders.locationHeader, location);
    }
    if (answer.body case final body?) _json(response, answer.status, body);
  } catch (error) {
    stderr.writeln('error: ${request.method} ${request.uri.path}: $error');
    _json(response, 500, {'error': 'internal error'});
  } finally {
    await response.close();
  }
}

/// The bearer token of the request, or null.
String? _bearer(HttpRequest request) {
  final header = request.headers.value(HttpHeaders.authorizationHeader);
  if (header == null) return null;
  const prefix = 'Bearer ';
  return header.startsWith(prefix) ? header.substring(prefix.length).trim() : null;
}

/// The datyx API's answer to [path], asked with the user's own [token] so
/// datyx sees the same person; null when datyx doesn't answer (logged).
Future<Forwarded?> _forward(Uri datyx, String path, String? token) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(datyx.replace(path: path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await response.transform(utf8.decoder).join();
    Object? json;
    try {
      json = body.isEmpty ? null : jsonDecode(body);
    } on FormatException {
      json = {'error': body};
    }
    return Forwarded(response.statusCode, json);
  } catch (error) {
    stderr.writeln('datyx: GET $path: $error');
    return null;
  } finally {
    client.close(force: true);
  }
}

/// The greeting, or null when the database doesn't answer (logged).
Future<Map<String, Object?>?> _greeting(Db db) async {
  try {
    return await db.greeting();
  } catch (error) {
    stderr.writeln('database: $error');
    return null;
  }
}

void _json(HttpResponse response, int status, Object body) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}
