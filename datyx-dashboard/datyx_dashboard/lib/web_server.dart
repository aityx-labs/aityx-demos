/// A small web server for the dashboard's release build, what
/// `devbox services up` runs (scripts/flutter-web.sh, WEB_MODE=release): the
/// build under /app/ (unknown paths fall back to index.html), /api/ and /q/
/// proxied to the API, and / redirected to /app/. The same shape as nginx
/// under Docker Compose (docker/nginx.conf). Only dart:io, so it compiles
/// to a native executable without extra packages (bin/web_server.dart).
library;

import 'dart:io';

/// Serves [root] on [host]:[port], proxying the API prefixes to [api].
Future<HttpServer> serveWeb({
  required Directory root,
  required String host,
  required int port,
  required Uri api,
  List<String> proxied = const ['/api/', '/q/'],
}) async {
  final client = HttpClient();
  final server = await HttpServer.bind(host, port);
  server.listen((request) async {
    try {
      final path = request.uri.path;
      if (path == '/' || path == '/app') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/app/');
        await request.response.close();
      } else if (proxied.any(path.startsWith)) {
        await _proxy(client, request, api);
      } else if (path.startsWith('/app/')) {
        await _serveFile(root, path.substring('/app/'.length), request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e) {
      stderr.writeln('web_server: ${request.method} ${request.uri}: $e');
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } catch (_) {}
    }
  });
  return server;
}

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'css': 'text/css',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'png': 'image/png',
  'ico': 'image/x-icon',
  'svg': 'image/svg+xml',
  'woff': 'font/woff',
  'woff2': 'font/woff2',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'txt': 'text/plain',
};

Future<void> _serveFile(Directory root, String relative, HttpRequest request) async {
  final rootPath = root.absolute.path;
  var file = File('$rootPath/${relative.isEmpty ? 'index.html' : relative}');
  // No escaping the build folder.
  if (!file.absolute.path.startsWith(rootPath)) {
    request.response.statusCode = HttpStatus.forbidden;
    await request.response.close();
    return;
  }
  if (!await file.exists()) file = File('$rootPath/index.html');
  final ext = file.path.split('.').last.toLowerCase();
  final response = request.response;
  response.headers.contentType = ContentType.parse(_types[ext] ?? 'application/octet-stream');
  if (ext == 'html') response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  await response.addStream(file.openRead());
  await response.close();
}

Future<void> _proxy(HttpClient client, HttpRequest request, Uri api) async {
  final target = api.replace(path: request.uri.path, query: request.uri.hasQuery ? request.uri.query : null);
  final upstream = await client.openUrl(request.method, target);
  request.headers.forEach((name, values) {
    if (name.toLowerCase() == HttpHeaders.hostHeader) return;
    for (final value in values) {
      upstream.headers.add(name, value);
    }
  });
  upstream.headers.set(HttpHeaders.hostHeader, '${target.host}:${target.port}');
  await upstream.addStream(request);
  final answer = await upstream.close();
  final response = request.response;
  response.statusCode = answer.statusCode;
  answer.headers.forEach((name, values) {
    if (name.toLowerCase() == HttpHeaders.transferEncodingHeader) return;
    for (final value in values) {
      response.headers.add(name, value);
    }
  });
  await response.addStream(answer);
  await response.close();
}
