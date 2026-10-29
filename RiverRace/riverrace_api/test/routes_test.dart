import 'package:riverrace_api/routes.dart';
import 'package:test/test.dart';

void main() {
  test('the root redirects to the app', () {
    final answer = route('GET', '/');
    expect(answer.status, 302);
    expect(answer.location, '/app/');
  });

  test('health answers ok, and whether the key is set', () {
    final without = route('GET', '/api/health');
    expect(without.status, 200);
    expect(without.body, {'ok': true, 'aityx': false});

    final withKey = route('GET', '/api/health', aityx: true);
    expect(withKey.body, {'ok': true, 'aityx': true});
  });

  test('a preflight answers 204', () {
    expect(route('OPTIONS', '/api/health').status, 204);
  });

  test('anything else is not found', () {
    expect(route('GET', '/api/nothing').status, 404);
    expect(route('POST', '/api/health').status, 404);
    expect(route('GET', '/api/hello').status, 404);
  });

  group('a call that spends the key', () {
    const origins = {'http://localhost:8940'};
    Answer? check({String? origin, String? site, String? type}) => refusal(
      origin: origin,
      fetchSite: site,
      mimeType: type,
      origins: origins,
    );

    test('goes ahead from the app, an allowed origin, or no browser', () {
      expect(
        check(origin: 'http://localhost:8940', type: 'application/json'),
        isNull,
      );
      // Behind a forwarded port: another host, but the browser says
      // same-origin.
      expect(
        check(
          origin: 'https://x-8940.app.github.dev',
          site: 'same-origin',
          type: 'application/json',
        ),
        isNull,
      );
      expect(check(type: 'application/json'), isNull);
    });

    test('is refused from another site, even as text/plain', () {
      for (final type in ['application/json', 'text/plain']) {
        final answer = check(
          origin: 'https://evil.example',
          site: 'cross-site',
          type: type,
        );
        expect(answer?.status, 403, reason: type);
      }
    });

    test('is refused without a JSON body', () {
      expect(
        check(origin: 'http://localhost:8940', type: 'text/plain')?.status,
        415,
      );
      expect(check()?.status, 415);
    });
  });
}
