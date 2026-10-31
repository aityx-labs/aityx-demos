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
}
