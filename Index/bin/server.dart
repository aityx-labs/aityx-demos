/// The aityx demos on one origin, all under /demos/: the index page
/// (www/), each demo's release web build under its own path, and, in dev
/// mode, a proxy to aityx that adds the key this server holds. One
/// origin, so a key the user sets once on the index page (the browser's
/// storage) is reused by every demo. Everything under one prefix, so the
/// same files, copied as they are, serve from a static host's /demos/
/// (the aityx website). Plain Dart, no packages, so `dart bin/server.dart`
/// runs it. The datyx group has an index of its own (datyx-index/).
///
///   GET /, /demos         301 to /demos/
///   GET /app/, /<slug>/... 301 to /demos/ and /demos/<slug>/...: the paths
///                         before everything moved under /demos/, so old
///                         links and bookmarks still open (the fragment,
///                         /#aityx-key, survives a redirect)
///   GET /demos/           www/index.html (the page)
///   GET /demos/<file>     a file in www/
///   GET /demos/<slug>/... a demo's release web build: every folder beside
///                         this one in this index's group (its group.id.txt
///                         says INDEX_GROUP, aityx) with a <slug>_app/
///                         package, the slug being the folder's name in
///                         lower case: /demos/mortgagehub/ is
///                         MortgageHub/mortgagehub_app/build/web. A path
///                         that isn't a file gets the build's index.html
///                         (the app routes it); a missing build, 503
///   GET /demos/aityx/config
///                         dev mode: {"available": true, "url": ...,
///                         "source": "environment" | ".env"} when this
///                         server has an aityx key (AITYX_API_KEY in its
///                         environment, else in the repo's .env), else
///                         {"available": false}; never the key
///   POST /demos/aityx/v1/systemone
///                         dev mode: the request's body, forwarded to
///                         <AITYX_URL>/v1/systemone with that key; only
///                         from this origin, never logged
///   GET /demos/api/health {"ok": true}
///   GET /demos/api/demos  each demo served here: its folder, its path,
///                         whether its build is there and made for that
///                         path; for scripts and the page's cards
///   GET /demos/api/group  {"group": "aityx"}: this index's group
///
/// Settings: INDEX_PORT (default 8800), INDEX_BIND_HOST (127.0.0.1),
/// INDEX_GROUP (aityx), INDEX_EMBED_ANCESTORS (the pages that may frame
/// key.html and the demos: the aityx website's dev server, port 4330, by
/// default), and for dev mode AITYX_API_KEY and AITYX_URL
/// (default https://api.aityx.ai), each from the environment, else from
/// the repo's .env, which is read again at most every 10 s.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

final _here = Directory.fromUri(Platform.script.resolve('..'));
final _www = Directory('${_here.path}/www');
final _root = Directory.fromUri(_here.uri.resolve('..'));

/// Where everything is served: the page at /demos/, each demo at
/// /demos/<slug>/, the dev proxy at /demos/aityx/, the API at /demos/api/.
/// The apps' base hrefs (each demo's scripts/build.sh) and the aityx_web
/// package's paths say the same.
const _prefix = '/demos/';

Future<void> main() async {
  final env = Platform.environment;
  final port = int.parse(env['INDEX_PORT'] ?? '8800');
  final host = env['INDEX_BIND_HOST'] ?? '127.0.0.1';
  final server = await HttpServer.bind(host, port);
  // main.dart.js and CanvasKit are several MB: gzip them for a browser
  // that asks (a codespace's forwarded port is a long way off).
  server.autoCompress = true;
  stdout.writeln('index on http://$host:$port$_prefix');
  await for (final request in server) {
    unawaited(_handle(request));
  }
}

Future<void> _handle(HttpRequest request) async {
  final response = request.response;
  response.headers
    ..set('X-Content-Type-Options', 'nosniff')
    ..set('Referrer-Policy', 'same-origin');
  try {
    final path = request.uri.path;
    if (path == '${_prefix}aityx/v1/systemone') {
      await _proxy(request);
    } else if (request.method != 'GET' && request.method != 'HEAD') {
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      _json(response, 405, {'error': 'method not allowed'});
    } else if (path == '/' ||
        path == _prefix.substring(0, _prefix.length - 1)) {
      // The root, and /demos without its slash: the page. Relative, so a
      // forwarded port's host is kept, and the query too.
      _redirect(request, _prefix);
    } else if (!path.startsWith(_prefix)) {
      await _old(request, path);
    } else if (path == '${_prefix}aityx/config') {
      _json(response, 200, await _config(), cache: 'no-store');
    } else if (path == '${_prefix}api/health') {
      _json(response, 200, {'ok': true});
    } else if (path == '${_prefix}api/demos') {
      final demos = await _demos();
      _json(response, 200, {
        'demos': [for (final demo in demos.values) await demo.describe()],
      });
    } else if (path == '${_prefix}api/group') {
      _json(response, 200, {'group': _group});
    } else {
      // Under the prefix: a demo's path, else a file of the page's.
      final under = path.substring(_prefix.length);
      final segments = Uri(path: under).pathSegments;
      final demo = segments.isEmpty ? null : (await _demos())[segments.first];
      if (demo == null) {
        await _page(request, under);
      } else if (under == demo.slug) {
        // The app's base href ends with a slash.
        _redirect(request, '$_prefix${demo.slug}/');
      } else {
        await _demoFile(request, demo, segments.skip(1).toList());
      }
    }
  } catch (error) {
    stderr.writeln('error: ${request.method} ${request.uri.path}: $error');
    try {
      _json(response, 500, {'error': 'internal error'});
    } catch (_) {
      // Headers already sent: nothing more to say.
    }
  } finally {
    await response.close();
  }
}

/// A path from before everything moved under /demos/: /app/ (the page)
/// and /<slug>/... (a demo) redirect to their place under the prefix;
/// anything else outside the prefix is 404.
Future<void> _old(HttpRequest request, String path) async {
  if (path == '/app' || path == '/app/') return _redirect(request, _prefix);
  final segments = request.uri.pathSegments;
  if (segments.isNotEmpty && (await _demos())[segments.first] != null) {
    // The rest of the path as sent (encoded), so a deep route is kept;
    // /<slug> gets its slash here, in one hop.
    final rest = path.substring(1);
    return _redirect(request, '$_prefix$rest${rest.contains('/') ? '' : '/'}');
  }
  _json(request.response, 404, {'error': 'not found'});
}

/// 301 to [to] (an absolute path), with the request's query.
void _redirect(HttpRequest request, String to) {
  request.response
    ..statusCode = HttpStatus.movedPermanently
    ..headers.set(
      HttpHeaders.locationHeader,
      '$to${request.uri.hasQuery ? '?${request.uri.query}' : ''}',
    );
}

/// Content types by extension; anything else is served as bytes.
const _types = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.map': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.mp4': 'video/mp4',
  '.webm': 'video/webm',
  '.ico': 'image/x-icon',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

/// The index page's own policy, sent as a header too, which (unlike the
/// page's meta tag) can forbid framing. Keep it the same as index.html's.
const _pageCsp =
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data:; connect-src 'self' https://*.aityx.ai; "
    "base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/// The pages allowed to frame key.html (the key form alone) and the
/// demos: the aityx website's dev server by default, INDEX_EMBED_ANCESTORS
/// (space-separated origins) when set. The index page itself is never
/// framed.
final _embedAncestors =
    (Platform.environment['INDEX_EMBED_ANCESTORS'] ?? '').trim().isNotEmpty
    ? Platform.environment['INDEX_EMBED_ANCESTORS']!.trim()
    : 'http://localhost:4330 http://127.0.0.1:4330';

/// key.html's policy: the page's, framed by [_embedAncestors] only.
final _keyCsp = _pageCsp.replaceFirst(
  "frame-ancestors 'none'",
  "frame-ancestors 'self' $_embedAncestors",
);

/// A demo's: only who may frame it (the app sets nothing else here).
final _demoCsp = "frame-ancestors 'self' $_embedAncestors";

/// A file right in www/, by its [name] after the prefix, as sent (still
/// percent-encoded, so an encoded separator is just a name that doesn't
/// exist): /demos/ is index.html.
Future<void> _page(HttpRequest request, String name) async {
  final response = request.response;
  if (name.isEmpty) name = 'index.html';
  // Only files right in www/, and none hidden.
  if (name.contains('/') || name.contains(r'\') || name.startsWith('.')) {
    return _json(response, 404, {'error': 'not found'});
  }
  final file = File('${_www.path}/$name');
  if (!await file.exists()) return _json(response, 404, {'error': 'not found'});
  if (name.endsWith('.html')) {
    response.headers.set(
      'Content-Security-Policy',
      name == 'key.html' ? _keyCsp : _pageCsp,
    );
  }
  await _send(request, file);
}

/// [file], with its type, revalidated on every load (nothing here is
/// fingerprinted), 304 when the browser's copy is current.
Future<void> _send(HttpRequest request, File file) async {
  final response = request.response;
  final stat = await file.stat();
  final modified = stat.modified.toUtc();
  final dot = file.path.lastIndexOf('.');
  final type = dot < 0 ? null : _types[file.path.substring(dot)];
  // The type on a 304 too: with nosniff and no type, Chrome's opaque
  // response blocking refuses the revalidated file to a page of another
  // origin (an image of the aityx website's blueprint pages), every other
  // load.
  response.headers
    ..set(HttpHeaders.cacheControlHeader, 'no-cache')
    ..set(HttpHeaders.lastModifiedHeader, HttpDate.format(modified))
    ..set(HttpHeaders.contentTypeHeader, type ?? 'application/octet-stream');
  final since = request.headers.ifModifiedSince;
  // The header has whole seconds; the file's time, milliseconds.
  if (since != null &&
      modified.millisecondsSinceEpoch ~/ 1000 <=
          since.millisecondsSinceEpoch ~/ 1000) {
    response.statusCode = HttpStatus.notModified;
    return;
  }
  response.statusCode = 200;
  if (type != null && type.startsWith('video/')) {
    return _sendRange(request, file, stat.size);
  }
  if (request.method == 'HEAD') return;
  await response.addStream(file.openRead());
}

/// A video, whole or the one byte range asked for (`Range: bytes=a-b`,
/// `a-` or `-n`): Safari plays a video only from ranges. Its length is
/// set, which also keeps it out of autoCompress (gzip would break ranges,
/// and saves nothing on a video).
Future<void> _sendRange(HttpRequest request, File file, int length) async {
  final response = request.response;
  response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
  var start = 0;
  var end = length - 1;
  final range = RegExp(r'^bytes=(\d*)-(\d*)$')
      .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
  if (range != null && '${range[1]}${range[2]}'.isNotEmpty) {
    final from = int.tryParse(range[1]!);
    final to = int.tryParse(range[2]!);
    if (from == null) {
      // The last n bytes.
      start = to == null ? length : (to >= length ? 0 : length - to);
    } else {
      start = from;
      if (to != null && to < end) end = to;
    }
    if (length == 0 || start > end || start >= length) {
      response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length')
        ..contentLength = 0;
      return;
    }
    response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$length');
  }
  response.contentLength = length == 0 ? 0 : end - start + 1;
  if (request.method == 'HEAD' || length == 0) return;
  await response.addStream(file.openRead(start, end + 1));
}

void _json(
  HttpResponse response,
  int status,
  Object body, {
  String cache = 'no-cache',
}) {
  response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..headers.set(HttpHeaders.cacheControlHeader, cache)
    ..write(jsonEncode(body));
}

// The demos -----------------------------------------------------------------

final _group = Platform.environment['INDEX_GROUP'] ?? 'aityx';

/// A demo this index serves.
class _Demo {
  _Demo(this.folder, this.slug, this.web);

  /// The folder's name (MortgageHub), its slug (mortgagehub: its path
  /// here is /demos/mortgagehub/) and its app's release web build.
  final String folder;
  final String slug;
  final Directory web;

  /// Where it is served: /demos/mortgagehub/.
  String get path => '$_prefix$slug/';

  /// The base href of the build's index.html (/demos/mortgagehub/), or
  /// null when there's no build.
  Future<String?> baseHref() async {
    final index = File('${web.path}/index.html');
    if (!await index.exists()) return null;
    final match = RegExp(r'''<base\s+href=["']([^"']*)["']''')
        .firstMatch(await index.readAsString());
    return match?.group(1) ?? '';
  }

  Future<Map<String, Object?>> describe() async {
    final base = await baseHref();
    return {
      'folder': folder,
      'path': path,
      'built': base != null,
      'baseHref': base,
      // Built for this path: a build made for another base href (an old
      // one, /mortgagehub/ at the root) loads its files from the wrong
      // place.
      'served': base == path,
    };
  }
}

/// The demos by slug, looked up again at most every 10 s, so a demo
/// added to the repository shows up without a restart.
Map<String, _Demo> _demoCache = {};
DateTime _demosAt = DateTime(0);

Future<Map<String, _Demo>> _demos() async {
  if (DateTime.now().difference(_demosAt) < const Duration(seconds: 10)) {
    return _demoCache;
  }
  final demos = <String, _Demo>{};
  final here = _name(_here);
  await for (final entry in _root.list()) {
    if (entry is! Directory || _name(entry) == here) continue;
    final folder = _name(entry);
    final slug = folder.toLowerCase();
    if (await _groupOf(entry) != _group) continue;
    if (!await File('${entry.path}/${slug}_app/pubspec.yaml').exists()) {
      continue;
    }
    // Never one of this server's own paths under the prefix.
    if (const {'api', 'aityx', 'demos'}.contains(slug)) continue;
    demos[slug] = _Demo(
      folder,
      slug,
      Directory('${entry.path}/${slug}_app/build/web'),
    );
  }
  _demosAt = DateTime.now();
  return _demoCache = Map.fromEntries(
    demos.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
}

/// The folder's group, from its group.id.txt (empty without one).
Future<String> _groupOf(Directory dir) async {
  final file = File('${dir.path}/group.id.txt');
  return await file.exists() ? (await file.readAsString()).trim() : '';
}

/// The folder's name.
String _name(Directory dir) =>
    dir.uri.pathSegments.where((s) => s.isNotEmpty).last;

/// A file of [demo]'s build, by the path's [segments] after the slug
/// (decoded): the file when there is one, else the build's index.html.
/// A segment that is hidden, `.` or `..`, or holds a separator is
/// refused, and so is a file that resolves (through a link) outside the
/// build.
Future<void> _demoFile(
  HttpRequest request,
  _Demo demo,
  List<String> segments,
) async {
  final response = request.response;
  final index = File('${demo.web.path}/index.html');
  if (!await index.exists()) return _notBuilt(response, demo);
  final parts = segments.where((s) => s.isNotEmpty).toList();
  if (parts.any(
    (s) =>
        s.startsWith('.') ||
        s.contains('/') ||
        s.contains(r'\') ||
        s.contains('\u0000'),
  )) {
    return _json(response, 400, {'error': 'bad path'});
  }
  var file = parts.isEmpty
      ? index
      : File('${demo.web.path}/${parts.join('/')}');
  if (await FileSystemEntity.type(file.path) != FileSystemEntityType.file) {
    file = index;
  }
  final base = await demo.web.resolveSymbolicLinks();
  final real = await file.resolveSymbolicLinks();
  if (!real.startsWith('$base${Platform.pathSeparator}')) {
    return _json(response, 404, {'error': 'not found'});
  }
  if (file.path.endsWith('.html')) {
    response.headers.set('Content-Security-Policy', _demoCsp);
  }
  await _send(request, file);
}

/// 503 and a short page: the demo's build isn't there yet.
void _notBuilt(HttpResponse response, _Demo demo) {
  response
    ..statusCode = HttpStatus.serviceUnavailable
    ..headers.contentType = ContentType.html
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
    // Its own inline styles, and nothing else.
    ..headers.set(
      'Content-Security-Policy',
      "default-src 'none'; style-src 'unsafe-inline'",
    )
    ..write(
      '<!doctype html><meta charset="utf-8"><title>${demo.folder}: '
      'not built yet</title><body style="font-family:sans-serif;'
      'background:#17161A;color:#EFF2F4;padding:24px">'
      '<p>${demo.folder} is not built yet: run <code>./build-all.sh '
      '${demo.folder}</code> at the root of the repository (or '
      '<code>./start-aityx.sh</code>, which builds what is missing), then '
      'reload.</p><p><a style="color:#EB7B58" href="$_prefix">The aityx '
      'demos</a></p>',
    );
}

// Dev mode: the key this server holds ----------------------------------------

const _defaultUrl = 'https://api.aityx.ai';

/// The key and where it goes, as this server reads them.
class _Settings {
  _Settings(this.key, this.source, this.url, this.base);

  /// The key (empty: none) and where it came from: environment or .env.
  final String key;
  final String source;

  /// AITYX_URL as set, without a trailing slash, and as a URL when it is
  /// a usable one (https, with a host), else null.
  final String url;
  final Uri? base;
}

_Settings? _settingsCache;
DateTime _settingsAt = DateTime(0);

/// A codespace's secrets, as Codespaces keeps them for its processes:
/// NAME=<base64 of the value>, one per line. Empty outside a codespace.
Future<Map<String, String>> _codespaceSecrets() async {
  final file = File('/workspaces/.codespaces/shared/.env-secrets');
  final secrets = <String, String>{};
  try {
    if (!await file.exists()) return secrets;
    for (final line in await file.readAsLines()) {
      final at = line.indexOf('=');
      if (at <= 0) continue;
      try {
        secrets[line.substring(0, at)] = utf8
            .decode(base64.decode(line.substring(at + 1).trim()))
            .trim();
      } on FormatException {
        continue;
      }
    }
  } on FileSystemException {
    return secrets;
  }
  return secrets;
}

/// The key and URL: each from the environment (a Codespaces secret, also
/// read from the codespace's secrets file), else from the repo's .env,
/// read again at most every 10 s, so a key added after the start is
/// picked up.
Future<_Settings> _settings() async {
  final cached = _settingsCache;
  if (cached != null &&
      DateTime.now().difference(_settingsAt) < const Duration(seconds: 10)) {
    return cached;
  }
  final env = Platform.environment;
  final file = File('${_root.path}/.env');
  List<String> lines;
  try {
    lines = await file.exists() ? await file.readAsLines() : <String>[];
  } on FileSystemException {
    lines = <String>[];
  }
  String fromFile(String name) {
    var value = '';
    for (var line in lines) {
      line = line.trim();
      if (line.startsWith('export ')) line = line.substring(7).trimLeft();
      if (!line.startsWith('$name=')) continue;
      value = line.substring(name.length + 1).trim();
      if (value.length >= 2 &&
          (value[0] == '"' || value[0] == "'") &&
          value.endsWith(value[0])) {
        value = value.substring(1, value.length - 1);
      }
    }
    return value;
  }

  // A codespace's secrets reach the processes its startup runs, but not
  // an SSH session's: a server restarted from one reads them from the
  // file Codespaces keeps them in.
  final secrets = await _codespaceSecrets();
  var envKey = env['AITYX_API_KEY'] ?? '';
  if (envKey.isEmpty) envKey = secrets['AITYX_API_KEY'] ?? '';
  final key = envKey.isNotEmpty ? envKey : fromFile('AITYX_API_KEY');
  var envUrl = env['AITYX_URL'] ?? '';
  if (envUrl.isEmpty) envUrl = secrets['AITYX_URL'] ?? '';
  var url = envUrl.isNotEmpty ? envUrl : fromFile('AITYX_URL');
  if (url.isEmpty) url = _defaultUrl;
  url = url.replaceFirst(RegExp(r'/+$'), '');
  final parsed = Uri.tryParse(url);
  final base =
      parsed != null &&
          parsed.scheme == 'https' &&
          parsed.host.isNotEmpty &&
          !parsed.hasQuery &&
          !parsed.hasFragment
      ? parsed
      : null;
  _settingsAt = DateTime.now();
  return _settingsCache = _Settings(
    key,
    envKey.isNotEmpty ? 'environment' : '.env',
    url,
    base,
  );
}

/// GET /demos/aityx/config: whether the dev proxy has a key; never the key.
Future<Map<String, Object?>> _config() async {
  final settings = await _settings();
  if (settings.key.isEmpty) return {'available': false};
  if (settings.base == null) {
    return {
      'available': false,
      'detail': 'AITYX_URL must be an https URL (it is ${settings.url})',
    };
  }
  return {'available': true, 'url': settings.url, 'source': settings.source};
}

/// The largest request the proxy forwards, and how long aityx has to
/// answer it (a RoboRules battle runs 50 turns in one call).
const _maxBody = 2 * 1024 * 1024;
const _proxyTimeout = Duration(seconds: 120);

final _client = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10)
  ..userAgent = 'aityx-demos-index';

/// Whether [request] comes from a page of this origin: the browser's
/// Sec-Fetch-Site says same-origin or, from a browser that doesn't send
/// it, Origin is absent or names this very host. A page elsewhere can't
/// spend this server's key.
bool _sameOrigin(HttpRequest request) {
  if (!_loopbackHost(request)) return false;
  final site = request.headers.value('sec-fetch-site');
  if (site != null) return site == 'same-origin';
  final origin = request.headers.value('origin');
  if (origin == null) return true;
  final host = request.headers.value(HttpHeaders.hostHeader);
  final from = Uri.tryParse(origin);
  if (host == null || from == null || from.host.isEmpty) return false;
  final self = Uri.tryParse('${from.scheme}://$host');
  return self != null &&
      self.host.toLowerCase() == from.host.toLowerCase() &&
      self.port == from.port;
}

/// Whether this server listens on the loopback only (INDEX_BIND_HOST, by
/// default 127.0.0.1: a laptop), where only this machine's browser
/// reaches it.
final _loopbackBind = () {
  final host = Platform.environment['INDEX_BIND_HOST'] ?? '127.0.0.1';
  return host == 'localhost' ||
      (InternetAddress.tryParse(host)?.isLoopback ?? false);
}();

/// Whether [request] names this machine as its host, when the server
/// listens on the loopback only: one that names another host reached it
/// through DNS rebinding (a page elsewhere whose name now points at
/// 127.0.0.1, and so is same-origin to itself), and must not spend this
/// server's key. Bound to every interface (a codespace), any host.
bool _loopbackHost(HttpRequest request) {
  if (!_loopbackBind) return true;
  var host = request.headers.host?.toLowerCase();
  if (host == null) return false;
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  return host == 'localhost' ||
      host.endsWith('.localhost') ||
      (InternetAddress.tryParse(host)?.isLoopback ?? false);
}

/// POST /demos/aityx/v1/systemone: the body, forwarded to aityx with this
/// server's key; aityx's status and body back unchanged. Redirects are not
/// followed (502: AITYX_URL is likely behind a login), and an aityx that
/// doesn't answer is a 502 too. Neither the key nor the bodies are logged.
Future<void> _proxy(HttpRequest request) async {
  final response = request.response;
  if (request.method != 'POST') {
    response.headers.set(HttpHeaders.allowHeader, 'POST');
    return _json(response, 405, {
      'code': 'method_not_allowed',
      'detail': 'the dev proxy takes POST only',
    }, cache: 'no-store');
  }
  if (!_sameOrigin(request)) {
    return _json(response, 403, {
      'code': 'proxy_cross_site',
      'detail': "the dev proxy answers this origin's pages only",
    }, cache: 'no-store');
  }
  final settings = await _settings();
  if (settings.key.isEmpty) {
    return _json(response, 503, {
      'code': 'proxy_no_key',
      'detail': 'this server has no aityx key: set yours on the index page',
    }, cache: 'no-store');
  }
  final base = settings.base;
  if (base == null) {
    return _json(response, 503, {
      'code': 'proxy_bad_url',
      'detail': 'AITYX_URL must be an https URL',
    }, cache: 'no-store');
  }
  if (request.contentLength > _maxBody) {
    return _json(response, 413, {
      'code': 'proxy_too_large',
      'detail': 'the request is over ${_maxBody ~/ (1024 * 1024)} MB',
    }, cache: 'no-store');
  }
  final body = BytesBuilder(copy: false);
  try {
    await for (final chunk in request.timeout(const Duration(seconds: 30))) {
      body.add(chunk);
      if (body.length > _maxBody) {
        return _json(response, 413, {
          'code': 'proxy_too_large',
          'detail': 'the request is over ${_maxBody ~/ (1024 * 1024)} MB',
        }, cache: 'no-store');
      }
    }
  } on TimeoutException {
    return _json(response, 408, {
      'code': 'proxy_request_timeout',
      'detail': 'the request body did not arrive',
    }, cache: 'no-store');
  }
  final target = Uri.parse('${base.toString()}/v1/systemone');
  final started = DateTime.now();
  final (int, ContentType?, Uint8List, String?) answer;
  try {
    answer = await _forward(
      target,
      settings.key,
      request.headers.contentType,
      body.takeBytes(),
    ).timeout(_proxyTimeout);
  } catch (error) {
    stderr.writeln('aityx proxy: no answer (${error.runtimeType})');
    return _json(response, 502, {
      'code': 'proxy_unreachable',
      'detail': 'aityx did not answer: ${error.runtimeType}',
    }, cache: 'no-store');
  }
  final (status, type, bytes, location) = answer;
  final took = DateTime.now().difference(started).inMilliseconds;
  stdout.writeln('aityx proxy: HTTP $status in $took ms');
  if (status >= 300 && status < 400) {
    final to = location == null ? null : target.resolve(location);
    final host = to == null || to.host.isEmpty ? target.host : to.host;
    return _json(response, 502, {
      'code': 'proxy_redirect',
      'detail': 'AITYX_URL redirected to $host: it may be behind a login',
    }, cache: 'no-store');
  }
  response
    ..statusCode = status
    ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
  if (type != null) response.headers.contentType = type;
  response.add(bytes);
}

/// One call to aityx: the status, type, body and Location of its answer.
Future<(int, ContentType?, Uint8List, String?)> _forward(
  Uri target,
  String key,
  ContentType? type,
  Uint8List body,
) async {
  final call = await _client.postUrl(target);
  call
    ..followRedirects = false
    ..headers.set(HttpHeaders.authorizationHeader, 'Bearer $key')
    ..headers.contentType = type ?? ContentType.json
    ..contentLength = body.length
    ..add(body);
  final answer = await call.close();
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in answer) {
    bytes.add(chunk);
  }
  return (
    answer.statusCode,
    answer.headers.contentType,
    bytes.takeBytes(),
    answer.headers.value(HttpHeaders.locationHeader),
  );
}
