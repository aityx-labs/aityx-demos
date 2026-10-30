import 'dart:io';

import 'package:pokerface_api/aityx_check.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('https://api.aityx.ai');

  test('a 400 invalid_request means aityx accepts the key', () {
    final answer = classifyAnswer(
      url,
      400,
      '{"code": "invalid_request", "detail": "state is required"}',
    );
    expect(answer, {
      'key': true,
      'ok': true,
      'url': 'https://api.aityx.ai',
      'detail': 'aityx accepts the key',
    });
  });

  test('a 401 says so, with aityx\'s detail', () {
    final answer = classifyAnswer(
      url,
      401,
      '{"code": "unauthorized", "detail": "invalid API key"}',
    );
    expect(answer['ok'], false);
    expect(answer['detail'], 'aityx answered HTTP 401: invalid API key');
  });

  test('a redirect names where it goes', () {
    final answer = classifyAnswer(
      Uri.parse('https://api-stage.aityx.ai'),
      302,
      '',
      location: 'https://aletyx.cloudflareaccess.com/cdn-cgi/access/login',
    );
    expect(answer['ok'], false);
    expect(answer['url'], 'https://api-stage.aityx.ai');
    expect(
      answer['detail'],
      'aityx answered HTTP 302, a redirect to aletyx.cloudflareaccess.com: '
      'AITYX_URL may be behind a login',
    );
  });

  test('an answer that is not JSON gives the status alone', () {
    expect(
      classifyAnswer(url, 502, '<html>')['detail'],
      'aityx answered HTTP 502',
    );
  });

  test('no key answers without calling aityx', () async {
    final check = AityxCheck('', url, HttpClient());
    expect(await check.status(), noKey);
  });
}
