import 'package:aityx_web/aityx_web.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('systemone', () {
    test('on the default aityx', () {
      expect(
        AityxConnection.user('k').systemone,
        Uri.parse('https://api.aityx.ai/v1/systemone'),
      );
    });

    test('with a trailing slash, or a path, in the user URL', () {
      expect(
        AityxConnection.user('k', url: 'https://x.example/').systemone,
        Uri.parse('https://x.example/v1/systemone'),
      );
      expect(
        AityxConnection.user('k', url: 'https://x.example/base').systemone,
        Uri.parse('https://x.example/base/v1/systemone'),
      );
    });

    test('through the dev proxy, at the origin root whatever the page', () {
      final dev = AityxConnection.dev(
        Uri.parse('http://localhost:8800/mortgagehub/index.html'),
      );
      expect(dev.endpoint, Uri.parse('http://localhost:8800/aityx/'));
      expect(
        dev.systemone,
        Uri.parse('http://localhost:8800/aityx/v1/systemone'),
      );
    });

    test('with an endpoint without the trailing slash', () {
      final connection = AityxConnection(
        endpoint: Uri.parse('http://localhost:8800/aityx'),
        source: AityxSource.dev,
        url: '',
      );
      expect(
        connection.systemone,
        Uri.parse('http://localhost:8800/aityx/v1/systemone'),
      );
    });
  });

  group('headers', () {
    test('the user key goes in Authorization', () {
      expect(AityxConnection.user('sk-test').headers(), {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer sk-test',
      });
    });

    test('no Authorization in dev mode: the proxy adds the key', () {
      final dev = AityxConnection.dev(Uri.parse('http://localhost:8800/'));
      expect(dev.key, isNull);
      expect(dev.headers(), {'Content-Type': 'application/json'});
    });

    test('without Content-Type when not JSON', () {
      expect(AityxConnection.user('sk-test').headers(json: false), {
        'Authorization': 'Bearer sk-test',
      });
      expect(AityxConnection.none.headers(json: false), isEmpty);
    });
  });

  test('whose key, for people', () {
    final origin = Uri.parse('http://localhost:8800/');
    expect(AityxConnection.user('k').whose, 'your key');
    expect(
      AityxConnection.dev(origin, devKeyFrom: '.env').whose,
      'dev key from .env',
    );
    expect(
      AityxConnection.dev(origin, devKeyFrom: 'environment').whose,
      'dev key from the environment',
    );
    expect(AityxConnection.dev(origin).whose, 'dev key');
    expect(AityxConnection.none.whose, 'no key');
  });

  test('toString never shows the key', () {
    expect(
      AityxConnection.user('sk-secret').toString(),
      isNot(contains('sk-secret')),
    );
  });

  group('normalizeAityxUrl', () {
    test('defaults when empty or not an http(s) URL', () {
      for (final url in [
        null,
        '',
        '  ',
        'api.aityx.ai',
        'ftp://x',
        'https://',
      ]) {
        expect(normalizeAityxUrl(url), aityxDefaultUrl, reason: '$url');
      }
    });

    test('trims, and drops trailing slashes', () {
      expect(normalizeAityxUrl(' https://x.example// '), 'https://x.example');
      expect(
        normalizeAityxUrl('http://localhost:9000'),
        'http://localhost:9000',
      );
    });

    test('the user connection uses it', () {
      expect(AityxConnection.user('k', url: 'nonsense').url, aityxDefaultUrl);
      expect(
        AityxConnection.user('k', url: 'https://x.example/').url,
        'https://x.example',
      );
    });
  });
}
