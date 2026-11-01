import 'dart:async';
import 'dart:convert';

import 'package:healthhub_api/care_centers.dart';
import 'package:healthhub_api/occupancy_alarms.dart';
import 'package:test/test.dart';

/// A forecast of [means] (and [p90s], the means when not given) hour by
/// hour from day 2, 01:00: the series ends at day 2, 00:00.
List<Map<String, Object?>> forecastOf(List<num> means, [List<num>? p90s]) => [
  for (var i = 0; i < means.length; i++)
    {
      'at': DateTime.utc(2026, 1, 2, i + 1).toIso8601String().substring(0, 16),
      'mean': means[i],
      'p10': 0.0,
      'p50': means[i],
      'p90': (p90s ?? means)[i],
    },
];

void main() {
  group('the setting', () {
    test('defaults to 5 s, 0 turns the alarms off, anything else is refused', () {
      expect(alarmEveryOf(null), const Duration(seconds: 5));
      expect(alarmEveryOf(''), const Duration(seconds: 5));
      expect(alarmEveryOf('1500'), const Duration(milliseconds: 1500));
      expect(alarmEveryOf('0'), Duration.zero);
      expect(() => alarmEveryOf('-1'), throwsFormatException);
      expect(() => alarmEveryOf('soon'), throwsFormatException);
      expect(() => alarmEveryOf('2.5'), throwsFormatException);
    });

    test('the threshold: 90% unless set, a share or a percentage, above 0 and at most 2', () {
      expect(alarmThresholdOf(null), 0.9);
      expect(alarmThresholdOf(' '), 0.9);
      expect(alarmThresholdOf('0.75'), 0.75);
      expect(alarmThresholdOf('85%'), closeTo(0.85, 1e-12));
      expect(alarmThresholdOf('1'), 1.0);
      expect(alarmThresholdOf('2'), 2.0);
      for (final bad in ['0', '-0.5', '2.5', '250%', 'high', 'NaN', 'Infinity', '%']) {
        expect(() => alarmThresholdOf(bad), throwsFormatException, reason: bad);
      }
    });

    test('reaching is at or above, give or take the rounding of a share times a capacity', () {
      expect(reaches(9, 0.9 * 10), isTrue);
      expect(reaches(7, 0.7 * 10), isTrue);
      expect(reaches(8.99, 9), isFalse);
      expect(reaches(10, 9), isTrue);
    });
  });

  group('the simulated clock', () {
    test('day 1 is 2026-01-01', () {
      expect(simDateOf(1), '2026-01-01');
      expect(simDateOf(154), '2026-06-03');
      expect(simDateOf(366), '2027-01-01');
      expect(simDayOfHour(DateTime.utc(2026, 6, 3, 16)), 154);
    });

    test('is the newest move\'s, by turn', () {
      expect(simNowOf(const []), isNull);
      expect(
        simNowOf([
          {'turn': 3, 'day': 1, 'simTime': '09:00'},
          {'turn': 5, 'day': 2, 'simTime': '11:00'},
          {'turn': 4, 'day': 2, 'simTime': '10:00'},
        ]),
        {'day': 2, 'simTime': '11:00', 'date': '2026-01-02'},
      );
    });
  });

  group('the level', () {
    // A threshold of 4 people: 90% of a capacity of 4.4..., or 80% of 5.
    test('expected when the mean reaches the threshold, at or above', () {
      final reading = readForecast(forecastOf([2, 3.9, 4, 9, 6], [3, 6, 8, 12, 9]), 4);
      expect(reading.level, AlarmLevel.expected);
      // 3.9 is below; 4 is at it, which reaches it: the third hour.
      expect(reading.overflowAt, DateTime.utc(2026, 1, 2, 3));
      expect(reading.leadHours, 3);
      expect((reading.mean, reading.p90), (4.0, 8.0));
      expect(reading.end, DateTime.utc(2026, 1, 2));
      expect(reading.horizonHours, 5);
      expect(reading.peak, (at: DateTime.utc(2026, 1, 2, 4), mean: 9.0, p90: 12.0));
    });

    test('possible when only the 90th percentile reaches it, the earliest', () {
      final reading = readForecast(forecastOf([1, 2, 3, 3], [3, 4, 7, 6]), 4);
      expect(reading.level, AlarmLevel.possible);
      expect(reading.overflowAt, DateTime.utc(2026, 1, 2, 2));
      expect(reading.leadHours, 2);
      expect((reading.mean, reading.p90), (2.0, 4.0));
      // The peak of the p90 for possible.
      expect(reading.peak, (at: DateTime.utc(2026, 1, 2, 3), mean: 3.0, p90: 7.0));
    });

    test('none when neither reaches it; a fraction below is below', () {
      final reading = readForecast(forecastOf([1, 3.9, 2], [3, 3.99, 3.5]), 4);
      expect(reading.level, isNull);
      expect((reading.overflowAt, reading.leadHours, reading.mean, reading.p90), (null, null, null, null));
      expect(reading.peak?.mean, 3.9);
    });

    test('a threshold of a share of the capacity: 90% of 10 is 9, reached by 9', () {
      expect(readForecast(forecastOf([8, 9], [8.5, 9.5]), 0.9 * 10).overflowAt, DateTime.utc(2026, 1, 2, 2));
      expect(readForecast(forecastOf([8, 8.9], [8.5, 8.95]), 0.9 * 10).level, isNull);
    });

    test('reads the whole horizon, in time order, skipping a step that isn\'t one', () {
      final steps = forecastOf(List.filled(24, 1)..[23] = 5);
      final reading = readForecast([steps.last, 'nonsense', {'at': 'x', 'mean': 1, 'p90': 1}, ...steps.take(23)], 4);
      expect(reading.level, AlarmLevel.expected);
      expect(reading.leadHours, 24);
      expect(reading.horizonHours, 24);
    });

    test('no forecast, no level', () {
      final reading = readForecast(const [], 4);
      expect(reading.level, isNull);
      expect(reading.peak, isNull);
      expect(reading.horizonHours, 0);
    });

    test('the levels in order: actual is the worst', () {
      expect(AlarmLevel.values, [AlarmLevel.possible, AlarmLevel.expected, AlarmLevel.actual]);
      expect([for (final name in ['possible', 'expected', 'actual', 'over', null]) alarmLevelNamed(name)],
          [AlarmLevel.possible, AlarmLevel.expected, AlarmLevel.actual, null, null]);
    });
  });

  group('the alarms', () {
    const run = 'abcd1234';
    final hospital = (name: 'Hospital del Mar', kind: 'hospital', key: 'test:1');
    final clinic = (name: 'CAP Reus', kind: 'health_station', key: 'test:2');
    final beds = simulatedCapacity(hospital.key, hospital.kind).places;
    final places = simulatedCapacity(clinic.key, clinic.kind).places;

    Map<String, Object?> prediction(int id, List<Map<String, Object?>> forecast, {String series = run}) => {
      'series': {'run_id': series, 'hospital_id': '$id'},
      'predicted': 1.0,
      'last': 1.0,
      'note': null,
      'forecast': forecast,
    };

    DatyxAnswer ok(List<Map<String, Object?>> predictions) =>
        (status: 200, body: {'runId': 4, 'target': 'occupancy', 'predictions': predictions});

    late List<DatyxAnswer?> answers;
    late List<String?> tokens;
    late List<List<Map<String, String>>> asked;
    late List<Map<String, Object?>> fired;
    late List<String> lookedUp;
    late String? currentRun;
    late DateTime now;
    late bool paused;
    late ObservedOccupancy seen;
    late List<(String, Map<int, List<Object?>>, Object?)> kept;

    OccupancyAlarms make({Duration every = const Duration(seconds: 5), int lowerAfter = 1, double threshold = 0.9}) =>
        OccupancyAlarms(
      infer: (token, series) async {
        tokens.add(token);
        asked.add(series);
        return answers.removeAt(0);
      },
      careCenters: (run) async {
        lookedUp.add(run);
        return {1: hospital, 2: clinic};
      },
      run: () => currentRun,
      clock: () => {'day': 2, 'simTime': '00:20', 'date': '2026-01-02'},
      observed: (run) async => seen,
      paused: () => paused,
      onEvent: fired.add,
      onForecasts: (run, forecasts, trainingRun) => kept.add((run, forecasts, trainingRun)),
      every: every,
      lowerAfter: lowerAfter,
      threshold: threshold,
      now: () => now,
    );

    setUp(() {
      answers = [];
      tokens = [];
      asked = [];
      fired = [];
      lookedUp = [];
      currentRun = run;
      now = DateTime.utc(2026, 11, 1, 14);
      paused = false;
      // No hour observed yet: no actual level.
      seen = (end: null, occupancy: const {});
      kept = [];
    });


    // The threshold is 90% of the capacity: 4.5 of the hospital's 5 beds,
    // 2.7 of the clinic's 3 places. Reached by the mean at the third hour,
    // by the p90 at the first.
    List<Map<String, Object?>> expected(int capacity) =>
        forecastOf([1, 2, capacity + 1, capacity + 2], [capacity + 1, capacity + 2, capacity + 3, capacity + 4]);
    // By the p90 only, at the third hour.
    List<Map<String, Object?>> possible(int capacity) => forecastOf([1, 1, 2, 2], [2, 2, capacity + 1, capacity + 1]);
    // Below it all along.
    List<Map<String, Object?>> calm(int capacity) => forecastOf([1, 1, 1, 1], [2, 2, 1, 1]);

    // The run's latest hour, day 2 at 00:00, where the forecasts start from.
    final latest = DateTime.utc(2026, 1, 2);

    test('actual when the occupancy observed reaches the threshold: the worst level, with datyx refusing too', () async {
      final alarms = make();
      seen = (end: latest, occupancy: {1: 5, 2: 1});
      answers = [(status: 404, body: {'error': 'no model of the group default of public.occupancy_hourly has been trained yet'})];
      await alarms.check(null);
      expect(fired, hasLength(1));
      final event = fired.single;
      expect(event, containsPair('kind', 'alarm'));
      expect(event, containsPair('level', 'actual'));
      expect(event, containsPair('hospitalId', 1));
      expect(event, containsPair('occupancy', 5));
      expect(event, containsPair('occupancyShare', 1.0));
      expect(event, containsPair('threshold', 0.9));
      expect(event, containsPair('thresholdPlaces', 4.5));
      expect(event, containsPair('observedAt', '2026-01-02T00:00'));
      // The hour reached is the one observed, 0 h ahead of the series' end, 20 min before the clock.
      expect(event, containsPair('overflowAt', '2026-01-02T00:00'));
      expect(event, containsPair('leadHours', 0));
      expect(event, containsPair('leadFromNowHours', -0.3));
      expect((event['mean'], event['p90'], event['peak']), (null, null, null));
      final snapshot = alarms.snapshot;
      expect(snapshot.status, 404);
      expect(snapshot.stale, isTrue);
      // Observed, not datyx's: current although datyx can't forecast.
      expect(snapshot.active.single['level'], 'actual');
      expect(snapshot.active.single['stale'], isFalse);
      expect(snapshot.threshold, 0.9);
    });

    test('actual outranks a forecast; it falls to the forecast\'s level once the occupancy is below', () async {
      final alarms = make();
      seen = (end: latest, occupancy: {1: 5});
      answers = [
        ok([prediction(1, expected(beds))]),
        ok([prediction(1, expected(beds))]),
        ok([prediction(1, calm(beds))]),
      ];
      await alarms.check(null);
      expect([for (final e in fired) (e['kind'], e['level'], e['previous'])], [('alarm', 'actual', null)]);
      // The forecast's peak still said.
      expect(alarms.snapshot.active.single['peak'], isNotNull);
      seen = (end: latest.add(const Duration(hours: 1)), occupancy: {1: 4});
      await alarms.check(null);
      expect(fired.last, containsPair('kind', 'downgraded'));
      expect(fired.last, containsPair('level', 'expected'));
      expect(fired.last, containsPair('previous', 'actual'));
      expect(fired.last, containsPair('occupancy', 4));
      expect(fired.last, containsPair('overflowAt', '2026-01-02T03:00'));
      // Nobody in care at the latest hour has no row: zero.
      seen = (end: latest.add(const Duration(hours: 2)), occupancy: const {});
      await alarms.check(null);
      expect(fired.last, containsPair('kind', 'cleared'));
      expect(fired.last, containsPair('occupancy', 0));
      expect(alarms.snapshot.active, isEmpty);
    });

    test('without a forecast, an actual alarm the occupancy no longer reaches is kept, stale', () async {
      final alarms = make();
      seen = (end: latest, occupancy: {1: 5});
      answers = [ok([prediction(1, expected(beds))]), null];
      await alarms.check(null);
      seen = (end: latest.add(const Duration(hours: 1)), occupancy: {1: 2});
      await alarms.check(null);
      expect(fired, hasLength(1));
      expect(alarms.snapshot.active.single['level'], 'actual');
      expect(alarms.snapshot.active.single['stale'], isTrue);
    });

    test('an actual alarm is stale once no occupancy was read for a while', () async {
      final alarms = make();
      seen = (end: latest, occupancy: {2: 3});
      answers = [ok([prediction(2, calm(places))])];
      await alarms.check(null);
      expect(alarms.snapshot.active.single['level'], 'actual');
      expect(alarms.snapshot.active.single['stale'], isFalse);
      now = now.add(alarms.staleAfter + const Duration(seconds: 1));
      expect(alarms.snapshot.active.single['stale'], isTrue);
    });

    test('the threshold is the alarms\' own: at 50%, 3 of 5 beds is actual, a mean of 2.5 expected', () async {
      final half = make(threshold: 0.5);
      seen = (end: latest, occupancy: {1: 3, 2: 1});
      answers = [ok([prediction(1, calm(beds)), prediction(2, forecastOf([1, 1.5], [1.2, 1.6]))])];
      await half.check(null);
      expect([for (final e in fired) (e['hospitalId'], e['level'], e['thresholdPlaces'])], [
        (1, 'actual', 2.5),
        (2, 'expected', 1.5),
      ]);
      expect(half.snapshot.threshold, 0.5);
    });

    test('each check\'s forecasts are handed on to be kept, from the datyx source the alarms read only', () async {
      final alarms = make();
      DatyxAnswer from(int source, List<Map<String, Object?>> predictions) =>
          (status: 200, body: {'runId': 4, 'sourceId': source, 'predictions': predictions});
      answers = [
        from(1, [prediction(1, calm(beds)), prediction(2, const [])]),
        from(7, [prediction(1, expected(beds))]),
        (status: 404, body: {'error': 'no model'}),
      ];
      expect(alarms.acceptsSource(7), isTrue);
      await alarms.check(null);
      expect(kept, hasLength(1));
      expect(kept.single.$1, run);
      // A care center without a forecast isn't handed on.
      expect(kept.single.$2.keys, [1]);
      expect(kept.single.$2[1], calm(beds));
      expect(kept.single.$3, 4);
      expect(alarms.acceptsSource(1), isTrue);
      expect(alarms.acceptsSource(7), isFalse);
      await alarms.check(null);
      await alarms.check(null);
      expect(kept, hasLength(1));
    });

    test('rise, escalate, stay, downgrade and clear, each change one event', () async {
      final alarms = make();
      answers = [
        ok([prediction(1, possible(beds))]),
        ok([prediction(1, expected(beds))]),
        // Later: over by the mean at the fourth hour only.
        ok([prediction(1, forecastOf([1, 2, 3, beds + 1], [beds + 1, beds + 2, beds + 3, beds + 4]))]),
        ok([prediction(1, possible(beds))]),
        ok([prediction(1, calm(beds))]),
      ];
      await alarms.check(null);
      expect(fired, hasLength(1));
      expect(fired.last, {
        'kind': 'alarm',
        'id': '$run-1-1',
        'run': run,
        'hospitalId': 1,
        'hospitalName': 'Hospital del Mar',
        'careCenterKind': 'hospital',
        'level': 'possible',
        'threshold': 0.9,
        'thresholdPlaces': 4.5,
        'occupancy': null,
        'occupancyShare': null,
        'observedAt': null,
        'overflowAt': '2026-01-02T03:00',
        'overflowDay': 2,
        'leadHours': 3,
        'leadFromNowHours': 2.7,
        'mean': 2.0,
        'p90': beds + 1.0,
        'peak': {'at': '2026-01-02T03:00', 'day': 2, 'mean': 2.0, 'p90': beds + 1.0},
        'capacity': beds,
        'unit': 'beds',
        'end': '2026-01-02T00:00',
        'horizonHours': 4,
        'trainingRun': 4,
        'now': {'day': 2, 'simTime': '00:20', 'date': '2026-01-02'},
        'previous': null,
        'raisedAt': '2026-11-01T14:00:00.000Z',
      });

      now = now.add(const Duration(seconds: 5));
      await alarms.check(null);
      expect(fired, hasLength(2));
      expect(fired.last, containsPair('kind', 'alarm'));
      expect(fired.last, containsPair('level', 'expected'));
      expect(fired.last, containsPair('previous', 'possible'));
      expect(fired.last, containsPair('overflowAt', '2026-01-02T03:00'));
      expect(fired.last, containsPair('mean', beds + 1.0));

      // The same level with other numbers: no event, the alarm updated.
      final since = alarms.snapshot.active.single['since'];
      now = now.add(const Duration(seconds: 5));
      await alarms.check(null);
      expect(fired, hasLength(2));
      final active = alarms.snapshot.active.single;
      expect(active['level'], 'expected');
      expect(active['overflowAt'], '2026-01-02T04:00');
      expect(active['since'], since);
      expect(active['checkedAt'], '2026-11-01T14:00:10.000Z');
      expect(active['stale'], isFalse);
      expect(active.containsKey('kind'), isFalse);
      expect(active['previous'], 'possible'); // the event's that gave it its level

      now = now.add(const Duration(seconds: 5));
      await alarms.check(null);
      expect(fired.last, containsPair('kind', 'downgraded'));
      expect(fired.last, containsPair('level', 'possible'));
      expect(fired.last, containsPair('previous', 'expected'));

      now = now.add(const Duration(seconds: 5));
      await alarms.check(null);
      expect(fired, hasLength(4));
      expect(fired.last, containsPair('kind', 'cleared'));
      expect(fired.last, containsPair('level', null));
      expect(fired.last, containsPair('previous', 'possible'));
      expect(fired.last, containsPair('overflowAt', null));
      expect(fired.last, containsPair('leadHours', null));
      expect(fired.last['capacity'], beds);
      expect(alarms.snapshot.active, isEmpty);
      // Newest first.
      expect([for (final e in alarms.snapshot.recent) e['kind']], ['cleared', 'downgraded', 'alarm', 'alarm']);
      // The run's care centers, asked for by name, every check.
      expect(lookedUp, List.filled(5, run));
      expect(asked.first, [
        {'run_id': run, 'hospital_id': '1'},
        {'run_id': run, 'hospital_id': '2'},
      ]);
    });

    test('straight to expected is one alarm; no repeat while unchanged', () async {
      final alarms = make();
      answers = [ok([prediction(1, expected(beds))]), ok([prediction(1, expected(beds))])];
      await alarms.check(null);
      await alarms.check(null);
      expect([for (final e in fired) (e['kind'], e['level'], e['previous'])], [('alarm', 'expected', null)]);
    });

    test('only the run going on counts; a care center left out is kept, stale, not cleared', () async {
      final alarms = make();
      answers = [
        ok([prediction(1, expected(beds), series: 'ffff0000'), prediction(2, possible(places))]),
        ok([]),
        ok([{...prediction(2, const []), 'forecast': null, 'note': 'no rows for this series'}]),
        ok([prediction(2, calm(places))]),
      ];
      await alarms.check(null);
      expect([for (final e in fired) e['hospitalId']], [2]);
      expect(fired.single['unit'], 'places');
      expect(alarms.snapshot.active.single['stale'], isFalse);
      // Left out, then without a forecast: still possible, marked stale.
      await alarms.check(null);
      await alarms.check(null);
      expect(fired, hasLength(1));
      expect(alarms.snapshot.active.single['level'], 'possible');
      expect(alarms.snapshot.active.single['stale'], isTrue);
      expect(alarms.snapshot.stale, isFalse);
      // Cleared only by a forecast within the capacity.
      await alarms.check(null);
      expect([for (final e in fired) e['kind']], ['alarm', 'cleared']);
    });

    test("an older run that ran longer doesn't hide this one: its care centers are asked for by name", () async {
      // As datyx answers a call without series: only the latest-ending
      // series, an older run's; asked by name, this run's.
      final alarms = OccupancyAlarms(
        infer: (token, series) async {
          asked.add(series);
          return ok([
            for (final s in series)
              if (s['run_id'] == run) prediction(int.parse(s['hospital_id']!), expected(beds)),
          ]);
        },
        careCenters: (r) async => {for (var id = 1; id <= 167; id++) id: hospital},
        run: () => currentRun,
        clock: () => null,
        onEvent: fired.add,
      );
      await alarms.check(null);
      // 167 care centers: two calls, 100 and 67, every one named with the run.
      expect([for (final s in asked) s.length], [100, 67]);
      expect(asked.expand((s) => s).every((s) => s['run_id'] == run), isTrue);
      expect(alarms.snapshot.active, hasLength(167));
      expect(fired, hasLength(167));
    });

    test('a level flapping at the capacity is one alarm; it falls after three checks in a row lower', () async {
      final alarms = make(lowerAfter: 3);
      // DeepAR's p90 at the capacity, then just over it, then at it...: new sample paths each call.
      final over = possible(beds);
      final at = calm(beds);
      answers = [
        for (var i = 0; i < 10; i++) ok([prediction(1, i.isEven ? over : at)]),
        ok([prediction(1, at)]),
        ok([prediction(1, at)]),
      ];
      for (var i = 0; i < 11; i++) {
        await alarms.check(null);
      }
      expect([for (final e in fired) e['kind']], ['alarm']);
      expect(alarms.snapshot.active.single['level'], 'possible');
      await alarms.check(null);
      expect([for (final e in fired) e['kind']], ['alarm', 'cleared']);
    });

    test('expected falls to the highest of the three checks lower', () async {
      final alarms = make(lowerAfter: 3);
      answers = [
        ok([prediction(1, expected(beds))]),
        ok([prediction(1, calm(beds))]),
        ok([prediction(1, possible(beds))]),
        ok([prediction(1, calm(beds))]),
      ];
      for (var i = 0; i < 4; i++) {
        await alarms.check(null);
      }
      expect([for (final e in fired) (e['kind'], e['level'], e['previous'])], [
        ('alarm', 'expected', null),
        ('downgraded', 'possible', 'expected'),
      ]);
      expect(alarms.snapshot.active.single['level'], 'possible');
    });

    test('no check while paused once one has read the run', () async {
      final alarms = make();
      answers = [ok([prediction(1, expected(beds))])];
      paused = true;
      // Not read yet: one check, even paused.
      expect(alarms.poke(null), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(minutes: 1));
      expect(alarms.poke(null), isFalse);
      paused = false;
      answers = [ok([prediction(1, expected(beds))])];
      expect(alarms.poke(null), isTrue);
    });

    test('an answer from another datyx data source is ignored', () async {
      final alarms = make();
      DatyxAnswer from(int source, List<Map<String, Object?>> predictions) =>
          (status: 200, body: {'runId': 4, 'sourceId': source, 'predictions': predictions});
      answers = [
        from(1, [prediction(1, possible(beds))]),
        // Someone's own source of a database named the same: their forecast isn't everyone's.
        from(7, [prediction(1, expected(beds)), prediction(2, expected(places))]),
        from(1, [prediction(1, expected(beds))]),
      ];
      await alarms.check(null);
      await alarms.check(null);
      expect([for (final e in fired) e['level']], ['possible']);
      expect(alarms.snapshot.status, 200);
      await alarms.check(null);
      expect([for (final e in fired) e['level']], ['possible', 'expected']);
    });

    test('stale once no check has read a forecast for a while, or the latest failed', () async {
      final alarms = make();
      answers = [ok([prediction(1, expected(beds))]), null];
      expect(alarms.snapshot.stale, isFalse);
      await alarms.check(null);
      expect(alarms.snapshot.stale, isFalse);
      now = now.add(alarms.staleAfter + const Duration(seconds: 1));
      expect(alarms.snapshot.stale, isTrue);
      expect(alarms.snapshot.active.single['stale'], isTrue);
      now = DateTime.utc(2026, 11, 1, 14, 0, 1);
      await alarms.check(null);
      expect(alarms.snapshot.status, 502);
      expect(alarms.snapshot.stale, isTrue);
      expect(alarms.snapshot.active.single['stale'], isTrue);
    });

    test('datyx refusing or silent keeps the alarms, and says why', () async {
      final alarms = make();
      answers = [
        ok([prediction(1, expected(beds))]),
        (status: 404, body: {'error': 'no model of the group default of public.occupancy_hourly has been trained yet'}),
        null,
      ];
      await alarms.check(null);
      expect(alarms.snapshot.status, 200);
      expect(alarms.snapshot.note, isNull);
      expect(alarms.snapshot.trainingRun, 4);
      await alarms.check(null);
      expect(alarms.snapshot.status, 404);
      expect(alarms.snapshot.note, contains('no model'));
      expect(alarms.snapshot.active, hasLength(1));
      await alarms.check(null);
      expect(alarms.snapshot.status, 502);
      expect(alarms.snapshot.note, 'the datyx API is not answering');
      expect(alarms.snapshot.active, hasLength(1));
      expect(fired, hasLength(1));
    });

    test('a new run starts with no alarms, and none fire for the old one', () async {
      final alarms = make();
      answers = [ok([prediction(1, expected(beds))]), ok([])];
      await alarms.check(null);
      currentRun = 'ffff0000';
      await alarms.check(null);
      expect(alarms.snapshot.active, isEmpty);
      expect(fired, hasLength(1));
    });

    test('a run moving on while datyx answers is left to the next check', () async {
      final alarms = make();
      final answer = Completer<DatyxAnswer?>();
      final slow = OccupancyAlarms(
        infer: (_, _) => answer.future,
        careCenters: (_) async => {1: hospital},
        run: () => currentRun,
        clock: () => null,
        onEvent: fired.add,
      );
      final checking = slow.check(null);
      currentRun = 'ffff0000';
      answer.complete(ok([prediction(1, expected(beds))]));
      await checking;
      expect(fired, isEmpty);
      expect(alarms.snapshot.active, isEmpty);
    });

    test('active: expected first, then the soonest overflow', () async {
      final alarms = make();
      final soon = forecastOf([1, 1, 1, 1], [beds + 1, beds + 1, beds + 1, beds + 1]);
      answers = [
        ok([
          prediction(1, possible(beds)),
          prediction(2, expected(places)),
          prediction(3, soon),
        ]),
      ];
      final make3 = OccupancyAlarms(
        infer: (token, _) async => answers.removeAt(0),
        careCenters: (_) async => {1: hospital, 2: clinic, 3: (name: 'Hospital 3', kind: 'hospital', key: 'test:1')},
        run: () => currentRun,
        clock: () => null,
      );
      await make3.check(null);
      expect([for (final a in make3.snapshot.active) (a['hospitalId'], a['level'], a['leadHours'])], [
        (2, 'expected', 3),
        (3, 'possible', 1),
        (1, 'possible', 3),
      ]);
      expect(alarms.snapshot.enabled, isTrue);
    });

    test('a check at most once per interval, never two at once, the poll not waiting', () async {
      final alarms = make();
      final answer = Completer<DatyxAnswer?>();
      var calls = 0;
      final slow = OccupancyAlarms(
        infer: (token, _) {
          calls++;
          return answer.future;
        },
        careCenters: (_) async => {1: hospital},
        run: () => currentRun,
        clock: () => null,
        now: () => now,
      );
      expect(slow.poke('t'), isTrue);
      // Returned at once: datyx hasn't answered.
      expect(slow.checking, isTrue);
      expect(calls, 0);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      expect(slow.poke('t'), isFalse);
      now = now.add(const Duration(seconds: 6));
      // The interval has passed, but one is still under way.
      expect(slow.poke('t'), isFalse);
      answer.complete(ok([]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(slow.checking, isFalse);
      // Measured from the start of the last: 6 s ago.
      expect(slow.poke('t'), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 2);
      expect(alarms.enabled, isTrue);
    });

    test('the interval: none before it, one after', () async {
      final alarms = make(every: const Duration(seconds: 5));
      answers = [ok([]), ok([])];
      expect(alarms.poke(null), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(milliseconds: 4999));
      expect(alarms.poke(null), isFalse);
      now = now.add(const Duration(milliseconds: 1));
      expect(alarms.poke(null), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(tokens, hasLength(2));
    });

    test('off at 0, and before the simulation has a run', () {
      final off = make(every: Duration.zero);
      expect(off.poke('t'), isFalse);
      expect(off.snapshot.enabled, isFalse);
      currentRun = null;
      expect(make().poke('t'), isFalse);
      expect(tokens, isEmpty);
    });

    test('the token goes to its own check\'s datyx call only, and is kept nowhere', () async {
      final alarms = make();
      answers = [ok([prediction(1, expected(beds))]), ok([prediction(1, expected(beds))])];
      expect(alarms.poke('secret-token-1'), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 5));
      // A later poll without a token: the first one's is not reused.
      expect(alarms.poke(null), isTrue);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(tokens, ['secret-token-1', null]);
      final everything = jsonEncode({
        'active': alarms.snapshot.active,
        'recent': alarms.snapshot.recent,
        'events': fired,
      });
      expect(everything, isNot(contains('secret-token')));
    });

    test('a failure of the database or of the listener doesn\'t stop the checks', () async {
      var down = true;
      final alarms = OccupancyAlarms(
        infer: (_, _) async => ok([prediction(1, expected(beds))]),
        careCenters: (_) async => down ? throw StateError('down') : {1: hospital},
        run: () => currentRun,
        clock: () => null,
        onEvent: (_) => throw StateError('listener'),
      );
      await alarms.check(null);
      expect(alarms.snapshot.status, 503);
      expect(alarms.snapshot.active, isEmpty);
      down = false;
      await alarms.check(null);
      expect(alarms.snapshot.active, hasLength(1));
      expect(alarms.snapshot.recent, hasLength(1));
    });
  });

  test('an event\'s Kafka record is keyed by the care center', () {
    final event = {'kind': 'alarm', 'id': 'abcd1234-12-1', 'hospitalId': 12, 'level': 'expected'};
    expect(alarmRecord(event), {'key': '12', 'value': event});
    expect(alarmsTopic, 'healthhub.alarms');
  });

  group('the retry queue', () {
    test('retries a failure until it passes, in order', () async {
      var failures = 2;
      final done = <int>[];
      final queue = RetryQueue<int>('test', (item) async {
        if (item == 1 && failures-- > 0) throw StateError('down');
        done.add(item);
      }, retryAfter: Duration.zero);
      queue
        ..add(1)
        ..add(2);
      await queue.idle;
      expect(done, [1, 2]);
      expect(queue.pending, 0);
    });

    test('drops what a retry can\'t fix', () async {
      final done = <int>[];
      final queue = RetryQueue<int>('test', (item) async {
        if (item == 1) throw ArgumentError('bad');
        done.add(item);
      }, isPermanent: (error) => error is ArgumentError, retryAfter: Duration.zero, limit: 2);
      queue
        ..add(1)
        ..add(2);
      await queue.idle;
      expect(done, [2]);
    });
  });
}
