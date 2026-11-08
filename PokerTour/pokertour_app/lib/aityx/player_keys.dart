/// The aityx key the player's table runs on, and where it sends it: the
/// player's own, set in the Profile tab and kept in the browser
/// (localStorage; sessionStorage is still read, for keys saved there
/// before), with its URL, else this environment's. There is no other:
/// without one the Profile tab opens and asks for it, and the player
/// can't play. Players never get the host's key.
///
/// This environment's URL is the server's (`GET /api/config`'s
/// `aityxUrl`): https://api-stage.aityx.ai on a laptop, https://api.aityx.ai
/// when deployed. The leaderboard doesn't use any of this: it plays on
/// the server, on a key of its own.
///
/// It is an [AityxKeyStore], so the table's AityxClient follows it: a key
/// saved or forgotten here takes effect at the next decision.
library;

import 'dart:async';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter/foundation.dart';

/// Whose key the table uses.
enum KeySource {
  /// The player's own, from the Profile tab.
  own,

  /// None yet.
  none,
}

class PlayerKeys extends ChangeNotifier implements AityxKeyStore {
  PlayerKeys({required this._local, required this._session});

  /// The storage entries, Poker Tour's own: not the index page's
  /// `aityx.key`, so the URL is kept even when it is production's.
  static const keyName = 'pokertour.aityx.key';
  static const urlName = 'pokertour.aityx.url';

  final StorageArea _local;
  final StorageArea _session;
  final _changes = StreamController<void>.broadcast();

  String _defaultUrl = aityxDefaultUrl;
  Uri? _relay;

  /// The server's relay to this environment's aityx (on a laptop), which
  /// calls to [defaultUrl] go through; null for direct calls.
  Uri? get relay => _relay;
  set relay(Uri? relay) {
    if (relay == _relay) return;
    _relay = relay;
    _changed();
  }

  /// This environment's aityx URL: the server's, else production's.
  String get defaultUrl => _defaultUrl;
  set defaultUrl(String url) {
    final next = url.trim().isEmpty ? aityxDefaultUrl : normalizeAityxUrl(url);
    if (next == _defaultUrl) return;
    _defaultUrl = next;
    _changed();
  }

  /// Whether this environment is aityx staging (a laptop's server).
  bool get staging => _defaultUrl.contains('stage');

  /// The player's own key; null when none is set.
  String? get ownKey => _read(_session, keyName) ?? _read(_local, keyName);

  /// The URL saved with the player's own key; null for a key saved
  /// without one (before URLs were always kept): this environment's.
  String? get ownUrl {
    final area = _read(_session, keyName) != null ? _session : _local;
    return _read(area, urlName);
  }

  KeySource get source => ownKey != null ? KeySource.own : KeySource.none;

  /// Whose key, for people.
  String get whose => switch (source) {
    KeySource.own => 'your key',
    KeySource.none => 'no key',
  };

  @override
  String? get key => ownKey;

  /// Where the key goes: the player's URL with their key, else this
  /// environment's. Never null with a key, so AityxSettings doesn't fall
  /// back to production's on a laptop.
  @override
  String? get url => ownKey != null ? ownUrl ?? _defaultUrl : null;

  @override
  bool get sessionOnly => _read(_session, keyName) != null;

  /// Saves the player's own key and the URL it goes to, [url] or, when
  /// empty, this environment's now: always kept, so the key keeps going
  /// where it was saved for, whatever the server's aityx later is (a
  /// staging key never drifts to production). In sessionStorage when
  /// [sessionOnly], else in localStorage; the other storage is cleared.
  @override
  void save(String key, {String? url, bool sessionOnly = false}) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) throw ArgumentError.value('', 'key', 'an empty key');
    final into = sessionOnly ? _session : _local;
    final other = sessionOnly ? _local : _session;
    _remove(other, keyName);
    _remove(other, urlName);
    _write(into, keyName, trimmed);
    final given = (url ?? '').trim();
    _write(into, urlName, given.isEmpty ? _defaultUrl : normalizeAityxUrl(given));
    _changed();
  }

  /// Forgets the player's own key: the table then has none.
  @override
  void forget() {
    for (final area in [_local, _session]) {
      _remove(area, keyName);
      _remove(area, urlName);
    }
    _changed();
  }

  @override
  Stream<void> get changes => _changes.stream;

  /// The connection the table uses now: the key and its URL, or none.
  /// Calls to this environment's aityx go through the server's relay
  /// when it has one; a key the player points elsewhere goes there
  /// directly.
  AityxConnection get connection {
    final k = key;
    if (k == null) return AityxConnection.none;
    final direct = AityxConnection.user(k, url: url);
    final through = _relay;
    if (through == null || direct.url != _defaultUrl) return direct;
    return AityxConnection(endpoint: through, source: AityxSource.user, url: direct.url, key: k);
  }

  void _changed() {
    _changes.add(null);
    notifyListeners();
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }

  // Storage can be refused (blocked cookies, some private modes): then
  // nothing is stored, rather than an error.

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
