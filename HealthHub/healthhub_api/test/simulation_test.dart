import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/care_centers_seed.dart';
import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/kafka_rest.dart';
import 'package:healthhub_api/simulation.dart';
import 'package:test/test.dart';

void main() {
  const sagradaFamilia = LatLon(41.4036, 2.1744);
  const hospitalDelMar = LatLon(41.3843, 2.1941);

  Place place(int id, String city, String kind, LatLon at) =>
      Place(id: id, name: '$kind $id', kind: kind, city: city, at: at);

  test('distance is the great-circle distance in meters', () {
    expect(distanceMeters(sagradaFamilia, sagradaFamilia), 0);
    // About 2.7 km across Barcelona.
    expect(distanceMeters(sagradaFamilia, hospitalDelMar), closeTo(2700, 100));
    // A degree of latitude is about 111 km.
    expect(distanceMeters(const LatLon(0, 0), const LatLon(1, 0)), closeTo(111195, 10));
  });

  test('a step goes the given distance towards the target', () {
    final next = stepTowards(sagradaFamilia, hospitalDelMar, 500);
    expect(distanceMeters(sagradaFamilia, next), closeTo(500, 5));
    expect(
      distanceMeters(next, hospitalDelMar),
      closeTo(distanceMeters(sagradaFamilia, hospitalDelMar) - 500, 5),
    );
  });

  test('a step longer than what is left stops exactly at the target', () {
    expect(stepTowards(sagradaFamilia, hospitalDelMar, 5000), hospitalDelMar);
    expect(stepTowards(hospitalDelMar, hospitalDelMar, 50), hospitalDelMar);
  });

  test('the clock starts at 06:00 on day 1 and wraps at midnight', () {
    expect(simTime(simMinutes(0, 60)), '06:00');
    expect(simDay(simMinutes(0, 60)), 1);
    expect(simTime(simMinutes(2, 60)), '08:00');
    // 18 hours later it is midnight of day 2.
    expect(simTime(simMinutes(18, 60)), '00:00');
    expect(simDay(simMinutes(18, 60)), 2);
    // A whole simulated day is 24 turns of an hour.
    expect(simMinutes(24, 60) - simMinutes(0, 60), 24 * 60);
    expect(simTime(simMinutes(13, 10)), '08:10');
    expect(dayStart(2), 24 * 60);
  });

  test('the travel mode follows the distance home to hospital', () {
    expect(travelMode(0), TravelMode.walk);
    expect(travelMode(2000), TravelMode.walk);
    expect(travelMode(2001), TravelMode.transit);
    expect(travelMode(15000), TravelMode.transit);
    expect(travelMode(15001), TravelMode.car);
  });

  test('a turn moves someone as far as their mode goes in that time', () {
    // An hour a turn: 5 km on foot, 20 by transport, 50 by car.
    expect(stepMeters(TravelMode.walk, 60), 5000);
    expect(stepMeters(TravelMode.transit, 60), 20000);
    expect(stepMeters(TravelMode.car, 60), 50000);
    expect(stepMeters(TravelMode.walk, 10), closeTo(833.3, 0.1));
  });

  test('a visit starts on the hour in the daytime, never in the past', () {
    final random = Random(9);
    for (var i = 0; i < 200; i++) {
      final start = nextVisitStart(3, dayStart(3) + 12 * 60, random);
      final ofDay = start % minutesPerDay;
      expect(ofDay % 60, 0);
      expect(ofDay ~/ 60, inInclusiveRange(visitFirstHour, visitLastHour));
      expect(start, greaterThan(dayStart(3) + 12 * 60));
      expect(simDay(start), inInclusiveRange(3, 4));
    }
  });

  test('the nearest hospital is searched among all of them', () {
    final places = [
      place(1, 'Barcelona', 'hospital', hospitalDelMar),
      place(2, 'Barcelona', 'clinic', sagradaFamilia),
      place(3, 'Reus', 'hospital', const LatLon(41.1554, 1.1076)),
      place(4, 'Cornudella de Montsant', 'health_station', const LatLon(41.2648, 0.9063)),
    ];
    // Cornudella has no hospital; Reus's is the nearest.
    expect(nearestHospital(const LatLon(41.2648, 0.9063), places)?.id, 3);
    // A clinic next door doesn't count.
    expect(nearestHospital(sagradaFamilia, places)?.id, 1);
    expect(nearestHospital(sagradaFamilia, [places[1]]), isNull);
  });

  test('a general hospital is preferred to a nearer specialised one', () {
    Place hospital(int id, String name, LatLon at, {String? subtype}) =>
        Place(id: id, name: name, kind: 'hospital', city: 'Barcelona', at: at, subtype: subtype);
    final psychiatric = hospital(1, 'Clínica Galatea', sagradaFamilia,
        subtype: 'Hospitales de salud mental y tratamiento de toxicomanías');
    final longStay = hospital(2, 'Centre Fórum', const LatLon(41.4037, 2.1745),
        subtype: 'Hospitales de media y larga estancia');
    final general = hospital(3, 'Hospital del Mar', hospitalDelMar, subtype: 'Hospitales Generales');
    expect(nearestHospital(sagradaFamilia, [psychiatric, longStay, general]), general);
    // With no general hospital at all, the nearest of any kind.
    expect(nearestHospital(sagradaFamilia, [longStay, psychiatric]), psychiatric);
  });

  test('the specialised hospitals of the real data are told from the general ones', () {
    // Subtypes and names as data/care_centers.jsonl has them.
    const specialised = [
      ('Hospitales de salud mental y tratamiento de toxicomanías', 'Institut Pere Mata, S.A'),
      ('Hospitales de media y larga estancia', 'Centre Sociosanitari Ciutat de Reus'),
      ('Hospitales especializados', 'Centre D\'Oftalmologia Barraquer'),
      ('HOSPITAL ESPECIALIZADO - PSIQUIATRIA', 'SAINT ROMAN'),
      ('HOSPITAL ESPECIALIZADO - MATERNIDADE', 'PRO MATRE PAULISTA'),
      ('HOSPITAL ESPECIALIZADO - PEDIATRIA', 'HOSPITAL DA CRIANCA'),
      ('HOSPITAL ESPECIALIZADO', 'INSTITUTO DE REABILITACAO LUCY MONTORO'),
      ('PRONTO SOCORRO ESPECIALIZADO', 'SANTA ISABELLA'),
      ('HOSPITAL GERAL', 'MATERNIDADE SAO LUIZ STAR'),
      ('HOSPITAL GERAL', 'HOSP MUN MATERNIDADE PROFESSOR MARIO DEGNI'),
      ('HOSPITAL GERAL', 'HOSPITAL BARRA DOR PEDIATRIA'),
      ('Psychiatric hospital (HIFLD TYPE: PSYCHIATRIC)', 'Jackson Behavioral Health Hospital'),
      ('Hospital', "NICKLAUS CHILDREN'S HOSPITAL FORT LAUDERDALE"),
      ('Hospital', 'KINDRED HOSPITAL-SOUTH FLORIDA-FT LAUDERDALE'),
      ('Hospital', 'SELECT SPECIALTY HOSPITAL-MIAMI'),
      ('Hospital', 'UNIVERSITY OF MIAMI HOSPITAL AND CLINICS-SYLVESTER COMPREHENSIVE'),
      ('Hospital', 'DOUGLAS GARDENS HOSPITAL'),
      ('VA hospital', 'MIAMI VA HEALTHCARE SYSTEM'),
      ('HOSPITAL GERAL', 'INSTITUTO DE INFECTOLOGIA EMILIO RIBAS'),
      ('HOSPITAL GERAL', 'HEALTHCARE HOSPITAL DE TRANSICAO'),
      ('HOSPITAL GERAL', 'HOSPITAL GERIATRICO E DE CONVALESCENTES D PEDRO II'),
      ('HOSPITAL GERAL', 'HOSPITAL MILITAR DE AREA DE SAO PAULO'),
      ('HOSPITAL GERAL', 'HOSPITAL NAVAL MARCILIO DIAS'),
      ('HOSPITAL GERAL', 'HOSPITAL CENTRAL DA AERONAUTICA HCA'),
      ('HOSPITAL GERAL', 'CBMERJ HOSP ARISTARCHO PESSOA HOSP DO CORPO DE BOMBEIROS'),
      ('PRONTO SOCORRO GERAL', 'SEAP CGSP RJ HOSPITAL DR HAMILTON AGOSTINHO VIEIRA CASTRO'),
      ('HOSPITAL GERAL', 'INSTITUTO ESTADUAL DE DERMATOLOGIA SANITARIA'),
      ('HOSPITAL GERAL', 'CENTRO REUMATOLOGICO BOTAFOGO'),
      ('HOSPITAL GERAL', 'HOSPITAL UNIVERSITARIO DOS SERVIDORES DO ESTADO'),
    ];
    const general = [
      ('Hospitales Generales', 'Hospital Clinic de Barcelona'),
      ('Hospitals i clíniques', 'Clínica Sant Jordi'),
      ('HOSPITAL GERAL', 'HOSPITAL E MATERNIDADE SALVALUS'),
      ('HOSPITAL GERAL', 'HOSPITAL ISRAELITA ALBERT EINSTEIN'),
      ('PRONTO SOCORRO GERAL', 'HOSPITAL MUNICIPAL'),
      ('UNIDADE MISTA', 'NIG BARRA'),
      ('Hospital', 'JACKSON MEMORIAL HOSPITAL'),
      ('Hospital', 'UNIVERSITY OF MIAMI HOSPITAL AND CLINICS-UHEALTH TOWER'),
      ('HOSPITAL GERAL', 'HC DA FMUSP HOSPITAL DAS CLINICAS SAO PAULO'),
      ('HOSPITAL GERAL', 'HOSPITAL UNIVERSITARIO CLEMENTINO FRAGA FILHO'),
      ('Hospitales Generales', "Hospital Universitari Vall D'Hebron"),
    ];
    for (final (subtype, name) in specialised) {
      expect(isSpecialised(subtype, name), true, reason: '$subtype: $name');
    }
    for (final (subtype, name) in general) {
      expect(isSpecialised(subtype, name), false, reason: '$subtype: $name');
    }
    expect(isSpecialised(null, 'Hospital Sant Joan'), false);
  });

  test('every city of the seed sends its people to a general hospital', () {
    final places = [
      for (final c in careCenterSeed)
        if (c.latitude != null && c.longitude != null)
          Place(id: 0, name: c.name, kind: c.kind, city: c.city, at: LatLon(c.latitude!, c.longitude!), subtype: c.subtype),
    ];
    final people = populate(places, 20, 60, Random(11));
    expect(people.map((p) => p.city).toSet(), hasLength(greaterThanOrEqualTo(7)));
    for (final person in people) {
      expect(person.hospital.isGeneralHospital, true, reason: '${person.city}: ${person.hospital.name}');
    }
  });

  test('homes are within 1.5 km of a care center of their own city', () {
    final random = Random(1);
    for (var i = 0; i < 200; i++) {
      final home = randomPointNear(sagradaFamilia, random);
      expect(distanceMeters(sagradaFamilia, home), lessThanOrEqualTo(homeRadiusMeters + 1));
    }
  });

  test('every city gets its people, at home, going to the nearest hospital', () {
    final places = [
      place(1, 'Barcelona', 'hospital', hospitalDelMar),
      place(2, 'Barcelona', 'clinic', sagradaFamilia),
      place(3, 'Reus', 'hospital', const LatLon(41.1554, 1.1076)),
      place(4, 'Cornudella de Montsant', 'health_station', const LatLon(41.2648, 0.9063)),
      place(5, 'São Paulo', 'hospital', const LatLon(-23.5558, -46.6696)),
    ];
    final people = populate(places, 3, 60, Random(2), conditions: [cold, diabetes]);
    expect(people, hasLength(12));
    expect(people.map((p) => p.id), containsAll(['barcelona-1', 'cornudella-de-montsant-3', 'sao-paulo-2']));
    for (final person in people) {
      expect(person.at, person.home);
      expect(person.state, PersonState.home);
      expect(person.hospital, nearestHospital(person.home, places));
      expect(person.mode, travelMode(distanceMeters(person.home, person.hospital.at)));
      // A chronic condition's first visit falls in the first days; the
      // first acute episode is ahead.
      if (person.chronic case final chronic?) {
        expect(chronic.condition.code, 'diabetes');
        expect(simDay(chronic.dueAt!), inInclusiveRange(1, chronicOnsetDays));
      }
      expect(person.acute, isNull);
      expect(person.acuteOnsetAt, greaterThanOrEqualTo(simStartMinutes + minutesPerDay));
    }
    final cornudella = people.firstWhere((p) => p.city == 'Cornudella de Montsant');
    expect(cornudella.hospital.city, 'Reus');
    // Some 20 km from Reus: by car.
    expect(cornudella.mode, TravelMode.car);
  });

  test('a record carries the person, keyed by id', () {
    final person = populate([place(1, 'Reus', 'hospital', const LatLon(41.1554, 1.1076))], 1, 10, Random(3), conditions: [cold]).single;
    // Only an acute condition: healthy until the first episode.
    expect(person.chronic, isNull);
    expect((person.record(13, 10)['value'] as Map)['conditionName'], isNull);
    person.beginAcute(cold, simStartMinutes, Random(3));
    final record = person.record(13, 10);
    expect(record['key'], 'reus-1');
    final value = record['value'] as Map;
    expect(value.keys, [
      'id', 'name', 'age', 'city', 'lat', 'lon', 'homeLat', 'homeLon', 'hospitalId', 'hospitalName',
      'state', 'mode', 'conditionName', 'conditionType', 'simTime', 'day', 'turn',
    ]);
    expect(value['name'], person.profile.name);
    expect(value['conditionName'], 'Common cold');
    expect(value['conditionType'], 'acute');
    expect(value['mode'], 'walk');
    expect(value['simTime'], '08:10');
    expect(value['day'], 1);
    expect(value['state'], 'home');
    expect(value['hospitalId'], 1);
  });

  test('city slugs are plain ASCII', () {
    expect(citySlug('São Paulo'), 'sao-paulo');
    expect(citySlug('Cornudella de Montsant'), 'cornudella-de-montsant');
    expect(citySlug('Fort Lauderdale'), 'fort-lauderdale');
  });

  test('the feed keeps the latest move of each of its people', () {
    final feed = PeopleFeed(throwingKafka, people: ['reus-1', 'reus-2'], random: Random(4));
    expect(feed.group, startsWith('healthhub-api-'));
    Map<String, Object?> at(String id, int turn) => {
      'id': id,
      'city': 'Reus',
      'lat': 41.1,
      'lon': 1.1,
      'homeLat': 41.2,
      'homeLon': 1.2,
      'hospitalId': 1,
      'hospitalName': 'Hospital Sant Joan',
      'state': 'to_hospital',
      'simTime': '09:10',
      'day': 1,
      'turn': turn,
    };
    feed
      ..add(at('reus-1', 1))
      ..add(at('reus-2', 1))
      ..add(at('reus-1', 2))
      ..add('not a move')
      // Someone else's person, and moves missing or mistyping what the map uses.
      ..add(at('miami-1', 3))
      ..add({...at('reus-2', 3), 'homeLat': null})
      ..add({...at('reus-2', 3), 'state': 'flying'})
      ..add({...at('reus-2', 3), 'simTime': 'noon'})
      ..add({...at('reus-2', 3), 'day': 0})
      ..add(Map.of(at('reus-2', 3))..remove('hospitalName'));
    expect(feed.people, [at('reus-1', 2), at('reus-2', 1)]);
    // Only the kept moves are recent events, newest first.
    expect([for (final event in feed.recent) event['turn']], [2, 1, 1]);
  });

  test('the feed keeps the latest records as events, up to its limit', () {
    final feed = PeopleFeed(throwingKafka, people: ['reus-1']);
    for (var turn = 0; turn < PeopleFeed.recentLimit + 5; turn++) {
      feed.add({
        'id': 'reus-1', 'city': 'Reus', 'lat': 41.1, 'lon': 1.1, 'homeLat': 41.2, 'homeLon': 1.2,
        'hospitalName': 'H', 'state': 'home', 'simTime': '06:00', 'day': 1, 'turn': turn,
      }, partition: 0, offset: turn);
    }
    expect(feed.recent, hasLength(PeopleFeed.recentLimit));
    expect(feed.recent.first['offset'], PeopleFeed.recentLimit + 4);
    expect(feed.recent.first['partition'], 0);
  });

  test('a stopped simulation stays stopped, even started again at once', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final turns = <String, List<int>>{};
    proxy.listen((request) async {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      for (final record in body['records'] as List) {
        final value = (record as Map)['value'] as Map;
        turns.putIfAbsent(value['id'] as String, () => []).add(value['turn'] as int);
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write('{"offsets":[{"partition":0,"offset":0}]}');
      await request.response.close();
    });
    final kafka = KafkaRest(Uri.parse('http://127.0.0.1:${proxy.port}'));
    addTearDown(() async {
      kafka.close();
      await proxy.close(force: true);
    });
    final places = [const Place(id: 1, name: 'H', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076))];
    final simulation = Simulation(populate(places, 1, 10, Random(6)), const SimulationSettings(turn: Duration(milliseconds: 30), minutesPerTurn: 10), kafka)
      ..start();
    final firstRun = simulation.run;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    simulation
      ..stop()
      ..start();
    // Every start is a new run, so its event ids never repeat the last's.
    expect(simulation.run, matches(RegExp(r'^[0-9a-f]{8}$')));
    expect(simulation.run, isNot(firstRun));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    simulation.stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final published = turns['reus-1']!.length;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // Nothing after the stop, and no turn twice in a row from two loops.
    expect(turns['reus-1']!.length, published);
    final second = turns['reus-1']!.skipWhile((t) => t != 0).skip(1).skipWhile((t) => t != 0).toList();
    expect(second.toSet().length, second.length);
  });

  test('settings fall back to the defaults', () {
    final settings = SimulationSettings.fromEnvironment({'HEALTHHUB_SIM_PEOPLE': '0', 'HEALTHHUB_SIM_TURN_MS': 'x'});
    expect(settings.peoplePerCity, 10);
    expect(settings.turn, const Duration(seconds: 1));
    expect(settings.minutesPerTurn, 60);
    expect(SimulationSettings.fromEnvironment({'HEALTHHUB_SIM_PEOPLE': '3'}).peoplePerCity, 3);
  });
}

MedicalCondition condition(
  String code,
  String type, {
  int count = 1,
  int interval = 1,
  int stay = 2,
  int minAge = 18,
  int maxAge = 90,
  double prevalence = 1,
  double femaleShare = 0.5,
  bool urgent = false,
  int? followUpStay,
  int? courseGap,
}) =>
    MedicalCondition(
      code: code,
      name: code == 'cold' ? 'Common cold' : code,
      type: type,
      prevalence: prevalence,
      minAge: minAge,
      maxAge: maxAge,
      summary: 's',
      treatment: 't',
      treatmentDurationDays: type == 'acute' ? 7 : null,
      duration: 'd',
      visitCount: count,
      visitIntervalDays: interval,
      stayHours: stay,
      first: const ['First, I am {name}, {age}.', 'First 2 {first_name}', 'First 3 {first_name}'],
      repeat: const ['Repeat {visit_number} after {days_since_first_visit} days', 'Repeat 2 {name}', 'Repeat 3 {name}'],
      last: const ['Last at {hospital} in {city}, a {sex} {occupation}', 'Last 2 {name}', 'Last 3 {name}'],
      femaleShare: femaleShare,
      urgent: urgent,
      followUpStayHours: followUpStay,
      courseGapDays: courseGap,
    );

final cold = condition('cold', 'acute');
final diabetes = condition('diabetes', 'chronic', count: 3, interval: 30, stay: 3, minAge: 40);

/// A client nothing in these tests calls.
final throwingKafka = KafkaRest(Uri.parse('http://127.0.0.1:1'));
