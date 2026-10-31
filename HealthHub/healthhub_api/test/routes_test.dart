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
    expect(without.body, {
      'ok': true, 'db': false, 'aityx': false, 'auth': false, 'kafka': false, 'simulation': false,
    });

    final withBoth = route('GET', '/api/health', db: true, aityx: true);
    expect(withBoth.body, {
      'ok': true, 'db': true, 'aityx': true, 'auth': false, 'kafka': false, 'simulation': false,
    });
  });

  test('health reports Kafka and the simulation, and stays ok without them', () {
    final up = route('GET', '/api/health', kafka: true, simulation: true).body as Map;
    expect(up['kafka'], true);
    expect(up['simulation'], true);
    expect(route('GET', '/api/health', db: true).body, containsPair('ok', true));
  });

  Map<String, Object?> moveOf(String id, int turn, String time) => {
    'id': id, 'city': 'Reus', 'lat': 41.15, 'lon': 1.1, 'homeLat': 41.16, 'homeLon': 1.11,
    'hospitalId': 7, 'hospitalName': 'Hospital Sant Joan', 'state': 'to_hospital',
    'simTime': time, 'day': 1, 'turn': turn, 'name': 'Núria Puig Soler', 'age': 54,
    'mode': 'transit', 'conditionName': 'Influenza', 'conditionType': 'acute',
  };

  test('people answer the latest moves and the newest time in dev mode', () {
    final answer = route('GET', '/api/people', dev: true,
        people: [moveOf('reus-1', 13, '08:10'), moveOf('reus-2', 14, '08:20')]);
    expect(answer.status, 200);
    final body = answer.body as Map;
    expect(body['enabled'], true);
    expect(body['simTime'], '08:20');
    expect(body['day'], 1);
    expect(body['people'], hasLength(2));
    expect((body['people'] as List).first, {
      'id': 'reus-1', 'name': 'Núria Puig Soler', 'age': 54, 'city': 'Reus', 'lat': 41.15,
      'lon': 1.1, 'homeLat': 41.16, 'homeLon': 1.11, 'state': 'to_hospital', 'mode': 'transit',
      'hospitalName': 'Hospital Sant Joan', 'conditionName': 'Influenza', 'conditionType': 'acute',
    });
  });

  test('people are empty before the first move, and off in prod', () {
    expect(route('GET', '/api/people', dev: true).body,
        {'enabled': true, 'simTime': null, 'day': null, 'people': []});
    expect(route('GET', '/api/people', people: [moveOf('reus-1', 1, '06:10')]).body,
        {'enabled': false, 'simTime': null, 'day': null, 'people': []});
  });

  test('people in a bbox are those there now, or whose home is there', () {
    final away = {...moveOf('reus-2', 14, '09:00'), 'lat': 41.5, 'lon': 2.0};
    final gone = {...moveOf('reus-3', 15, '09:10'), 'lat': 41.5, 'lon': 2.0, 'homeLat': 41.5, 'homeLon': 2.0};
    final body = route('GET', '/api/people', dev: true, query: {'bbox': '1.0,41.1,1.2,41.2'},
        people: [moveOf('reus-1', 13, '08:50'), away, gone]).body as Map;
    expect([for (final p in body['people'] as List) (p as Map)['id']], ['reus-1', 'reus-2']);
    // The clock is everyone's, not only the people in view.
    expect(body['simTime'], '09:10');
    expect(route('GET', '/api/people', dev: true, query: {'bbox': 'x'}).status, 400);
  });

  test('events are the latest records, newest first, as many as asked', () {
    final events = [
      for (var turn = 30; turn > 0; turn--) {...moveOf('reus-1', turn, '09:00'), 'partition': 0, 'offset': 100 + turn},
    ];
    final body = route('GET', '/api/events', dev: true, events: events).body as Map;
    expect(body['enabled'], true);
    expect(body['topic'], 'healthhub.people.moves');
    final list = body['events'] as List;
    expect(list, hasLength(eventsLimit));
    expect(list.first, {
      'type': 'move', 'id': 'reus-1', 'name': 'Núria Puig Soler', 'age': 54, 'city': 'Reus',
      'state': 'to_hospital', 'mode': 'transit', 'conditionName': 'Influenza', 'conditionType': 'acute',
      'hospitalName': 'Hospital Sant Joan', 'simTime': '09:00', 'day': 1, 'turn': 30, 'lat': 41.15,
      'lon': 1.1, 'partition': 0, 'offset': 130,
    });
    expect(body['topics'], ['healthhub.people.moves', 'healthhub.admissions']);
    expect((route('GET', '/api/events', dev: true, events: events, query: {'limit': '5'}).body as Map)['events'], hasLength(5));
    expect(route('GET', '/api/events', dev: true, query: {'limit': 'x'}).status, 400);
    expect((route('GET', '/api/events', events: events).body as Map)['events'], isEmpty);
  });

  Map<String, Object?> admissionOf(int turn) => {
    'type': 'admission', 'eventId': 'reus-1-d1-t$turn', 'personId': 'reus-1', 'name': 'Núria Puig Soler',
    'age': 54, 'sex': 'woman', 'occupation': 'teacher', 'city': 'Reus', 'conditionCode': 'influenza',
    'conditionName': 'Influenza', 'conditionType': 'acute', 'visit': 'first', 'visitNumber': 1,
    'complaint': 'I have had a fever since yesterday.', 'hospitalId': 7, 'hospitalName': 'Hospital Sant Joan',
    'simTime': '09:00', 'day': 1, 'turn': turn, 'partition': 0, 'offset': 5,
  };

  test('events hold admissions with all their fields, and filter by type', () {
    final events = [
      {...moveOf('reus-1', 4, '10:00'), 'type': 'move', 'partition': 0, 'offset': 40},
      admissionOf(3),
      {...moveOf('reus-1', 3, '09:00'), 'type': 'move', 'partition': 0, 'offset': 30},
    ];
    final all = (route('GET', '/api/events', dev: true, events: events).body as Map)['events'] as List;
    expect([for (final e in all) (e as Map)['type']], ['move', 'admission', 'move']);
    expect(all[1], {...admissionOf(3), 'id': 'reus-1'});
    final admissions = (route('GET', '/api/events', dev: true, events: events, query: {'type': 'admission'}).body as Map)['events'] as List;
    expect(admissions, [{...admissionOf(3), 'id': 'reus-1'}]);
    final moves = (route('GET', '/api/events', dev: true, events: events, query: {'type': 'move', 'limit': '1'}).body as Map)['events'] as List;
    expect([for (final e in moves) (e as Map)['turn']], [4]);
    expect(route('GET', '/api/events', dev: true, query: {'type': 'arrival'}).status, 400);
  });

  test('admissions answer the database\'s latest, 400 for a bad limit, 503 without it', () {
    final rows = [admissionOf(2)];
    final answer = route('GET', '/api/admissions', admissions: rows);
    expect(answer.status, 200);
    expect(answer.body, {'admissions': rows});
    expect(route('GET', '/api/admissions').status, 503);
    expect(route('GET', '/api/admissions', query: {'limit': '0'}, admissions: rows).status, 400);
    expect(route('GET', '/api/admissions', query: {'limit': 'x'}, admissions: rows).status, 400);
    expect(admissionsLimitOf(const {}), 20);
    expect(admissionsLimitOf(const {'limit': '5'}), 5);
    expect(admissionsLimitOf(const {'limit': '5000'}), 200);
    const on = AuthSettings(issuer: 'https://accounts.google.com', clientId: 'healthhub-client');
    expect(route('GET', '/api/admissions', auth: on, admissions: rows).status, 200);
  });

  test('people need no sign-in', () {
    const on = AuthSettings(issuer: 'https://accounts.google.com', clientId: 'healthhub-client');
    expect(route('GET', '/api/people', auth: on, dev: true).status, 200);
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
