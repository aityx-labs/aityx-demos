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
      'paused': false, 'triage': false,
    });

    final withBoth = route('GET', '/api/health', db: true, aityx: true, triageEnabled: true);
    expect(withBoth.body, {
      'ok': true, 'db': true, 'aityx': true, 'auth': false, 'kafka': false, 'simulation': false,
      'paused': false, 'triage': true,
    });
  });

  test('health reports Kafka and the simulation, and stays ok without them', () {
    final up = route('GET', '/api/health', kafka: true, simulation: true).body as Map;
    expect(up['kafka'], true);
    expect(up['simulation'], true);
    expect(up['paused'], false);
    expect((route('GET', '/api/health', simulation: true, paused: true).body as Map)['paused'], true);
    expect(route('GET', '/api/health', db: true).body, containsPair('ok', true));
  });

  Map<String, Object?> moveOf(String id, int turn, String time) => {
    'id': id, 'city': 'Reus', 'lat': 41.15, 'lon': 1.1, 'homeLat': 41.16, 'homeLon': 1.11,
    'hospitalId': 7, 'hospitalName': 'Hospital Sant Joan', 'careCenterKind': 'hospital', 'state': 'to_hospital',
    'simTime': time, 'day': 1, 'turn': turn, 'name': 'Núria Puig Soler', 'age': 54,
    'mode': 'transit', 'monitored': false, 'monitoredFor': null, 'conditionName': 'Influenza', 'conditionType': 'acute',
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
      'monitored': false, 'monitoredFor': null, 'hospitalId': 7, 'hospitalName': 'Hospital Sant Joan',
      'careCenterKind': 'hospital', 'conditionName': 'Influenza', 'conditionType': 'acute',
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
      'state': 'to_hospital', 'mode': 'transit', 'monitored': false, 'monitoredFor': null, 'conditionName': 'Influenza',
      'conditionType': 'acute', 'hospitalId': 7, 'hospitalName': 'Hospital Sant Joan', 'careCenterKind': 'hospital',
      'simTime': '09:00', 'day': 1, 'turn': 30, 'lat': 41.15,
      'lon': 1.1, 'partition': 0, 'offset': 130,
    });
    expect(body['topics'], ['healthhub.people.moves', 'healthhub.admissions']);
    expect((route('GET', '/api/events', dev: true, events: events, query: {'limit': '5'}).body as Map)['events'], hasLength(5));
    expect(route('GET', '/api/events', dev: true, query: {'limit': 'x'}).status, 400);
    expect((route('GET', '/api/events', events: events).body as Map)['events'], isEmpty);
  });

  test('events say how many the feed read, and how many a second', () {
    final body = route('GET', '/api/events', dev: true, eventsTotal: 48213, eventsPerSecond: 70.4321).body as Map;
    expect(body['total'], 48213);
    expect(body['perSecond'], 70.4);
    final prod = route('GET', '/api/events', eventsTotal: 5, eventsPerSecond: 1).body as Map;
    expect((prod['total'], prod['perSecond']), (0, 0));
  });

  Map<String, Object?> admissionOf(int turn) => {
    'type': 'admission', 'eventId': 'reus-1-d1-t$turn', 'personId': 'reus-1', 'name': 'Núria Puig Soler',
    'age': 54, 'sex': 'woman', 'occupation': 'teacher', 'city': 'Reus', 'conditionCode': 'influenza',
    'conditionName': 'Influenza', 'conditionType': 'acute', 'visit': 'first', 'visitNumber': 1,
    'complaint': 'I have had a fever since yesterday.', 'hospitalId': 7, 'hospitalName': 'Hospital Sant Joan',
    'careCenterKind': 'hospital',
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

  test('a person path names the id, and whether it asks for the prediction', () {
    expect(personPath('/api/people/reus-5'), ('reus-5', false));
    expect(personPath('/api/people/reus-5/prediction'), ('reus-5', true));
    expect(personPath('/api/people/s%C3%A3o-paulo-2'), ('são-paulo-2', false));
    expect(personPath('/api/people/'), isNull);
    expect(personPath('/api/people/a/b'), isNull);
    expect(personPath('/api/people/%E0'), isNull);
    expect(personPath('/api/people'), isNull);
  });

  group('a person', () {
    final history = {
      'run': 'df0837e4',
      'admissions': [
        {
          'eventId': 'df0837e4-reus-5-d141-t3369',
          'name': 'Cristina Roca Navarro',
          'age': 23,
          'sex': 'woman',
          'occupation': 'university student',
          'city': 'Reus',
          'conditionType': 'chronic',
          'triage': {'level': 'blue'},
        },
        {'eventId': 'df0837e4-reus-5-d30-t700', 'conditionType': 'acute', 'triage': null},
      ],
      'days': [
        {'day': '2026-05-21', 'stayHours': 4},
        {'day': '2026-01-30', 'stayHours': 6},
      ],
    };
    final move = {
      'id': 'reus-5', 'name': 'Cristina Roca Navarro', 'age': 23, 'city': 'Reus', 'state': 'at_hospital',
      'hospitalName': 'Hospital Sant Joan', 'simTime': '15:15', 'day': 141, 'lat': 41.1, 'lon': 1.1,
    };

    test('answers their facts, where they are now, their admissions and days, counted', () {
      final answer = route('GET', '/api/people/reus-5',
          dev: true, people: [move], person: PersonLookup(history, currentRun: 'df0837e4'));
      expect(answer.status, 200);
      final body = answer.body as Map;
      expect(body['run'], 'df0837e4');
      expect(body['current'], isTrue);
      expect(body['sex'], 'woman'); // from the admission: a move has none
      expect(body['occupation'], 'university student');
      expect((body['now'] as Map)['state'], 'at_hospital');
      expect((body['now'] as Map)['hospitalName'], 'Hospital Sant Joan');
      expect(body['summary'], {'admissions': 2, 'acute': 1, 'chronic': 1, 'triaged': 1, 'days': 2, 'stayHours': 10});
      expect(body['admissions'], hasLength(2));
      expect(body['days'], hasLength(2));
    });

    test('of a past run: no now, even though someone of that id moves', () {
      final body = route('GET', '/api/people/reus-5',
          dev: true, people: [move], person: PersonLookup(history, currentRun: 'a1b2c3d4')).body as Map;
      expect(body['current'], isFalse);
      expect(body['now'], isNull);
      expect(body['name'], 'Cristina Roca Navarro');
    });

    test('moving this run without admissions yet: their move alone', () {
      final body = route('GET', '/api/people/reus-5',
              dev: true,
              people: [move],
              person: const PersonLookup({'run': null, 'admissions': [], 'days': []}, currentRun: 'df0837e4'))
          .body as Map;
      expect(body['run'], 'df0837e4');
      expect(body['current'], isTrue);
      expect(body['sex'], isNull);
      expect((body['summary'] as Map)['admissions'], 0);
    });

    test('nobody known is a 404, no database a 503', () {
      expect(
        route('GET', '/api/people/nobody', dev: true, person: const PersonLookup({'run': null})).status,
        404,
      );
      expect(route('GET', '/api/people/reus-5').status, 503);
    });
  });

  test("a prediction is datyx's for the person, trimmed; datyx's errors pass through", () {
    const scored = Forwarded(200, {
      'callId': 7, 'runId': 1, 'trainedAt': '2026-11-01T09:42:05Z', 'table': 'datyx-ds-1.healthhub.public.patient_days',
      'group': 'care', 'target': 'stay_hours', 'horizon': '30D', 'requested': 1, 'scored': 1, 'millis': 63, 'sourceId': 1,
      'predictions': [
        {'series': {'run_id': 'df0837e4', 'person_id': 'reus-5'}, 'predicted': 9.022, 'last': 4.0, 'note': null},
      ],
    });
    final answer = route('GET', '/api/people/reus-5/prediction', prediction: scored);
    expect(answer.status, 200);
    expect(answer.body, {
      'predicted': 9.022,
      'last': 4.0,
      'note': null,
      'series': {'run_id': 'df0837e4', 'person_id': 'reus-5'},
      'target': 'stay_hours',
      'horizon': '30D',
      'group': 'care',
      'table': 'datyx-ds-1.healthhub.public.patient_days',
      'trainingRunId': 1,
      'trainedAt': '2026-11-01T09:42:05Z',
      'sourceId': 1,
      'millis': 63,
    });
    final noModel = route('GET', '/api/people/reus-5/prediction',
        prediction: const Forwarded(404, {'error': 'no model of the group care has been trained yet'}));
    expect(noModel.status, 404);
    expect(noModel.body, {'error': 'no model of the group care has been trained yet'});
    expect(route('GET', '/api/people/reus-5/prediction').status, 502);
    expect(route('GET', '/api/people/reus-5/prediction', auth: on).status, 401);
  });

  group("a hospital's admissions per hour", () {
    test('a path names the hospital, and whether it asks for the forecast', () {
      expect(careCenterSeriesPath('/api/care-centers/42/admissions'), (42, CareCenterSeries.admissions, false));
      expect(careCenterSeriesPath('/api/care-centers/42/admissions/forecast'), (42, CareCenterSeries.admissions, true));
      expect(careCenterSeriesPath('/api/care-centers/42'), isNull);
      expect(careCenterSeriesPath('/api/care-centers/x/admissions'), isNull);
      expect(careCenterSeriesPath('/api/care-centers/42/admissions/other'), isNull);
      expect(careCenterSeriesPath('/api/care-centers'), isNull);
      expect(careCenterSeriesPath('/api/care-centers/42/occupancy'), (42, CareCenterSeries.occupancy, false));
      expect(careCenterSeriesPath('/api/care-centers/42/occupancy/forecast'), (42, CareCenterSeries.occupancy, true));
      expect(careCenterSeriesPath('/api/care-centers/42/beds'), isNull);
    });

    test('the people in care, every hour up to the run\'s end, an hour without a row a zero', () {
      final hourly = HourlyLookup(
        run: 'adf5309c',
        end: DateTime.utc(2026, 1, 4, 10),
        rows: [
          {'hour': DateTime.utc(2026, 1, 4, 8), 'occupancy': 3},
          {'hour': DateTime.utc(2026, 1, 4, 9), 'occupancy': 2},
        ],
      );
      final answer = route('GET', '/api/care-centers/42/occupancy', query: {'hours': '3'}, hourly: hourly, auth: on);
      expect(answer.status, 200);
      expect(answer.body, {
        'hospitalId': 42,
        'run': 'adf5309c',
        'current': false,
        'end': '2026-01-04T10:00',
        'hours': [
          {'hour': '2026-01-04T08:00', 'occupancy': 3},
          {'hour': '2026-01-04T09:00', 'occupancy': 2},
          {'hour': '2026-01-04T10:00', 'occupancy': 0},
        ],
      });
      expect(route('GET', '/api/care-centers/42/occupancy', query: {'hours': 'x'}, hourly: hourly).status, 400);
      expect(route('GET', '/api/care-centers/42/occupancy').status, 503);
      expect(CareCenterSeries.occupancy.table, 'public.occupancy_hourly');
    });

    test('every hour up to the run\'s end, an hour without a row a zero', () {
      final hourly = HourlyLookup(
        run: 'adf5309c',
        end: DateTime.utc(2026, 1, 4, 10),
        current: true,
        rows: [
          {'hour': DateTime.utc(2026, 1, 4, 8), 'admissions': 2, 'acute': 1, 'chronic': 1},
          {'hour': DateTime.utc(2026, 1, 4, 10), 'admissions': 1, 'acute': 1, 'chronic': 0},
        ],
      );
      final answer = route('GET', '/api/care-centers/42/admissions', query: {'hours': '4'}, hourly: hourly);
      expect(answer.status, 200);
      expect(answer.body, {
        'hospitalId': 42,
        'run': 'adf5309c',
        'current': true,
        'end': '2026-01-04T10:00',
        'hours': [
          {'hour': '2026-01-04T07:00', 'admissions': 0, 'acute': 0, 'chronic': 0},
          {'hour': '2026-01-04T08:00', 'admissions': 2, 'acute': 1, 'chronic': 1},
          {'hour': '2026-01-04T09:00', 'admissions': 0, 'acute': 0, 'chronic': 0},
          {'hour': '2026-01-04T10:00', 'admissions': 1, 'acute': 1, 'chronic': 0},
        ],
      });
      // Three simulated days unless asked, at most 30; open to everyone.
      final unasked = route('GET', '/api/care-centers/42/admissions', hourly: hourly, auth: on);
      expect((unasked.body as Map)['hours'], hasLength(72));
      expect(((route('GET', '/api/care-centers/42/admissions', query: {'hours': '5000'}, hourly: hourly).body
          as Map)['hours'] as List), hasLength(720));
    });

    test('no admissions there: no run, no hours; bad hours, no database', () {
      final none = route('GET', '/api/care-centers/7/admissions', hourly: const HourlyLookup());
      expect(none.body, {'hospitalId': 7, 'run': null, 'current': false, 'end': null, 'hours': []});
      expect(route('GET', '/api/care-centers/7/admissions', query: {'hours': '0'}, hourly: const HourlyLookup()).status,
          400);
      expect(route('GET', '/api/care-centers/7/admissions').status, 503);
    });

    test("the forecast is datyx's, step by step; datyx's errors pass through", () {
      const step = {'at': '2026-01-04T11:00', 'mean': 0.31, 'p10': 0.0, 'p50': 0.0, 'p90': 1.0};
      const scored = Forwarded(200, {
        'callId': 9, 'runId': 4, 'trainedAt': '2026-11-01T11:31:53Z',
        'table': 'datyx-ds-1.healthhub.public.admissions_hourly', 'group': 'default', 'target': 'admissions',
        'horizon': '1D', 'requested': 1, 'scored': 1, 'millis': 21, 'sourceId': 1,
        'predictions': [
          {
            'series': {'run_id': 'adf5309c', 'hospital_id': '42'},
            'predicted': 0.31, 'last': 1.0, 'note': null, 'forecast': [step],
          },
        ],
      });
      final answer = route('GET', '/api/care-centers/42/admissions/forecast', forecast: scored);
      expect(answer.status, 200);
      final body = answer.body as Map;
      expect(body['forecast'], [step]);
      expect(body['predicted'], 0.31);
      expect(body['horizon'], '1D');
      expect(body['trainingRunId'], 4);
      expect(body['series'], {'run_id': 'adf5309c', 'hospital_id': '42'});
      final noRows = route('GET', '/api/care-centers/42/admissions/forecast', forecast: const Forwarded(200, {
        'predictions': [
          {'series': {'run_id': 'adf5309c', 'hospital_id': '42'}, 'predicted': null, 'last': null,
            'note': 'no rows for this series'},
        ],
      }));
      expect((noRows.body as Map)['forecast'], isEmpty);
      expect((noRows.body as Map)['note'], 'no rows for this series');
      final noModel = route('GET', '/api/care-centers/42/admissions/forecast',
          forecast: const Forwarded(404, {'error': 'no model of the group default has been trained yet'}));
      expect(noModel.status, 404);
      expect(noModel.body, {'error': 'no model of the group default has been trained yet'});
      expect(route('GET', '/api/care-centers/42/admissions/forecast').status, 502);
      expect(route('GET', '/api/care-centers/42/admissions/forecast', auth: on).status, 401);
    });
  });

  group('pausing the simulation', () {
    // A fake simulation's control: records each call, answers the state.
    late List<bool> calls;
    bool control(bool pause) {
      calls.add(pause);
      return pause;
    }

    setUp(() => calls = []);

    test('pause and resume answer the state after the call', () {
      final paused = route('POST', '/api/simulation/pause', dev: true, simulation: true, control: control);
      expect(paused.status, 200);
      expect(paused.body, {'paused': true});
      // Again: still paused, no harm done.
      expect(route('POST', '/api/simulation/pause', dev: true, simulation: true, control: control).body,
          {'paused': true});
      final resumed = route('POST', '/api/simulation/resume', dev: true, simulation: true, control: control);
      expect(resumed.status, 200);
      expect(resumed.body, {'paused': false});
      expect(calls, [true, true, false]);
    });

    test('want a signed-in user once authentication is on, before anything changes', () {
      for (final path in ['/api/simulation/pause', '/api/simulation/resume']) {
        final answer = route('POST', path, auth: on, dev: true, simulation: true, control: control);
        expect(answer.status, 401);
        expect(answer.body, {'error': 'sign in first'});
      }
      expect(calls, isEmpty);
      expect(route('POST', '/api/simulation/pause', auth: on, identity: alice, dev: true, simulation: true,
          control: control).body, {'paused': true});
    });

    test('are a 409 when the simulation does not run: prod, or not started', () {
      for (final (dev, simulation) in [(false, false), (false, true), (true, false)]) {
        final answer = route('POST', '/api/simulation/pause', dev: dev, simulation: simulation, control: control);
        expect(answer.status, 409);
        expect(answer.body, {'error': 'the simulation does not run'});
      }
      expect(route('POST', '/api/simulation/resume', dev: true, simulation: true).status, 409);
      expect(calls, isEmpty);
    });

    test('only by POST', () {
      expect(route('GET', '/api/simulation/pause', dev: true, simulation: true, control: control).status, 404);
      expect(calls, isEmpty);
    });

    test('events say whether it is paused, and never in prod', () {
      expect((route('GET', '/api/events', dev: true).body as Map)['paused'], false);
      expect((route('GET', '/api/events', dev: true, paused: true).body as Map)['paused'], true);
      expect((route('GET', '/api/events', paused: true).body as Map)['paused'], false);
    });
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
