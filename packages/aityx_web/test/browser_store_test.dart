@TestOn('browser')
library;

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// The browser store over the real localStorage and sessionStorage, as
/// the index page writes them: `flutter test --platform chrome`.
void main() {
  setUp(() {
    web.window.localStorage.clear();
    web.window.sessionStorage.clear();
  });

  test('reads what the index page wrote, session first', () {
    web.window.localStorage.setItem('aityx.key', 'sk-device');
    web.window.localStorage.setItem('aityx.url', 'https://x.example');
    final store = AityxKeyStore.browser();
    expect(store.key, 'sk-device');
    expect(store.url, 'https://x.example');
    expect(store.sessionOnly, isFalse);
    web.window.sessionStorage.setItem('aityx.key', 'sk-session');
    expect(store.key, 'sk-session');
    expect(store.url, isNull);
    expect(store.sessionOnly, isTrue);
  });

  test('saves and forgets in the real storages', () async {
    final store = AityxKeyStore.browser();
    var changes = 0;
    final subscription = store.changes.listen((_) => changes++);
    store.save('sk-1', sessionOnly: true);
    expect(web.window.sessionStorage.getItem('aityx.key'), 'sk-1');
    expect(web.window.localStorage.getItem('aityx.key'), isNull);
    store.save('sk-2', url: 'https://x.example');
    expect(web.window.localStorage.getItem('aityx.key'), 'sk-2');
    expect(web.window.localStorage.getItem('aityx.url'), 'https://x.example');
    expect(web.window.sessionStorage.getItem('aityx.key'), isNull);
    store.forget();
    expect(web.window.localStorage.getItem('aityx.key'), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(changes, 3);
    await subscription.cancel();
  });

  test('passes on the storage event from another tab', () async {
    final store = AityxKeyStore.browser();
    final change = store.changes.first;
    web.window.dispatchEvent(
      web.StorageEvent('storage', web.StorageEventInit(key: 'aityx.key')),
    );
    await change.timeout(const Duration(seconds: 2));
  });

  test('ignores the storage event for other entries', () async {
    final store = AityxKeyStore.browser();
    var changes = 0;
    final subscription = store.changes.listen((_) => changes++);
    web.window.dispatchEvent(
      web.StorageEvent('storage', web.StorageEventInit(key: 'other')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(changes, 0);
    await subscription.cancel();
  });
}
