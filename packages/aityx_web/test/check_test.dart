import 'dart:async';
import 'dart:convert';

import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final user = AityxConnection.user('sk-test');
final dev = AityxConnection.dev(
  Uri.parse('http://localhost:8800/'),
  url: 'https://api.aityx.ai',
  devKeyFrom: '.env',
);

void main() {
  group('classifyAityx', () {
    // status, body, connection → kind, tooltip
    final table = <(int, String, AityxConnection, AityxStateKind, String)>[
      (
        400,
        '{"code":"invalid_request","detail":"state is required"}',
        user,
        AityxStateKind.ready,
        'aityx: ready (your key, https://api.aityx.ai)',
      ),
      (
        400,
        '{"code":"invalid_request"}',
        dev,
        AityxStateKind.ready,
        'aityx: ready (dev key from .env, https://api.aityx.ai)',
      ),
      (
        401,
        '{"code":"unauthorized","detail":"invalid API key"}',
        user,
        AityxStateKind.rejected,
        'aityx: key rejected — aityx answered HTTP 401: invalid API key: '
            'set a new key on the index page',
      ),
      (
        403,
        '',
        user,
        AityxStateKind.rejected,
        'aityx: key rejected — aityx answered HTTP 403: '
            'set a new key on the index page',
      ),
      (
        401,
        '{"detail":"invalid API key"}',
        dev,
        AityxStateKind.rejected,
        'aityx: key rejected — the dev key from .env got HTTP 401: '
            'invalid API key',
      ),
      (
        502,
        '{"code":"proxy_unreachable","detail":"aityx did not answer: SocketException"}',
        dev,
        AityxStateKind.unreachable,
        'aityx: not reachable — aityx did not answer: SocketException',
      ),
      (
        502,
        '{"code":"proxy_redirect","detail":"AITYX_URL redirected to login.example: it may be behind a login"}',
        dev,
        AityxStateKind.unreachable,
        'aityx: not reachable — AITYX_URL redirected to login.example: '
            'it may be behind a login',
      ),
      (
        502,
        '<html>Bad gateway</html>',
        user,
        AityxStateKind.failing,
        'aityx: not working — aityx answered HTTP 502',
      ),
      (
        400,
        '{"code":"something_else","detail":"nope"}',
        user,
        AityxStateKind.failing,
        'aityx: not working — aityx answered HTTP 400: nope',
      ),
      (
        400,
        'not json',
        user,
        AityxStateKind.failing,
        'aityx: not working — aityx answered HTTP 400',
      ),
      (
        200,
        '{}',
        user,
        AityxStateKind.failing,
        'aityx: not working — aityx answered HTTP 200',
      ),
      (
        302,
        '',
        user,
        AityxStateKind.failing,
        'aityx: not working — aityx answered HTTP 302, a redirect: '
            'it may be behind a login',
      ),
      (
        500,
        '{"detail":"boom"}',
        user,
        AityxStateKind.failing,
        'aityx: not working — aityx answered HTTP 500: boom',
      ),
      (
        400,
        '{"code":"invalid_request"}',
        AityxConnection.none,
        AityxStateKind.noKey,
        'aityx: no key — set yours on the index page',
      ),
    ];
    for (final (status, body, connection, kind, tooltip) in table) {
      test('$status $body (${connection.source.name})', () {
        final state = classifyAityx(
          status: status,
          body: body,
          connection: connection,
        );
        expect(state.kind, kind);
        expect(state.ok, kind == AityxStateKind.ready);
        expect(state.key, kind != AityxStateKind.noKey);
        expect(state.source, connection.source);
        expect(state.tooltip, tooltip);
        expect(state.toString(), tooltip);
      });
    }

    test('ready in dev mode without a URL in the config', () {
      final state = classifyAityx(
        status: 400,
        body: '{"code":"invalid_request"}',
        connection: AityxConnection.dev(
          Uri.parse('http://localhost:8800/'),
          devKeyFrom: 'environment',
        ),
      );
      expect(state.tooltip, 'aityx: ready (dev key from the environment)');
    });
  });

  group('checkAityx', () {
    test('POSTs {} with the key and classifies the answer', () async {
      late http.Request sent;
      final state = await checkAityx(
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode({'code': 'invalid_request'}), 400);
        }),
        connection: user,
      );
      expect(sent.method, 'POST');
      expect(sent.url, Uri.parse('https://api.aityx.ai/v1/systemone'));
      expect(sent.body, '{}');
      expect(sent.headers['Authorization'], 'Bearer sk-test');
      expect(state.ok, isTrue);
      expect(state.url, 'https://api.aityx.ai');
    });

    test('resolves the connection: dev proxy, no Authorization', () async {
      final log = <String>[];
      final state = await checkAityx(
        client: MockClient((request) async {
          log.add('${request.method} ${request.url.path}');
          expect(request.headers.containsKey('Authorization'), isFalse);
          if (request.url.path == '/aityx/config') {
            return http.Response(
              jsonEncode({
                'available': true,
                'url': 'https://api.aityx.ai',
                'source': '.env',
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'code': 'invalid_request'}), 400);
        }),
        store: AityxKeyStore.memory(),
        origin: Uri.parse('http://localhost:8800/cellfie/'),
      );
      expect(log, ['GET /aityx/config', 'POST /aityx/v1/systemone']);
      expect(state.ok, isTrue);
      expect(state.source, AityxSource.dev);
      expect(
        state.tooltip,
        'aityx: ready (dev key from .env, https://api.aityx.ai)',
      );
    });

    test('no key: says so, without calling aityx', () async {
      var calls = 0;
      final state = await checkAityx(
        client: MockClient((request) async {
          calls++;
          return http.Response('Not found', 404);
        }),
        store: AityxKeyStore.memory(),
        origin: Uri.parse('http://localhost:8800/cellfie/'),
      );
      expect(calls, 1); // only /aityx/config
      expect(state.kind, AityxStateKind.noKey);
      expect(state.key, isFalse);
      expect(state.url, isNull);
      expect(state.tooltip, 'aityx: no key — set yours on the index page');
    });

    test('no answer: not reachable', () async {
      final state = await checkAityx(
        client: MockClient(
          (request) async =>
              throw http.ClientException('XMLHttpRequest error.'),
        ),
        connection: user,
      );
      expect(state.kind, AityxStateKind.unreachable);
      expect(state.key, isTrue);
      expect(
        state.tooltip,
        'aityx: not reachable — no answer from https://api.aityx.ai '
        '(network, CORS or a blocker)',
      );
    });

    test('no answer from the dev proxy names it', () async {
      final state = await checkAityx(
        client: MockClient((request) async => throw http.ClientException('x')),
        connection: dev,
      );
      expect(
        state.detail,
        contains('the dev proxy (http://localhost:8800/aityx/)'),
      );
    });

    test('a timeout: not reachable, saying so', () async {
      final never = Completer<http.Response>();
      final state = await checkAityx(
        client: MockClient((request) => never.future),
        connection: user,
        timeout: const Duration(milliseconds: 20),
      );
      expect(state.kind, AityxStateKind.unreachable);
      expect(state.detail, 'no answer from https://api.aityx.ai in 20 ms');
    });
  });
}
