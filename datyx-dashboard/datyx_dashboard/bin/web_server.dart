/// The web server `devbox services up` runs in release mode (see
/// scripts/flutter-web.sh): the dashboard's release build under /app/, and /api/
/// and /q/ proxied to the API, on one origin. See lib/web_server.dart.
///
/// Settings, from the environment:
///   WEB_ROOT          the build to serve (datyx_dashboard/build/web)
///   FLUTTER_WEB_PORT  the port (default 9906)
///   DATYX_BIND_HOST   the address to bind (default 127.0.0.1)
///   DATYX_API_URL     the API (default http://127.0.0.1:9900)
library;

import 'dart:io';

import 'package:datyx_dashboard/web_server.dart';

Future<void> main() async {
  final env = Platform.environment;
  final root = Directory(env['WEB_ROOT'] ?? '');
  if (root.path.isEmpty || !await File('${root.path}/index.html').exists()) {
    stderr.writeln(
      'error: WEB_ROOT must be a web build (index.html): '
      "'${root.path}'",
    );
    exit(1);
  }
  final port = int.parse(env['FLUTTER_WEB_PORT'] ?? '9906');
  final host = env['DATYX_BIND_HOST'] ?? '127.0.0.1';
  final api = Uri.parse(env['DATYX_API_URL'] ?? 'http://127.0.0.1:9900');
  await serveWeb(root: root, host: host, port: port, api: api);
  stdout.writeln(
    'datyx dash on http://$host:$port/app/ (${root.path}; /api/ to $api)',
  );
}
