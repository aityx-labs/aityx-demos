import 'package:mortgagehub_api/aityx_status.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('https://api.aityx.ai');

  test('a 400 invalid_request means aityx accepts the key', () {
    final answer = classify(url, 400, '{"code":"invalid_request"}');
    expect(answer, {
      'key': true,
      'ok': true,
      'url': 'https://api.aityx.ai',
      'detail': 'aityx accepts the key',
    });
  });

  test('a 401 says so, with aityx\'s detail', () {
    final answer = classify(url, 401, '{"detail":"invalid API key"}');
    expect(answer['ok'], isFalse);
    expect(answer['detail'], 'aityx answered HTTP 401: invalid API key');
  });

  test('a redirect names where it goes', () {
    final answer = classify(
      url,
      302,
      '',
      location: 'https://login.example.com/access?x=1',
    );
    expect(answer['ok'], isFalse);
    expect(
      answer['detail'],
      'aityx answered HTTP 302, a redirect to login.example.com: '
      'AITYX_URL may be behind a login',
    );
  });

  test('no key: says so', () {
    expect(noKey, {
      'key': false,
      'ok': false,
      'detail': 'AITYX_API_KEY is not set',
    });
  });
}
