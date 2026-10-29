import 'package:web/web.dart' as web;

import 'session_store.dart';

/// The browser tab's session storage, under a `datyx.` prefix.
class PlatformSessionStore implements SessionStore {
  static const _prefix = 'datyx.';

  @override
  String? read(String key) {
    try {
      return web.window.sessionStorage.getItem('$_prefix$key');
    } catch (_) {
      return null;
    }
  }

  @override
  void write(String key, String value) {
    try {
      web.window.sessionStorage.setItem('$_prefix$key', value);
    } catch (_) {
      // Blocked or full: the next reload starts without it.
    }
  }

  @override
  void remove(String key) {
    try {
      web.window.sessionStorage.removeItem('$_prefix$key');
    } catch (_) {}
  }
}
