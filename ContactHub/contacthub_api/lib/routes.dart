/// What the API answers, by method and path, apart from the HTTP plumbing in
/// bin/server.dart, so it can be tested without a server.
library;

/// An answer: a status, and a JSON body or a redirect.
class Answer {
  const Answer(this.status, {this.body, this.location});

  final int status;
  final Object? body;

  /// The Location of a redirect.
  final String? location;
}

/// [aityx]: whether the API has an aityx key, reported by /api/health.
Answer route(String method, String path, {bool aityx = false}) {
  if (method == 'OPTIONS') return const Answer(204);
  if (method == 'GET') {
    switch (path) {
      // The site root, which the dev server proxies here
      // (scripts/flutter-web.sh), so a forwarded port's bare URL opens the
      // app. Relative, so it keeps the forwarded host and port.
      case '/':
        return const Answer(302, location: '/app/');
      case '/api/health':
        return Answer(200, body: {'ok': true, 'aityx': aityx});
    }
  }
  return const Answer(404, body: {'error': 'not found'});
}
