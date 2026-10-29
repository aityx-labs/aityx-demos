import 'package:web/web.dart' as web;

/// Replaces the address's query, keeping its path and its `#` route.
void replaceQuery(Map<String, String> query) {
  try {
    final location = web.window.location;
    final address = Uri.parse(location.href).replace(queryParameters: query);
    web.window.history.replaceState(null, '', address.toString());
  } catch (_) {
    // Not worth failing for: the tab just isn't kept.
  }
}
