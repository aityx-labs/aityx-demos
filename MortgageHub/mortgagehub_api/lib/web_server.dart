/// The web server `devbox services up` runs: serves the app's release
/// build under /app/ and proxies /api/ (and the bare /) to the API, as
/// nginx does under Docker Compose (docker/nginx.conf). One small native
/// process, instead of Flutter's dev server with its compiler.
library;

import 'dart:async';
import 'dart:io';

/// Content types by extension; anything else is served as bytes.
const _types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
};

/// Headers that belong to one hop, not forwarded through the proxy.
const _hopByHop = {
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};

/// Serves [root] (the app's `build/web`) under /app/ on [host]:[port],
/// and forwards `/api/...` and `/` to [api]. Returns the bound server.
Future<HttpServer> serveWeb({
  required Directory root,
  required String host,
  required int port,
  required Uri api,
  HttpClient? client,
}) async {
  final web = _WebServer(root.absolute, api, client ?? HttpClient());
  final server = await HttpServer.bind(host, port);
  server.listen((request) => unawaited(web.handle(request)));
  return server;
}

class _WebServer {
  _WebServer(this.root, this.api, this.client);

  final Directory root;
  final Uri api;
  final HttpClient client;

  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    try {
      final path = request.uri.path;
      if (path == '/' || path.startsWith('/api/')) {
        await _proxy(request);
      } else if (path == '/app') {
        // The app lives under /app/; relative, so a forwarded port's host
        // is kept.
        response
          ..statusCode = HttpStatus.movedPermanently
          ..headers.set(HttpHeaders.locationHeader, '/app/');
      } else if (path.startsWith('/app/')) {
        if (request.method != 'GET' && request.method != 'HEAD') {
          response.statusCode = HttpStatus.methodNotAllowed;
        } else {
          await _file(request, path.substring('/app/'.length));
        }
      } else {
        response
          ..statusCode = HttpStatus.notFound
          ..headers.contentType = ContentType.text
          ..write('not found');
      }
    } catch (error) {
      stderr.writeln('error: ${request.method} ${request.uri.path}: $error');
      if (!response.headers.persistentConnection ||
          response.contentLength < 0) {
        // Nothing sent yet (the usual case): say so.
        try {
          response
            ..statusCode = HttpStatus.internalServerError
            ..headers.contentType = ContentType.text
            ..write('internal error');
        } catch (_) {}
      }
    } finally {
      await response.close();
    }
  }

  /// The file at [relative] in [root], or index.html for the app's own
  /// routes (what nginx's `try_files $uri $uri/ /app/index.html` does).
  /// Only files inside [root] are served: the path is normalized first.
  Future<void> _file(HttpRequest request, String relative) async {
    final response = request.response;
    var file = _resolve(relative);
    if (file == null || !await file.exists()) file = _resolve('index.html');
    if (file == null || !await file.exists()) {
      response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.text
        ..write('the web build is missing: ${root.path}');
      return;
    }
    final stat = await file.stat();
    final modified = stat.modified.toUtc();
    final since = request.headers.ifModifiedSince;
    // The build's files aren't fingerprinted: always revalidate, so a new
    // build is seen on the next load, but an unchanged file costs 304.
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(modified));
    // The header has whole seconds; the file's time, milliseconds.
    if (since != null &&
        modified.millisecondsSinceEpoch ~/ 1000 <=
            since.millisecondsSinceEpoch ~/ 1000) {
      response.statusCode = HttpStatus.notModified;
      return;
    }
    final dot = file.path.lastIndexOf('.');
    final type = dot < 0 ? null : _types[file.path.substring(dot)];
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      type ?? 'application/octet-stream',
    );
    response.contentLength = stat.size;
    if (request.method == 'HEAD') return;
    await response.addStream(file.openRead());
  }

  /// [relative] as a file under [root], or null when it escapes it (`..`,
  /// an absolute path) or names the root itself.
  File? _resolve(String relative) {
    final segments = <String>[];
    for (final segment in Uri.decodeComponent(relative).split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') return null;
      segments.add(segment);
    }
    if (segments.isEmpty) return File('${root.path}/index.html');
    final file = File('${root.path}/${segments.join('/')}');
    if (!file.absolute.path.startsWith('${root.path}/')) return null;
    return file;
  }

  /// [request] replayed against the API: same method, path and query,
  /// the end-to-end headers and the body; the answer streamed back with
  /// its status and headers. 502 when the API doesn't answer.
  Future<void> _proxy(HttpRequest request) async {
    final response = request.response;
    final HttpClientRequest upstream;
    try {
      upstream = await client.openUrl(
        request.method,
        api.replace(path: request.uri.path, query: request.uri.query),
      );
    } on SocketException catch (error) {
      stderr.writeln('api unreachable: $error');
      response
        ..statusCode = HttpStatus.badGateway
        ..headers.contentType = ContentType.json
        ..write('{"error":"the API is not answering"}');
      return;
    }
    request.headers.forEach((name, values) {
      if (_hopByHop.contains(name) || name == HttpHeaders.hostHeader) return;
      for (final value in values) {
        upstream.headers.add(name, value);
      }
    });
    upstream.followRedirects = false;
    upstream.contentLength = request.contentLength;
    await upstream.addStream(request);
    final HttpClientResponse answer;
    try {
      answer = await upstream.close();
    } on SocketException catch (error) {
      stderr.writeln('api unreachable: $error');
      response
        ..statusCode = HttpStatus.badGateway
        ..headers.contentType = ContentType.json
        ..write('{"error":"the API is not answering"}');
      return;
    }
    response.statusCode = answer.statusCode;
    answer.headers.forEach((name, values) {
      if (_hopByHop.contains(name)) return;
      response.headers.set(name, values);
    });
    await response.addStream(answer);
  }
}
