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
///                       "simulation": true when the simulation runs,
///                       "paused": true when it is paused, "triage"}
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
///                       {"enabled", "paused", "topic", "topics", "events":
///                       [...]}: the latest moves and admissions read from
///                       the streams, newest first, each with its "type"
///                       (dev mode), and whether the simulation is paused,
///                       for home's events; open to all
///   POST /api/simulation/pause, POST /api/simulation/resume
///                       {"paused": true|false}, the state after the call:
///                       freezes or resumes the simulation, the same one
///                       everyone watches (idempotent); 401 without a user
///                       once authentication is on, 409 when it doesn't run
///   GET  /api/admissions?limit=20
///                       {"admissions": [...]}: the latest admissions
///                       recorded in the database, newest first (at most
///                       200), open to all; 503 when the database doesn't
///                       answer
///   GET  /api/triage?limit=20
///                       {"enabled", "summary", "triaged": [...]}: how
///                       aityx has triaged the admissions so far, against
///                       their reference levels, and the latest triages,
///                       newest first (lib/triage.dart), open to all; 503
///                       when the database doesn't answer
///   GET  /api/triage/{eventId}
///                       one admission's triage with aityx's receipt; 404
///                       when it has none
///   GET  /api/auth/config  how to sign in: {"enabled", "issuer", "clientId"}
///   GET  /api/me        who the bearer token says is calling (lib/auth.dart);
///                       401 without a valid one once authentication is on
///   GET  /api/people/{id}   one person of a run (?run=, else the current
///                       one, else the newest with their admissions):
///                       facts, where they
///                       are now, admissions with triage, days of care
///   GET  /api/people/{id}/prediction
///                       datyx's XGBoost prediction of their hours of
///                       care over the next 30 days, asked with the
///                       user's own token; 502 when datyx is down
///   GET  /api/datyx/me, /api/datyx/datasources
///                       the datyx API's /api/me and /api/datasources, asked
///                       with the user's own token, so datyx sees the same
///                       person; 401 without a user, 502 when datyx is down
///
/// Settings, from the environment (scripts/api.sh loads .env):
///   AITYX_API_KEY         the key (secret), which triages the admissions
///   AITYX_URL             aityx's base URL (default https://api.aityx.ai)
///   HEALTHHUB_TRIAGE      on (the default, with a key) or off: whether
///                         each admission is triaged with aityx
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
import 'package:healthhub_api/triage.dart';

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
  final triageSetting = (env['HEALTHHUB_TRIAGE'] ?? '').isEmpty ? 'on' : env['HEALTHHUB_TRIAGE']!;
  if (triageSetting != 'on' && triageSetting != 'off') {
    stderr.writeln('error: HEALTHHUB_TRIAGE must be on or off');
    exit(1);
  }
  final aityx = Aityx(url, key);

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
  final live = _Live(dev: mode == 'dev', kafka: kafka, aityx: aityx, triage: triageSetting == 'on' && aityx.configured);
  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'healthhub_api on http://$host:$port (mode: $mode; aityx: ${url.host}; '
    'database: ${db.settings}; '
    'auth: ${auth.enabled ? 'on, ${auth.issuer}' : 'off'}; datyx: $datyx; '
    'kafka: ${kafka.base}; triage: ${live.triage ? 'on' : 'off'})',
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
  _Live({required this.dev, required this.kafka, required this.aityx, required this.triage});

  final bool dev;
  final KafkaRest kafka;

  /// aityx, which triages each admission recorded when [triage] is on.
  final Aityx aityx;
  final bool triage;
  Simulation? simulation;
  PeopleFeed? feed;
  AdmissionRecorder? recorder;
  Triager? triager;

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
  // The triages under way, given a moment to finish and be recorded.
  try {
    await live.triager?.idle.timeout(const Duration(seconds: 5));
  } catch (_) {}
  live.triager?.stop();
  live.aityx.close();
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
  // Each admission recorded the first time is triaged with aityx, in the
  // background; a triage the database can't record is logged and lost.
  final triager = live.triage
      ? live.triager = Triager((admission) async => db.recordTriage(await triageAdmission(live.aityx, admission)))
      : null;
  // Bad data the database refuses is dropped, not retried forever.
  final recorder = live.recorder = AdmissionRecorder(
    (admission) async {
      final inserted = await db.recordAdmission(admission);
      if (inserted) triager?.triage(admission);
      return inserted;
    },
    isPermanent: Db.isPermanentError,
  );
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
    // /api/people/{id} and /api/people/{id}/prediction: the id, and which.
    final personRoute = personPath(path);
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
        paused: live.simulation?.paused ?? false,
        triageEnabled: live.triage,
      ),
      ('GET', '/api/triage') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        triageEnabled: live.triage,
        triage: await _triage(db, request.uri.queryParameters),
      ),
      ('GET', _) when triageEventId(path) != null => route(
        method,
        path,
        auth: auth,
        triageDetail: await _triageOf(db, triageEventId(path)!),
      ),
      ('GET', '/api/events') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        dev: live.dev,
        paused: live.simulation?.paused ?? false,
        events: live.feed?.recent ?? const [],
      ),
      ('POST', simulationPausePath || simulationResumePath) => route(
        method,
        path,
        auth: auth,
        identity: identity,
        dev: live.dev,
        simulation: live.simulation?.running ?? false,
        control: (pause) {
          final simulation = live.simulation;
          if (simulation == null) return false;
          if (pause) {
            simulation.pause();
          } else {
            simulation.resume();
          }
          return simulation.paused;
        },
      ),
      ('GET', '/api/admissions') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        admissions: await _admissions(db, request.uri.queryParameters),
      ),
      ('GET', _) when personRoute != null && !personRoute.$2 => route(
        method,
        path,
        auth: auth,
        dev: live.dev,
        people: live.feed?.people ?? const [],
        person: await _person(
          db,
          personRoute.$1,
          request.uri.queryParameters['run'] ?? live.simulation?.run,
          live.simulation?.run,
        ),
      ),
      ('GET', _) when personRoute != null => route(
        method,
        path,
        auth: auth,
        identity: identity,
        prediction: auth.enabled && identity == null
            ? null
            : await _prediction(
                datyx, token, db, personRoute.$1, request.uri.queryParameters['run'] ?? live.simulation?.run),
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

/// The summary of every triage and the latest [query] asks for (none for
/// a limit that isn't one, which the route answers 400); null when the
/// database doesn't answer (logged).
Future<Map<String, Object?>?> _triage(Db db, Map<String, String> query) async {
  final limit = admissionsLimitOf(query);
  if (limit == null) return const {};
  try {
    return {'summary': await db.triageSummary(), 'triaged': await db.latestTriage(limit: limit)};
  } catch (error) {
    stderr.writeln('triage: $error');
    return null;
  }
}

/// One admission's triage, as the route wants it, with the rules of the
/// level and area tables, so the app can show each rule tried up to the
/// one that fired; null when the database doesn't answer (logged).
Future<TriageLookup?> _triageOf(Db db, String eventId) async {
  try {
    final row = await db.triageOf(eventId);
    return TriageLookup(
      row == null ? null : {...row, 'rules': {'level': triageRules('level'), 'area': triageRules('area')}},
    );
  } catch (error) {
    stderr.writeln('triage: $error');
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

/// One person of [run] (the newest run with their admissions when
/// null), as the route wants them; null when the database doesn't answer
/// (logged).
Future<PersonLookup?> _person(Db db, String id, String? run, String? currentRun) async {
  try {
    return PersonLookup(await db.personHistory(id, run: run), currentRun: currentRun);
  } catch (error) {
    stderr.writeln('people: $error');
    return null;
  }
}

/// The table and group of datyx's model of HealthHub's patients: their
/// hours of care, summed over the next 30 days, by XGBoost.
const _predictionTable = 'public.patient_days';
const _predictionGroup = 'care';

/// datyx's prediction for one person of [run] (the newest run with their
/// admissions when null), asked with the user's own [token]: their
/// datyx data source for this API's database (the database source whose
/// database is ours), then the inference of their series of
/// patient_days; the answer carries the source's id. A 404 of ours when
/// datyx has no such source or the person no run; null when datyx
/// doesn't answer (logged).
Future<Forwarded?> _prediction(Uri datyx, String? token, Db db, String id, String? run) async {
  var series = run;
  if (series == null) {
    try {
      series = (await db.personHistory(id))['run'] as String?;
    } catch (error) {
      stderr.writeln('people: $error');
    }
    if (series == null) return const Forwarded(404, {'error': 'nobody with that id has been admitted'});
  }
  final sources = await _forward(datyx, '/api/datasources', token);
  if (sources == null || sources.status != 200 || sources.body is! List) return sources;
  int? sourceId;
  for (final source in sources.body as List) {
    if (source is Map && source['type'] == 'database' && (source['database'] as Map?)?['database'] == db.settings.database) {
      sourceId = (source['id'] as num?)?.toInt();
      break;
    }
  }
  if (sourceId == null) {
    return Forwarded(404, {'error': "datyx has no data source for HealthHub's database (${db.settings.database})"});
  }
  final scored = await _forward(datyx, '/api/datasources/$sourceId/inference', token, payload: {
    'table': _predictionTable,
    'group': _predictionGroup,
    'series': [
      {'run_id': series, 'person_id': id},
    ],
  });
  if (scored != null && scored.body is Map) {
    return Forwarded(scored.status, {...(scored.body as Map), 'sourceId': sourceId});
  }
  return scored;
}

/// The datyx API's answer to [path], asked with the user's own [token] so
/// datyx sees the same person: a GET, or a POST of [payload] as JSON; null
/// when datyx doesn't answer (logged).
Future<Forwarded?> _forward(Uri datyx, String path, String? token, {Object? payload}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final url = datyx.replace(path: path);
    final request = payload == null ? await client.getUrl(url) : await client.postUrl(url);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (token != null) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (payload != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
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
    stderr.writeln('datyx: ${payload == null ? 'GET' : 'POST'} $path: $error');
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
