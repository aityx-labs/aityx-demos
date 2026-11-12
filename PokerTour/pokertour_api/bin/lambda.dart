/// Poker Tour on AWS: one executable, `bootstrap`, for two Lambda
/// functions, told apart by POKERTOUR_ROLE:
///   api     answers the API (lib/routes.dart) behind the function's URL,
///           which CloudFront serves under /api/ beside the app in S3;
///           when an admin asks for a tournament, or a player enters a
///           strategy, queues one in the tour's table (lib/queue.dart)
///           and invokes the runner function without waiting for it
///   runner  plays the queue's oldest tournament (lib/runner.dart) per
///           invocation, under the table's lock, within the function's
///           time limit, and invokes itself again while more wait;
///           invoked by the EventBridge schedule four times a day (which
///           queues the schedule's), and by the API
/// Both keep the tour in the data bucket (lib/store.dart: leaderboard.json
/// and live.json, under a prefix) and the tour's table (lib/tour_db.dart:
/// the players' strategies and aliases), and read the leaderboard's key from its
/// S3 object with the function's own role: nothing secret is in the
/// environment or the template, and players never get the key.
///
/// Settings, from the environment (deploy/template.yaml sets them):
///   POKERTOUR_ROLE            api or runner
///   POKERTOUR_DATA_BUCKET     the bucket with the tour's files
///   POKERTOUR_DATA_PREFIX     their prefix in it (default tour/)
///   POKERTOUR_TABLE           the tour's DynamoDB table: the players'
///                             strategies and aliases (lib/tour_db.dart)
///   POKERTOUR_RUNNER_FUNCTION the runner function's name (the api's, and
///                             the runner's own, to go on with the queue)
///   POKERTOUR_LEADERBOARD_KEY_OBJECT  the leaderboard's key object in
///                             the data bucket (the key alone)
///   POKERTOUR_MODELS          the models folder (default models/, beside
///                             the executable)
///   AITYX_URL, OIDC_ISSUER, OIDC_CLIENT_ID, POKERTOUR_ALLOWED_DOMAINS,
///   POKERTOUR_SCHEDULE_HOURS,
///   POKERTOUR_MAX_HANDS, POKERTOUR_MAX_ENTRIES, POKERTOUR_MAX_DAILY_TOURNAMENTS  as bin/server.dart's
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aws_lite/aws_lite.dart';
import 'package:poker_core/sample.dart';
import 'package:poker_core/table.dart';
import 'package:pokertour_api/aityx.dart';
import 'package:pokertour_api/auth.dart';
import 'package:pokertour_api/aws/dynamodb.dart';
import 'package:pokertour_api/aws/lambda.dart';
import 'package:pokertour_api/aws/s3.dart';
import 'package:pokertour_api/lambda/runtime.dart';
import 'package:pokertour_api/leaderboard.dart';
import 'package:pokertour_api/models_dir.dart';
import 'package:pokertour_api/queue.dart';
import 'package:pokertour_api/routes.dart';
import 'package:pokertour_api/runner.dart';
import 'package:pokertour_api/schedule.dart';
import 'package:pokertour_api/store.dart';
import 'package:pokertour_api/tour_db.dart';

Future<void> main() async {
  final env = Platform.environment;
  final role = env['POKERTOUR_ROLE'] ?? 'api';
  final region = env['AWS_REGION'] ?? env['AWS_DEFAULT_REGION'] ?? 'us-east-1';
  final credentials = AwsCredentials.fromEnvironment(env);
  final bucket = env['POKERTOUR_DATA_BUCKET'] ?? '';
  final table = env['POKERTOUR_TABLE'] ?? '';
  if (credentials == null || bucket.isEmpty || table.isEmpty) {
    stderr.writeln('error: AWS credentials, POKERTOUR_DATA_BUCKET and POKERTOUR_TABLE are needed');
    exit(1);
  }
  final urlText = (env['AITYX_URL'] ?? '').isEmpty ? 'https://api.aityx.ai' : env['AITYX_URL']!;
  final url = Uri.parse(urlText);
  // The host's key goes there, and the players' are sent there by the app.
  if (url.scheme != 'https' || url.host.isEmpty) {
    stderr.writeln('error: AITYX_URL must be an https URL');
    exit(1);
  }
  final Models models;
  try {
    models = await loadModelsFrom(Directory((env['POKERTOUR_MODELS'] ?? '').isEmpty ? 'models' : env['POKERTOUR_MODELS']!));
  } catch (error) {
    stderr.writeln('error: the models could not be read: $error');
    exit(1);
  }
  final s3 = S3Client(credentials: credentials, region: region);
  final tour = _Tour(
    env: env,
    region: region,
    s3: s3,
    lambda: LambdaClient(credentials: credentials, region: region),
    boards: Boards(
      store: S3Store(s3, bucket, prefix: env['POKERTOUR_DATA_PREFIX'] ?? 'tour/'),
      db: DynamoTourDb(DynamoClient(credentials: credentials, region: region), table),
      models: models,
      maxPerPlayer: int.tryParse(env['POKERTOUR_MAX_ENTRIES'] ?? '') ?? 3,
    ),
    auth: AuthSettings.fromEnvironment(env),
    bucket: bucket,
    leaderboardKey: env['POKERTOUR_LEADERBOARD_KEY_OBJECT'] ?? '',
    aityxUrl: url,
    schedule: Schedule.fromEnvironment(env),
    runnerFunction: env['POKERTOUR_RUNNER_FUNCTION'] ?? '',
    maxHands: int.tryParse(env['POKERTOUR_MAX_HANDS'] ?? '') ?? 300,
    maxDaily: int.tryParse(env['POKERTOUR_MAX_DAILY_TOURNAMENTS'] ?? '') ?? 12,
  );
  stdout.writeln('pokertour $role: data in s3://$bucket, region $region');
  await runLambda(role == 'runner' ? tour.runner : tour.api);
}

class _Tour {
  _Tour({
    required this.env,
    required this.region,
    required this.s3,
    required this.lambda,
    required this.boards,
    required this.auth,
    required this.bucket,
    required this.leaderboardKey,
    required this.aityxUrl,
    required this.schedule,
    required this.runnerFunction,
    required this.maxHands,
    required this.maxDaily,
  }) : verifier = TokenVerifier(auth);

  final Map<String, String> env;
  final String region;
  final S3Client s3;
  final LambdaClient lambda;
  final Boards boards;
  final AuthSettings auth;
  final TokenVerifier verifier;
  /// The data bucket, and the leaderboard's key object in it.
  final String bucket;
  final String leaderboardKey;
  final Uri aityxUrl;
  final Schedule schedule;
  final String runnerFunction;
  final int maxHands;
  final int maxDaily;

  Store get store => boards.store;

  /// The leaderboard plays when its key is in S3 and there is a runner
  /// function to invoke.
  bool get runnerEnabled => leaderboardKey.isNotEmpty && runnerFunction.isNotEmpty;

  AityxDecider? _decider;
  DateTime _keyRead = DateTime.fromMillisecondsSinceEpoch(0);

  /// aityx on the leaderboard's key, read from its S3 object (and again
  /// after ten minutes, in case the host changed it); null when there is
  /// no key object, or it can't be read.
  Future<AityxDecider?> decider() async {
    if (leaderboardKey.isEmpty) return null;
    if (_decider != null && DateTime.now().difference(_keyRead) < const Duration(minutes: 10)) return _decider;
    try {
      final object = await s3.get(bucket, leaderboardKey);
      final key = object?.text.trim() ?? '';
      if (key.isEmpty || key.contains('\n') || key.length > 512) {
        stderr.writeln('key: the object s3://$bucket/$leaderboardKey is ${object == null ? 'missing' : 'not a key'}');
        return _decider;
      }
      _decider?.close();
      _decider = AityxDecider(AityxSettings(key: key, url: aityxUrl), boards.models);
      _keyRead = DateTime.now();
    } on AwsException catch (e) {
      stderr.writeln('key: could not read the key object: $e');
    }
    return _decider;
  }

  /// Runs [json]'s rules on aityx with the sample situation; throws when
  /// aityx refuses them, and [CheckUnavailable] when it can't be asked:
  /// nothing goes in unchecked (for POST /api/strategies).
  Future<void> check(Object? json) async {
    final strategy = Strategy.fromJson(json, id: 'check', custom: true);
    final aityx = await decider();
    if (aityx == null) throw const CheckUnavailable('the leaderboard has no key');
    try {
      await aityx.act(strategy, sampleSituation);
    } on DecisionException catch (e) {
      if (e.strategyFault) throw Exception(e.message);
      stderr.writeln('check: aityx could not be asked: ${e.message}');
      throw CheckUnavailable(e.keyFault ? 'the leaderboard\'s key is not working' : e.message);
    }
  }

  /// Asks for a tournament from [source], by [by]: queued in the table,
  /// and the runner function invoked, which plays it when its turn comes.
  Future<String> start(String source, Identity by) async {
    final asked = await _queue('api').ask(source, by: by.ownerId);
    // Even when one was waiting: a runner that died left it to the next.
    await lambda.invokeAsync(runnerFunction, {'source': source});
    stdout.writeln('api: a tournament asked for by the $source (${by.ownerId}): ${asked.name}');
    return asked.name;
  }

  /// The queue as [holder] sees it; a runner's lock lasts until [until]
  /// (its function's own deadline), so a function that dies holding it
  /// never keeps the next one waiting.
  TournamentQueue _queue(String holder, {DateTime? until}) => TournamentQueue(
    boards.db,
    holder: holder,
    lease: until == null ? LiveState.staleAfter : until.difference(DateTime.now()),
  );

  /// The API function: a Lambda function URL event (payload 2.0) in, the
  /// answer out.
  Future<Object?> api(Object? event, LambdaContext context) async {
    final e = event is Map ? event.cast<String, Object?>() : const <String, Object?>{};
    final http = e['requestContext'] is Map && (e['requestContext'] as Map)['http'] is Map
        ? ((e['requestContext'] as Map)['http'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final method = (http['method'] as String? ?? 'GET').toUpperCase();
    final path = e['rawPath'] as String? ?? '/';
    final headers = {
      for (final h in (e['headers'] is Map ? (e['headers'] as Map) : const {}).entries) '${h.key}'.toLowerCase(): '${h.value}',
    };
    var text = e['body'] as String? ?? '';
    if (e['isBase64Encoded'] == true && text.isNotEmpty) text = utf8.decode(base64.decode(text), allowMalformed: true);
    final bearer = headers['authorization'];
    final token = bearer != null && bearer.startsWith('Bearer ') ? bearer.substring(7).trim() : null;
    final who = token == null ? null : await verifier.verify(token);
    Object? body;
    if (method == 'POST' || method == 'PUT') {
      if (text.length > 256 * 1024) return _answer(const Answer(413, {'error': 'request too large'}));
      try {
        body = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        return _answer(const Answer(400, {'error': 'invalid JSON'}));
      }
    }
    final answer = await route(
      method,
      path,
      auth: auth,
      boards: boards,
      who: who,
      body: body,
      // Whether the key is in S3 and readable, not just named.
      aityx: (await decider()) != null,
      aityxUrl: aityxUrl.toString(),
      live: await readLive(store),
      schedule: schedule,
      runnerEnabled: runnerEnabled,
      start: runnerEnabled ? start : null,
      waiting: _queue('api').waiting,
      check: check,
    );
    return _answer(answer);
  }

  Map<String, Object?> _answer(Answer answer) => {
    'statusCode': answer.status,
    'headers': {
      if (answer.body != null) 'content-type': 'application/json',
      'cache-control': 'no-store',
    },
    if (answer.body != null) 'body': jsonEncode(answer.body),
  };

  /// The runner function: the queue's oldest tournament, within the time
  /// left, under the table's lock; then itself again, while more wait.
  Future<Object?> runner(Object? event, LambdaContext context) async {
    final source = event is Map ? event['source'] : null;
    final queue = _queue('runner-${context.requestId}', until: context.deadline.add(const Duration(seconds: 5)));
    if (source == TournamentSource.schedule) await queue.ask(TournamentSource.schedule);
    final aityx = await decider();
    if (aityx == null) {
      final live = LiveState(state: 'error', detail: 'the host\'s key is not in S3: the leaderboard cannot play');
      await store.write(LiveState.name, jsonEncode(live.toJson()));
      return {'played': false, 'detail': live.detail};
    }
    final runner = Runner(boards: boards, decider: aityx, maxHands: maxHands, maxDaily: maxDaily);
    // Room after the deadline for a last aityx call (30 s) and the writes
    // that record the result.
    final deadline = context.deadline.subtract(const Duration(seconds: 90));
    TournamentResult? result;
    var played = 0;
    var more = false;
    try {
      played = await queue.drain(max: 1, (request) async {
        stdout.writeln('runner: a tournament asked for by the ${request.source}, ${context.remaining().inSeconds} s left');
        result = await runner.playAsked(request, deadline: deadline);
      });
    } finally {
      // The next one gets a function of its own, with all its time; even
      // when this one failed, so the queue never strands.
      try {
        more = played > 0 && (await queue.waiting()).isNotEmpty;
        if (more) await lambda.invokeAsync(runnerFunction, {'source': 'queue'});
      } catch (error) {
        stderr.writeln('runner: could not hand the queue on: $error');
      }
    }
    final r = result;
    return {
      'played': r != null,
      if (r != null) 'number': r.number,
      if (r != null) 'hands': r.hands,
      if (r != null) 'calls': r.calls,
      'state': runner.live.state,
      'detail': played == 0 ? 'nothing to play, or another runner is playing' : runner.live.detail,
      'more': more,
    };
  }
}
