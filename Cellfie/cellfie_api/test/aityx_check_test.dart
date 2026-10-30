import 'package:cellfie_api/aityx_check.dart';
import 'package:test/test.dart';

void main() {
  test('a 400 invalid_request means aityx accepts the key', () {
    expect(
      classifyAityxAnswer(400, '{"code": "invalid_request", "detail": "x"}'),
      {'ok': true, 'detail': 'aityx accepts the key'},
    );
  });

  test('a 401 is not working, with aityx\'s detail', () {
    expect(
      classifyAityxAnswer(401, '{"detail": "invalid API key"}'),
      {'ok': false, 'detail': 'aityx answered HTTP 401: invalid API key'},
    );
  });

  test('a 400 of another kind is not working', () {
    expect(classifyAityxAnswer(400, 'oops')['ok'], false);
  });

  test('a redirect names where it leads', () {
    final status = classifyAityxAnswer(
      302,
      '',
      location: 'https://login.example.com/access?x=1',
    );
    expect(status['ok'], false);
    expect(
      status['detail'],
      'aityx answered HTTP 302, a redirect to login.example.com: '
      'AITYX_URL may be behind a login',
    );
  });

  test('without a key, it says so without calling aityx', () async {
    final check = AityxCheck('', Uri.parse('https://api.aityx.ai'));
    expect(await check.status(), {
      'key': false,
      'ok': false,
      'detail': 'AITYX_API_KEY is not set',
    });
  });

  test('a URL that is not https is refused before any call', () async {
    final check = AityxCheck('k', Uri.parse('http://api.aityx.ai'));
    final status = await check.status();
    expect(status['ok'], false);
    expect(status['detail'], 'AITYX_URL must be an https URL');
    expect(status.containsKey('url'), false);
  });

  test('the answer never holds the key', () async {
    final check = AityxCheck('secret-key', Uri.parse('http://localhost'));
    expect((await check.status()).values, isNot(contains('secret-key')));
  });
}
