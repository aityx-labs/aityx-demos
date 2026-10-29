/// RoboRules' API. Holds the aityx.ai key, which must never reach the app,
/// and plays battles on aityx:
///
///   GET  /                  302 to /app/, so a forwarded port's bare URL
///                           opens the app (the dev server proxies it here)
///   GET  /api/health        {"ok": true, "aityx": true when the key is set}
///   POST /api/battle/turns  {"robots": [robot models], "world": {...},
///                           "turns": n, "explain": bool} → {"frames": [the
///                           world after each turn]}, with the aityx call
///                           under "aityx" when explain is true
///   POST /api/battle/score  {"results": [{id, died, damage}]} → {"scores",
///                           "winner", "aityx"}
///
/// The battle's model is models/world.json with each robot's brain added
/// (lib/battle.dart); the scoring is models/scoring.json.
///
/// Settings, from the environment (scripts/api.sh loads .env):
///   AITYX_API_KEY         the key (secret)
///   AITYX_URL             aityx's base URL (default https://api.aityx.ai)
///   API_PORT              the port (default 8921)
///   ROBORULES_BIND_HOST   the address to bind (default 127.0.0.1)
///   ALLOWED_ORIGINS       comma-separated origins allowed by CORS
///                         (default http://localhost:8920)
///
/// `server healthcheck` instead asks a running server's /api/health on
/// 127.0.0.1:API_PORT and exits 0 when it answers ok: the Docker health
/// check, since the image has no shell or curl.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:roborules_api/battle.dart';
import 'package:roborules_api/routes.dart';

/// Robot models are small; ten of them and a world fit well under this.
const _maxBody = 512 * 1024;

/// How long a call waits for aityx; docker/nginx.conf's proxy waits longer.
const _aityxDeadline = Duration(seconds: 90);

/// What a call to aityx needs: the key, where aityx is, the models and a
/// client.
class _Aityx {
  _Aityx(this.key, this.url, this.world, this.scoring);

  final String key;
  final Uri url;
  final Map<String, Object?> world;
  final Map<String, Object?> scoring;
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
  final port = int.parse(env['API_PORT'] ?? '8921');
  final host = env['ROBORULES_BIND_HOST'] ?? '127.0.0.1';
  final origins = (env['ALLOWED_ORIGINS'] ?? 'http://localhost:8920')
      .split(',')
      .map((origin) => origin.trim())
      .where((origin) => origin.isNotEmpty)
      .toSet();
  Future<Map<String, Object?>> model(String name) async => jsonDecode(
    await File.fromUri(Platform.script.resolve('../models/$name'))
        .readAsString(),
  ) as Map<String, Object?>;
  final aityx = _Aityx(
    key,
    url,
    await model('world.json'),
    await model('scoring.json'),
  );
  if (key.isEmpty) stderr.writeln('warning: AITYX_API_KEY is not set');

  final server = await HttpServer.bind(host, port);
  stdout.writeln('roborules_api on http://$host:$port (aityx: ${url.host})');

  await for (final request in server) {
    unawaited(_handle(request, origins, aityx));
  }
}

/// 0 when the server on this machine answers /api/health with ok, else 1.
Future<int> _healthcheck() async {
  final port = int.parse(Platform.environment['API_PORT'] ?? '8921');
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
    final path = request.uri.path;
    final isBattleCall =
        request.method == 'POST' &&
        (path == '/api/battle/turns' || path == '/api/battle/score');
    if (isBattleCall &&
        origin != null &&
        !origins.contains(origin) &&
        request.headers.value('sec-fetch-site') != 'same-origin') {
      _json(response, 403, {'error': 'origin not allowed'});
      return;
    }
    if (request.method == 'POST' && path == '/api/battle/turns') {
      await _post(request, aityx, _turns);
    } else if (request.method == 'POST' && path == '/api/battle/score') {
      await _post(request, aityx, _score);
    } else {
      final answer = route(request.method, path, aityx: aityx.key.isNotEmpty);
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

/// Reads the body, turns it into the aityx request with [build], calls
/// aityx and answers with what [build]'s reader makes of the answer.
Future<void> _post(
  HttpRequest request,
  _Aityx aityx,
  _Call Function(Map<String, Object?> body, _Aityx aityx) build,
) async {
  final response = request.response;
  if (request.headers.contentType?.mimeType != 'application/json') {
    return _json(response, 415, {'error': 'expected application/json'});
  }
  if (aityx.key.isEmpty) {
    return _json(response, 503, {'error': 'aityx is not set up'});
  }
  final _Call call;
  try {
    final body = jsonDecode(await _readBody(request));
    if (body is! Map<String, Object?>) {
      throw InvalidBattle('expected an object');
    }
    call = build(body, aityx);
  } on InvalidBattle catch (error) {
    return _json(response, 400, {'error': error.message});
  } on FormatException {
    return _json(response, 400, {'error': 'invalid JSON'});
  }

  final outgoing = await aityx.client.postUrl(
    aityx.url.resolve('/v1/systemone'),
  );
  outgoing.headers
    ..set('Authorization', 'Bearer ${aityx.key}')
    ..contentType = ContentType.json;
  outgoing.write(jsonEncode(call.sent));
  // One deadline for the whole answer, body included; when it runs out the
  // call to aityx is aborted, not left running.
  final HttpClientResponse answer;
  final String text;
  try {
    (answer, text) = await () async {
      final answer = await outgoing.close();
      return (answer, await answer.transform(utf8.decoder).join());
    }().timeout(_aityxDeadline);
  } on TimeoutException {
    outgoing.abort(TimeoutException('aityx did not answer in time'));
    return _json(response, 504, {'error': 'aityx did not answer in time'});
  }
  if (answer.statusCode != 200) {
    // aityx's problem details never include the key; they say what in a
    // robot's rules it couldn't run, which the app shows.
    stderr.writeln('aityx: HTTP ${answer.statusCode}: $text');
    final problem = _problem(text);
    return _json(response, 502, {
      'error': 'aityx answered HTTP ${answer.statusCode}',
      'detail': ?problem,
    });
  }
  try {
    final json = jsonDecode(text) as Map<String, Object?>;
    final out = call.read(json);
    final explain = call.explain && !text.contains(aityx.key);
    _json(response, 200, {
      ...out,
      if (explain) 'aityx': {'request': call.sent, 'response': json},
    });
  } on InvalidBattle catch (error) {
    _json(response, 502, {'error': error.message});
  } on FormatException catch (error) {
    stderr.writeln('aityx: $error');
    _json(response, 502, {'error': 'unexpected answer from aityx'});
  }
}

/// aityx's explanation of a failed call: its detail and errors.
String? _problem(String text) {
  try {
    final json = jsonDecode(text);
    if (json is! Map) return null;
    final errors = [
      for (final e in (json['errors'] as List?) ?? const [])
        if (e is Map && e['message'] is String) e['message'] as String,
    ];
    return [if (json['detail'] is String) json['detail'], ...errors].join(' ');
  } on FormatException {
    return null;
  }
}

/// A call to aityx: what to send, how to read the answer, and whether to
/// include the call in the API's answer.
class _Call {
  _Call(this.sent, this.read, {this.explain = false});

  final Map<String, Object?> sent;
  final Map<String, Object?> Function(Map<String, Object?> answer) read;
  final bool explain;
}

_Call _turns(Map<String, Object?> body, _Aityx aityx) {
  final robots = body['robots'];
  if (robots is! List) throw InvalidBattle('robots is required');
  final turns = body['turns'];
  return _Call(
    battleRequest(
      aityx.world,
      robots,
      body['world'],
      turns is int ? turns : 10,
    ),
    (answer) => {'frames': framesOf(answer)},
    explain: body['explain'] == true,
  );
}

_Call _score(Map<String, Object?> body, _Aityx aityx) {
  final results = body['results'];
  if (results is! List || results.isEmpty) {
    throw InvalidBattle('results is required');
  }
  return _Call(
    {
      'decision': aityx.scoring,
      'state': {'results': results},
    },
    (answer) {
      final answers = answer['answers'] as Map?;
      final scores = (answers?['scores'] as Map?)?['value'];
      if (scores is! List) throw InvalidBattle('aityx answered without scores');
      return {
        'scores': scores,
        'winner': (answers?['winner'] as Map?)?['value'],
      };
    },
    explain: true,
  );
}

Future<String> _readBody(HttpRequest request) async {
  final bytes = <int>[];
  await for (final chunk in request) {
    bytes.addAll(chunk);
    if (bytes.length > _maxBody) throw InvalidBattle('request too large');
  }
  return utf8.decode(bytes);
}

void _json(HttpResponse response, int status, Object body) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}
