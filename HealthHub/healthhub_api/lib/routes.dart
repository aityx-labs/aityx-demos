/// What the API answers, by method and path, apart from the HTTP plumbing in
/// bin/server.dart, so it can be tested without a server or a database.
library;

import 'auth.dart';

/// An answer: a status, and a JSON body or a redirect.
class Answer {
  const Answer(this.status, {this.body, this.location});

  final int status;
  final Object? body;

  /// The Location of a redirect.
  final String? location;
}

/// An answer the datyx API gave to a call made on the user's behalf, with
/// the user's own token: passed on as it came.
class Forwarded {
  const Forwarded(this.status, this.body);

  final int status;
  final Object? body;
}

/// [db]: whether the database answers, reported by /api/health.
/// [aityx]: whether the API has an aityx key, reported by /api/health.
/// [greeting]: what GET /api/hello answers, read from the database by the
/// server (null when it can't be read: 503).
/// [auth]: how the API authenticates (GET /api/auth/config); with it on,
/// /api/me and /api/datyx/* want a signed-in user ([identity], from the
/// bearer token the server verified), a 401 without one.
/// [datyx]: the datyx API's answer for /api/datyx/*, which the server
/// fetched with the user's token (null: it didn't answer, 502).
Answer route(
  String method,
  String path, {
  bool db = false,
  bool aityx = false,
  Map<String, Object?>? greeting,
  AuthSettings auth = const AuthSettings(issuer: 'https://accounts.google.com', clientId: ''),
  Identity? identity,
  Forwarded? datyx,
}) {
  if (method == 'OPTIONS') return const Answer(204);
  if (method == 'GET') {
    switch (path) {
      // The site root, which the web server proxies here
      // (scripts/flutter-web.sh), so a forwarded port's bare URL opens the
      // app. Relative, so it keeps the forwarded host and port.
      case '/':
        return const Answer(302, location: '/app/');
      case '/api/health':
        return Answer(200, body: {'ok': true, 'db': db, 'aityx': aityx, 'auth': auth.enabled});
      case '/api/auth/config':
        return Answer(200, body: auth.toJson());
      case '/api/me':
        if (auth.enabled && identity == null) return _signIn;
        return Answer(200, body: {
          'authenticated': identity != null,
          if (identity != null) ...identity.toJson(),
        });
      case '/api/hello':
        if (greeting == null) {
          return const Answer(
            503,
            body: {'error': 'the database is not answering'},
          );
        }
        // Addressed to the signed-in user, when there is one.
        final name = identity?.name ?? identity?.email;
        return Answer(200, body: {
          ...greeting,
          if (name != null) 'message': 'Hello, $name',
          'user': identity?.toJson(),
        });
      case '/api/datyx/me':
      case '/api/datyx/datasources':
        if (auth.enabled && identity == null) return _signIn;
        if (datyx == null) {
          return const Answer(502, body: {'error': 'the datyx API is not answering'});
        }
        return Answer(datyx.status, body: datyx.body);
    }
  }
  return const Answer(404, body: {'error': 'not found'});
}

const _signIn = Answer(401, body: {'error': 'sign in first'});

/// The datyx API's path behind one of ours (/api/datyx/me, /api/datyx/datasources), or null.
String? datyxPath(String path) => switch (path) {
  '/api/datyx/me' => '/api/me',
  '/api/datyx/datasources' => '/api/datasources',
  _ => null,
};
