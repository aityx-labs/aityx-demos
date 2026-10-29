import 'package:pokerface_api/routes.dart';
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

  test('strategies lists the presets', () {
    final answer = route(
      'GET',
      '/api/strategies',
      strategies: [
        {'id': 'rock', 'name': 'The Rock'},
      ],
    );
    expect(answer.status, 200);
    expect(answer.body, {
      'strategies': [
        {'id': 'rock', 'name': 'The Rock'},
      ],
    });
  });

  test('a preflight answers 204', () {
    expect(route('OPTIONS', '/api/act').status, 204);
  });

  test('anything else is not found', () {
    expect(route('GET', '/api/nothing').status, 404);
    expect(route('POST', '/api/health').status, 404);
    expect(route('GET', '/api/act').status, 404);
  });
}
