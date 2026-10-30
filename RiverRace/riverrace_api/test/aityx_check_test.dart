import 'dart:io';

import 'package:riverrace_api/aityx_check.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('https://api.aityx.ai');

  test('without a key, no call and the reason', () async {
    expect(aityxStatus(key: false), {
      'key': false,
      'ok': false,
      'detail': 'AITYX_API_KEY is not set',
    });
    final check = AityxCheck('', url, HttpClient());
    expect((await check.status())['key'], false);
  });

  test('400 invalid_request means aityx accepts the key', () {
    final status = aityxStatus(
      key: true,
      url: url,
      status: 400,
      body: '{"code": "invalid_request", "detail": "state is required"}',
    );
    expect(status, {
      'key': true,
      'ok': true,
      'url': 'https://api.aityx.ai',
      'detail': 'aityx accepts the key',
    });
  });

  test('a refused key says what aityx answered', () {
    final status = aityxStatus(
      key: true,
      url: url,
      status: 401,
      body: '{"detail": "invalid API key"}',
    );
    expect(status['ok'], false);
    expect(status['detail'], 'aityx answered HTTP 401: invalid API key');
  });

  test('a redirect names where it leads', () {
    final status = aityxStatus(
      key: true,
      url: Uri.parse('https://api-stage.aityx.ai'),
      status: 302,
      body: '',
      location: 'https://aletyx.cloudflareaccess.com/cdn-cgi/access/login/x',
    );
    expect(status['ok'], false);
    expect(
      status['detail'],
      'aityx answered HTTP 302, a redirect to aletyx.cloudflareaccess.com: '
      'AITYX_URL may be behind a login',
    );
  });

  test('no answer names the error, and the key is never in the result', () {
    final status = aityxStatus(
      key: true,
      url: url,
      error: const SocketException('down'),
    );
    expect(status['detail'], 'aityx did not answer: SocketException');
    expect(status.containsKey('key') && status['key'] == true, isTrue);
    expect(status.values.whereType<String>().join(), isNot(contains('Bearer')));
  });

  test('a URL that is not https is refused', () {
    final status = aityxStatus(key: true, url: Uri.parse('http://x'));
    expect(status['detail'], 'AITYX_URL must be an https URL');
  });
}
