/// Off the web (the VM in tests, native builds): the key lives in memory,
/// and there's no index page to open.
library;

import '../key_store.dart';

final _store = AityxKeyStore.memory();

/// The one in-memory store, so every part of the app sees the same key.
AityxKeyStore browserKeyStore() => _store;

/// Opens [page] in the same tab: nothing to open off the web.
void openPage(Uri page) {}

/// Off the web the app is never inside another page.
bool embedded() => false;

/// No page around the app to post to.
void postToParent(String message) {}
