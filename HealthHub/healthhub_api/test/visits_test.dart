import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/admissions.dart';
import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/kafka_rest.dart';
import 'package:healthhub_api/people_profiles.dart';
import 'package:healthhub_api/simulation.dart';
import 'package:test/test.dart';

import 'simulation_test.dart' show condition, throwingKafka;

void main() {
  const reusHospital = Place(
    id: 7,
    name: 'Hospital Sant Joan',
    kind: 'hospital',
    city: 'Reus',
    at: LatLon(41.1554, 1.1076),
  );
  // About 1 km from the hospital: on foot, 13 minutes.
  const nearHome = LatLon(41.1644, 1.1076);
  // About 20 km away, as from Cornudella: by car.
  const farHome = LatLon(41.2648, 0.9063);
  const profile = Profile(firstName: 'Núria', lastName: 'Puig Soler', age: 54, sex: 'woman', occupation: 'teacher');

  Person person({LatLon home = nearHome, int minutesPerTurn = 60, Profile who = profile, String id = 'reus-1'}) => Person(
    id: id,
    city: 'Reus',
    home: home,
    hospital: reusHospital,
    profile: who,
    minutesPerTurn: minutesPerTurn,
  );

  /// Runs [p] for [turns] turns from [from], returning each admission with
  /// its turn.
  List<(int, Map<String, Object?>)> run(
    Person p,
    int turns,
    List<MedicalCondition> conditions, {
    int minutesPerTurn = 60,
    int seed = 1,
    int from = 0,
    Random? random,
  }) {
    random ??= Random(seed);
    return [
      for (var turn = from; turn < from + turns; turn++)
        if (advance(p, turn: turn, minutesPerTurn: minutesPerTurn, random: random, conditions: conditions, run: 'r1')
            case final admission?)
          (turn, admission),
    ];
  }

  /// The clock at [admission]'s arrival, in minutes.
  int arrivalOf(Map<String, Object?> admission) {
    final time = (admission['simTime'] as String).split(':').map(int.parse).toList();
    return dayStart(admission['day'] as int) + time[0] * 60 + time[1];
  }

  int hourOf(Map<String, Object?> admission) => int.parse((admission['simTime'] as String).substring(0, 2));

  final diabetes = condition('diabetes', 'chronic', count: 3, interval: 30, stay: 3);
  final cold = condition('cold', 'acute');
  final flu = condition('flu', 'acute', count: 2, interval: 3, stay: 4);
  final walkMinutes = travelMinutes(distanceMeters(nearHome, reusHospital.at), TravelMode.walk);

  group('profiles', () {
    test('names follow the city', () {
      expect(localeOf('Reus'), NameLocale.catalan);
      expect(localeOf('Cornudella de Montsant'), NameLocale.catalan);
      expect(localeOf('Barcelona'), NameLocale.catalan);
      expect(localeOf('Miami'), NameLocale.us);
      expect(localeOf('Fort Lauderdale'), NameLocale.us);
      expect(localeOf('São Paulo'), NameLocale.brazilian);
      expect(localeOf('Rio de Janeiro'), NameLocale.brazilian);
      for (final locale in NameLocale.values) {
        final (first, last) = nameCounts(locale);
        expect(first, greaterThanOrEqualTo(40));
        expect(last, greaterThanOrEqualTo(40));
      }
      final random = Random(3);
      // Catalan and Spanish names carry two surnames, American ones one.
      for (var i = 0; i < 50; i++) {
        final catalan = randomProfile('Reus', random);
        expect(catalan.lastName.split(' '), hasLength(2));
        expect(catalan.lastName.split(' ').toSet(), hasLength(2));
        expect(randomProfile('Miami', random).lastName.split(' '), hasLength(1));
        expect(randomProfile('São Paulo', random).lastName.split(' ').length, inInclusiveRange(1, 2));
      }
      expect(const Profile(firstName: 'A', lastName: 'B C', age: 30, sex: 'man', occupation: 'cook').name, 'A B C');
    });

    test('ages are adult, mostly middle-aged, and the old are retired', () {
      final random = Random(4);
      final profiles = [for (var i = 0; i < 3000; i++) randomProfile('Barcelona', random)];
      final ages = profiles.map((p) => p.age);
      expect(ages.every((a) => a >= 18 && a <= 90), true);
      expect(ages.reduce(min), lessThan(22));
      expect(ages.reduce(max), greaterThan(85));
      final mean = ages.reduce((a, b) => a + b) / ages.length;
      expect(mean, closeTo(48, 3));
      expect(ages.where((a) => a >= 80).length / ages.length, closeTo(0.05, 0.02));
      expect(profiles.map((p) => p.sex).toSet(), {'man', 'woman'});
      for (final p in profiles) {
        if (p.age >= retirementAge) expect(p.occupation, startsWith('retired '));
        if (p.age < 63) expect(p.occupation, isNot(startsWith('retired')));
      }
      // Every occupation reads after "a", as the templates say it.
      for (final job in occupations) {
        expect(job[0], isNot(anyOf('a', 'e', 'i', 'o', 'u')), reason: job);
      }
    });
  });


  group('visits', () {
    test('a chronic condition: first only once, then courses of repeats and a last, the count going on', () {
      final p = person()..giveChronic(diabetes, 2, Random(1));
      final admissions = run(p, 24 * 400, [diabetes]);
      expect(admissions.length, greaterThanOrEqualTo(6));
      final kinds = [for (final (_, a) in admissions.take(6)) a['visit']];
      expect(kinds, ['first', 'repeat', 'last', 'repeat', 'repeat', 'last']);
      expect([for (final (_, a) in admissions) a['visitNumber']], [for (var n = 1; n <= admissions.length; n++) n]);
      expect(admissions.where((a) => a.$2['visit'] == 'first'), hasLength(1));
      final days = [for (final (_, a) in admissions) a['day'] as int];
      expect(days.first, 2);
      expect(days[1] - days[0], 30);
      expect(days[2] - days[1], 30);
      // The next course after a gap; still the same condition.
      expect(days[3] - days[2], inInclusiveRange(chronicGapDays.$1, chronicGapDays.$2));
      expect(admissions.every((e) => e.$2['conditionCode'] == 'diabetes'), true);
      // A random template of the visit's kind, with the visit and the days
      // since the condition's first visit, across courses.
      expect([
        'Repeat 2 after 30 days',
        'Repeat 2 Núria Puig Soler',
        'Repeat 3 Núria Puig Soler',
      ], contains(admissions[1].$2['complaint']));
      expect([
        'Repeat 4 after ${days[3] - days[0]} days',
        'Repeat 2 Núria Puig Soler',
        'Repeat 3 Núria Puig Soler',
      ], contains(admissions[3].$2['complaint']));
      for (final (_, a) in admissions) {
        expect(hourOf(a), inInclusiveRange(visitFirstHour, visitLastHour));
      }
    });

    test('a stay lasts its hours from the arrival minute, then the person goes home', () {
      final p = person()..giveChronic(diabetes, 1, Random(2));
      final random = Random(2);
      final states = <PersonState>[];
      int? arrived;
      Map<String, Object?>? admission;
      for (var turn = 0; turn < 48; turn++) {
        final a = advance(p, turn: turn, minutesPerTurn: 60, random: random, conditions: [diabetes], run: 'r1');
        if (a != null) (arrived, admission) = (turn, a);
        states.add(p.state);
      }
      expect(arrived, isNotNull);
      // Walking 1 km takes 13 minutes: there the turn they leave, at the
      // minute they get there.
      expect(walkMinutes, 13);
      expect(states[arrived!], PersonState.atHospital);
      expect(admission!['simTime'], simTime(simMinutes(arrived, 60) + walkMinutes));
      // Three hours from HH:13 they leave, in the turn after the third, and
      // are home within it.
      expect(states.sublist(arrived, arrived + 4), everyElement(PersonState.atHospital));
      expect(states[arrived + 4], PersonState.home);
      expect(p.at, nearHome);
      expect(simDay(p.nextVisitAt!), 31);
    });

    test('an acute single visit uses the first templates, and episodes recur', () {
      // The onset before the first daytime slot: the visit is that day.
      final p = person()..beginAcute(cold, dayStart(3) + 7 * 60, Random(3));
      final admissions = run(p, 24 * 400, [cold], seed: 3);
      expect(admissions.length, greaterThanOrEqualTo(2));
      expect(admissions.every((a) => a.$2['visit'] == 'first' && a.$2['visitNumber'] == 1), true);
      expect(admissions.first.$2['day'], 3);
      final gap = (admissions[1].$2['day'] as int) - (admissions[0].$2['day'] as int);
      expect(gap, greaterThanOrEqualTo(1));
    });

    test('after an acute episode the person is healthy until the next, drawn among the acute ones', () {
      final p = person()..beginAcute(flu, simStartMinutes, Random(4));
      final random = Random(4);
      final kinds = <String>[];
      var turn = 0;
      final conditions = [diabetes, cold];
      while (kinds.length < 2) {
        final a = advance(p, turn: turn++, minutesPerTurn: 60, random: random, conditions: conditions, run: 'r1');
        if (a != null) kinds.add(a['visit'] as String);
      }
      expect(kinds, ['first', 'last']);
      // Home again: healthy, nothing due, the next episode ahead.
      while (p.state != PersonState.home) {
        advance(p, turn: turn++, minutesPerTurn: 60, random: random, conditions: conditions, run: 'r1');
      }
      expect(p.condition, isNull);
      expect(p.acute, isNull);
      expect(p.nextVisitAt, isNull);
      final onset = p.acuteOnsetAt!;
      expect(onset, greaterThanOrEqualTo(simMinutes(turn - 1, 60) + minutesPerDay));
      expect(p.record(turn, 60)['value'], containsPair('conditionName', null));
      while (p.acute == null) {
        advance(p, turn: turn++, minutesPerTurn: 60, random: random, conditions: conditions, run: 'r1');
      }
      expect(simMinutes(turn - 1, 60), greaterThanOrEqualTo(onset));
      // Never the chronic condition as an episode.
      expect(p.acute!.condition.code, 'cold');
      expect(p.chronic, isNull);
      expect(p.nextVisitAt, isNotNull);
    });

    test('nobody moves without conditions', () {
      final p = person();
      startConditions(p, const [], Random(5));
      expect(p.chronic, isNull);
      expect(p.acuteOnsetAt, isNull);
      expect(run(p, 24 * 30, const []), isEmpty);
      expect(p.state, PersonState.home);
      expect(p.at, nearHome);
    });

    test('a car trip moves at most its step a turn, and arrives at the minute the distance takes', () {
      final p = person(home: farHome, minutesPerTurn: 10)..giveChronic(diabetes, 1, Random(6));
      expect(p.mode, TravelMode.car);
      final random = Random(6);
      var turn = 0;
      while (p.state == PersonState.home) {
        advance(p, turn: turn++, minutesPerTurn: 10, random: random, conditions: [diabetes], run: 'r1');
      }
      final departure = simMinutes(turn - 1, 10);
      var previous = farHome;
      var trip = 0;
      Map<String, Object?>? admission;
      // The first step was in the turn they left.
      expect(distanceMeters(previous, p.at), closeTo(p.step, p.step * 0.005));
      previous = p.at;
      while (p.state == PersonState.toHospital) {
        admission = advance(p, turn: turn++, minutesPerTurn: 10, random: random, conditions: [diabetes], run: 'r1');
        if (p.state == PersonState.toHospital) {
          // Straight in degrees, so within a fraction of a percent of the step.
          expect(distanceMeters(previous, p.at), closeTo(p.step, p.step * 0.005));
        }
        previous = p.at;
        trip++;
      }
      final meters = distanceMeters(farHome, reusHospital.at);
      // About 25 km at 50 km/h, 8.3 km a turn of 10 minutes: three turns.
      expect(trip + 1, (meters / p.step).ceil());
      expect(p.at, reusHospital.at);
      expect(p.state, PersonState.atHospital);
      // Admitted on the turn they arrive, at the exact minute.
      final arrival = departure + travelMinutes(meters, TravelMode.car);
      expect(admission!['simTime'], simTime(arrival));
      expect(arrival, inInclusiveRange(simMinutes(turn - 1, 10), simMinutes(turn, 10)));
    });

    test('a long chronic course with no gap goes on every interval, as dialysis does', () {
      final dialysis = condition('dialysis', 'chronic', count: 3, interval: 2, stay: 4, courseGap: 0);
      final p = person()..giveChronic(dialysis, 1, Random(7));
      final admissions = run(p, 24 * 60, [dialysis], seed: 7);
      expect(admissions.length, greaterThanOrEqualTo(25));
      final days = [for (final (_, a) in admissions) a['day'] as int];
      for (var i = 1; i < days.length; i++) {
        expect(days[i] - days[i - 1], 2);
      }
      expect([for (final (_, a) in admissions.take(7)) a['visit']], [
        'first', 'repeat', 'last', 'repeat', 'repeat', 'last', 'repeat',
      ]);
      expect([for (final (_, a) in admissions) a['visitNumber']], [for (var n = 1; n <= admissions.length; n++) n]);
    });

    test('a follow-up visit stays its own hours', () {
      final appendicitis = condition('appendicitis', 'acute', count: 2, interval: 14, stay: 48, followUpStay: 1, urgent: true);
      final p = person()..beginAcute(appendicitis, dayStart(2) + 10 * 60, Random(8));
      final random = Random(8);
      final stays = <int>[];
      for (var turn = 0; turn < 24 * 30 && stays.length < 2; turn++) {
        final a = advance(p, turn: turn, minutesPerTurn: 60, random: random, conditions: const [], run: 'r1');
        if (a != null) stays.add(p.leaveAt! - arrivalOf(a));
      }
      expect(stays, [48 * 60, 60]);
      expect(appendicitis.stayHoursOf(VisitKind.first), 48);
      expect(appendicitis.stayHoursOf(VisitKind.last), 1);
      expect(cold.stayHoursOf(VisitKind.repeat), cold.stayHours);
    });

    test('an urgent first visit is made at night, at once', () {
      final renalColic = condition('renal_colic', 'acute', count: 2, interval: 14, stay: 8, urgent: true);
      // The pain starts at 02:30 on day 3.
      final p = person()..beginAcute(renalColic, dayStart(3) + 2 * 60 + 30, Random(9));
      expect(p.nextVisitAt, dayStart(3) + 2 * 60 + 30);
      final admissions = run(p, 24 * 30, const [], seed: 9);
      // They leave at the turn after the onset, 03:00, and walk 13 minutes.
      expect(admissions.first.$2['simTime'], '03:13');
      expect(admissions.first.$2['day'], 3);
      expect(admissions.first.$2['visit'], 'first');
      // The follow-up is planned: in the daytime.
      expect(hourOf(admissions[1].$2), inInclusiveRange(visitFirstHour, visitLastHour));
    });

    test('a visit due while the person is out waits until they are home', () {
      final longStay = condition('long', 'acute', stay: 10);
      final urgent = condition('urgent', 'acute', urgent: true);
      final p = person()..giveChronic(diabetes, 1, Random(10));
      p.chronic!.dueAt = dayStart(1) + 10 * 60;
      p.acute = Course(longStay)..dueAt = dayStart(1) + 8 * 60;
      final admissions = run(p, 24 * 5, const [], seed: 10);
      // The acute visit at 08:13 lasts until 18:13; the chronic one, due at
      // 10:00, waits for the next daytime slot after they are home.
      expect(admissions[0].$2['conditionCode'], 'long');
      expect(admissions[0].$2['simTime'], '08:13');
      expect(admissions[1].$2['conditionCode'], 'diabetes');
      expect(admissions[1].$2['day'], 2);
      expect(hourOf(admissions[1].$2), inInclusiveRange(visitFirstHour, visitLastHour));

      // An emergency that starts during a visit goes at once when they are
      // back: the chronic visit 10:13 to 13:13, home at 14:00, out at 15:00.
      final q = person()..giveChronic(diabetes, 1, Random(11));
      q.chronic!.dueAt = dayStart(1) + 10 * 60;
      q.beginAcute(urgent, dayStart(1) + 11 * 60 + 30, Random(11));
      final both = run(q, 24 * 2, const [], seed: 11);
      expect([for (final (_, a) in both) (a['conditionCode'], a['simTime'])], [
        ('diabetes', '10:13'),
        ('urgent', '15:13'),
      ]);
    });

    test('over a year, chronic and acute visits interleave, one at a time', () {
      final random = Random(12);
      final byCode = {for (final c in conditionSeed) c.code: c};
      var both = 0;
      var nightUrgent = 0;
      const people = 300;
      for (var n = 0; n < people; n++) {
        final p = person(id: 'reus-$n', who: randomProfile('Reus', random));
        startConditions(p, conditionSeed, random);
        final admissions = [for (final (_, a) in run(p, 24 * 365, conditionSeed, random: random)) a];
        final chronic = [for (final a in admissions) if (a['conditionType'] == 'chronic') a];
        final acute = [for (final a in admissions) if (a['conditionType'] == 'acute') a];
        if (chronic.isNotEmpty && acute.isNotEmpty) both++;
        // One chronic condition, its first template once, its count going on.
        expect(chronic.map((a) => a['conditionCode']).toSet().length, lessThanOrEqualTo(1));
        expect(chronic.where((a) => a['visit'] == 'first').length, lessThanOrEqualTo(1));
        if (chronic.isNotEmpty) {
          expect(chronic.first['visit'], 'first');
          expect([for (final a in chronic) a['visitNumber']], [for (var i = 1; i <= chronic.length; i++) i]);
          expect(byCode[chronic.first['conditionCode']]!.isChronic, true);
        }
        // Every acute episode starts with its first visit.
        for (final a in acute) {
          expect(a['visit'] == 'first', a['visitNumber'] == 1);
          expect(byCode[a['conditionCode']]!.isChronic, false);
        }
        // Never two visits at once: each arrival after the last stay ended.
        for (var i = 1; i < admissions.length; i++) {
          final previous = admissions[i - 1];
          final kind = VisitKind.values.firstWhere((k) => k.json == previous['visit']);
          final stay = byCode[previous['conditionCode']]!.stayHoursOf(kind) * 60;
          expect(arrivalOf(admissions[i]), greaterThanOrEqualTo(arrivalOf(previous) + stay));
        }
        // Planned visits in the daytime; only an emergency's first at night.
        for (final a in admissions) {
          final urgentFirst = a['visit'] == 'first' && byCode[a['conditionCode']]!.urgent;
          if (!urgentFirst) {
            expect(hourOf(a), inInclusiveRange(visitFirstHour, visitLastHour), reason: '$a');
          } else if (hourOf(a) < visitFirstHour || hourOf(a) > visitLastHour) {
            nightUrgent++;
          }
        }
      }
      // About 60% have a chronic condition, and nearly all an episode a year.
      expect(both, greaterThan(people * 0.4));
      expect(nightUrgent, greaterThan(0));
    });
  });

  test('an admission carries the person, the condition, the visit and the complaint', () {
    final p = person()..beginAcute(flu, simStartMinutes, Random(7));
    final (turn, admission) = run(p, 48, [flu], seed: 7).first;
    expect(admission.keys, [
      'type',
      'eventId',
      'personId',
      'name',
      'age',
      'sex',
      'occupation',
      'city',
      'conditionCode',
      'conditionName',
      'conditionType',
      'visit',
      'visitNumber',
      'complaint',
      'hospitalId',
      'hospitalName',
      'simTime',
      'day',
      'turn',
    ]);
    expect(admission['type'], 'admission');
    // The run id first: the same person, day and turn of another run is
    // another event.
    expect(admission['eventId'], 'r1-reus-1-d1-t$turn');
    expect(admission['name'], 'Núria Puig Soler');
    expect(admission['age'], 54);
    expect(admission['conditionType'], 'acute');
    expect(admission['visit'], 'first');
    expect(admission['hospitalId'], 7);
    expect(admission['complaint'], isNot(contains('{')));
    expect(
      flu.first.map((t) => renderComplaint(t, complaintValues(p, visitNumber: 1, daysSinceFirstVisit: 0))),
      contains(admission['complaint']),
    );
    expect(PeopleFeed.isAdmission(admission), true);
    Map<String, Object?> of(String run) => admissionEvent(
      p,
      condition: flu,
      run: run,
      turn: turn,
      minutes: simMinutes(turn, 60),
      kind: VisitKind.first,
      visitNumber: 1,
      complaint: 'x',
    );
    expect(of('aaaa0001')['eventId'], isNot(of('bbbb0002')['eventId']));
  });

  group('feed', () {
    Map<String, Object?> admissionOf(String person, int turn) => {
      'type': 'admission',
      'eventId': 'r1-$person-d1-t$turn',
      'personId': person,
      'name': 'Núria Puig Soler',
      'age': 54,
      'sex': 'woman',
      'occupation': 'teacher',
      'city': 'Reus',
      'conditionCode': 'flu',
      'conditionName': 'Influenza',
      'conditionType': 'acute',
      'visit': 'first',
      'visitNumber': 1,
      'complaint': 'I have a fever.',
      'hospitalId': 7,
      'hospitalName': 'Hospital Sant Joan',
      'simTime': '09:00',
      'day': 1,
      'turn': turn,
    };
    Map<String, Object?> moveOf(String id, int turn) => {
      'id': id,
      'city': 'Reus',
      'lat': 41.1,
      'lon': 1.1,
      'homeLat': 41.2,
      'homeLon': 1.2,
      'hospitalName': 'H',
      'state': 'home',
      'simTime': '06:00',
      'day': 1,
      'turn': turn,
    };

    test('admissions of its people, valid, are kept and handed on', () {
      final handed = <Map<String, Object?>>[];
      final feed = PeopleFeed(throwingKafka, people: ['reus-1'], onAdmission: handed.add);
      feed
        ..addAdmission(admissionOf('reus-1', 3), partition: 0, offset: 9)
        ..addAdmission(admissionOf('miami-1', 3))
        ..addAdmission({...admissionOf('reus-1', 4), 'sex': 'other'})
        ..addAdmission({...admissionOf('reus-1', 4), 'age': '54'})
        ..addAdmission({...admissionOf('reus-1', 4), 'visit': 'second'})
        ..addAdmission({...admissionOf('reus-1', 4), 'conditionType': 'mild'})
        ..addAdmission({...admissionOf('reus-1', 4), 'complaint': ''})
        ..addAdmission({...admissionOf('reus-1', 4), 'visitNumber': 0})
        ..addAdmission({...admissionOf('reus-1', 4), 'simTime': '9am'})
        ..addAdmission(Map.of(admissionOf('reus-1', 4))..remove('hospitalId'))
        // Beyond what the database's INT columns hold, or a NUL it refuses.
        ..addAdmission({...admissionOf('reus-1', 4), 'hospitalId': 2147483648})
        ..addAdmission({...admissionOf('reus-1', 4), 'day': PeopleFeed.maxDay + 1})
        ..addAdmission({...admissionOf('reus-1', 4), 'turn': 1 << 40})
        ..addAdmission({...admissionOf('reus-1', 4), 'visitNumber': PeopleFeed.maxVisitNumber + 1})
        ..addAdmission({...admissionOf('reus-1', 4), 'age': 91})
        ..addAdmission({...admissionOf('reus-1', 4), 'complaint': 'I have\u0000 a fever.'})
        ..addAdmission({...admissionOf('reus-1', 4), 'name': 'Núria\u0000'})
        ..addAdmission('not an admission');
      expect(handed, [admissionOf('reus-1', 3)]);
      expect(feed.recent.single, {...admissionOf('reus-1', 3), 'partition': 0, 'offset': 9});
      // An admission is no move: the map's people don't change.
      expect(feed.people, isEmpty);
      expect(PeopleFeed.isAdmission({...admissionOf('reus-1', 4), 'hospitalId': 2147483647}), true);
    });

    test('an admission read twice is kept and handed on once', () {
      final handed = <Map<String, Object?>>[];
      final feed = PeopleFeed(throwingKafka, people: ['reus-1'], onAdmission: handed.add);
      feed
        ..addAdmission(admissionOf('reus-1', 3), partition: 0, offset: 1)
        ..addAdmission(admissionOf('reus-1', 3), partition: 0, offset: 2)
        ..addAdmission(admissionOf('reus-1', 4), partition: 0, offset: 3);
      expect([for (final a in handed) a['turn']], [3, 4]);
      expect([for (final e in feed.recent) e['offset']], [3, 1]);
      // The memory is bounded: an id long gone is new again.
      for (var turn = 5; turn < 5 + PeopleFeed.seenLimit; turn++) {
        feed.addAdmission(admissionOf('reus-1', turn));
      }
      handed.clear();
      feed
        ..addAdmission(admissionOf('reus-1', 3))
        ..addAdmission(admissionOf('reus-1', 5 + PeopleFeed.seenLimit - 1));
      expect([for (final a in handed) a['turn']], [3]);
    });

    test('records go by topic', () {
      final feed = PeopleFeed(throwingKafka, people: ['reus-1']);
      feed
        ..addRecord(KafkaRecord(topic: movesTopic, key: 'reus-1', value: moveOf('reus-1', 1), partition: 0, offset: 1))
        ..addRecord(
          KafkaRecord(topic: admissionsTopic, key: 'reus-1', value: admissionOf('reus-1', 1), partition: 0, offset: 1),
        )
        // A move on the admissions topic is no admission.
        ..addRecord(
          KafkaRecord(topic: admissionsTopic, key: 'reus-1', value: moveOf('reus-1', 2), partition: 0, offset: 2),
        );
      expect([for (final e in feed.recent) e['type']], ['admission', 'move']);
    });

    test('moves never push admissions out, and both merge newest first', () {
      final feed = PeopleFeed(throwingKafka, people: ['reus-1']);
      for (var turn = 0; turn < 300; turn++) {
        feed.add(moveOf('reus-1', turn), partition: 0, offset: turn);
        if (turn % 100 == 50) feed.addAdmission(admissionOf('reus-1', turn), partition: 0, offset: turn);
      }
      final recent = feed.recent;
      expect(recent.where((e) => e['type'] == 'move'), hasLength(PeopleFeed.recentLimit));
      expect([for (final e in recent.where((e) => e['type'] == 'admission')) e['turn']], [250, 150, 50]);
      expect(recent.first['turn'], 299);
      // Newest first by arrival: the admission of turn 250 after the move of 250.
      final at = recent.indexWhere((e) => e['type'] == 'admission');
      expect(recent[at - 1], containsPair('turn', 251));
      expect(recent[at + 1], containsPair('turn', 250));
    });
  });

  group('recorder', () {
    test('records in order, retrying a failure until it is written', () async {
      final written = <String>[];
      var failures = 2;
      final recorder = AdmissionRecorder((a) async {
        if (failures-- > 0) throw StateError('database down');
        written.add(a['eventId'] as String);
        return true;
      }, retryAfter: const Duration(milliseconds: 5));
      recorder
        ..record({'eventId': 'a'})
        ..record({'eventId': 'b'});
      expect(recorder.pending, 2);
      await recorder.idle;
      expect(written, ['a', 'b']);
      expect(recorder.pending, 0);
      recorder.record({'eventId': 'c'});
      await recorder.idle;
      expect(written, ['a', 'b', 'c']);
    });

    test('an admission already recorded is skipped, and logged', () async {
      final out = _Lines();
      final recorder = AdmissionRecorder((a) async => a['eventId'] != 'old');
      await IOOverrides.runZoned(() async {
        recorder
          ..record({'eventId': 'old'})
          ..record({'eventId': 'new'});
        await recorder.idle;
      }, stdout: () => out);
      expect(out.lines, ['admissions: old already recorded, skipped']);
      expect(recorder.pending, 0);
    });

    test('an admission the database refuses is dropped, logged, and the rest go on', () async {
      final written = <String>[];
      final err = _Lines();
      final recorder = AdmissionRecorder(
        (a) async {
          if (a['eventId'] == 'bad') throw const FormatException('value out of range');
          written.add(a['eventId'] as String);
          return true;
        },
        // Long enough that a retry would time the test out.
        retryAfter: const Duration(hours: 1),
        isPermanent: (error) => error is FormatException,
      );
      await IOOverrides.runZoned(() async {
        for (final id in ['a', 'bad', 'c']) {
          recorder.record({'eventId': id});
        }
        await recorder.idle;
      }, stderr: () => err);
      expect(written, ['a', 'c']);
      expect(err.lines.single, startsWith('admissions: dropped bad, the database refused it'));
    });

    test('beyond its limit the oldest waiting are dropped', () async {
      final recorder = AdmissionRecorder(
        (_) async => throw StateError('down'),
        retryAfter: const Duration(milliseconds: 5),
        limit: 2,
      );
      for (final id in ['a', 'b', 'c']) {
        recorder.record({'eventId': id});
      }
      expect(recorder.pending, 2);
      recorder.stop();
      await recorder.idle;
    });
  });
}

/// A standard output that keeps the lines written to it.
class _Lines implements Stdout {
  final lines = <String>[];

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
