/// Cellfie's API. Holds the aityx.ai key, which must never reach the
/// app, and answers:
///
///   GET  /             302 to /app/, so a forwarded port's bare URL opens
///                      the app (the dev server proxies the root here)
///   GET  /api/health   {"ok": true, "aityx": true when the key is set}
///   POST /api/step     {"generation": 12, "situations": [...],
///                      "clusters": [...]} → the next generation (see
///                      lib/life.dart): the Life model on aityx's
///                      /v1/systemone decides the fate of every situation
///                      on the board and names the patterns among its
///                      clusters; with the body sent to aityx and its
///                      answer under "aityx" (the key, a header, is in
///                      neither); 504 after 30 s
///
/// Settings, from the environment (scripts/api.sh loads .env):
///   AITYX_API_KEY      the key (secret)
///   AITYX_URL          aityx's base URL (default https://api.aityx.ai)
///   API_PORT           the port (default 8931)
///   CELLFIE_BIND_HOST  the address to bind (default 127.0.0.1)
///   ALLOWED_ORIGINS    comma-separated origins allowed by CORS
///                      (default http://localhost:8930)
///
/// `server healthcheck` instead asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cellfie_api/life.dart';
import 'package:cellfie_api/routes.dart';

/// Room for the board's 18 situations and its clusters' shapes.
const _maxBody = 64 * 1024;

/// How long a generation waits for aityx; docker/nginx.conf's proxy waits
/// longer.
const _aityxDeadline = Duration(seconds: 30);

/// What a generation needs: the key, where aityx is, the model and a
/// client.
class _Aityx {
  _Aityx(this.key, this.url, this.model);

  final String key;
  final Uri url;
  final Map<String, Object?> model;
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
  final port = int.parse(env['API_PORT'] ?? '8931');
  final host = env['CELLFIE_BIND_HOST'] ?? '127.0.0.1';
  final origins = (env['ALLOWED_ORIGINS'] ?? 'http://localhost:8930')
      .split(',')
      .map((origin) => origin.trim())
      .where((origin) => origin.isNotEmpty)
      .toSet();
  final modelFile = File.fromUri(
    Platform.script.resolve('../models/life.json'),
  );
  final model =
      jsonDecode(await modelFile.readAsString()) as Map<String, Object?>;
  if (key.isEmpty) stderr.writeln('warning: AITYX_API_KEY is not set');

  final aityx = _Aityx(key, url, model);
  final server = await HttpServer.bind(host, port);
  stdout.writeln('cellfie_api on http://$host:$port (aityx: ${url.host})');

  await for (final request in server) {
    unawaited(_handle(request, origins, aityx));
  }
}

/// 0 when the server on this machine answers /api/health with ok, else 1.
Future<int> _healthcheck() async {
  final port = int.parse(Platform.environment['API_PORT'] ?? '8931');
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
    if (request.method == 'POST' && request.uri.path == '/api/step') {
      await _step(request, aityx);
    } else {
      final answer = route(
        request.method,
        request.uri.path,
        aityx: aityx.key.isNotEmpty,
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

/// POST /api/step: the board's situations → aityx → the next generation.
Future<void> _step(HttpRequest request, _Aityx aityx) async {
  final response = request.response;
  if (aityx.key.isEmpty) {
    return _json(response, 503, {'error': 'aityx is not set up'});
  }
  final Map<String, Object?> state;
  try {
    state = stateFrom(jsonDecode(await _readBody(request)));
  } on InvalidRequest catch (error) {
    return _json(response, 400, {'error': error.message});
  } on FormatException {
    return _json(response, 400, {'error': 'invalid JSON'});
  }

  final sent = generationRequest(aityx.model, state);
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
    // aityx's problem details never include the key.
    stderr.writeln('aityx: HTTP ${answer.statusCode}: $text');
    return _json(response, 502, {
      'error': 'aityx answered HTTP ${answer.statusCode}',
    });
  }
  try {
    final json = jsonDecode(text) as Map<String, Object?>;
    final generation = toGeneration(sent, json);
    _json(
      response,
      200,
      withAityx(
        generation,
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
  } on GenerationFailed catch (error) {
    stderr.writeln('aityx: $error');
    _json(response, 502, {'error': 'aityx could not decide it: $error'});
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
