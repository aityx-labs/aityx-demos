/// Where the key comes from: the user's, then the dev proxy, then none.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'body.dart';
import 'connection.dart';
import 'key_store.dart';
import 'paths.dart';
import 'platform/platform_vm.dart'
    if (dart.library.js_interop) 'platform/platform_web.dart';

/// Reads the key the way the index page and every demo agree on:
///
/// 0. nothing at all, when the page around the app makes its calls
///    (`?bridge=1`): the aityx console's Demos tab, where the app is framed
///    with an origin of its own and has no storage to read a key from;
/// 1. the user's key from the [AityxKeyStore] (sessionStorage, then
///    localStorage), sent straight to its URL;
/// 2. else the dev key, when the origin's `/demos/aityx/config` says the
///    index server has one: calls go to `<origin>/demos/aityx/`, which
///    adds it;
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
  /// `/demos/aityx/config` (a new one unless given). Never throws: a
  /// missing, failing or non-JSON `/demos/aityx/config` (a static host's
  /// 404 or its index.html) means no dev key.
  static Future<AityxConnection> resolve({
    http.Client? client,
    Uri? origin,
    AityxKeyStore? store,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    // Before the store: framed by the console there is no store to read, and
    // no key would be the right answer anyway.
    if (bridgeRequested()) return AityxConnection.bridge();

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
            page.resolve(demosPath('aityx/config')),
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
