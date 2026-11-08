/// Poker Tour's server, on a laptop or in the container: one process that
/// serves the app's release web build under /app/, answers the API under
/// /api/ (lib/routes.dart), keeps the tour in Floci, the local AWS
/// (floci/compose.yaml): leaderboard.json and live.json in its S3, the
/// strategies and aliases in its DynamoDB (lib/leaderboard.dart,
/// lib/store.dart, lib/tour_db.dart), as the functions keep them in AWS,
/// and plays the leaderboard's tournaments on aityx with the
/// leaderboard's key (lib/runner.dart) when the schedule says, or an
/// admin asks. On AWS the same code runs as two Lambda functions instead
/// (bin/lambda.dart). The key never reaches a browser: players bring
/// their own.
///
/// Settings, from the environment (scripts/serve.sh loads .env):
///   POKERTOUR_LEADERBOARD_KEY  the leaderboard's key (secret): the
///                         runner's decisions; else AITYX_API_KEY. Never
///                         the players' key, which they fetch from S3
///   AITYX_URL             aityx's base URL (default https://api.aityx.ai),
///                         the browsers' too (GET /api/config)
///   API_PORT              the port (default 9810); FLUTTER_WEB_PORT is
///                         the same port, the app being served here
///   POKERTOUR_BIND_HOST   the address to bind (default 127.0.0.1)
///   WEB_ROOT              the web build (pokertour_app/build/web)
///   POKERTOUR_MODELS      the models folder (table.json, strategies/);
///                         default ../pokertour_app/assets/models
///   POKERTOUR_AWS_ENDPOINT  Floci's address (default http://localhost:9811):
///                         never AWS's, and with Floci's dummy credentials
///   POKERTOUR_DATA_BUCKET, POKERTOUR_TABLE  the bucket and the table in
///                         it (default pokertour-local, both)
///   OIDC_ISSUER, OIDC_CLIENT_ID, POKERTOUR_ALLOWED_DOMAINS,
///   POKERTOUR_ADMIN_DOMAINS  the sign-in and the admins (lib/auth.dart)
///   POKERTOUR_RUN         on (the default, with a key) or off: the runner
///   POKERTOUR_SCHEDULE_HOURS  when it plays on its own: hours of the day,
///                         UTC (default 0,6,12,18; off for none)
///   POKERTOUR_MAX_HANDS   hands after which a tournament ends on chips
///                         (default 300)
///   POKERTOUR_MAX_ENTRIES strategies a player may have in (default 3)
///
/// `server healthcheck` asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:poker_core/sample.dart';
import 'package:poker_core/table.dart';
import 'package:pokertour_api/aityx.dart';
import 'package:aws_lite/aws_lite.dart';
import 'package:pokertour_api/aityx_relay.dart';
import 'package:pokertour_api/auth.dart';
import 'package:pokertour_api/aws/dynamodb.dart';
import 'package:pokertour_api/aws/s3.dart';
import 'package:pokertour_api/leaderboard.dart';
import 'package:pokertour_api/models_dir.dart';
import 'package:pokertour_api/routes.dart';
import 'package:pokertour_api/runner.dart';
import 'package:pokertour_api/schedule.dart';
import 'package:pokertour_api/static_files.dart';
import 'package:pokertour_api/store.dart';
import 'package:pokertour_api/tour_db.dart';

/// A tournament on a laptop gets the time a Lambda function would.
const _timeLimit = Duration(minutes: 14);

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'healthcheck') exit(await _healthcheck());
  final env = Platform.environment;
  final port = int.parse(env['API_PORT'] ?? '9810');
  final host = env['POKERTOUR_BIND_HOST'] ?? '127.0.0.1';
  final key = (env['POKERTOUR_LEADERBOARD_KEY'] ?? '').isEmpty ? env['AITYX_API_KEY'] ?? '' : env['POKERTOUR_LEADERBOARD_KEY']!;
  final urlText = (env['AITYX_URL'] ?? '').isEmpty ? 'https://api.aityx.ai' : env['AITYX_URL']!;
  final url = Uri.parse(urlText);
  if (url.scheme != 'https') {
    stderr.writeln('error: AITYX_URL must be https');
    exit(1);
  }
  final modelsDir = Directory((env['POKERTOUR_MODELS'] ?? '').isEmpty ? '../pokertour_app/assets/models' : env['POKERTOUR_MODELS']!);
  final Models models;
  try {
    models = await loadModelsFrom(modelsDir);
  } catch (error) {
    stderr.writeln('error: the models could not be read from ${modelsDir.path}: $error');
    exit(1);
  }
  final webRoot = Directory((env['WEB_ROOT'] ?? '').isEmpty ? '../pokertour_app/build/web' : env['WEB_ROOT']!);
  if (!await File('${webRoot.path}/index.html').exists()) {
    stderr.writeln('warning: no web build at ${webRoot.path} (WEB_ROOT): /app/ answers 404 until there is one');
  }
  final floci = Uri.parse((env['POKERTOUR_AWS_ENDPOINT'] ?? '').isEmpty ? 'http://localhost:9811' : env['POKERTOUR_AWS_ENDPOINT']!);
  if (floci.host.endsWith('amazonaws.com')) {
    stderr.writeln('error: POKERTOUR_AWS_ENDPOINT is AWS ($floci): a local run keeps the tour in Floci');
    exit(1);
  }
  final bucket = (env['POKERTOUR_DATA_BUCKET'] ?? '').isEmpty ? 'pokertour-local' : env['POKERTOUR_DATA_BUCKET']!;
  final table = (env['POKERTOUR_TABLE'] ?? '').isEmpty ? 'pokertour-local' : env['POKERTOUR_TABLE']!;
  // Floci takes any credentials; these are never AWS's.
  const flociCredentials = AwsCredentials(accessKeyId: 'test', secretAccessKey: 'test');
  final auth = AuthSettings.fromEnvironment(env);
  final verifier = TokenVerifier(auth);
  final aityx = AityxDecider(AityxSettings(key: key, url: url), models);
  final store = S3Store(S3Client(credentials: flociCredentials, region: 'us-east-1', endpoint: floci), bucket);
  final boards = Boards(
    store: store,
    db: DynamoTourDb(DynamoClient(credentials: flociCredentials, region: 'us-east-1', endpoint: floci), table),
    models: models,
    maxPerPlayer: int.tryParse(env['POKERTOUR_MAX_ENTRIES'] ?? '') ?? 3,
  );
  final run = (env['POKERTOUR_RUN'] ?? '').isEmpty ? 'on' : env['POKERTOUR_RUN']!;
  if (run != 'on' && run != 'off') {
    stderr.writeln('error: POKERTOUR_RUN must be on or off');
    exit(1);
  }
  final schedule = Schedule.fromEnvironment(env);
  final enabled = key.isNotEmpty && run == 'on';
  final runner = Runner(
    boards: boards,
    decider: aityx,
    maxHands: int.tryParse(env['POKERTOUR_MAX_HANDS'] ?? '') ?? 300,
  );
  if (key.isEmpty) {
    stderr.writeln('warning: POKERTOUR_LEADERBOARD_KEY (or AITYX_API_KEY) is not set: the leaderboard will not play');
  } else if (run == 'off') {
    stdout.writeln('note: POKERTOUR_RUN=off: the leaderboard will not play');
  }
  if (!auth.enabled) stderr.writeln('warning: OIDC_CLIENT_ID is not set: nobody can sign in or enter strategies');

  // A tournament the last process left unfinished.
  final before = await readLive(store);
  if (before != null && before.stale(DateTime.now())) {
    await store.write(LiveState.name, jsonEncode(LiveState(state: 'error', detail: 'the last tournament was cut short: the server stopped').toJson()));
  }

  /// The schedule: a timer to the next hour on it, then the next.
  Timer? timer;
  void scheduleNext() {
    final now = DateTime.now();
    final next = schedule.next(now);
    if (!enabled || next == null) return;
    timer = Timer(next.difference(now), () async {
      await runner.play(deadline: DateTime.now().add(_timeLimit));
      scheduleNext();
    });
    stdout.writeln('runner: the next scheduled tournament is at ${next.toIso8601String()}');
  }

  scheduleNext();
  if (enabled && !schedule.enabled) stdout.writeln('note: POKERTOUR_SCHEDULE_HOURS=off: tournaments only when an admin asks');

  /// An admin's "now": started here and then, unless one is on.
  Future<String> start(Identity by) async {
    if (runner.playing) return 'running';
    stdout.writeln('api: a tournament was started by ${by.ownerId}');
    unawaited(runner.play(deadline: DateTime.now().add(_timeLimit)));
    return 'started';
  }

  /// Runs [json]'s rules on aityx with the sample situation; throws when
  /// aityx refuses them (for POST /api/strategies).
  Future<void> check(Object? json) async {
    final strategy = Strategy.fromJson(json, id: 'check', custom: true);
    try {
      await aityx.act(strategy, sampleSituation);
    } on DecisionException catch (e) {
      if (e.strategyFault) throw Exception(e.message);
      // The key or the network: not the strategy's fault, let it in.
      stderr.writeln('check: aityx could not be asked (${e.message}); the entry goes in unchecked');
    }
  }

  // aityx staging takes no browser calls: the app's go through here.
  final relay = AityxRelay(url);
  final files = StaticFiles(webRoot);
  final server = await HttpServer.bind(host, port);
  stdout.writeln('pokertour on http://$host:$port/app/ (api at /api/, models from ${modelsDir.path}, tour in Floci at $floci, s3://$bucket and table $table)');
  // A clean stop: the runner finishes its decision and the file is saved.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      timer?.cancel();
      runner.stop();
      await server.close(force: true);
      exit(0);
    });
  }

  await for (final request in server) {
    unawaited(() async {
      final live = runner.playing ? runner.live : (await readLive(store) ?? runner.live);
      await _handle(
        request,
        files: files,
        verifier: verifier,
        relay: relay,
        route: (method, path, who, body) => route(
          method,
          path,
          auth: auth,
          boards: boards,
          who: who,
          body: body,
          aityx: aityx.settings.hasKey,
          aityxUrl: urlText,
          aityxRelay: '/aityx/',
          live: live,
          schedule: schedule,
          runnerEnabled: enabled,
          start: enabled ? start : null,
          check: check,
        ),
      );
    }());
  }
}

typedef _Route = Future<Answer> Function(String method, String path, Verified? who, Object? body);

Future<void> _handle(
  HttpRequest request, {
  required StaticFiles files,
  required TokenVerifier verifier,
  required AityxRelay relay,
  required _Route route,
}) async {
  final response = request.response;
  try {
    final path = request.uri.path;
    if (path == '/aityx/v1/systemone') {
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final body = <int>[];
      await for (final chunk in request) {
        body.addAll(chunk);
        if (body.length > AityxRelay.maxBody) break;
      }
      // The browser's own key, passed on as it is; never logged.
      final answer = await relay.systemone(body, authorization: request.headers.value(HttpHeaders.authorizationHeader));
      response
        ..statusCode = answer.status
        ..headers.set(HttpHeaders.contentTypeHeader, answer.contentType)
        ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
        ..add(answer.body);
    } else if (path == '/' || path == '/app') {
      response
        ..statusCode = HttpStatus.movedPermanently
        ..headers.set(HttpHeaders.locationHeader, '/app/');
    } else if (path.startsWith('/app/')) {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        await files.serve(request, path.substring('/app/'.length));
      }
    } else if (path.startsWith('/api/')) {
      final bearer = request.headers.value(HttpHeaders.authorizationHeader);
      final token = bearer != null && bearer.startsWith('Bearer ') ? bearer.substring(7).trim() : null;
      final who = token == null ? null : await verifier.verify(token);
      Object? body;
      if (request.method == 'POST' || request.method == 'PUT') {
        final text = await utf8.decoder.bind(request).join();
        if (text.length > 256 * 1024) {
          _json(response, 413, {'error': 'request too large'});
          return;
        }
        try {
          body = text.isEmpty ? null : jsonDecode(text);
        } on FormatException {
          _json(response, 400, {'error': 'invalid JSON'});
          return;
        }
      }
      final answer = await route(request.method, path, who, body);
      if (answer.body == null) {
        response.statusCode = answer.status;
      } else {
        _json(response, answer.status, answer.body!);
      }
    } else {
      _json(response, 404, {'error': 'not found'});
    }
  } catch (error, stack) {
    stderr.writeln('error: ${request.method} ${request.uri.path}: $error\n$stack');
    try {
      _json(response, 500, {'error': 'internal error'});
    } catch (_) {}
  } finally {
    await response.close();
  }
}

void _json(HttpResponse response, int status, Object body) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
    ..write(jsonEncode(body));
}

Future<int> _healthcheck() async {
  final port = Platform.environment['API_PORT'] ?? '9810';
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/api/health'));
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = await utf8.decoder.bind(response).join();
    client.close();
    return response.statusCode == 200 && jsonDecode(body)['ok'] == true ? 0 : 1;
  } catch (_) {
    return 1;
  }
}
