import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final origin = Uri.parse('http://localhost:8800/mortgagehub/');

/// A client whose /aityx/config answers [answer]; [asked] records calls.
MockClient config(http.Response answer, List<Uri> asked) =>
    MockClient((request) async {
      asked.add(request.url);
      return answer;
    });

http.Response jsonAnswer(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

final devConfig = jsonAnswer({
  'available': true,
  'url': 'https://api.aityx.ai',
  'source': '.env',
});

void main() {
  test("the user's key beats the dev key, without asking the server", () async {
    final asked = <Uri>[];
    final connection = await AityxSettings.resolve(
      client: config(devConfig, asked),
      origin: origin,
      store: AityxKeyStore.memory(local: {'aityx.key': 'sk-user'}),
    );
    expect(connection.source, AityxSource.user);
    expect(connection.key, 'sk-user');
    expect(connection.url, aityxDefaultUrl);
    expect(connection.endpoint, Uri.parse(aityxDefaultUrl));
    expect(asked, isEmpty);
  });

  test('the session key beats the device key, with its URL', () async {
    final connection = await AityxSettings.resolve(
      origin: origin,
      store: AityxKeyStore.memory(
        local: {'aityx.key': 'sk-device'},
        session: {'aityx.key': 'sk-session', 'aityx.url': 'https://x.example'},
      ),
    );
    expect(connection.key, 'sk-session');
    expect(connection.url, 'https://x.example');
    expect(connection.systemone, Uri.parse('https://x.example/v1/systemone'));
  });

  test('the dev key, at the root of the origin', () async {
    final asked = <Uri>[];
    final connection = await AityxSettings.resolve(
      client: config(devConfig, asked),
      origin: origin,
      store: AityxKeyStore.memory(),
    );
    expect(asked, [Uri.parse('http://localhost:8800/aityx/config')]);
    expect(connection.source, AityxSource.dev);
    expect(connection.key, isNull);
    expect(connection.url, 'https://api.aityx.ai');
    expect(connection.devKeyFrom, '.env');
    expect(connection.whose, 'dev key from .env');
    expect(
      connection.systemone,
      Uri.parse('http://localhost:8800/aityx/v1/systemone'),
    );
  });

  group('no key', () {
    Future<AityxConnection> resolveWith(http.Response answer) =>
        AityxSettings.resolve(
          client: config(answer, []),
          origin: origin,
          store: AityxKeyStore.memory(),
        );

    test('when the server has none', () async {
      expect(
        (await resolveWith(jsonAnswer({'available': false}))).source,
        AityxSource.none,
      );
    });

    test("on a static host: /aityx/config is a 404", () async {
      expect(
        (await resolveWith(http.Response('Not found', 404))).source,
        AityxSource.none,
      );
    });

    test("on a static host: /aityx/config is the app's index.html", () async {
      expect(
        (await resolveWith(http.Response('<!DOCTYPE html><html></html>', 200)))
            .source,
        AityxSource.none,
      );
    });

    test('when the config is JSON but not an object', () async {
      expect((await resolveWith(jsonAnswer([true]))).source, AityxSource.none);
    });

    test('when the server does not answer', () async {
      final connection = await AityxSettings.resolve(
        client: MockClient((request) async => throw http.ClientException('x')),
        origin: origin,
        store: AityxKeyStore.memory(),
      );
      expect(connection.source, AityxSource.none);
    });

    test('off http(s), without asking', () async {
      final asked = <Uri>[];
      final connection = await AityxSettings.resolve(
        client: config(devConfig, asked),
        origin: Uri.parse('file:///tmp/'),
        store: AityxKeyStore.memory(),
      );
      expect(connection.source, AityxSource.none);
      expect(asked, isEmpty);
    });
  });

  test('a missing url or source in the config', () async {
    final connection = await AityxSettings.resolve(
      client: config(jsonAnswer({'available': true}), []),
      origin: origin,
      store: AityxKeyStore.memory(),
    );
    expect(connection.source, AityxSource.dev);
    expect(connection.url, '');
    expect(connection.devKeyFrom, isNull);
  });

  test(
    'AityxSettings.store is the default store, and a test can set it',
    () async {
      final before = AityxSettings.store;
      try {
        AityxSettings.store = AityxKeyStore.memory(
          local: {'aityx.key': 'sk-t'},
        );
        final connection = await AityxSettings.resolve(origin: origin);
        expect(connection.key, 'sk-t');
      } finally {
        AityxSettings.store = before;
      }
    },
  );
}
