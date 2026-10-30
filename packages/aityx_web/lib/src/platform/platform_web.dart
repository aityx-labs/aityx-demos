/// In the browser: localStorage and sessionStorage, the storage event, and
/// navigation, through package:web.
library;

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
