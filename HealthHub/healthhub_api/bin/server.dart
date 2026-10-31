/// HealthHub's API. Holds the aityx.ai key, which must never reach the
/// app, talks to PostgreSQL (lib/db.dart), and answers:
///
///   GET  /              302 to /app/, so a forwarded port's bare URL
///                       opens the app (the web server proxies the root
///                       here)
///   GET  /api/health    {"ok": true, "db": true when the database
///                       answers, "aityx": true when the key is set,
///                       "auth": true when authentication is on, "kafka":
///                       true when Kafka's REST proxy answers,
///                       "simulation": true when the simulation runs}
///   GET  /api/hello     {"message": "Hello, world", "since": when the
///                       row was written, "postgres": the server's
///                       version(), "user": who is signed in, or null},
///                       read from the database, addressed to the
///                       signed-in user; 503 when the database doesn't
///                       answer
///   GET  /api/care-centers?bbox=west,south,east,north
///                       {"centers": [...], "truncated": whether there were
///                       more}: the hospitals, clinics and health stations
///                       in the area (lib/care_centers.dart), open to all;
///                       503 when the database doesn't answer
///   GET  /api/people    {"enabled": dev mode, "simTime", "day", "people":
///                       [...]}: the simulated people's latest moves, read
///                       back from Kafka (lib/simulation.dart), open to all
///   GET  /api/events?limit=20&type=admission|move
///                       {"enabled", "topic", "topics", "events": [...]}:
///                       the latest moves and admissions read from the
///                       streams, newest first, each with its "type" (dev
///                       mode), for home's events; open to all
///   GET  /api/admissions?limit=20
///                       {"admissions": [...]}: the latest admissions
///                       recorded in the database, newest first (at most
///                       200), open to all; 503 when the database doesn't
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
///   HEALTHHUB_MODE        dev (the default) or prod; dev runs the
///                         simulation of people moving across the map
///   HEALTHHUB_KAFKA_REST_URL  Kafka's REST proxy (default
///                         http://127.0.0.1:9805)
///   HEALTHHUB_SIM_*       the simulation (see lib/simulation.dart)
///
/// `server healthcheck` instead asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/admissions.dart';
import 'package:healthhub_api/auth.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/kafka_rest.dart';
import 'package:healthhub_api/routes.dart';
import 'package:healthhub_api/simulation.dart';

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
  final mode = (env['HEALTHHUB_MODE'] ?? '').isEmpty ? 'dev' : env['HEALTHHUB_MODE']!;
  if (mode != 'dev' && mode != 'prod') {
    stderr.writeln('error: HEALTHHUB_MODE must be dev or prod');
    exit(1);
  }
  final kafka = KafkaRest(Uri.parse(
    (env['HEALTHHUB_KAFKA_REST_URL'] ?? '').isEmpty
        ? 'http://127.0.0.1:9805'
        : env['HEALTHHUB_KAFKA_REST_URL']!,
  ));
  final live = _Live(dev: mode == 'dev', kafka: kafka);
  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'healthhub_api on http://$host:$port (mode: $mode; aityx: ${url.host}; '
    'database: ${db.settings}; '
    'auth: ${auth.enabled ? 'on, ${auth.issuer}' : 'off'}; datyx: $datyx; '
    'kafka: ${kafka.base})',
  );
  // The tables, once the database answers: retried in the background, so
  // the server is up (and /api/health says db: false) meanwhile. The
  // simulation needs the care centers, so it starts after.
  unawaited(_migrate(db).then((_) => live.dev ? _simulate(db, live) : null));
  live.watchKafka();
  // Stopped by process-compose, a rebuild, Docker or Ctrl-C: delete the
  // feed's consumers on the proxy, or each restart leaves them behind.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) => _shutdown(server, live));
  }

  await for (final request in server) {
    unawaited(_handle(request, origins, db, verifier, datyx, live, aityx: key.isNotEmpty));
  }
}

/// Kafka and, in dev mode, the simulation writing to it and the feed
/// reading it back.
class _Live {
  _Live({required this.dev, required this.kafka});

  final bool dev;
  final KafkaRest kafka;
  Simulation? simulation;
  PeopleFeed? feed;
  AdmissionRecorder? recorder;

  /// Whether the REST proxy answered its last ping. /api/health reports
  /// this rather than pinging, so a hung proxy never slows the health
  /// check (and Docker's healthcheck) down.
  bool kafkaUp = false;
  Timer? _kafkaWatch;

  /// Pings the proxy now and every 5 s, one ping at a time.
  void watchKafka() {
    var pinging = false;
    Future<void> ping() async {
      if (pinging) return;
      pinging = true;
      kafkaUp = await kafka.ping();
      pinging = false;
    }

    unawaited(ping());
    _kafkaWatch = Timer.periodic(const Duration(seconds: 5), (_) => ping());
  }

  void stopWatching() => _kafkaWatch?.cancel();
}

/// Stops the simulation, deletes the feed's two consumers (waiting a while
/// for their polls to end), and exits.
Future<void> _shutdown(HttpServer server, _Live live) async {
  stdout.writeln('healthhub_api: stopping');
  live.simulation?.stop();
  live.stopWatching();
  try {
    await live.feed?.stop().timeout(const Duration(seconds: 15));
  } catch (_) {}
  // The admissions read before the stop, given a moment to be written.
  try {
    await live.recorder?.idle.timeout(const Duration(seconds: 5));
  } catch (_) {}
  live.recorder?.stop();
  live.kafka.close();
  await server.close(force: true);
  exit(0);
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

/// Dev mode: reads the care centers (retried like the migration), starts
/// the feed and the simulation. Neither waits for Kafka: the people keep
/// moving and retry publishing, the feed retries connecting.
Future<void> _simulate(Db db, _Live live) async {
  final settings = SimulationSettings.fromEnvironment();
  List<Place> places;
  for (var attempt = 1; ; attempt++) {
    try {
      places = await db.places();
      break;
    } catch (error) {
      if (attempt == 1 || attempt % 10 == 0) {
        stderr.writeln('simulation: care centers not readable (attempt $attempt): $error');
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
  final random = Random();
  final people = populate(
    places,
    settings.peoplePerCity,
    settings.minutesPerTurn,
    random,
    conditions: conditionSeed,
  );
  if (people.isEmpty) {
    stderr.writeln('simulation: no hospitals with a location, so nobody to move');
    return;
  }
  if (conditionSeed.isEmpty) {
    stderr.writeln('simulation: no medical conditions, so nobody goes to the hospital');
  }
  // Bad data the database refuses is dropped, not retried forever.
  final recorder = live.recorder = AdmissionRecorder(db.recordAdmission, isPermanent: Db.isPermanentError);
  final feed = live.feed = PeopleFeed(
    live.kafka,
    people: [for (final person in people) person.id],
    onAdmission: recorder.record,
  );
  unawaited(feed.run());
  live.simulation = Simulation(people, settings, live.kafka, conditions: conditionSeed, random: random)..start();
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
  Uri datyx,
  _Live live, {
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
        kafka: live.kafkaUp,
        simulation: live.simulation?.running ?? false,
      ),
      ('GET', '/api/events') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        dev: live.dev,
        events: live.feed?.recent ?? const [],
      ),
      ('GET', '/api/admissions') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        admissions: await _admissions(db, request.uri.queryParameters),
      ),
      ('GET', '/api/people') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        dev: live.dev,
        people: live.feed?.people ?? const [],
      ),
      ('GET', '/api/hello') => route(
        method,
        path,
        greeting: await _greeting(db),
        auth: auth,
        identity: identity,
      ),
      ('GET', '/api/care-centers') => route(
        method,
        path,
        query: request.uri.queryParameters,
        careCenters: await _careCenters(db, request.uri.queryParameters['bbox']),
        auth: auth,
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

/// The care centers in [bbox] (everywhere without one; none for a bbox
/// that isn't one, which the route answers 400), one more than an answer
/// holds; null when the database doesn't answer (logged).
Future<List<Map<String, Object?>>?> _careCenters(Db db, String? bbox) async {
  final box = Bbox.parse(bbox);
  if (bbox != null && box == null) return const [];
  try {
    return await db.careCenters(box, limit: careCentersLimit + 1);
  } catch (error) {
    stderr.writeln('care centers: $error');
    return null;
  }
}

/// The latest admissions [query] asks for (none for a limit that isn't
/// one, which the route answers 400); null when the database doesn't
/// answer (logged).
Future<List<Map<String, Object?>>?> _admissions(Db db, Map<String, String> query) async {
  final limit = admissionsLimitOf(query);
  if (limit == null) return const [];
  try {
    return await db.latestAdmissions(limit: limit);
  } catch (error) {
    stderr.writeln('admissions: $error');
    return null;
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
