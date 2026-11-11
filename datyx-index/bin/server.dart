/// The index of the datyx group: serves www/ (the page) and says which
/// of its systems are up. Plain Dart, no packages, so `dart bin/server.dart`
/// runs it. The aityx demos have their own index (Index/).
///
///   GET /, /app/        www/index.html (the page; /app/ so start-all.sh
///                       checks it like a demo)
///   GET /<file>         a file in www/
///   GET /api/health     {"ok": true}
///   GET /api/demos      every folder beside this one with a
///                       process-compose.yaml whose group.id.txt says
///                       INDEX_GROUP (datyx): its web and API ports (the
///                       defaults in that file) and whether its web app,
///                       or its API when it has no web app, answers right
///                       now; for scripts. With INDEX_DEMOS set, exactly
///                       the folders it names instead
///
/// Settings: INDEX_PORT (default 9800), INDEX_BIND_HOST (127.0.0.1),
/// INDEX_GROUP (datyx), INDEX_DEMOS (unset): for a server with no folders
/// beside it (a container), a comma-separated list of <folder>=<URL to
/// check>, e.g. datyx=http://datyx-api:9900/api/health; /api/demos then
/// lists those folders, each with its URL and whether that answers 2xx
/// or 3xx within 2 s.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _here = Directory.fromUri(Platform.script.resolve('..'));
final _www = Directory('${_here.path}/www');
final _root = Directory('${_here.path}/..');
final _group = Platform.environment['INDEX_GROUP'] ?? 'datyx';
final _client = HttpClient()..connectionTimeout = const Duration(seconds: 2);

/// INDEX_DEMOS, folder by folder: the URL that says whether it's up.
/// Empty when it's unset: the folders beside this one are listed then.
final Map<String, String> _listed = _parseDemos(
  Platform.environment['INDEX_DEMOS'] ?? '',
);

Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['INDEX_PORT'] ?? '9800');
  final host = env['INDEX_BIND_HOST'] ?? '127.0.0.1';
  // A malformed INDEX_DEMOS stops the server at start, not at the first
  // /api/demos.
  try {
    if (_listed.isNotEmpty) {
      stdout.writeln('listing INDEX_DEMOS: ${_listed.keys.join(', ')}');
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(64);
  }
  final server = await HttpServer.bind(host, port);
  stdout.writeln('datyx index on http://$host:$port/');
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

/// Every folder of the group, with its ports and whether it answers; or,
/// with INDEX_DEMOS set, the folders it names, with their URLs.
Future<List<Map<String, Object?>>> _demos() async {
  if (_listed.isNotEmpty) {
    final names = _listed.keys.toList()..sort();
    return Future.wait(
      names.map((name) async {
        final url = _listed[name]!;
        return {
          'folder': name,
          'url': url,
          'up': await _answers(url, below: 400),
        };
      }),
    );
  }
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
  // The web app, or, for a folder without one (the datyx API), the API.
  final up = web != null
      ? await _answers('http://127.0.0.1:$web/app/')
      : api != null && await _answers('http://127.0.0.1:$api/api/health');
  return {'folder': name, 'web': web, 'api': api, 'up': up};
}

/// Whether the URL answers within 2 s with a status from 200 to [below]:
/// 2xx for the folders beside this one, 2xx or 3xx (400) for INDEX_DEMOS.
Future<bool> _answers(String url, {int below = 300}) async {
  try {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close().timeout(const Duration(seconds: 2));
    await response.drain<void>().timeout(const Duration(seconds: 2));
    return response.statusCode >= 200 && response.statusCode < below;
  } catch (_) {
    return false;
  }
}

/// INDEX_DEMOS's <folder>=<URL> pairs, comma-separated. A pair without a
/// folder or an http(s) URL is a FormatException.
Map<String, String> _parseDemos(String setting) {
  final demos = <String, String>{};
  for (final pair in setting.split(',')) {
    if (pair.trim().isEmpty) continue;
    final at = pair.indexOf('=');
    final folder = at < 0 ? '' : pair.substring(0, at).trim();
    final url = at < 0 ? '' : pair.substring(at + 1).trim();
    final scheme = Uri.tryParse(url)?.scheme;
    if (folder.isEmpty || (scheme != 'http' && scheme != 'https')) {
      throw FormatException(
        'INDEX_DEMOS: "$pair" is not <folder>=<http(s) URL to check>',
      );
    }
    demos[folder] = url;
  }
  return demos;
}
