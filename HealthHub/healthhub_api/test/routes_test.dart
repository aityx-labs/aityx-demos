import 'package:healthhub_api/auth.dart';
import 'package:healthhub_api/routes.dart';
import 'package:test/test.dart';

void main() {
  test('the root redirects to the app', () {
    final answer = route('GET', '/');
    expect(answer.status, 302);
    expect(answer.location, '/app/');
  });

  test('health answers ok, whether the database answers and the key is set',
      () {
    final without = route('GET', '/api/health');
    expect(without.status, 200);
    expect(without.body, {'ok': true, 'db': false, 'aityx': false, 'auth': false});

    final withBoth = route('GET', '/api/health', db: true, aityx: true);
    expect(withBoth.body, {'ok': true, 'db': true, 'aityx': true, 'auth': false});
  });

  test('hello answers the greeting from the database, or 503 without it',
      () {
    final answer = route(
      'GET',
      '/api/hello',
      greeting: {'message': 'Hello, world', 'postgres': 'PostgreSQL 17'},
    );
    expect(answer.status, 200);
    expect(answer.body, {'message': 'Hello, world', 'postgres': 'PostgreSQL 17', 'user': null});

    final down = route('GET', '/api/hello');
    expect(down.status, 503);
    expect(down.body, {'error': 'the database is not answering'});
  });

  const on = AuthSettings(issuer: 'https://accounts.google.com', clientId: 'healthhub-client');
  const alice = Identity(subject: 'sub-1', email: 'alice@example.com', name: 'Alice');

  test('auth config says how to sign in', () {
    expect(route('GET', '/api/auth/config').body,
        {'enabled': false, 'issuer': 'https://accounts.google.com', 'clientId': null});
    expect(route('GET', '/api/auth/config', auth: on).body,
        {'enabled': true, 'issuer': 'https://accounts.google.com', 'clientId': 'healthhub-client'});
  });

  test('me wants a signed-in user once authentication is on', () {
    expect(route('GET', '/api/me').body, {'authenticated': false});
    expect(route('GET', '/api/me', auth: on).status, 401);
    final me = route('GET', '/api/me', auth: on, identity: alice);
    expect(me.status, 200);
    expect(me.body, {
      'authenticated': true,
      'subject': 'sub-1',
      'email': 'alice@example.com',
      'name': 'Alice',
      'picture': null,
    });
  });

  test('hello is addressed to the signed-in user', () {
    final answer = route('GET', '/api/hello', auth: on, identity: alice,
        greeting: {'message': 'Hello, world', 'postgres': 'PostgreSQL 17'});
    expect((answer.body as Map)['message'], 'Hello, Alice');
    expect(((answer.body as Map)['user'] as Map)['email'], 'alice@example.com');
  });

  test('datyx answers pass through, with the user, or 401 and 502', () {
    expect(datyxPath('/api/datyx/me'), '/api/me');
    expect(datyxPath('/api/datyx/datasources'), '/api/datasources');
    expect(datyxPath('/api/datyx/other'), isNull);
    expect(route('GET', '/api/datyx/me', auth: on).status, 401);
    expect(route('GET', '/api/datyx/me', auth: on, identity: alice).status, 502);
    final passed = route('GET', '/api/datyx/datasources', auth: on, identity: alice,
        datyx: const Forwarded(200, [{'id': 1}]));
    expect(passed.status, 200);
    expect(passed.body, [{'id': 1}]);
    final refused = route('GET', '/api/datyx/me', datyx: const Forwarded(401, {'error': 'x'}));
    expect(refused.status, 401);
  });

  test('a preflight answers 204', () {
    expect(route('OPTIONS', '/api/hello').status, 204);
  });

  test('anything else is not found', () {
    expect(route('GET', '/api/nothing').status, 404);
    expect(route('POST', '/api/health').status, 404);
    expect(route('POST', '/api/hello').status, 404);
  });
}
