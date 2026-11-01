import 'dart:math';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/people_profiles.dart';
import 'package:healthhub_api/simulation.dart';
import 'package:test/test.dart';

import 'simulation_test.dart' show cold, condition, diabetes, throwingKafka;

void main() {
  const hospital = Place(id: 7, name: 'Hospital Sant Joan', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076));
  const station = Place(id: 2, name: 'CAP Llibertat', kind: 'health_station', city: 'Reus', at: LatLon(41.1600, 1.1076));
  const profile = Profile(firstName: 'Núria', lastName: 'Puig Soler', age: 54, sex: 'woman', occupation: 'teacher');

  /// Someone of Reus whose primary and mental health visits go to the
  /// health station, the rest to the hospital.
  Person person(String id, LatLon home, Profile who) => Person(
    id: id,
    city: 'Reus',
    home: home,
    hospital: hospital,
    careCenters: const {CareSetting.primary: station, CareSetting.mentalHealth: station},
    profile: who,
    minutesPerTurn: 60,
  );

  /// The hour of day [admission] arrived at.
  int hourOf(Map<String, Object?> admission) => int.parse((admission['simTime'] as String).substring(0, 2));

  /// A seeded run of 400 people with the seed's conditions for 150 days of
  /// an hour a turn, [flow] set on day 1: the admissions of days 31 to 150
  /// at each care center, by id, and the hours of day of the hospital's.
  (Map<int, int>, List<int>) runWith(Map<int, double> flow, {int seed = 1}) {
    final random = Random(seed);
    final people = [
      for (var n = 1; n <= 400; n++)
        person('reus-$n', randomPointNear(hospital.at, random), randomProfile('Reus', random)),
    ];
    for (final p in people) {
      startConditions(p, conditionSeed, random);
      retime(p, simMinutes(0, 60), const {}, flow, random);
    }
    final counts = <int, int>{};
    final hours = List.filled(24, 0);
    for (var turn = 0; turn < 24 * 150; turn++) {
      for (final p in people) {
        final admission = advance(p, turn: turn, minutesPerTurn: 60, random: random, conditions: conditionSeed, run: 'r', flow: flow);
        if (admission == null || turn < 24 * 30) continue;
        final id = admission['hospitalId'] as int;
        counts[id] = (counts[id] ?? 0) + 1;
        if (id == hospital.id) hours[hourOf(admission)]++;
      }
    }
    return (counts, hours);
  }

  /// The share of [hours] from [visitFirstHour] to [visitLastHour].
  double daytime(List<int> hours) =>
      hours.sublist(visitFirstHour, visitLastHour + 1).reduce((a, b) => a + b) / hours.reduce((a, b) => a + b);

  test('a flow factor doubles, halves or resets, from 1/8 to 8', () {
    var factor = 1.0;
    final doubled = [for (var i = 0; i < 5; i++) factor = flowAfter(factor, 'double')!];
    expect(doubled, [2, 4, 8, 8, 8]);
    final halved = [for (var i = 0; i < 8; i++) factor = flowAfter(factor, 'halve')!];
    expect(halved, [4, 2, 1, 0.5, 0.25, 0.125, 0.125, 0.125]);
    expect(flowAfter(0.125, 'reset'), 1);
    expect(flowAfter(8, 'reset'), 1);
    expect(flowAfter(1, 'triple'), isNull);
    expect(flowAt(const {7: 2}, hospital), 2);
    expect(flowAt(const {7: 2}, station), 1);
    expect(flowLabel(2), '×2');
    expect(flowLabel(0.125), '×1/8');
  });

  test('a planned visit moved by the flow keeps to the daytime, on the hour', () {
    final random = Random(3);
    // Within the daytime: the next hour, that day.
    expect(visitSlotFrom(dayStart(4) + 9 * 60 + 20, random), dayStart(4) + 10 * 60);
    expect(visitSlotFrom(dayStart(4) + 9 * 60, random), dayStart(4) + 9 * 60);
    for (var i = 0; i < 100; i++) {
      // At night: a daytime hour, that day before 08:00, the next after 17:00.
      final early = visitSlotFrom(dayStart(4) + 3 * 60, random);
      expect(simDay(early), 4);
      expect((early % minutesPerDay) ~/ 60, inInclusiveRange(visitFirstHour, visitLastHour));
      final late = visitSlotFrom(dayStart(4) + 17 * 60 + 1, random);
      expect(simDay(late), 5);
      expect(late % 60, 0);
    }
  });

  test('at the normal flow nothing changes, not even the random draws', () {
    List<Map<String, Object?>> admissions(Map<int, double> flow) {
      final random = Random(5);
      final people = [
        for (var n = 1; n <= 30; n++) person('reus-$n', randomPointNear(hospital.at, random), randomProfile('Reus', random)),
      ];
      for (final p in people) {
        startConditions(p, conditionSeed, random);
        expect(retime(p, simMinutes(0, 60), const {}, flow, random), isFalse);
      }
      return [
        for (var turn = 0; turn < 24 * 60; turn++)
          for (final p in people)
            ?advance(p, turn: turn, minutesPerTurn: 60, random: random, conditions: conditionSeed, run: 'r', flow: flow),
      ];
    }

    expect(admissions(const {}), admissions(const {99: 1}));
  });

  test('the admissions at a care center scale with its flow, its daily profile kept', () {
    final (normal, normalHours) = runWith(const {});
    final (doubled, doubledHours) = runWith(const {7: 2});
    final (halved, _) = runWith(const {7: 0.5});
    final (eight, _) = runWith(const {7: 8});
    final (stationDoubled, _) = runWith(const {2: 2});
    final (stationHalved, _) = runWith(const {2: 0.5});
    double ratio(Map<int, int> counts, int id) => counts[id]! / normal[id]!;
    expect(normal[7], greaterThan(100));
    expect(normal[2], greaterThan(500));
    // About the factor: measured 1.75, 0.48, 6.6, 1.94 and 0.62 with this seed.
    expect(ratio(doubled, 7), inInclusiveRange(1.5, 2.3));
    expect(ratio(halved, 7), inInclusiveRange(0.35, 0.65));
    expect(ratio(eight, 7), inInclusiveRange(5.5, 9));
    expect(ratio(stationDoubled, 2), inInclusiveRange(1.6, 2.3));
    expect(ratio(stationHalved, 2), inInclusiveRange(0.45, 0.75));
    // The other care center keeps about its own.
    expect(ratio(halved, 2), inInclusiveRange(0.85, 1.15));
    expect(ratio(stationDoubled, 7), inInclusiveRange(0.7, 1.3));
    // Planned visits in the daytime, emergencies at any hour, as before.
    expect(daytime(doubledHours), closeTo(daytime(normalHours), 0.08));
  });

  group('a change of flow', () {
    test('brings a planned visit there forward, or puts it off, by the time left', () {
      final p = person('reus-1', hospital.at, profile)..giveChronic(diabetes, 30, Random(1));
      final now = dayStart(10) + 9 * 60;
      final due = p.chronic!.dueAt!;
      expect(p.nextDestination(p.chronic!), hospital);
      expect(retime(p, now, const {}, const {7: 2}, Random(2)), isTrue);
      final sooner = p.chronic!.dueAt!;
      // Half the time left, give or take the move to a daytime hour.
      expect(sooner - now, closeTo((due - now) / 2, minutesPerDay));
      expect((sooner % minutesPerDay) ~/ 60, inInclusiveRange(visitFirstHour, visitLastHour));
      // Halved from there: four times as long as at the double.
      expect(retime(p, now, const {7: 2}, const {7: 0.5}, Random(2)), isTrue);
      expect(p.chronic!.dueAt! - now, closeTo((sooner - now) * 4, minutesPerDay));
      // Another care center's flow leaves it be.
      final put = p.chronic!.dueAt;
      expect(retime(p, now, const {7: 0.5}, const {7: 0.5, 2: 4}, Random(2)), isFalse);
      expect(p.chronic!.dueAt, put);
    });

    test('draws the next acute onset again at the new pace', () {
      final random = Random(4);
      final now = dayStart(10);
      var total = 0;
      const people = 400;
      for (var n = 0; n < people; n++) {
        final p = person('reus-$n', hospital.at, profile)..acuteOnsetAt = now + 200 * minutesPerDay;
        expect(retime(p, now, const {}, const {2: 4}, random), isTrue);
        total += p.acuteOnsetAt! - now;
      }
      // Four times the pace: a mean gap of about a quarter of 90 days.
      expect(total / people / minutesPerDay, closeTo(acuteMeanGapDays / 4, 5));
    });

    test('thins the episodes headed to a care center slowed down, keeps the rest', () {
      final random = Random(6);
      final urgent = condition('appendicitis', 'acute', urgent: true);
      final checkUp = condition('check_up', 'acute', setting: CareSetting.primary);
      var kept = 0;
      var keptElsewhere = 0;
      for (var n = 0; n < 1000; n++) {
        final p = person('reus-$n', hospital.at, profile)..beginAcute(urgent, dayStart(5), random, flow: const {7: 0.25});
        if (p.acute != null) kept++;
        final q = person('reus-$n', hospital.at, profile)..beginAcute(checkUp, dayStart(5), random, flow: const {7: 0.25});
        if (q.acute != null) keptElsewhere++;
      }
      expect(kept / 1000, closeTo(0.25, 0.05));
      expect(keptElsewhere, 1000);
    });
  });

  test('the simulation keeps a factor per care center for the run, a new run at the normal flow', () {
    final places = [hospital, station];
    final simulation = Simulation(
      populate(places, 20, 60, Random(1), conditions: [cold, diabetes]),
      const SimulationSettings(peoplePerCity: 20),
      throwingKafka,
      conditions: [cold, diabetes],
      places: places,
      random: Random(2),
    );
    expect(simulation.flowOf(7), 1);
    expect(simulation.changeFlow(7, 'double'), 2);
    expect(simulation.changeFlow(7, 'double'), 4);
    expect(simulation.changeFlow(2, 'halve'), 0.5);
    expect(simulation.flow, {7: 4, 2: 0.5});
    expect(simulation.changeFlow(7, 'reset'), 1);
    expect(simulation.flow, {2: 0.5});
    // A care center the simulation sends nobody to, or no action.
    expect(simulation.changeFlow(99, 'double'), isNull);
    expect(simulation.changeFlow(7, 'triple'), isNull);
    // Newcomers join under the flow as it is.
    expect(simulation.setPeoplePerCity(25).joined, hasLength(5));
    simulation
      ..start()
      ..stop();
    expect(simulation.flow, isEmpty);
    expect(simulation.flowOf(2), 1);
  });
}
