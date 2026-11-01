/// HealthHub's API. Holds the aityx.ai key, which must never reach the
/// app, talks to PostgreSQL (lib/db.dart), and answers:
///
///   GET  /              302 to /app/, so a forwarded port's bare URL
///                       opens the app (the web server proxies the root
///                       here)
///   GET  /api/health    {"ok": true, "db": true when the database
///                       answers, "aityx": true when HealthHub has
///                       the key, or calls go through datyx and datyx
///                       last said it has one (GET /api/aityx/v1/status,
///                       asked at most once a minute, in the background),
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
///   GET  /api/care-centers/nearest?lat=..&lon=..
///                       {"center": {..., "distance": metres} or null}: the
///                       care center nearest the point, of any kind, which
///                       home's map centres on; open to all; the point is
///                       used for the query only, never logged or kept; 400
///                       for a point that isn't one, 503 when the database
///                       doesn't answer
///   GET  /api/people    {"enabled": dev mode, "simTime", "day", "people":
///                       [...]}: the simulated people's latest moves, read
///                       back from Kafka (lib/simulation.dart), open to all
///   GET  /api/events?limit=20&type=admission|move
///                       {"enabled", "paused", "topic", "topics", "busiest",
///                       "events": [...]}: the latest changes of state and
///                       admissions read from the streams, newest first by
///                       simulated time, each with its "type" (dev mode),
///                       whether the simulation is paused, and the care
///                       center with the most people in care now, for
///                       home's events; open to all
///   POST /api/simulation/pause, POST /api/simulation/resume
///                       {"paused": true|false}, the state after the call:
///                       freezes or resumes the simulation, the same one
///                       everyone watches (idempotent); 401 without a user
///                       once authentication is on, 409 when it doesn't run
///   POST /api/simulation/people {"perCity": n}
///                       {"perCity": n}, the people a city after the call
///                       (1 to 200): people join at the turn now or the
///                       last to join leave; signed in and running as for
///                       pause, 400 for any other number
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
///   GET  /api/care-centers/{id}
///                       one care center: where it is, its capacity in
///                       the simulation, who is there and on the way now,
///                       its flow factor this run ("flow", 1 normally),
///                       its admissions counted and the latest; open to
///                       all; 404 for none, 503 without the database
///   POST /api/care-centers/{id}/flow {"action": "double"|"halve"|"reset"}
///                       {"id", "factor"}: the flow at that care center
///                       after the call (1/8 to 8, 1 normal): the visits
///                       headed there come that many times as often, for
///                       the rest of the run; signed in and running as
///                       for pause, 400 for another action, 404 for a
///                       care center the simulation sends nobody to
///   GET  /api/people/{id}/prediction
///                       datyx's XGBoost prediction of their hours of
///                       care over the next 30 days, asked with the
///                       user's own token; 502 when datyx is down
///   GET  /api/care-centers/{id}/admissions?run=&hours=72
///                       the hospital's admissions in each hour up to its
///                       run's end, missing hours zero; open to all; 503
///                       without the database
///   GET  /api/care-centers/{id}/admissions/forecast?run=
///                       datyx's DeepAR forecast of the hospital's
///                       admissions per hour, step by step, asked with the
///                       user's own token; 502 when datyx is down
///   GET  /api/care-centers/{id}/occupancy?run=&hours=72
///                       the people in care there in each hour up to its
///                       run's end, missing hours zero, with what datyx
///                       predicted of each before it was observed (signed
///                       in, once sign-in is on), the alarms' threshold
///                       and the simulated clock; open to all; 503 without
///                       the database
///   GET  /api/care-centers/{id}/occupancy/forecast?run=
///                       datyx's DeepAR forecast of them, step by step, as
///                       the admissions' is asked
///   GET  /api/alarms?limit=20
///                       {"enabled", "now", "active", "recent", ...}: the
///                       care centers whose occupancy, observed or as
///                       datyx's forecast puts it, reaches the threshold of
///                       their capacity, and the latest alarm events
///                       (lib/occupancy_alarms.dart); signed in, once
///                       sign-in is on, as the forecast. It and
///                       GET /api/events (which carries them too) set a
///                       check off with the caller's token, at most once
///                       every HEALTHHUB_ALARM_EVERY_MS, in the background
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
///   DATYX_SERVICE_TOKEN   datyx's service token (secret): with it, the
///                         triage's calls go through datyx's aityx
///                         gateway, with datyx's key, and to aityx
///                         directly only when datyx can't pass them on
///   HEALTHHUB_AITYX_VIA_DATYX  on or off: whether they do (default on in
///                         dev mode, off in prod)
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
///   HEALTHHUB_HISTORY_DAYS  in dev mode, the days of admissions history
///                         written at start (default 90; 0 for none; see
///                         lib/history.dart)
///   HEALTHHUB_ALARM_EVERY_MS  real milliseconds between two occupancy
///                         alarm checks at least (default 5000; 0: off)
///   HEALTHHUB_ALARM_THRESHOLD  the share of a care center's capacity
///                         whose reaching is an alarm (default 0.9, or
///                         90%; above 0, at most 2)
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
import 'package:healthhub_api/history.dart';
import 'package:healthhub_api/kafka_rest.dart';
import 'package:healthhub_api/occupancy_alarms.dart';
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
  final triageSetting = (env['HEALTHHUB_TRIAGE'] ?? '').isEmpty ? 'on' : env['HEALTHHUB_TRIAGE']!;
  if (triageSetting != 'on' && triageSetting != 'off') {
    stderr.writeln('error: HEALTHHUB_TRIAGE must be on or off');
    exit(1);
  }

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
  // The triage's calls through datyx's aityx gateway: on in dev mode
  // unless off, and only with datyx's service token.
  final viaDatyx = (env['HEALTHHUB_AITYX_VIA_DATYX'] ?? '').isEmpty
      ? (mode == 'dev' ? 'on' : 'off')
      : env['HEALTHHUB_AITYX_VIA_DATYX']!;
  if (viaDatyx != 'on' && viaDatyx != 'off') {
    stderr.writeln('error: HEALTHHUB_AITYX_VIA_DATYX must be on or off');
    exit(1);
  }
  final serviceToken = env['DATYX_SERVICE_TOKEN'] ?? '';
  if (viaDatyx == 'on' && serviceToken.isEmpty) {
    stderr.writeln('note: DATYX_SERVICE_TOKEN is not set, so aityx is called directly, not through datyx');
  }
  final aityx = Aityx(url, key, datyx: viaDatyx == 'on' ? datyx : null, serviceToken: serviceToken);
  if (key.isEmpty) {
    stderr.writeln(
      aityx.routesViaDatyx
          ? 'note: AITYX_API_KEY is not set, so aityx is reached through datyx only'
          : 'warning: AITYX_API_KEY is not set',
    );
  }
  final int historyDays;
  try {
    historyDays = historyDaysFromEnvironment(env);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exit(1);
  }
  final kafka = KafkaRest(Uri.parse(
    (env['HEALTHHUB_KAFKA_REST_URL'] ?? '').isEmpty
        ? 'http://127.0.0.1:9805'
        : env['HEALTHHUB_KAFKA_REST_URL']!,
  ));
  final Duration alarmEvery;
  final double alarmThreshold;
  try {
    alarmEvery = alarmEveryOf(env['HEALTHHUB_ALARM_EVERY_MS']);
    alarmThreshold = alarmThresholdOf(env['HEALTHHUB_ALARM_THRESHOLD']);
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exit(1);
  }
  final live = _Live(
    dev: mode == 'dev',
    kafka: kafka,
    aityx: aityx,
    triage: triageSetting == 'on' && aityx.configured,
    threshold: alarmThreshold,
  );
  if (live.dev && alarmEvery > Duration.zero) live.alarms = _alarms(db, datyx, live, alarmEvery);
  // Without a key of HealthHub's, whether datyx has one: until it says
  // so, aityx isn't reported and no admission is triaged.
  if (key.isEmpty && aityx.routesViaDatyx) {
    unawaited(aityx.check().then((available) {
      if (!available) stderr.writeln('note: datyx has no aityx key (or no answer) and HealthHub none, so triage waits for one');
    }));
  }
  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'healthhub_api on http://$host:$port (mode: $mode; '
    'aityx: ${aityx.routesViaDatyx ? 'through datyx${key.isEmpty ? '' : ', else ${url.host}'}' : url.host}; '
    'database: ${db.settings}; '
    'auth: ${auth.enabled ? 'on, ${auth.issuer}' : 'off'}; datyx: $datyx; '
    'kafka: ${kafka.base}; triage: ${live.triage ? 'on' : 'off'}; '
    'alarms: ${live.alarms == null ? 'off' : 'every ${alarmEvery.inMilliseconds} ms'}, at ${(alarmThreshold * 100).round()}%)',
  );
  // The tables, once the database answers: retried in the background, so
  // the server is up (and /api/health says db: false) meanwhile. The
  // simulation needs the care centers, so it starts after.
  unawaited(_migrate(db).then((_) => live.dev ? _simulate(db, live, historyDays) : null));
  live.watchKafka();
  // Stopped by process-compose, a rebuild, Docker or Ctrl-C: delete the
  // feed's consumers on the proxy, or each restart leaves them behind.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) => _shutdown(server, live));
  }

  await for (final request in server) {
    unawaited(_handle(request, origins, db, verifier, datyx, live));
  }
}

/// Kafka and, in dev mode, the simulation writing to it and the feed
/// reading it back.
class _Live {
  _Live({required this.dev, required this.kafka, required this.aityx, required this.triage, required this.threshold});

  final bool dev;

  /// The share of a care center's capacity whose reaching is an alarm.
  final double threshold;

  /// The writes of what datyx forecast (occupancy_forecast), one at a time.
  Future<void> _forecastWrites = Future.value();
  int _forecastsWaiting = 0;

  /// The run the last write was of, and the writes since the last prune.
  String? _forecastRun;
  int _forecastsSincePrune = 0;

  /// Keeps what datyx forecast of [run]'s care centers ([Db.recordForecasts])
  /// in the background, one write at a time; with too many waiting (the
  /// database slow) this one is dropped, as the next check's forecast says
  /// it again. Before the first write of a run (a new run, or after a
  /// restart), and every 500 writes (an hour or so of checks), what is
  /// kept of older runs and hours is pruned ([Db.pruneForecasts]). A
  /// failure is logged.
  void keepForecasts(Db db, String run, Map<int, List<Object?>> forecasts, Object? trainingRun) {
    if (_forecastsWaiting >= 4) {
      stderr.writeln('occupancy forecasts: ${forecasts.length} care centers not kept, too many writes waiting');
      return;
    }
    _forecastsWaiting++;
    final prune = run != _forecastRun || ++_forecastsSincePrune >= 500;
    if (prune) _forecastsSincePrune = 0;
    _forecastRun = run;
    _forecastWrites = _forecastWrites.then((_) async {
      try {
        if (prune) {
          final deleted = await db.pruneForecasts();
          if (deleted > 0) stderr.writeln('occupancy forecasts: $deleted rows of older runs and hours pruned');
        }
        await db.recordForecasts(run, forecasts, trainingRun: trainingRun);
      } catch (error) {
        stderr.writeln('occupancy forecasts: $error');
      } finally {
        _forecastsWaiting--;
      }
    });
  }
  final KafkaRest kafka;

  /// aityx, which triages each admission recorded when [triage] is on.
  final Aityx aityx;
  final bool triage;

  /// Whether there is a key to reach aityx with ([Aityx.available]), as
  /// last known: a stale answer from datyx is asked again in the
  /// background, so the health check never waits on datyx.
  bool get aityxAvailable {
    unawaited(aityx.check());
    return aityx.available;
  }

  /// Whether admissions are triaged now: [triage] on, with a key.
  bool get triaging => triage && aityxAvailable;
  Simulation? simulation;
  PeopleFeed? feed;
  AdmissionRecorder? recorder;
  Triager? triager;

  /// The occupancy alarms, in dev mode unless turned off, and the queues
  /// that store and publish their events.
  OccupancyAlarms? alarms;
  List<RetryQueue<Map<String, Object?>>> alarmQueues = const [];

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
  // The alarm events found, given a moment to be stored and published.
  for (final queue in live.alarmQueues) {
    try {
      await queue.idle.timeout(const Duration(seconds: 3));
    } catch (_) {}
    queue.stop();
  }
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
/// the feed and the simulation, and writes [historyDays] days of
/// admissions history in the background ([_history]). Neither waits for
/// Kafka: the people keep moving and retry publishing, the feed retries
/// connecting.
Future<void> _simulate(Db db, _Live live, int historyDays) async {
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
  // The same people at every start ([populationSeed]), so the history
  // covers the care centers they use; what they do is drawn afresh.
  final people = populate(
    places,
    settings.peoplePerCity,
    settings.minutesPerTurn,
    Random(populationSeed),
    conditions: conditionSeed,
  );
  if (people.isEmpty) {
    stderr.writeln('simulation: no hospitals with a location, so nobody to move');
    return;
  }
  if (historyDays > 0) unawaited(_history(db, historyCenters(people, conditionSeed), historyDays));
  final random = Random();
  if (conditionSeed.isEmpty) {
    stderr.writeln('simulation: no medical conditions, so nobody goes to the hospital');
  }
  // Each admission recorded the first time is triaged with aityx, in the
  // background; a triage the database can't record is logged and lost.
  // The events carry its level once it is recorded.
  final triager = live.triage
      ? live.triager = Triager(
          (admission) async {
            final triage = await triageAdmission(live.aityx, admission);
            await db.recordTriage(triage);
            live.feed?.triaged(triage['eventId'], triage['level']);
          },
          ready: live.aityx.check,
        )
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
  live.simulation = Simulation(people, settings, live.kafka, conditions: conditionSeed, places: places, random: random)
    ..start();
}

/// The JSON body of [request], at most 4 KB; null when it isn't JSON.
Future<Object?> _jsonBody(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
    if (bytes.length > 4096) return null;
  }
  try {
    return jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
}

/// The occupancy alarms (lib/occupancy_alarms.dart): datyx's forecast of
/// every care center's occupancy, asked with the token of the request that
/// set the check off, each event stored and published to [alarmsTopic] in
/// the background, retried until it is.
OccupancyAlarms _alarms(Db db, Uri datyx, _Live live, Duration every) {
  String describe(Map<String, Object?> event) => '${event['id']}';
  final store = RetryQueue<Map<String, Object?>>(
    'occupancy alarms: recording',
    db.recordAlarm,
    isPermanent: Db.isPermanentError,
    describe: describe,
  );
  final publish = RetryQueue<Map<String, Object?>>(
    'occupancy alarms: publishing to $alarmsTopic',
    (event) => live.kafka.produce(alarmsTopic, [alarmRecord(event)]),
    describe: describe,
  );
  live.alarmQueues = [store, publish];
  return OccupancyAlarms(
    infer: (token, series) async {
      final answer = await _inference(datyx, token, db, CareCenterSeries.occupancy.table,
          CareCenterSeries.occupancy.group, series,
          options: const {'algorithm': 'DeepAR'}, timeout: const Duration(seconds: 30));
      return answer == null ? null : (status: answer.status, body: answer.body);
    },
    careCenters: db.alarmCareCenters,
    observed: db.observedOccupancy,
    onForecasts: (run, forecasts, trainingRun) => live.keepForecasts(db, run, forecasts, trainingRun),
    threshold: live.threshold,
    run: () => live.simulation?.run,
    clock: () => simNowOf(live.feed?.people ?? const []),
    paused: () => live.simulation?.paused ?? false,
    onEvent: (event) {
      stdout.writeln(
        'occupancy alarm: ${event['kind']} ${event['level'] ?? event['previous']} at ${event['hospitalName']} '
        '(${event['hospitalId']}), ${event['threshold']} of ${event['capacity']} reached at ${event['overflowAt'] ?? '-'}, '
        '${event['id']}',
      );
      store.add(event);
      publish.add(event);
    },
    every: every,
  );
}

/// Writes [days] days of admissions history (lib/history.dart) for
/// [centers], those the simulation's people use: retried a few times,
/// then logged and left.
Future<void> _history(Db db, List<Place> centers, int days) async {
  for (var attempt = 1; attempt <= 5; attempt++) {
    try {
      final written = await db.writeHistory(centers, days);
      stdout.writeln(
        'history: run $historyRun, $days days, ${written.centers} care centers '
        '(${written.written} written, the others up to date), ${written.rows} rows',
      );
      return;
    } catch (error) {
      stderr.writeln('history: not written (attempt $attempt): $error');
      await Future<void>.delayed(const Duration(seconds: 5));
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
  Uri datyx,
  _Live live,
) async {
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
    // /api/care-centers/{id}/admissions or .../occupancy, and .../forecast: the care center, the series, and which.
    final hourlyRoute = careCenterSeriesPath(path);
    // The panel's polls set an alarm check off, with the caller's token for
    // that check's datyx call only; never one without a user once sign-in
    // is on. Returns at once.
    if (method == 'GET' && (path == '/api/events' || path == '/api/alarms') && (!auth.enabled || identity != null)) {
      live.alarms?.poke(token);
    }
    // Only the routes that need the database, or datyx, ask them.
    final answer = switch ((method, path)) {
      ('GET', '/api/health') => route(
        method,
        path,
        db: await db.ping(),
        aityx: live.aityxAvailable,
        auth: auth,
        kafka: live.kafkaUp,
        simulation: live.simulation?.running ?? false,
        paused: live.simulation?.paused ?? false,
        triageEnabled: live.triaging,
      ),
      ('GET', '/api/triage') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        triageEnabled: live.triaging,
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
        peoplePerCity: live.simulation?.peoplePerCity,
        events: live.feed?.recent ?? const [],
        busiest: live.feed?.busiest,
        eventsTotal: live.feed?.counter.total ?? 0,
        eventsPerSecond: live.feed?.counter.perSecond ?? 0,
        people: live.feed?.people ?? const [],
        alarms: live.alarms?.snapshot ?? AlarmsSnapshot(threshold: live.threshold),
        identity: identity,
      ),
      ('GET', '/api/alarms') => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        identity: identity,
        dev: live.dev,
        paused: live.simulation?.paused ?? false,
        people: live.feed?.people ?? const [],
        alarms: live.alarms?.snapshot ?? AlarmsSnapshot(threshold: live.threshold),
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
      ('POST', simulationPeoplePath) => route(
        method,
        path,
        auth: auth,
        identity: identity,
        dev: live.dev,
        simulation: live.simulation?.running ?? false,
        body: await _jsonBody(request),
        population: (perCity) {
          final simulation = live.simulation!;
          final changed = simulation.setPeoplePerCity(perCity);
          live.feed?.join(changed.joined);
          live.feed?.leave(changed.left);
          return simulation.peoplePerCity;
        },
      ),
      ('POST', _) when careCenterFlowIdOf(path) != null => route(
        method,
        path,
        auth: auth,
        identity: identity,
        dev: live.dev,
        simulation: live.simulation?.running ?? false,
        body: await _jsonBody(request),
        flow: (id, action) => live.simulation?.changeFlow(id, action),
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
      ('GET', _) when careCenterIdOf(path) != null => route(
        method,
        path,
        auth: auth,
        dev: live.dev,
        people: live.feed?.people ?? const [],
        careCenter: await _careCenter(db, careCenterIdOf(path)!, live.simulation),
      ),
      ('GET', _) when hourlyRoute != null && !hourlyRoute.$3 => route(
        method,
        path,
        query: request.uri.queryParameters,
        auth: auth,
        identity: identity,
        hourly: await _hourly(
          db,
          hourlyRoute.$2,
          hourlyRoute.$1,
          request.uri.queryParameters,
          request.uri.queryParameters['run'] ?? live.simulation?.run,
          live,
        ),
      ),
      ('GET', _) when hourlyRoute != null => route(
        method,
        path,
        auth: auth,
        identity: identity,
        forecast: auth.enabled && identity == null
            ? null
            : await _forecast(datyx, token, db, hourlyRoute.$2, hourlyRoute.$1,
                request.uri.queryParameters['run'] ?? live.simulation?.run, live),
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
      ('GET', '/api/care-centers/nearest') => route(
        method,
        path,
        query: request.uri.queryParameters,
        nearest: await _nearest(db, request.uri.queryParameters),
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
      _ => route(method, path, auth: auth, identity: identity),
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

/// The care center nearest the point [query] names (none for a point that
/// isn't one, which the route answers 400); null when the database doesn't
/// answer (logged, without the point).
Future<NearestCenter?> _nearest(Db db, Map<String, String> query) async {
  final point = nearestPoint(query);
  if (point == null) return const NearestCenter(null);
  try {
    return NearestCenter(await db.nearestCareCenter(point.lat, point.lon));
  } catch (error) {
    stderr.writeln('nearest care center: $error');
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

/// One care center, with its admissions of [simulation]'s run and of all
/// runs, and its flow factor in that run (the run and the factor null when
/// the simulation doesn't run); null when the database doesn't answer
/// (logged).
Future<CareCenterLookup?> _careCenter(Db db, int id, Simulation? simulation) async {
  final run = simulation?.run;
  try {
    return CareCenterLookup(
      await db.careCenterHistory(id, run: run),
      currentRun: run,
      flow: simulation != null && simulation.running ? simulation.flowOf(id) : null,
    );
  } catch (error) {
    stderr.writeln('care centers: $error');
    return null;
  }
}

/// One care center's [series] per hour in [run] (the newest run with its
/// admissions when null; none for hours that aren't a number, which the
/// route answers 400); null when the database doesn't answer (logged).
///
/// The occupancy comes with what datyx predicted of those hours before
/// they were observed (occupancy_forecast), the alarms' threshold, and
/// the simulated clock when the run is the current one.
Future<HourlyLookup?> _hourly(
  Db db,
  CareCenterSeries series,
  int id,
  Map<String, String> query,
  String? run,
  _Live live,
) async {
  final hours = hoursOf(query);
  if (hours == null) return const HourlyLookup();
  final currentRun = live.simulation?.run;
  try {
    final read = await _read(db, series, id, run: run, hours: hours);
    final current = read.run != null && read.run == currentRun;
    final end = read.end;
    if (series != CareCenterSeries.occupancy) {
      return HourlyLookup(run: read.run, end: end, current: current, rows: read.rows);
    }
    return HourlyLookup(
      run: read.run,
      end: end,
      current: current,
      rows: read.rows,
      predicted: read.run == null || end == null
          ? const []
          : await db.predictedOccupancy(id, read.run!, end.subtract(Duration(hours: hours)), end),
      threshold: live.threshold,
      now: current ? simNowOf(live.feed?.people ?? const []) : null,
    );
  } catch (error) {
    stderr.writeln('${series.path} per hour: $error');
    return null;
  }
}

Future<({String? run, DateTime? end, List<Map<String, Object?>> rows})> _read(
  Db db,
  CareCenterSeries series,
  int id, {
  String? run,
  required int hours,
}) => switch (series) {
  CareCenterSeries.admissions => db.hospitalHourly(id, run: run, hours: hours),
  CareCenterSeries.occupancy => db.hospitalOccupancy(id, run: run, hours: hours),
};

/// datyx's DeepAR forecast of one care center's [series] per hour in [run]
/// (the newest run with its admissions when null), asked with the user's
/// own [token], as [_prediction] asks: from the end of the care center's
/// series of the series' table, group default. An occupancy forecast of
/// the run going on, from the datyx source the alarms' checks settled on,
/// is kept (occupancy_forecast), as the checks keep theirs; none before a
/// check has, or with the alarms off.
Future<Forwarded?> _forecast(
  Uri datyx,
  String? token,
  Db db,
  CareCenterSeries series,
  int id,
  String? run,
  _Live live,
) async {
  var chosen = run;
  if (chosen == null) {
    try {
      chosen = (await _read(db, series, id, hours: 1)).run;
    } catch (error) {
      stderr.writeln('${series.path} per hour: $error');
    }
    if (chosen == null) return const Forwarded(404, {'error': 'nobody has been admitted there'});
  }
  final answer = await _inference(datyx, token, db, series.table, series.group, [{'run_id': chosen, 'hospital_id': '$id'}]);
  final body = answer?.body;
  if (series == CareCenterSeries.occupancy && answer?.status == 200 && body is Map && live.dev) {
    // Only from the source the alarms settled on, of the run going on: nothing kept before, or with the alarms off.
    final accepted = live.alarms?.keepsForecastOf(chosen, body['sourceId']) ?? false;
    final predictions = body['predictions'];
    final first = predictions is List && predictions.isNotEmpty && predictions.first is Map ? predictions.first as Map : null;
    final forecast = first?['forecast'];
    if (accepted && forecast is List && forecast.isNotEmpty && '${(first?['series'] as Map?)?['run_id'] ?? chosen}' == chosen) {
      live.keepForecasts(db, chosen, {id: forecast}, body['runId']);
    }
  }
  return answer;
}

/// The table and group of datyx's model of HealthHub's patients: their
/// hours of care, summed over the next 30 days, by XGBoost.
const _predictionTable = 'public.patient_days';
const _predictionGroup = 'care';

/// datyx's prediction for one person of [run] (the newest run with their
/// admissions when null), asked with the user's own [token]: the
/// inference of their series of patient_days ([_inference]). A 404 of
/// ours when the person has no run.
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
  return _inference(datyx, token, db, _predictionTable, _predictionGroup, [{'run_id': series, 'person_id': id}]);
}

/// datyx's inference of [series] of [table]'s [group] (each named by its
/// key, at most 100), asked with the user's own [token]: their datyx data
/// source for this API's database (the database source whose database is
/// ours), then the inference; the answer carries the source's id. A 404
/// of ours when datyx has no such source; null when datyx doesn't answer
/// (logged). [options] go in the request too (the algorithm).
Future<Forwarded?> _inference(
  Uri datyx,
  String? token,
  Db db,
  String table,
  String group,
  List<Map<String, String>> series, {
  Map<String, Object?> options = const {},
  Duration timeout = const Duration(seconds: 10),
}) async {
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
  final scored = await _forward(datyx, '/api/datasources/$sourceId/inference', token, timeout: timeout, payload: {
    'table': table,
    'group': group,
    'series': series,
    ...options,
  });
  if (scored != null && scored.body is Map) {
    return Forwarded(scored.status, {...(scored.body as Map), 'sourceId': sourceId});
  }
  return scored;
}

/// The datyx API's answer to [path], asked with the user's own [token] so
/// datyx sees the same person: a GET, or a POST of [payload] as JSON; null
/// when datyx doesn't answer (logged).
Future<Forwarded?> _forward(
  Uri datyx,
  String path,
  String? token, {
  Object? payload,
  Duration timeout = const Duration(seconds: 10),
}) async {
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
    final response = await request.close().timeout(timeout);
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
