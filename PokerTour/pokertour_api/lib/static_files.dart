/// Serves the app's release web build under /app/, as HealthHub's web
/// server does: a file inside the build, else index.html for the app's
/// own routes; only files inside the root.
library;

import 'dart:io';

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

class StaticFiles {
  StaticFiles(Directory root) : root = root.absolute;

  final Directory root;

  /// Writes the file at [relative] (under /app/) to [request]'s response.
  Future<void> serve(HttpRequest request, String relative) async {
    final response = request.response;
    var file = resolve(relative);
    if (file == null || !await file.exists()) file = resolve('index.html');
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
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(modified));
    if (since != null && modified.millisecondsSinceEpoch ~/ 1000 <= since.millisecondsSinceEpoch ~/ 1000) {
      response.statusCode = HttpStatus.notModified;
      return;
    }
    final dot = file.path.lastIndexOf('.');
    final type = dot < 0 ? null : _types[file.path.substring(dot)];
    response.headers.set(HttpHeaders.contentTypeHeader, type ?? 'application/octet-stream');
    response.contentLength = stat.size;
    if (request.method == 'HEAD') return;
    await response.addStream(file.openRead());
  }

  /// [relative] as a file under [root], or null when it escapes it.
  File? resolve(String relative) {
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
}
