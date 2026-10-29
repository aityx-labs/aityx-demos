/// The index of the aityx demos: serves www/ (the page) and says which
/// demos are up. Plain Dart, no packages, so `dart bin/server.dart` runs
/// it. The datyx group has an index of its own (datyx-index/).
///
///   GET /, /app/        www/index.html (the page; /app/ so start-all.sh
///                       checks it like a demo)
///   GET /<file>         a file in www/
///   GET /api/health     {"ok": true}
///   GET /api/demos      every folder beside this one with a
///                       process-compose.yaml in this index's group (its
///                       group.id.txt says INDEX_GROUP, aityx): its web and
///                       API ports (the defaults in that file) and whether
///                       its web app and API answer right now, and whether
///                       the API has its aityx key; for scripts
///   GET /api/aityx      whether an aityx key is set (AITYX_API_KEY here,
///                       else in the repo's .env) and whether aityx accepts
///                       it: {"key": bool, "source": ..., "ok": bool,
///                       "detail": ...}; never the key. The page's banner
///                       and status light read it
///   GET /api/group      {"group": "aityx"}: this index's group
///                       (INDEX_GROUP); every card on the page is in it
///
/// Settings: INDEX_PORT (default 8800), INDEX_BIND_HOST (127.0.0.1),
/// INDEX_GROUP (aityx).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _here = Directory.fromUri(Platform.script.resolve('..'));
final _www = Directory('${_here.path}/www');
final _root = Directory('${_here.path}/..');
final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['INDEX_PORT'] ?? '8800');
  final host = env['INDEX_BIND_HOST'] ?? '127.0.0.1';
  final server = await HttpServer.bind(host, port);
  stdout.writeln('index on http://$host:$port/');
  await for (final request in server) {
    unawaited(_handle(request));
  }
}

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  try {
    final path = request.uri.path;
    if (request.method != 'GET' && request.method != 'HEAD') {
      _json(response, 405, {'error': 'method not allowed'});
    } else if (path == '/api/health') {
      _json(response, 200, {'ok': true});
    } else if (path == '/api/demos') {
      _json(response, 200, {'demos': await _demos()});
    } else if (path == '/api/aityx') {
      _json(response, 200, await _aityx());
    } else if (path == '/api/group') {
      _json(response, 200, {'group': _group});
    } else {
      await _file(response, path);
    }
  } catch (error) {
    stderr.writeln('error: ${request.method} ${request.uri.path}: $error');
    _json(response, 500, {'error': 'internal error'});
  } finally {
    await response.close();
  }
}

const _types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
};

Future<void> _file(HttpResponse response, String path) async {
  var name = path == '/' || path == '/app' || path == '/app/'
      ? 'index.html'
      : path.startsWith('/app/')
      ? path.substring('/app/'.length)
      : path.substring(1);
  if (name.isEmpty) name = 'index.html';
  // Only files right in www/: no dots in the name's directory part.
  if (name.contains('..') || name.contains('/')) {
    return _json(response, 404, {'error': 'not found'});
  }
  final file = File('${_www.path}/$name');
  if (!await file.exists()) return _json(response, 404, {'error': 'not found'});
  final dot = name.lastIndexOf('.');
  final type = dot < 0 ? null : _types[name.substring(dot)];
  response
    ..statusCode = 200
    ..headers.set(
      HttpHeaders.contentTypeHeader,
      type ?? 'application/octet-stream',
    )
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  await response.addStream(file.openRead());
}

void _json(HttpResponse response, int status, Object body) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
}

final _group = Platform.environment['INDEX_GROUP'] ?? 'aityx';

/// Every demo folder of this index's group, with its ports and whether it answers.
Future<List<Map<String, Object?>>> _demos() async {
  final folders = <Directory>[];
  await for (final entry in _root.list()) {
    if (entry is Directory &&
        _name(entry) != _name(_here) &&
        await File('${entry.path}/process-compose.yaml').exists() &&
        await _groupOf(entry) == _group) {
      folders.add(entry);
    }
  }
  folders.sort((a, b) => a.path.compareTo(b.path));
  return Future.wait(folders.map(_demo));
}

final _webPort = RegExp(r'\$\{FLUTTER_WEB_PORT:-(\d+)\}');
final _apiPort = RegExp(r'\$\{API_PORT:-(\d+)\}');

/// The folder's group, from its group.id.txt (empty without one).
Future<String> _groupOf(Directory dir) async {
  final file = File('${dir.path}/group.id.txt');
  return await file.exists() ? (await file.readAsString()).trim() : '';
}

/// The folder's name.
String _name(Directory dir) =>
    dir.uri.pathSegments.where((s) => s.isNotEmpty).last;

Future<Map<String, Object?>> _demo(Directory dir) async {
  final name = _name(dir);
  final compose = await File('${dir.path}/process-compose.yaml').readAsString();
  final web = int.tryParse(_webPort.firstMatch(compose)?.group(1) ?? '');
  final api = int.tryParse(_apiPort.firstMatch(compose)?.group(1) ?? '');
  var up = false;
  bool? aityx;
  if (web != null) {
    up = await _answers('http://127.0.0.1:$web/app/') != null;
    // The API through the web app's origin, as the app itself reaches it.
    final health = await _answers('http://127.0.0.1:$web/api/health');
    if (health != null) {
      try {
        final json = jsonDecode(health);
        if (json is Map && json['aityx'] is bool) aityx = json['aityx'] as bool;
      } on FormatException {
        // Not JSON: no API behind it.
      }
    }
  }
  return {'folder': name, 'web': web, 'api': api, 'up': up, 'aityx': aityx};
}

/// The body of a 2xx answer within 2 s, else null.
Future<String?> _answers(String url) async {
  try {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 2));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 2));
    return response.statusCode >= 200 && response.statusCode < 300
        ? body
        : null;
  } catch (_) {
    return null;
  }
}

/// The aityx check, kept for a minute so the page's polling doesn't call
/// aityx each time; requests that arrive while it runs share it.
Future<Map<String, Object?>>? _aityxCheck;
DateTime _aityxAt = DateTime(0);

Future<Map<String, Object?>> _aityx() {
  final check = _aityxCheck;
  if (check != null &&
      DateTime.now().difference(_aityxAt) < const Duration(minutes: 1)) {
    return check;
  }
  _aityxAt = DateTime.now();
  return _aityxCheck = _checkAityx();
}

/// The key and URL, each as the demos' scripts read it: from the
/// environment (start-all.sh exports them), else from the repo's .env,
/// which every demo's .env links to.
Future<(String, String, String)?> _aityxSettings() async {
  final env = Platform.environment;
  final file = File('${_root.path}/.env');
  final lines = await file.exists() ? await file.readAsLines() : <String>[];
  String fromFile(String name) => lines
      .where((l) => l.startsWith('$name='))
      .map((l) => l.substring(name.length + 1).trim())
      .fold('', (_, v) => v);
  final envKey = env['AITYX_API_KEY'] ?? '';
  final key = envKey.isNotEmpty ? envKey : fromFile('AITYX_API_KEY');
  if (key.isEmpty) return null;
  final envUrl = env['AITYX_URL'] ?? '';
  final url = envUrl.isNotEmpty ? envUrl : fromFile('AITYX_URL');
  return (key, url, envKey.isNotEmpty ? 'environment' : '.env');
}

/// Posts an empty request to /v1/systemone: aityx checks the key first, so
/// a working key gets 400 "invalid_request" (state is required) and a bad
/// one 401, without running any model.
Future<Map<String, Object?>> _checkAityx() async {
  final settings = await _aityxSettings();
  if (settings == null) {
    return {'key': false, 'ok': false, 'detail': 'AITYX_API_KEY is not set'};
  }
  final (key, setUrl, source) = settings;
  final base = Uri.tryParse(setUrl.isEmpty ? 'https://api.aityx.ai' : setUrl);
  final result = <String, Object?>{'key': true, 'source': source, 'ok': false};
  if (base == null || base.scheme != 'https' || base.host.isEmpty) {
    return result..['detail'] = 'AITYX_URL must be an https URL';
  }
  result['url'] = base.origin;
  try {
    final call = await _client.postUrl(base.resolve('/v1/systemone'));
    call.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
      ..contentType = ContentType.json;
    call.write('{}');
    final answer = await call.close().timeout(const Duration(seconds: 10));
    final text = await answer
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      json = null;
    }
    final code = json is Map ? json['code'] : null;
    if (answer.statusCode == 400 && code == 'invalid_request') {
      return result
        ..['ok'] = true
        ..['detail'] = 'aityx accepts the key';
    }
    final detail = json is Map ? json['detail'] : null;
    return result
      ..['detail'] =
          'aityx answered HTTP ${answer.statusCode}'
          '${detail is String ? ': $detail' : ''}';
  } catch (error) {
    return result..['detail'] = 'aityx did not answer: ${error.runtimeType}';
  }
}
