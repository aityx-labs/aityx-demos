import 'dart:async';
import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final origin = Uri.parse('http://localhost:8800/riverrace/');

void main() {
  group('systemone', () {
    test("POSTs the body with the user's key, and answers timed", () async {
      late http.Request sent;
      final client = AityxClient(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{"decision":"approve"}', 200);
        }),
        connection: AityxConnection.user('sk-test'),
      );
      final answer = await client.systemone({'state': 1});
      expect(sent.method, 'POST');
      expect(sent.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
      expect(sent.headers['Authorization'], 'Bearer sk-test');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), {'state': 1});
      expect(answer.status, 200);
      expect(answer.ok, isTrue);
      expect(answer.json, {'decision': 'approve'});
      expect(answer.text, '{"decision":"approve"}');
      expect(answer.took, greaterThanOrEqualTo(Duration.zero));
      expect(answer.problem, isNull);
    });

    test('sends a string body as it is', () async {
      late String body;
      final client = AityxClient(
        client: MockClient((request) async {
          body = request.body;
          return http.Response('{}', 200);
        }),
        connection: AityxConnection.user('sk'),
      );
      await client.systemone('{"a": 1}');
      expect(body, '{"a": 1}');
    });

    test('dev mode: the proxy, without Authorization', () async {
      late http.Request sent;
      final client = AityxClient(
        client: MockClient((request) async {
          sent = request;
          return http.Response('{}', 200);
        }),
        connection: AityxConnection.dev(origin),
      );
      await client.systemone({});
      expect(sent.url, Uri.parse('http://localhost:8800/aityx/v1/systemone'));
      expect(sent.headers.containsKey('Authorization'), isFalse);
    });

    test('reads the body as UTF-8 without a charset', () async {
      final client = AityxClient(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode('{"name":"Zoë — ok"}'),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
        connection: AityxConnection.user('sk'),
      );
      final answer = await client.systemone({});
      expect(answer.json, {'name': 'Zoë — ok'});
    });

    test('answers errors too, with the problem in words', () async {
      Future<AityxAnswer> answering(int status, String body) => AityxClient(
        client: MockClient((request) async => http.Response(body, status)),
        connection: AityxConnection.user('sk'),
      ).systemone({});

      final rejected = await answering(401, '{"detail":"bad key"}');
      expect(rejected.ok, isFalse);
      expect(rejected.problem, 'aityx rejected the key');
      expect((await answering(403, '')).problem, 'aityx rejected the key');

      final invalid = await answering(
        400,
        '{"code":"invalid_request","detail":"state is required"}',
      );
      expect(invalid.code, 'invalid_request');
      expect(invalid.detail, 'state is required');
      expect(invalid.problem, 'aityx answered HTTP 400: state is required');

      final html = await answering(500, '<html>oops</html>');
      expect(html.json, isNull);
      expect(html.text, '<html>oops</html>');
      expect(html.detail, isNull);
      expect(html.problem, 'aityx answered HTTP 500');

      final proxy = await answering(
        502,
        '{"code":"proxy_unreachable","detail":"aityx did not answer: SocketException"}',
      );
      expect(
        proxy.problem,
        'aityx answered HTTP 502: aityx did not answer: SocketException',
      );
    });

    test('without a key: AityxNoKey, and no request', () async {
      var calls = 0;
      final client = AityxClient(
        client: MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
        connection: AityxConnection.none,
      );
      await expectLater(
        client.systemone({}),
        throwsA(
          isA<AityxNoKey>().having(
            (e) => e.toString(),
            'message',
            'aityx is not set up: set your key on the index page',
          ),
        ),
      );
      expect(calls, 0);
    });

    test('no answer (network, CORS): AityxUnreachable', () async {
      final client = AityxClient(
        client: MockClient(
          (request) async =>
              throw http.ClientException('XMLHttpRequest error.'),
        ),
        connection: AityxConnection.user('sk'),
      );
      await expectLater(
        client.systemone({}),
        throwsA(
          isA<AityxUnreachable>()
              .having((e) => e.toString(), 'message', 'aityx did not answer')
              .having((e) => e.cause, 'cause', 'ClientException'),
        ),
      );
    });

    test('a timeout: AityxUnreachable, saying so', () async {
      final never = Completer<http.Response>();
      final client = AityxClient(
        client: MockClient((request) => never.future),
        connection: AityxConnection.user('sk'),
      );
      await expectLater(
        client.systemone({}, timeout: const Duration(milliseconds: 20)),
        throwsA(
          isA<AityxUnreachable>().having(
            (e) => e.cause,
            'cause',
            'timed out after 20 ms',
          ),
        ),
      );
    });
  });

  group('the connection, resolved lazily', () {
    /// A client that counts /aityx/config asks and answers systemone.
    MockClient server(List<String> log, {bool dev = true}) => MockClient((
      request,
    ) async {
      log.add('${request.method} ${request.url}');
      if (request.url.path == '/aityx/config') {
        return http.Response(
          jsonEncode(
            dev
                ? {'available': true, 'url': aityxDefaultUrl, 'source': '.env'}
                : {'available': false},
          ),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    test('asks /aityx/config once, then keeps the dev connection', () async {
      final log = <String>[];
      final client = AityxClient(
        client: server(log),
        store: AityxKeyStore.memory(),
        origin: origin,
      );
      await client.systemone({});
      await client.systemone({});
      expect(log, [
        'GET http://localhost:8800/aityx/config',
        'POST http://localhost:8800/aityx/v1/systemone',
        'POST http://localhost:8800/aityx/v1/systemone',
      ]);
      expect((await client.connection()).source, AityxSource.dev);
    });

    test('concurrent calls share one resolution', () async {
      final log = <String>[];
      final client = AityxClient(
        client: server(log),
        store: AityxKeyStore.memory(),
        origin: origin,
      );
      await Future.wait([client.connection(), client.connection()]);
      expect(log, ['GET http://localhost:8800/aityx/config']);
    });

    test('switches to the user key once it is saved, and back', () async {
      final log = <String>[];
      final store = AityxKeyStore.memory();
      final client = AityxClient(
        client: server(log),
        store: store,
        origin: origin,
      );
      expect((await client.connection()).source, AityxSource.dev);
      store.save('sk-new', url: 'https://x.example');
      final user = await client.connection();
      expect(user.source, AityxSource.user);
      expect(user.key, 'sk-new');
      expect(user.url, 'https://x.example');
      store.forget();
      expect((await client.connection()).source, AityxSource.dev);
    });

    test('asks again while there is no key', () async {
      final log = <String>[];
      final client = AityxClient(
        client: server(log, dev: false),
        store: AityxKeyStore.memory(),
        origin: origin,
      );
      await expectLater(client.systemone({}), throwsA(isA<AityxNoKey>()));
      await expectLater(client.systemone({}), throwsA(isA<AityxNoKey>()));
      expect(log, [
        'GET http://localhost:8800/aityx/config',
        'GET http://localhost:8800/aityx/config',
      ]);
    });

    test('a given connection is used as it is', () async {
      final fixed = AityxConnection.user('sk');
      final client = AityxClient(
        connection: fixed,
        store: AityxKeyStore.memory(local: {'aityx.key': 'other'}),
      );
      expect(await client.connection(), same(fixed));
      client.close();
    });
  });
}
