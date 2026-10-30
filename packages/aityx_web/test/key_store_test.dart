import 'dart:async';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';

/// A storage that throws, like a browser that blocks it.
class BlockedArea implements StorageArea {
  @override
  String? read(String name) => throw StateError('blocked');

  @override
  void write(String name, String value) => throw StateError('blocked');

  @override
  void remove(String name) => throw StateError('blocked');
}

void main() {
  group('the memory store', () {
    test('starts empty', () {
      final store = AityxKeyStore.memory();
      expect(store.key, isNull);
      expect(store.url, isNull);
      expect(store.sessionOnly, isFalse);
    });

    test('remembers on this device', () {
      final store = AityxKeyStore.memory() as StorageKeyStore;
      store.save('  sk-1  ', url: 'https://x.example/');
      expect(store.key, 'sk-1');
      expect(store.url, 'https://x.example');
      expect(store.sessionOnly, isFalse);
      expect((store.local as MapArea).entries, {
        'aityx.key': 'sk-1',
        'aityx.url': 'https://x.example',
      });
      expect((store.session as MapArea).entries, isEmpty);
    });

    test('only this session, clearing the device key', () {
      final store =
          AityxKeyStore.memory(local: {'aityx.key': 'old'}) as StorageKeyStore;
      store.save('sk-2', sessionOnly: true);
      expect(store.key, 'sk-2');
      expect(store.sessionOnly, isTrue);
      expect((store.local as MapArea).entries, isEmpty);
      expect((store.session as MapArea).entries, {'aityx.key': 'sk-2'});
    });

    test('the default URL, or none, is not stored', () {
      final store = AityxKeyStore.memory() as StorageKeyStore;
      store.save('sk', url: 'https://x.example');
      store.save('sk', url: aityxDefaultUrl);
      expect(store.url, isNull);
      store.save('sk', url: '  ');
      expect((store.local as MapArea).entries, {'aityx.key': 'sk'});
    });

    test('sessionStorage beats localStorage', () {
      final store = AityxKeyStore.memory(
        local: {'aityx.key': 'local-key', 'aityx.url': 'https://local.example'},
        session: {'aityx.key': 'session-key'},
      );
      expect(store.key, 'session-key');
      expect(store.sessionOnly, isTrue);
      // The URL comes with the key: none in session, so the default.
      expect(store.url, isNull);
    });

    test('the URL comes from the storage that holds the key', () {
      final store = AityxKeyStore.memory(
        local: {'aityx.key': 'local-key', 'aityx.url': 'https://local.example'},
        session: {'aityx.url': 'https://session.example'},
      );
      expect(store.key, 'local-key');
      expect(store.url, 'https://local.example');
    });

    test('blank entries are no key', () {
      final store = AityxKeyStore.memory(
        local: {'aityx.key': 'local-key'},
        session: {'aityx.key': '   '},
      );
      expect(store.key, 'local-key');
      expect(store.sessionOnly, isFalse);
    });

    test('forgets both', () {
      final store = AityxKeyStore.memory(
        local: {'aityx.key': 'a', 'aityx.url': 'https://a.example'},
        session: {'aityx.key': 'b'},
      );
      store.forget();
      expect(store.key, isNull);
      expect(store.url, isNull);
    });

    test('refuses an empty key', () {
      expect(() => AityxKeyStore.memory().save('  '), throwsArgumentError);
    });

    test('says when it changes', () async {
      final store = AityxKeyStore.memory();
      var changes = 0;
      final subscription = store.changes.listen((_) => changes++);
      store.save('sk');
      store.forget();
      await Future<void>.delayed(Duration.zero);
      expect(changes, 2);
      await subscription.cancel();
    });
  });

  test('passes on changes from elsewhere (the storage event)', () async {
    final external = StreamController<void>.broadcast();
    final store = StorageKeyStore(
      MapArea(),
      MapArea(),
      external: external.stream,
    );
    var changes = 0;
    final subscription = store.changes.listen((_) => changes++);
    external.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(changes, 1);
    await subscription.cancel();
    expect(external.hasListener, isFalse);
    await external.close();
  });

  test('blocked storage means no key, not an error', () {
    final store = StorageKeyStore(BlockedArea(), BlockedArea());
    expect(store.key, isNull);
    expect(store.url, isNull);
    expect(store.sessionOnly, isFalse);
    store.save('sk');
    store.forget();
    expect(store.key, isNull);
  });

  test(
    'off the web, the browser store is one shared memory store',
    testOn: 'vm',
    () {
      final store = AityxKeyStore.browser();
      expect(identical(store, AityxKeyStore.browser()), isTrue);
      store.save('sk');
      expect(AityxKeyStore.browser().key, 'sk');
      store.forget();
    },
  );
}
