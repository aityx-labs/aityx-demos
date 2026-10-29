/// Mortgage Hub's API. Holds the aityx.ai key, which must never reach the
/// app, and answers:
///
///   GET  /api/health           {"ok": true, "aityx": true when the key is set}
///   POST /api/proposals/check  a ProposalRequest's JSON → the regulatory
///                              check (see lib/proposal_check.dart), with
///                              the body sent to aityx and its answer under
///                              "aityx" (the key, a header, is in neither)
///
/// Settings, from the environment (scripts/api.sh loads .env):
///   AITYX_API_KEY   the key (secret)
///   AITYX_URL       aityx's base URL (default https://api.aityx.ai)
///   API_PORT        the port (default 8881)
///   MORTGAGEHUB_BIND_HOST  the address to bind (default 127.0.0.1)
///   ALLOWED_ORIGINS comma-separated origins allowed by CORS
///                   (default http://localhost:8880)
///   ASSUMED_RATE    the annual rate in % for payment estimates (default 6.5)
///
/// `server healthcheck` instead asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mortgagehub_api/proposal_check.dart';

const _maxBody = 64 * 1024;

Future<void> main(List<String> args) async {
  if (args.firstOrNull == 'healthcheck') exit(await _healthcheck());
  final env = Platform.environment;
  final key = env['AITYX_API_KEY'] ?? '';
  final aityx = Uri.parse(
    (env['AITYX_URL'] ?? '').isEmpty
        ? 'https://api.aityx.ai'
        : env['AITYX_URL']!,
  );
  if (aityx.scheme != 'https') {
    stderr.writeln('error: AITYX_URL must be https');
    exit(1);
  }
  final port = int.parse(env['API_PORT'] ?? '8881');
  final host = env['MORTGAGEHUB_BIND_HOST'] ?? '127.0.0.1';
  final origins = (env['ALLOWED_ORIGINS'] ?? 'http://localhost:8880')
      .split(',')
      .map((origin) => origin.trim())
      .where((origin) => origin.isNotEmpty)
      .toSet();
  final assumedRate = double.parse(env['ASSUMED_RATE'] ?? '6.5');
  final modelFile = File.fromUri(
    Platform.script.resolve('../models/proposal-check.json'),
  );
  final model = jsonDecode(await modelFile.readAsString());
  if (key.isEmpty) stderr.writeln('warning: AITYX_API_KEY is not set');

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final server = await HttpServer.bind(host, port);
  stdout.writeln(
    'mortgagehub_api on http://$host:$port (aityx: ${aityx.host})',
  );

  await for (final request in server) {
    unawaited(
      _handle(request, key, aityx, origins, assumedRate, model, client),
    );
  }
}

/// 0 when the server on this machine answers /api/health with ok, else 1.
Future<int> _healthcheck() async {
  final port = int.parse(Platform.environment['API_PORT'] ?? '8881');
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
  String key,
  Uri aityx,
  Set<String> origins,
  double assumedRate,
  Object? model,
  HttpClient client,
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
    final path = request.uri.path;
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
    } else if (path == '/' && request.method == 'GET') {
      // The site root, which the dev server proxies here
      // (scripts/flutter-web.sh), so a forwarded port's bare URL opens the
      // app. Relative, so it keeps the forwarded host and port.
      response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, '/app/');
    } else if (path == '/api/health' && request.method == 'GET') {
      _json(response, 200, {'ok': true, 'aityx': key.isNotEmpty});
    } else if (path == '/api/proposals/check' && request.method == 'POST') {
      await _check(request, key, aityx, assumedRate, model, client);
    } else {
      _json(response, 404, {'error': 'not found'});
    }
  } catch (error) {
    stderr.writeln('error: ${request.method} ${request.uri.path}: $error');
    _json(response, 500, {'error': 'internal error'});
  } finally {
    await response.close();
  }
}

Future<void> _check(
  HttpRequest request,
  String key,
  Uri aityx,
  double assumedRate,
  Object? model,
  HttpClient client,
) async {
  final response = request.response;
  if (key.isEmpty) {
    return _json(response, 503, {'error': 'aityx is not set up'});
  }
  final Map<String, Object?> state;
  try {
    final body = await _readBody(request);
    final json = jsonDecode(body);
    if (json is! Map<String, Object?>) {
      throw InvalidRequest('expected an object');
    }
    state = toState(json, assumedRate);
  } on InvalidRequest catch (error) {
    return _json(response, 400, {'error': error.message});
  } on FormatException {
    return _json(response, 400, {'error': 'invalid JSON'});
  }

  final sent = {'decision': model, 'state': state};
  final call = await client.postUrl(aityx.resolve('/v1/systemone'));
  call.headers
    ..set('Authorization', 'Bearer $key')
    ..contentType = ContentType.json;
  call.write(jsonEncode(sent));
  final answer = await call.close().timeout(const Duration(seconds: 60));
  final text = await answer.transform(utf8.decoder).join();
  if (answer.statusCode != 200) {
    // aityx's problem details never include the key.
    stderr.writeln('aityx: HTTP ${answer.statusCode}: $text');
    return _json(response, 502, {
      'error': 'aityx answered HTTP ${answer.statusCode}',
    });
  }
  try {
    final answers = jsonDecode(text) as Map<String, Object?>;
    final result = toResult(answers, assumedRate);
    _json(response, 200, withAityx(result, sent, answers, text, key));
  } on FormatException catch (error) {
    stderr.writeln('$error');
    _json(response, 502, {'error': 'unexpected answer from aityx'});
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
