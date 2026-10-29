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

/// Why a call that spends the aityx key (`POST /api/decide`) is refused, or
/// null when it may go ahead. Any website can make a browser POST here; a
/// JSON body is not a "simple" request, so a cross-site page has to ask
/// first (a CORS preflight, which only [origins] pass), and an [origin]
/// that isn't allowed is refused outright unless the browser itself says
/// the request is same-origin ([fetchSite], `Sec-Fetch-Site`, which pages
/// can't set): the app through the web server's or nginx's proxy,
/// whatever host a forwarded port gives it. A request without an Origin
/// (curl, a script) isn't a browser's, so it isn't a cross-site one.
Answer? refusal({
  required String? origin,
  required String? fetchSite,
  required String? mimeType,
  required Set<String> origins,
}) {
  if (origin != null &&
      !origins.contains(origin) &&
      fetchSite != 'same-origin') {
    return const Answer(403, body: {'error': 'origin not allowed'});
  }
  if (mimeType != 'application/json') {
    return const Answer(415, body: {'error': 'expected application/json'});
  }
  return null;
}
