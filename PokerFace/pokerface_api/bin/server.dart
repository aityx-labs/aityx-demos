/// PokerFace's API. Holds the aityx.ai key, which must never reach the
/// app, and answers:
///
///   GET  /                302 to /app/, so a forwarded port's bare URL
///                         opens the app (the dev server proxies the root
///                         here)
///   GET  /api/health      {"ok": true, "aityx": true when the key is set}
///   GET  /api/strategies  {"strategies": [...]}: the preset strategies
///                         (models/strategies/*.json), each with its rules
///   POST /api/act         {"strategy": "shark" | {...}, "situation": {...}}
///                         → the player's action (see lib/table.dart): the
///                         strategy's rules, run on aityx's /v1/systemone
///                         with the situation as the state; with the body
///                         sent to aityx and its answer under "aityx" (the
///                         key, a header, is in neither); 504 after 30 s
///
/// Settings, from the environment (scripts/api.sh loads .env):
///   AITYX_API_KEY       the key (secret)
///   AITYX_URL           aityx's base URL (default https://api.aityx.ai)
///   API_PORT            the port (default 8911)
///   POKERFACE_BIND_HOST  the address to bind (default 127.0.0.1)
///   ALLOWED_ORIGINS     comma-separated origins allowed by CORS
///                       (default http://localhost:8910)
///
/// `server healthcheck` instead asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pokerface_api/routes.dart';
import 'package:pokerface_api/table.dart';

const _maxBody = 64 * 1024;

/// How long a decision waits for aityx; docker/nginx.conf's proxy waits
/// longer.
const _aityxDeadline = Duration(seconds: 30);

/// What a decision needs: the key, where aityx is, the models and a
/// client.
class _Aityx {
  _Aityx(this.key, this.url, this.models);

  final String key;
  final Uri url;
  final Models models;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
}

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
  final port = int.parse(env['API_PORT'] ?? '8911');
  final host = env['POKERFACE_BIND_HOST'] ?? '127.0.0.1';
  final origins = (env['ALLOWED_ORIGINS'] ?? 'http://localhost:8910')
      .split(',')
      .map((origin) => origin.trim())
      .where((origin) => origin.isNotEmpty)
      .toSet();
  final models = await Models.load(
    Directory.fromUri(Platform.script.resolve('../models/')),
  );
  if (key.isEmpty) stderr.writeln('warning: AITYX_API_KEY is not set');

  final aityx = _Aityx(key, url, models);
  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'pokerface_api on http://$host:$port (aityx: ${url.host}; '
    '${models.strategies.length} strategies)',
  );

  await for (final request in server) {
    unawaited(_handle(request, origins, aityx));
  }
}

/// 0 when the server on this machine answers /api/health with ok, else 1.
Future<int> _healthcheck() async {
  final port = int.parse(Platform.environment['API_PORT'] ?? '8911');
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
  _Aityx aityx,
) async {
  final response = request.response;
  final origin = request.headers.value('origin');
  if (origin != null && origins.contains(origin)) {
    response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Vary', 'Origin')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type');
  }
  try {
    if (request.method == 'POST' && request.uri.path == '/api/act') {
      await _act(request, aityx);
    } else {
      final answer = route(
        request.method,
        request.uri.path,
        aityx: aityx.key.isNotEmpty,
        strategies: [
          for (final s in aityx.models.strategies.values) s.toJson(),
        ],
      );
      response.statusCode = answer.status;
      if (answer.location case final location?) {
        response.headers.set(HttpHeaders.locationHeader, location);
      }
      if (answer.body case final body?) _json(response, answer.status, body);
    }
  } catch (error) {
    stderr.writeln('error: ${request.method} ${request.uri.path}: $error');
    _json(response, 500, {'error': 'internal error'});
  } finally {
    await response.close();
  }
}

/// POST /api/act: the player's strategy and situation → aityx → the action.
Future<void> _act(HttpRequest request, _Aityx aityx) async {
  final response = request.response;
  if (aityx.key.isEmpty) {
    return _json(response, 503, {'error': 'aityx is not set up'});
  }
  final Strategy strategy;
  final Map<String, Object?> situation;
  try {
    final body = jsonDecode(await _readBody(request));
    if (body is! Map) throw InvalidRequest('expected an object');
    strategy = aityx.models.strategyFrom(body['strategy']);
    situation = situationFrom(body['situation']);
  } on InvalidRequest catch (error) {
    return _json(response, 400, {'error': error.message});
  } on FormatException {
    return _json(response, 400, {'error': 'invalid JSON'});
  }

  final sent = actRequest(aityx.models, strategy, situation);
  final call = await aityx.client.postUrl(aityx.url.resolve('/v1/systemone'));
  call.headers
    ..set('Authorization', 'Bearer ${aityx.key}')
    ..contentType = ContentType.json;
  call.write(jsonEncode(sent));
  // One deadline for the whole answer, body included; when it runs out
  // the call to aityx is aborted, not left running.
  final stopwatch = Stopwatch()..start();
  final HttpClientResponse answer;
  final String text;
  try {
    (answer, text) = await () async {
      final answer = await call.close();
      return (answer, await answer.transform(utf8.decoder).join());
    }().timeout(_aityxDeadline);
  } on TimeoutException {
    call.abort(TimeoutException('aityx did not answer in time'));
    return _json(response, 504, {'error': 'aityx did not answer in time'});
  }
  stopwatch.stop();
  if (answer.statusCode != 200) {
    // aityx's problem details never include the key. A 422 is most often
    // a custom strategy's mistake: pass its detail on to the app.
    stderr.writeln('aityx: HTTP ${answer.statusCode}: $text');
    return _json(response, 502, {
      'error': 'aityx answered HTTP ${answer.statusCode}${_detail(text)}',
    });
  }
  try {
    final json = jsonDecode(text) as Map<String, Object?>;
    final action = toAction(sent, json);
    _json(
      response,
      200,
      withAityx(
        action,
        sent,
        json,
        text,
        aityx.key,
        tookMs: stopwatch.elapsedMilliseconds,
      ),
    );
  } on FormatException catch (error) {
    stderr.writeln('aityx: $error');
    _json(response, 502, {'error': 'unexpected answer from aityx'});
  } on DecisionFailed catch (error) {
    stderr.writeln('aityx: $error');
    _json(response, 502, {'error': 'aityx could not decide it: $error'});
  }
}

/// aityx's problem details, in a short form for the app: the code, the
/// detail, and the first errors' paths and messages.
String _detail(String text) {
  try {
    final json = jsonDecode(text);
    if (json is! Map) return '';
    final parts = <String>[
      if (json['code'] is String) json['code'] as String,
      if (json['detail'] is String) json['detail'] as String,
    ];
    if (json['errors'] case final List errors) {
      for (final e in errors.take(3)) {
        if (e is Map) parts.add('${e['path']}: ${e['message']}');
      }
    }
    return parts.isEmpty ? '' : ': ${parts.join('; ')}';
  } on FormatException {
    return '';
  }
}

Future<String> _readBody(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
    if (bytes.length > _maxBody) throw InvalidRequest('request too large');
  }
  return utf8.decode(bytes);
}

void _json(HttpResponse response, int status, Object body) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}
