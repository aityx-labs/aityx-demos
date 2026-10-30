/// The key, as stored by the index page.
library;

import 'dart:async';

import 'connection.dart';
import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart'
    as platform;

/// The user's aityx key and URL, as the index page stores them: in
/// localStorage ("remember on this device") or sessionStorage ("only this
/// session"), under `aityx.key` and `aityx.url`. sessionStorage wins when
/// both hold a key.
abstract class AityxKeyStore {
  const AityxKeyStore();

  /// The browser's storage, shared by every page on the origin; an
  /// in-memory store off the web (tests, native builds).
  factory AityxKeyStore.browser() => platform.browserKeyStore();

  /// An in-memory store, for tests: [local] and [session] are the two
  /// storages' starting entries (`aityx.key`, `aityx.url`), so a test can
  /// set both the way two index page visits could.
  factory AityxKeyStore.memory({
    Map<String, String>? local,
    Map<String, String>? session,
  }) => StorageKeyStore(MapArea(local), MapArea(session));

  /// The key, trimmed; null when none is set.
  String? get key;

  /// The aityx URL stored with [key]; null when none is (callers default
  /// to https://api.aityx.ai).
  String? get url;

  /// Whether [key] comes from sessionStorage ("only this session").
  bool get sessionOnly;

  /// Stores [key] (and [url], unless null, empty or the default) in
  /// sessionStorage when [sessionOnly], else in localStorage, and clears
  /// the other storage.
  void save(String key, {String? url, bool sessionOnly = false});

  /// Removes the key and URL from both storages.
  void forget();

  /// An event whenever the key or URL changes: on [save] and [forget],
  /// and in the browser when another tab (the index page) changes them.
  Stream<void> get changes;
}

/// One storage: localStorage, sessionStorage, or a map.
abstract class StorageArea {
  String? read(String name);
  void write(String name, String value);
  void remove(String name);
}

/// A [StorageArea] in memory.
class MapArea implements StorageArea {
  MapArea([Map<String, String>? entries]) : entries = {...?entries};

  final Map<String, String> entries;

  @override
  String? read(String name) => entries[name];

  @override
  void write(String name, String value) => entries[name] = value;

  @override
  void remove(String name) => entries.remove(name);
}

/// [AityxKeyStore] over two [StorageArea]s, the browser's semantics: the
/// in-memory store and the browser's are this, over maps or over Storage.
class StorageKeyStore implements AityxKeyStore {
  StorageKeyStore(this.local, this.session, {this.external});

  final StorageArea local;
  final StorageArea session;

  /// Changes from elsewhere: the browser's storage event.
  final Stream<void>? external;

  late final StreamController<void> _changes = StreamController.broadcast(
    onListen: _listenExternal,
    onCancel: () => _externalSubscription?.cancel(),
  );
  StreamSubscription<void>? _externalSubscription;

  void _listenExternal() {
    _externalSubscription = external?.listen((_) => _changes.add(null));
  }

  /// The area that holds the key: session first.
  StorageArea? get _holder {
    if (_read(session, aityxKeyName) != null) return session;
    if (_read(local, aityxKeyName) != null) return local;
    return null;
  }

  @override
  String? get key {
    final holder = _holder;
    return holder == null ? null : _read(holder, aityxKeyName);
  }

  @override
  String? get url {
    final holder = _holder;
    if (holder != null) return _read(holder, aityxUrlName);
    return _read(session, aityxUrlName) ?? _read(local, aityxUrlName);
  }

  @override
  bool get sessionOnly => identical(_holder, session);

  @override
  void save(String key, {String? url, bool sessionOnly = false}) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value('', 'key', 'an empty key');
    }
    final into = sessionOnly ? session : local;
    final other = sessionOnly ? local : session;
    _remove(other, aityxKeyName);
    _remove(other, aityxUrlName);
    _write(into, aityxKeyName, trimmed);
    final shown = url == null || url.trim().isEmpty
        ? null
        : normalizeAityxUrl(url);
    if (shown == null || shown == aityxDefaultUrl) {
      _remove(into, aityxUrlName);
    } else {
      _write(into, aityxUrlName, shown);
    }
    _changes.add(null);
  }

  @override
  void forget() {
    for (final area in [local, session]) {
      _remove(area, aityxKeyName);
      _remove(area, aityxUrlName);
    }
    _changes.add(null);
  }

  @override
  Stream<void> get changes => _changes.stream;

  // The browser can refuse storage (blocked cookies, some private modes):
  // then there's no key, rather than an error.

  static String? _read(StorageArea area, String name) {
    try {
      final value = area.read(name)?.trim();
      return value == null || value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static void _write(StorageArea area, String name, String value) {
    try {
      area.write(name, value);
    } catch (_) {}
  }

  static void _remove(StorageArea area, String name) {
    try {
      area.remove(name);
    } catch (_) {}
  }
}
