import 'dart:io';

import 'package:healthhub_api/care_centers.dart';
import 'package:healthhub_api/care_centers_seed.dart';
import 'package:healthhub_api/routes.dart';
import 'package:test/test.dart';

import '../tool/generate_care_centers.dart';

void main() {
  const hospital = {
    'name': 'Hospital del Mar',
    'kind': 'hospital',
    'subtype': 'Hospital',
    'address': 'Passeig Marítim 25-29',
    'postal_code': '08003',
    'city': 'Barcelona',
    'region': 'Catalonia',
    'country': 'ES',
    'lat': 41.3843,
    'lon': 2.1941,
    'phone': null,
    'website': null,
    'ownership': 'public',
    'source': 'CatSalut',
    'source_id': '08003',
  };

  test('a row reads into a care center keyed by its source and id', () {
    final center = CareCenter.fromJson(hospital);
    expect(center.key, 'CatSalut:08003');
    expect(center.kind, 'hospital');
    expect(center.latitude, 41.3843);
    expect(center.values, hasLength(CareCenter.columns.length));
  });

  test('without a source id the key is the place and the name', () {
    final center = CareCenter.fromJson({...hospital, 'source_id': null});
    expect(center.key, 'es:barcelona:hospital del mar:passeig marítim 25-29');
  });

  test('a kind or ownership outside the lists is refused', () {
    expect(() => CareCenter.fromJson({...hospital, 'kind': 'pharmacy'}), throwsFormatException);
    expect(() => CareCenter.fromJson({...hospital, 'ownership': 'mixed'}), throwsFormatException);
    expect(() => CareCenter.fromJson({...hospital, 'name': ' '}), throwsFormatException);
  });

  test('an email address is not a website', () {
    expect(CareCenter.fromJson({...hospital, 'website': 'http://someone@example.org'}).website, isNull);
    expect(CareCenter.fromJson({...hospital, 'website': 'www.example.org'}).website, 'www.example.org');
  });

  test('two rows with one key are refused', () {
    const line = '{"name":"A","kind":"clinic","city":"Reus","region":"Catalonia","country":"ES","source":"S","source_id":"1"}';
    expect(readCareCenters([line, '', line.replaceFirst('"1"', '"2"')]), hasLength(2));
    expect(() => readCareCenters([line, line]), throwsFormatException);
  });

  test('the compiled seed is the data file, regenerated', () {
    final data = readCareCenters(File('data/care_centers.jsonl').readAsLinesSync());
    expect(careCenterSeed.map((c) => c.values), data.map((c) => c.values));
  });

  test('a bbox is west,south,east,north in degrees', () {
    final box = Bbox.parse('2.05,41.3,2.25,41.47')!;
    expect([box.west, box.south, box.east, box.north], [2.05, 41.3, 2.25, 41.47]);
    for (final bad in [null, '', '1,2,3', 'a,b,c,d', '10,0,5,1', '0,10,1,5', '-181,0,0,1', '0,0,1,91']) {
      expect(Bbox.parse(bad), isNull, reason: bad);
    }
  });

  test('care centers answers the centers, truncated beyond the limit', () {
    final some = [for (var i = 0; i < 3; i++) {'id': i, 'name': 'C$i'}];
    final answer = route('GET', '/api/care-centers', careCenters: some);
    expect(answer.status, 200);
    expect(answer.body, {'centers': some, 'truncated': false});

    final many = [for (var i = 0; i <= careCentersLimit; i++) {'id': i}];
    final full = route('GET', '/api/care-centers', careCenters: many).body as Map;
    expect((full['centers'] as List).length, careCentersLimit);
    expect(full['truncated'], true);
  });

  test('care centers is 400 for a bad bbox and 503 without the database', () {
    expect(route('GET', '/api/care-centers', query: {'bbox': 'x'}, careCenters: const []).status, 400);
    expect(route('GET', '/api/care-centers', query: {'bbox': '0,0,1,1'}).status, 503);
  });

  test('a care center path names its id, a positive number', () {
    expect(careCenterIdOf('/api/care-centers/42'), 42);
    expect(careCenterIdOf('/api/care-centers/0'), isNull);
    expect(careCenterIdOf('/api/care-centers/-1'), isNull);
    expect(careCenterIdOf('/api/care-centers/4a'), isNull);
    expect(careCenterIdOf('/api/care-centers/1234567890'), isNull);
    expect(careCenterIdOf('/api/care-centers/'), isNull);
    expect(careCenterIdOf('/api/care-centers'), isNull);
  });

  test('a capacity is sized to the simulation, by kind, the same for a key every time', () {
    for (final key in ['cnes:1', 'cnes:2', 'siap:07', 'hfrs:100', 'es:reus:cap:']) {
      final bed = simulatedCapacity(key, 'hospital');
      expect(bed.unit, 'beds');
      expect(bed.places, inInclusiveRange(4, 12));
      expect(simulatedCapacity(key, 'clinic').places, inInclusiveRange(2, 6));
      expect(simulatedCapacity(key, 'health_station').places, inInclusiveRange(2, 5));
      expect(simulatedCapacity(key, 'clinic').unit, 'places');
      expect(simulatedCapacity(key, 'hospital').places, bed.places);
    }
    // FNV-1a, not String.hashCode: fixed across runs and Dart versions.
    expect(simulatedCapacity('cnes:2269910', 'hospital').places, simulatedCapacity('cnes:2269910', 'hospital').places);
    final sizes = {for (final c in careCenterSeed.where((c) => c.kind == 'hospital')) simulatedCapacity(c.key, c.kind).places};
    expect(sizes.length, greaterThan(5), reason: 'the hospitals are not all one size');
  });

  group('a care center', () {
    final history = {
      'center': {
        'id': 42, 'key': 'siap:43148', 'name': 'Hospital Universitari Sant Joan de Reus', 'kind': 'hospital',
        'subtype': 'Hospital', 'city': 'Reus', 'country': 'ES', 'lat': 41.15, 'lon': 1.11,
      },
      'admissions': {
        'run': 'df0837e4', 'thisRun': 2, 'total': 5, 'latestOf': 'run',
        'latest': [
          {'eventId': 'df0837e4-reus-5-d3-t60', 'personId': 'reus-5', 'triage': {'level': 'green'}},
        ],
      },
    };
    Map<String, Object?> move(String id, String state, {int hospital = 42, int turn = 60}) => {
      'id': id, 'name': 'Someone', 'age': 40, 'city': 'Reus', 'state': state, 'hospitalId': hospital,
      'lat': 41.15, 'lon': 1.11, 'homeLat': 41.16, 'homeLon': 1.1, 'simTime': '12:00', 'day': 3, 'turn': turn,
    };
    final moves = [
      move('reus-1', 'at_hospital'),
      move('reus-2', 'at_hospital', turn: 61),
      move('reus-3', 'to_hospital'),
      move('reus-4', 'home'),
      move('reus-5', 'at_hospital', hospital: 7),
    ];

    test('answers where it is, its capacity, who is there and on the way, and its admissions', () {
      final answer = route('GET', '/api/care-centers/42',
          dev: true, people: moves, careCenter: CareCenterLookup(history, currentRun: 'df0837e4'));
      expect(answer.status, 200);
      final body = answer.body as Map;
      expect(body['name'], 'Hospital Universitari Sant Joan de Reus');
      expect(body.containsKey('key'), isFalse);
      final capacity = body['capacity'] as Map;
      expect(capacity['places'], simulatedCapacity('siap:43148', 'hospital').places);
      expect(capacity['unit'], 'beds');
      expect(capacity['simulated'], isTrue);
      expect(body['serves'], ['hospital', 'urgent_care', 'dialysis']);
      final now = body['now'] as Map;
      expect(now['enabled'], isTrue);
      expect(now['run'], 'df0837e4');
      expect([for (final p in now['here'] as List) (p as Map)['id']], ['reus-1', 'reus-2']);
      expect([for (final p in now['onTheWay'] as List) (p as Map)['id']], ['reus-3']);
      expect(now['inUse'], 2);
      expect(now['usage'], 2 / (capacity['places'] as int));
      expect(now['assigned'], 4); // reus-4 at home has it as their hospital too; reus-5 has another
      expect(now['day'], 3);
      expect(((body['admissions'] as Map)['latest'] as List), hasLength(1));
    });

    test('in prod: nobody now, the admissions still', () {
      final body = route('GET', '/api/care-centers/42',
          people: moves, careCenter: CareCenterLookup(history)).body as Map;
      final now = body['now'] as Map;
      expect(now['enabled'], isFalse);
      expect(now['here'], isEmpty);
      expect(now['inUse'], 0);
      expect(now['simTime'], isNull);
      expect((body['admissions'] as Map)['total'], 5);
    });

    test('says what the simulation sends people to it for: nothing, for a dental clinic', () {
      Map<String, Object?> serves(String kind, String subtype) => (route('GET', '/api/care-centers/3',
          careCenter: CareCenterLookup({
            'center': {'id': 3, 'key': 'k', 'name': 'n', 'kind': kind, 'subtype': subtype},
          })).body as Map).cast();
      expect(serves('health_station', 'CAP')['serves'], ['primary', 'mental_health']);
      expect(serves('clinic', 'CUAP')['serves'], ['urgent_care']);
      expect(serves('clinic', 'CLINICA/CENTRO DE ESPECIALIDADE - CEO-I')['serves'], isEmpty);
    });

    test('none is a 404, no database a 503', () {
      expect(route('GET', '/api/care-centers/9', careCenter: const CareCenterLookup({'center': null})).status, 404);
      expect(route('GET', '/api/care-centers/42').status, 503);
      expect(route('GET', '/api/care-centers/x').status, 404);
    });
  });
}
