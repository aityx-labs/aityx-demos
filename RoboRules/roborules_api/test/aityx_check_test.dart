import 'package:roborules_api/aityx_check.dart';
import 'package:test/test.dart';

void main() {
  const url = 'https://api.aityx.ai';

  test('no key: nothing to ask', () {
    expect(noKey, {
      'key': false,
      'ok': false,
      'detail': 'AITYX_API_KEY is not set',
    });
  });

  test('400 invalid_request: aityx accepts the key', () {
    final status = aityxStatus(
      url: url,
      status: 400,
      body: '{"code": "invalid_request", "detail": "state is required"}',
    );
    expect(status, {
      'key': true,
      'ok': true,
      'url': url,
      'detail': 'aityx accepts the key',
    });
  });

  test('401: not working, with aityx\'s detail', () {
    final status = aityxStatus(
      url: url,
      status: 401,
      body: '{"detail": "invalid API key"}',
    );
    expect(status['ok'], false);
    expect(status['key'], true);
    expect(status['detail'], 'aityx answered HTTP 401: invalid API key');
  });

  test('a redirect: AITYX_URL may be behind a login', () {
    final status = aityxStatus(
      url: 'https://api-stage.aityx.ai',
      status: 302,
      body: '',
      location: 'https://aletyx.cloudflareaccess.com/cdn-cgi/access/login',
    );
    expect(status['ok'], false);
    expect(
      status['detail'],
      'aityx answered HTTP 302, a redirect to aletyx.cloudflareaccess.com: '
      'AITYX_URL may be behind a login',
    );
  });

  test('another 400, or a body that is not JSON, is not ok', () {
    expect(
      aityxStatus(url: url, status: 400, body: '{"code": "other"}')['ok'],
      false,
    );
    expect(
      aityxStatus(url: url, status: 500, body: 'oops')['detail'],
      'aityx answered HTTP 500',
    );
  });

  test('no answer', () {
    final status = aityxUnreachable(url, const FormatException());
    expect(status['ok'], false);
    expect(status['detail'], 'aityx did not answer: FormatException');
  });
}
