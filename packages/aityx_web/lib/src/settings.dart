/// Where the key comes from: the user's, then the dev proxy, then none.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'body.dart';
import 'connection.dart';
import 'key_store.dart';

/// Reads the key the way the index page and every demo agree on:
///
/// 1. the user's key from the [AityxKeyStore] (sessionStorage, then
///    localStorage), sent straight to its URL;
/// 2. else the dev key, when the origin's `/aityx/config` says the index
///    server has one: calls go to `<origin>/aityx/`, which adds it;
/// 3. else none.
class AityxSettings {
  AityxSettings._();

  static AityxKeyStore? _store;

  /// The store [resolve], AityxClient and the status light use when not
  /// given one: the browser's. A test can set an in-memory one here.
  static AityxKeyStore get store => _store ??= AityxKeyStore.browser();
  static set store(AityxKeyStore value) => _store = value;

  /// The connection to use now. [origin] is the page's (Uri.base unless a
  /// test says); off http(s) there's no dev proxy to ask. [client] asks
  /// `/aityx/config` (a new one unless given). Never throws: a missing,
  /// failing or non-JSON `/aityx/config` (a static host's 404 or its
  /// index.html) means no dev key.
  static Future<AityxConnection> resolve({
    http.Client? client,
    Uri? origin,
    AityxKeyStore? store,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final keys = store ?? AityxSettings.store;
    final key = keys.key;
    if (key != null) return AityxConnection.user(key, url: keys.url);

    final page = origin ?? Uri.base;
    if (!(page.isScheme('http') || page.isScheme('https'))) {
      return AityxConnection.none;
    }
    final http.Client asker = client ?? http.Client();
    try {
      final answer = await asker
          .get(
            page.resolve('/aityx/config'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(timeout);
      final config = tryJson(bodyText(answer));
      if (answer.statusCode != 200 ||
          config is! Map ||
          config['available'] != true) {
        return AityxConnection.none;
      }
      final url = config['url'];
      final from = config['source'];
      return AityxConnection.dev(
        page,
        url: url is String ? url : '',
        devKeyFrom: from is String ? from : null,
      );
    } catch (_) {
      return AityxConnection.none;
    } finally {
      if (client == null) asker.close();
    }
  }
}
