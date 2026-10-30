import 'dart:convert';
import 'dart:io';

import 'package:contacthub_api/aityx_check.dart';
import 'package:test/test.dart';

void main() {
  group('classifyAityx', () {
    test('400 invalid_request means aityx accepts the key', () {
      expect(classifyAityx(400, '{"code": "invalid_request"}'), {
        'ok': true,
        'detail': 'aityx accepts the key',
      });
    });

    test('another answer says what aityx answered', () {
      expect(classifyAityx(401, '{"detail": "invalid API key"}'), {
        'ok': false,
        'detail': 'aityx answered HTTP 401: invalid API key',
      });
      expect(classifyAityx(500, 'oops')['detail'], 'aityx answered HTTP 500');
    });

    test('a redirect names its host, as a login', () {
      expect(
        classifyAityx(
          302,
          '',
          location: 'https://login.example.com/access?x=1',
        )['detail'],
        'aityx answered HTTP 302, a redirect to login.example.com: '
        'AITYX_URL may be behind a login',
      );
    });
  });

  group('AityxCheck', () {
    late HttpServer aityx;
    late int calls;
    String? authorization;

    setUp(() async {
      calls = 0;
      aityx = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      aityx.listen((request) async {
        calls++;
        authorization = request.headers.value('authorization');
        await request.drain<void>();
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'code': 'invalid_request'}));
        await request.response.close();
      });
    });

    tearDown(() => aityx.close(force: true));

    Uri url() => Uri.parse('http://127.0.0.1:${aityx.port}');

    test('without a key, says so without calling aityx', () async {
      final status = await AityxCheck('', url()).status();
      expect(status, {
        'key': false,
        'ok': false,
        'detail': 'AITYX_API_KEY is not set',
      });
      expect(calls, 0);
    });

    test('with a key aityx accepts, is ok and never shows the key', () async {
      final status = await AityxCheck('secret-key', url()).status();
      expect(status['key'], true);
      expect(status['ok'], true);
      expect(status['url'], url().origin);
      expect(authorization, 'Bearer secret-key');
      expect(jsonEncode(status), isNot(contains('secret-key')));
    });

    test('checks aityx at most once a minute', () async {
      final check = AityxCheck('secret-key', url());
      await Future.wait([check.status(), check.status()]);
      await check.status();
      expect(calls, 1);
    });

    test('when aityx does not answer, says so', () async {
      final gone = url();
      await aityx.close(force: true);
      final status = await AityxCheck('secret-key', gone).status();
      expect(status['ok'], false);
      expect(status['detail'], startsWith('aityx did not answer: '));
    });
  });
}
