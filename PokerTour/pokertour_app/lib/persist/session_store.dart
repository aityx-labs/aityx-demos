import 'session_store_memory.dart'
    if (dart.library.js_interop) 'session_store_web.dart'
    as impl;

/// What the app keeps across a reload of the page: the browser tab's
/// session storage on the web (gone when the tab closes, never shared with
/// other tabs), memory elsewhere. Every read and write is allowed to fail
/// (storage blocked, full, private mode): the app then starts fresh.
abstract class SessionStore {
  /// The browser's session storage on the web, memory elsewhere.
  factory SessionStore() = impl.PlatformSessionStore;

  /// Memory only: what tests use.
  factory SessionStore.memory() = MemorySessionStore;

  String? read(String key);
  void write(String key, String value);
  void remove(String key);
}

/// A [SessionStore] in memory.
class MemorySessionStore implements SessionStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String value) => _values[key] = value;

  @override
  void remove(String key) => _values.remove(key);
}
