import 'package:flutter_test/flutter_test.dart';
import 'package:riverrace_app/strategy/decide.dart';

void main() {
  final page = Uri.parse('https://x-8940.app.github.dev/app/#/');

  test('API_BASE_URL wins, on the web and native', () {
    for (final web in [true, false]) {
      expect(
        decideUrl('http://10.0.2.2:8941', web: web, page: page).toString(),
        'http://10.0.2.2:8941/api/decide',
      );
    }
  });

  test('without it, the web app calls its own origin', () {
    expect(
      decideUrl('', web: true, page: page).toString(),
      'https://x-8940.app.github.dev/api/decide',
    );
  });

  test('without it, a native app calls the local API, not a file', () {
    final url = decideUrl('', web: false, page: Uri.parse('file:///app/'));
    expect(url.toString(), '$nativeApi/api/decide');
    expect(url.scheme, 'http');
  });
}
