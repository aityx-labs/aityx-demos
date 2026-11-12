/// In the browser: localStorage and sessionStorage, the storage event, and
/// navigation, through package:web.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../connection.dart';
import '../key_store.dart';

/// One Storage, looked up on each use: reading `window.localStorage` can
/// throw when the browser blocks storage, and StorageKeyStore catches it.
class _WebArea implements StorageArea {
  _WebArea(this._storage);

  final web.Storage Function() _storage;

  @override
  String? read(String name) => _storage().getItem(name);

  @override
  void write(String name, String value) => _storage().setItem(name, value);

  @override
  void remove(String name) => _storage().removeItem(name);
}

/// The storage event fires in the other tabs of the origin when one
/// changes localStorage; a null key means storage was cleared.
final _store = StorageKeyStore(
  _WebArea(() => web.window.localStorage),
  _WebArea(() => web.window.sessionStorage),
  external: web.EventStreamProviders.storageEvent
      .forTarget(web.window)
      .where(
        (event) =>
            event.key == null ||
            event.key == aityxKeyName ||
            event.key == aityxUrlName,
      ),
);

/// The one browser store, so every part of the app shares its changes.
AityxKeyStore browserKeyStore() => _store;

/// Opens [page] in the same tab.
void openPage(Uri page) => web.window.location.assign(page.toString());

/// Opens [page] in a new tab, which gets no handle on this one.
void openNewTab(Uri page) =>
    web.window.open(page.toString(), '_blank', 'noopener,noreferrer');

/// Whether the page that loaded the app asked for it embedded (`?embed=1`)
/// and the app is in a frame. Read once, at the first use: the query is
/// the one the app was loaded with, whatever it routes to since.
final bool _embedded =
    Uri.base.queryParameters['embed'] == '1' && web.window.parent != null;

bool embedded() => _embedded;

/// Posts [message] to the page around the app. To any origin: the
/// message is a name, never the key or anything the user typed.
void postToParent(String message) =>
    web.window.parent?.postMessage(message.toJS, '*'.toJS);

/// Whether the page that framed the app makes its aityx calls for it
/// (`?bridge=1`): the aityx console's Demos tab, which frames the app
/// sandboxed, with an origin of its own. There the app has no storage, no
/// cookies and no key, and could not reach aityx by itself. Read once, at
/// the first use, like [embedded].
final bool _bridged =
    Uri.base.queryParameters['bridge'] == '1' && web.window.parent != null;

bool bridgeRequested() => _bridged;

var _nextCall = 0;

/// Asks the page around the app for one decision and waits for its answer.
///
/// The message carries the body and nothing else: no URL, no method, no
/// header. The page decides what it calls, so the app can reach nothing
/// through this but a decision on the signed-in account. To and from any
/// origin, because a sandboxed app has none to name, and nothing secret is
/// said either way: the body is the app's own, the answer is aityx's.
///
/// Answers with status 0 when no answer comes within [timeout], which the
/// caller reports as unreachable.
Future<({int status, String body})> askParent(
  String body,
  Duration timeout,
) async {
  final parent = web.window.parent;
  if (parent == null) return (status: 0, body: '');
  final id = 'c${_nextCall++}';
  final answer = Completer<({int status, String body})>();
  late final JSFunction listener;
  void stop() => web.window.removeEventListener('message', listener);
  listener =
      ((web.MessageEvent event) {
        if (answer.isCompleted) return;
        final data = event.data.dartify();
        if (data is! Map) return;
        final number = data['aityx'];
        if (number is! num || number.toInt() != 1) return;
        if (data['type'] != 'answer' || data['id'] != id) return;
        final status = data['status'];
        final text = data['body'];
        stop();
        answer.complete((
          status: status is num ? status.toInt() : 0,
          body: text is String ? text : '',
        ));
      }).toJS;
  web.window.addEventListener('message', listener);
  parent.postMessage(
    {'aityx': 1, 'type': 'call', 'id': id, 'body': body}.jsify(),
    '*'.toJS,
  );
  return answer.future.timeout(
    timeout,
    onTimeout: () {
      stop();
      return (status: 0, body: '');
    },
  );
}
