/// The web server `devbox services up` runs in release mode (see
/// scripts/flutter-web.sh): the app's release build under /app/, and
/// /api/ proxied to the API, on one origin, as nginx does under Docker
/// Compose. See lib/web_server.dart.
///
/// Settings, from the environment:
///   WEB_ROOT              the build to serve (contacthub_app/build/web)
///   FLUTTER_WEB_PORT      the port (default 8890)
///   CONTACTHUB_BIND_HOST  the address to bind (default 127.0.0.1)
///   API_PORT              the API's port on 127.0.0.1 (default 8891)
library;

import 'dart:io';

import 'package:contacthub_api/web_server.dart';

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
  final port = int.parse(env['FLUTTER_WEB_PORT'] ?? '8890');
  final host = env['CONTACTHUB_BIND_HOST'] ?? '127.0.0.1';
  final api = Uri.parse('http://127.0.0.1:${env['API_PORT'] ?? '8891'}');
  await serveWeb(root: root, host: host, port: port, api: api);
  stdout.writeln(
    'contacthub web on http://$host:$port/app/ (${root.path}; '
    '/api/ to $api)',
  );
}
