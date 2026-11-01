import 'dart:math';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/history.dart';
import 'package:healthhub_api/simulation.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'simulation_test.dart' show condition, throwingKafka;

/// The first harmonic fitted to 24 values, one an hour: its amplitude
/// over the mean, and the hour it peaks at (0 to 24).
({double mean, double amplitude, double peak}) firstHarmonic(List<num> byHour) {
  var a = 0.0, b = 0.0, mean = 0.0;
  for (var h = 0; h < 24; h++) {
    mean += byHour[h] / 24;
    a += byHour[h] * cos(2 * pi * h / 24) / 12;
    b += byHour[h] * sin(2 * pi * h / 24) / 12;
  }
  final peak = (atan2(b, a) * 24 / (2 * pi)) % 24;
  return (mean: mean, amplitude: sqrt(a * a + b * b) / mean, peak: peak);
}

/// The k-th harmonic's amplitude of 24 values, one an hour.
double harmonic(List<num> byHour, int k) {
  var a = 0.0, b = 0.0;
  for (var h = 0; h < 24; h++) {
    a += byHour[h] * cos(2 * pi * k * h / 24) / 12;
    b += byHour[h] * sin(2 * pi * k * h / 24) / 12;
  }
  return sqrt(a * a + b * b);
}

void main() {
  const hospital = Place(id: 3, name: 'Hospital Sant Joan', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076));
  const station = Place(id: 4, name: 'CAP Reus 1', kind: 'health_station', city: 'Reus', at: LatLon(41.1600, 1.1050));
  const clinic = Place(id: 5, name: 'CUAP Reus', kind: 'clinic', city: 'Reus', at: LatLon(41.1500, 1.1100), subtype: 'CUAP');

  group('the daily profile', () {
    test('peaks at 13:00, bottoms at 01:00, and is a single harmonic', () {
      final weights = [for (var h = 0; h < 24; h++) arrivalWeight(h)];
      expect(weights.reduce((a, b) => a + b), closeTo(24, 1e-9));
      expect(weights.indexOf(weights.reduce(max)), arrivalPeakHour);
      expect(weights.indexOf(weights.reduce(min)), 1);
      expect(arrivalWeight(13), 2);
      expect(arrivalWeight(1), closeTo(0, 1e-12));
      // Symmetric about the peak.
      for (var d = 1; d < 12; d++) {
        expect(arrivalWeight(13 - d), closeTo(arrivalWeight(13 + d), 1e-12));
      }
      final fit = firstHarmonic(weights);
      expect(fit.mean, closeTo(1, 1e-9));
      expect(fit.amplitude, closeTo(arrivalAmplitude, 1e-9));
      expect(fit.peak, closeTo(13, 1e-9));
      for (var k = 2; k <= 11; k++) {
        expect(harmonic(weights, k), closeTo(0, 1e-9), reason: 'harmonic $k');
      }
      // The history's profile is the same, from 0 to 1.
      expect(dailyProfile(13), 1);
      expect(dailyProfile(1), closeTo(0, 1e-12));
      expect(dailyProfile(7), closeTo(0.5, 1e-12));
    });

    test('arrival hours drawn from it crowd around 13:00, never at 01:00', () {
      final random = Random(1);
      final byHour = List.filled(24, 0);
      const draws = 200000;
      for (var i = 0; i < draws; i++) {
        byHour[arrivalHour(random)]++;
      }
      final mode = byHour.indexOf(byHour.reduce(max));
      expect(mode, inInclusiveRange(12, 14));
      expect(byHour[1], 0);
      final fit = firstHarmonic(byHour);
      expect(fit.peak, closeTo(13, 0.1));
      expect(fit.amplitude, closeTo(arrivalAmplitude, 0.03));
      // Each hour within a few standard errors of its weight's share.
      for (var h = 0; h < 24; h++) {
        final expected = draws * arrivalWeight(h) / 24;
        expect(byHour[h], closeTo(expected, 5 * sqrt(expected) + 1), reason: 'hour $h');
      }
    });

    test("a visit's start: on the hour from the profile, never in the past, the same day's hours not favoured", () {
      final random = Random(4);
      final byHour = List.filled(24, 0);
      for (var i = 0; i < 40000; i++) {
        // Asked for on the day of [after], as an acute visit is: the hours
        // later than it may come that day, the others the next.
        final after = dayStart(5) + random.nextInt(minutesPerDay);
        final start = nextVisitStart(5, after, random);
        expect(start, greaterThan(after));
        expect(start % 60, 0);
        expect(simDay(start), inInclusiveRange(5, 6));
        byHour[(start % minutesPerDay) ~/ 60]++;
      }
      final fit = firstHarmonic(byHour);
      expect(fit.peak, closeTo(13, 0.15));
      expect(fit.amplitude, closeTo(arrivalAmplitude, 0.05));
    });

    test('an acute onset falls on a later day, on the hour from the profile', () {
      final random = Random(2);
      final byHour = List.filled(24, 0);
      for (var i = 0; i < 20000; i++) {
        final after = dayStart(5) + random.nextInt(minutesPerDay);
        final onset = acuteOnsetAfter(after, random);
        expect(onset, greaterThan(after));
        expect(simDay(onset), greaterThan(5));
        expect(onset % 60, 0);
        byHour[(onset % minutesPerDay) ~/ 60]++;
      }
      expect(firstHarmonic(byHour).peak, closeTo(13, 0.2));
    });

    test("a live run's acute and chronic admissions both peak at 13:00, as the history's", () {
      final places = [
        const Place(id: 10, name: 'H Reus', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076), subtype: 'Hospitales Generales'),
        const Place(id: 11, name: 'CAP Reus', kind: 'health_station', city: 'Reus', at: LatLon(41.1600, 1.1050)),
        const Place(id: 12, name: 'CUAP Reus', kind: 'clinic', city: 'Reus', at: LatLon(41.1500, 1.1100), subtype: 'CUAP'),
        const Place(id: 20, name: 'H Bcn', kind: 'hospital', city: 'Barcelona', at: LatLon(41.3843, 2.1941), subtype: 'Hospitales Generales'),
        const Place(id: 21, name: 'CAP Bcn', kind: 'health_station', city: 'Barcelona', at: LatLon(41.4036, 2.1744)),
      ];
      /// The admissions by hour of day of 100 people a city over two
      /// years with [conditions], acute and chronic apart.
      Map<String, List<int>> admissions(List<MedicalCondition> conditions) {
        final random = Random(5);
        final people = populate(places, 100, 60, random, conditions: conditions);
        final byType = {'acute': List.filled(24, 0), 'chronic': List.filled(24, 0)};
        final byCode = {for (final c in conditions) c.code: c};
        for (var turn = 0; turn < 730 * 24; turn++) {
          for (final person in people) {
            final admission = advance(person, turn: turn, minutesPerTurn: 60, random: random, conditions: conditions, run: 'r1');
            if (admission == null) continue;
            final hour = int.parse((admission['simTime'] as String).substring(0, 2));
            byType[byCode[admission['conditionCode']]!.isChronic ? 'chronic' : 'acute']![hour]++;
          }
        }
        return byType;
      }

      // The seed's conditions: planned visits and same-day acute ones
      // (the next slot after the onset) alike.
      final all = admissions(conditionSeed);
      // Only emergencies: each acute admission the first visit, made at
      // the onset.
      final urgent = admissions([condition('appendicitis', 'acute', urgent: true, minAge: 0, maxAge: 120)])['acute']!;
      for (final (name, byHour) in [('acute', all['acute']!), ('chronic', all['chronic']!), ('urgent', urgent)]) {
        expect(byHour.reduce((a, b) => a + b), greaterThan(1000), reason: name);
        final fit = firstHarmonic(byHour);
        expect(fit.peak, closeTo(13, 0.25), reason: '$name $byHour');
        expect(fit.amplitude, closeTo(arrivalAmplitude, 0.1), reason: '$name $byHour');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('settings', () {
    test('HEALTHHUB_HISTORY_DAYS: 90 by default, 0 for none, a whole number up to the most', () {
      expect(historyDaysFromEnvironment({}), 90);
      expect(historyDaysFromEnvironment({'HEALTHHUB_HISTORY_DAYS': ''}), 90);
      expect(historyDaysFromEnvironment({'HEALTHHUB_HISTORY_DAYS': '0'}), 0);
      expect(historyDaysFromEnvironment({'HEALTHHUB_HISTORY_DAYS': ' 30 '}), 30);
      expect(historyDaysFromEnvironment({'HEALTHHUB_HISTORY_DAYS': '$maxHistoryDays'}), maxHistoryDays);
      for (final bad in ['-1', '+5', 'ninety', '1.5', '${maxHistoryDays + 1}', '0x10', '99999999999999999999']) {
        expect(() => historyDaysFromEnvironment({'HEALTHHUB_HISTORY_DAYS': bad}), throwsFormatException, reason: bad);
      }
    });

    test('the history run is a run id of its own', () {
      expect(historyRun, matches(RegExp(r'^[0-9a-f]{8}$')));
      final simulation = Simulation(const [], const SimulationSettings(), throwingKafka)..start();
      addTearDown(simulation.stop);
      expect(simulation.run, isNot(historyRun));
    });
  });

  group('the history', () {
    test('rates: acute and chronic add up to the peak at 13:00, one harmonic shape for both, milder weekends', () {
      const level = (peak: 5.0, acuteShare: 0.6);
      final noon = historyRates(level, 13, weekend: false);
      expect(noon.acute + noon.chronic, closeTo(5, 1e-9));
      expect(noon.acute, closeTo(3, 1e-9));
      final night = historyRates(level, 1, weekend: false);
      expect(night.acute + night.chronic, closeTo(0, 1e-12));
      final sunday = historyRates(level, 13, weekend: true);
      expect(sunday.acute + sunday.chronic, closeTo(5 * historyWeekendFactor, 1e-9));
      // Each the daily profile, as a live run's: a single harmonic at 13:00.
      for (final part in [(({double acute, double chronic}) r) => r.acute, (({double acute, double chronic}) r) => r.chronic]) {
        final byHour = [for (var h = 0; h < 24; h++) part(historyRates(level, h, weekend: false))];
        final fit = firstHarmonic(byHour);
        expect(fit.peak, closeTo(13, 1e-9));
        expect(fit.amplitude, closeTo(arrivalAmplitude, 1e-9));
        for (var k = 2; k <= 11; k++) {
          expect(harmonic(byHour, k), closeTo(0, 1e-9), reason: 'harmonic $k');
        }
      }
    });

    test('levels by kind: a hospital busiest, varied by center', () {
      final levels = {
        for (final kind in ['hospital', 'health_station', 'clinic'])
          kind: [
            for (var id = 1; id <= 200; id++)
              historyLevel(Place(id: id, name: '', kind: kind, city: 'Reus', at: const LatLon(0, 0)), Random(id)),
          ],
      };
      final hospitals = levels['hospital']!.map((l) => l.peak);
      expect(hospitals.reduce(min), greaterThanOrEqualTo(3));
      expect(hospitals.reduce(max), lessThan(8));
      expect(hospitals.reduce(max) - hospitals.reduce(min), greaterThan(4));
      expect(levels['health_station']!.every((l) => l.peak >= 1.5 && l.peak < 4), true);
      expect(levels['clinic']!.every((l) => l.peak >= 1 && l.peak < 3), true);
    });

    test('poisson counts have the mean asked', () {
      final random = Random(3);
      for (final mean in [0.05, 0.8, 3.0, 7.5]) {
        var sum = 0;
        const n = 40000;
        for (var i = 0; i < n; i++) {
          sum += poisson(mean, random);
        }
        expect(sum / n, closeTo(mean, 5 * sqrt(mean / n) + 0.005), reason: '$mean');
      }
      expect(poisson(0, random), 0);
    });

    test('the calendar: day 1, 2026-01-01, is a Thursday', () {
      expect([for (var day = 1; day <= 8; day++) isWeekend(day)], [false, false, true, true, false, false, false, false]);
      expect(historyStart, DateTime.utc(2026, 1, 1));
    });

    test("a center's series: every hour with an admission, adding up, the same every time", () {
      const days = 90;
      for (final center in [hospital, station, clinic]) {
        final series = historySeries(center, days);
        expect(series, isNotEmpty);
        final hours = [for (final h in series) h.hour];
        // In order, each hour once, within the days.
        expect(hours.toSet().length, hours.length);
        expect([...hours]..sort(), hours);
        expect(hours.first, greaterThanOrEqualTo(0));
        expect(hours.last, lessThan(days * 24));
        // Only hours with an admission, as admissions_hourly keeps them.
        expect(series.every((h) => h.acute >= 0 && h.chronic >= 0 && h.acute + h.chronic > 0), true);
        // Deterministic: seeded by the center's id.
        expect(historySeries(center, days), series);
        // A longer history starts with the same days.
        expect(historySeries(center, days + 7).take(series.length), series);
      }
      expect(historySeries(hospital, 30), isNot(historySeries(const Place(
        id: 99, name: 'Other', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076)), 30)));
      // A hospital fills most hours of the day.
      expect(historySeries(hospital, days).length, greaterThan(days * 24 * 0.6));
      expect(historySeries(hospital, 0), isEmpty);
    });

    test('its mean by hour of day peaks at midday, smooth, and weekends are quieter', () {
      const days = 364;
      final sums = List.filled(24, 0.0);
      var weekday = 0.0, weekend = 0.0;
      for (final center in [hospital, station, clinic]) {
        for (final h in historySeries(center, days)) {
          final count = h.acute + h.chronic;
          sums[h.hour % 24] += count / days;
          if (isWeekend(h.hour ~/ 24 + 1)) {
            weekend += count;
          } else {
            weekday += count;
          }
        }
      }
      final peak = sums.indexOf(sums.reduce(max));
      expect(peak, inInclusiveRange(12, 14), reason: '$sums');
      final fit = firstHarmonic(sums);
      expect(fit.peak, closeTo(13, 0.3));
      expect(fit.amplitude, greaterThan(0.8));
      // Per day: 104 weekend days against 260 weekdays.
      expect((weekend / 104) / (weekday / 260), closeTo(historyWeekendFactor, 0.03));
    });

    test('acute and chronic series each peak at 13:00 with the amplitude of the profile', () {
      const days = 364;
      final acute = List.filled(24, 0), chronic = List.filled(24, 0);
      for (final h in historySeries(hospital, days)) {
        acute[h.hour % 24] += h.acute;
        chronic[h.hour % 24] += h.chronic;
      }
      for (final byHour in [acute, chronic]) {
        final fit = firstHarmonic(byHour);
        expect(fit.peak, closeTo(13, 0.2), reason: '$byHour');
        expect(fit.amplitude, closeTo(arrivalAmplitude, 0.06), reason: '$byHour');
      }
    });

    test("covers the care centers the people's visits go to; the API's people are the same every time", () {
      Place place(int id, String city, String kind, LatLon at, [String? subtype]) =>
          Place(id: id, name: '$kind $id', kind: kind, city: city, at: at, subtype: subtype);
      final places = [
        place(10, 'Reus', 'hospital', const LatLon(41.1554, 1.1076), 'Hospitales Generales'),
        place(11, 'Reus', 'health_station', const LatLon(41.1600, 1.1050)),
        place(12, 'Reus', 'clinic', const LatLon(41.1500, 1.1100), 'CUAP'),
        place(13, 'Reus', 'clinic', const LatLon(41.1520, 1.1000), 'CSMA'),
        place(20, 'Barcelona', 'hospital', const LatLon(41.3843, 2.1941), 'Hospitales Generales'),
        place(21, 'Barcelona', 'health_station', const LatLon(41.4036, 2.1744)),
      ];
      List<Person> people([List<MedicalCondition> conditions = conditionSeed]) =>
          populate(places, 20, 60, Random(populationSeed), conditions: conditions);
      // Every setting of the seed's conditions, the mental health clinic's too.
      final centers = historyCenters(people(), conditionSeed);
      expect([for (final c in centers) c.id], [10, 11, 12, 13, 20, 21]);
      // Every care center a person goes to.
      final settings = {for (final c in conditionSeed) for (final kind in VisitKind.values) c.settingOf(kind)};
      for (final person in people()) {
        for (final setting in settings) {
          expect(centers, contains(person.careCenterFor(setting)));
        }
        expect(centers, contains(person.hospital));
      }
      // The API's people, drawn with [populationSeed]: the same homes and
      // care centers at every start, so the same history.
      final again = people();
      expect([for (final p in again) p.home], [for (final p in people()) p.home]);
      expect(historyCenters(again, conditionSeed), centers);
      // Only the settings the visits go to: no mental health here.
      final some = [
        condition('cold', 'acute'),
        condition('check', 'chronic', setting: CareSetting.primary),
        condition('sprain', 'acute', setting: CareSetting.urgentCare),
      ];
      expect([for (final c in historyCenters(people(some), some)) c.id], [10, 11, 12, 20, 21]);
      // Only the hospitals when every visit is at one.
      final cold = [condition('cold', 'acute')];
      expect([for (final c in historyCenters(people(cold), cold)) c.id], [10, 20]);
    });

    /// Against the database HEALTHHUB_DB_* names (127.0.0.1:9803 by
    /// default), when it is up and has admissions_hourly; skipped
    /// otherwise. Into a temporary table of the same name and definition,
    /// which hides the real one from this connection only and goes with
    /// it: nothing is written to the real table, nobody else sees the
    /// rows, and nothing is left behind even when the test is killed.
    test('written to admissions_hourly once, rewritten when it changes, nothing else under its run', () async {
      final settings = DbSettings.fromEnvironment();
      final db = Db(settings);
      addTearDown(db.close);
      if (!await db.ping()) {
        markTestSkipped('PostgreSQL not answering at $settings');
        return;
      }
      final c = await Connection.open(
        Endpoint(
          host: settings.host,
          port: settings.port,
          database: settings.database,
          username: settings.user,
          password: settings.password,
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      addTearDown(c.close);
      if ((await c.execute("SELECT to_regclass('public.admissions_hourly')")).single[0] == null) {
        markTestSkipped('no admissions_hourly at $settings');
        return;
      }
      await c.execute('CREATE TEMPORARY TABLE admissions_hourly (LIKE public.admissions_hourly INCLUDING ALL)');
      // The unqualified name is the temporary table now.
      expect(
        (await c.execute("SELECT relnamespace = pg_my_temp_schema() FROM pg_class WHERE oid = 'admissions_hourly'::regclass"))
            .single[0],
        true,
      );
      const run = 'fffffff1';
      const a = Place(id: 900001, name: 'Test hospital', kind: 'hospital', city: 'Reus', at: LatLon(41.1554, 1.1076));
      const b = Place(id: 900002, name: 'Test clinic', kind: 'clinic', city: 'Reus', at: LatLon(41.1500, 1.1100));
      Future<List<List<Object?>>> rows() async => [
        for (final r in await c.execute(
          Sql.named('''
            SELECT hospital_id, hospital_name, hour_start, admissions, acute_admissions, chronic_admissions
            FROM admissions_hourly WHERE run_id = @run ORDER BY hospital_id, hour_start
          '''),
          parameters: {'run': run},
        ))
          [...r],
      ];

      var written = await writeAdmissionsHistory(c, [a, b], 3, run: run);
      final expected = [
        for (final center in [a, b])
          for (final h in historySeries(center, 3))
            [center.id, center.name, historyStart.add(Duration(hours: h.hour)), h.acute + h.chronic, h.acute, h.chronic],
      ];
      expect(written, (centers: 2, written: 2, rows: expected.length));
      expect(await rows(), expected);

      // Again: up to date, nothing written.
      written = await writeAdmissionsHistory(c, [a, b], 3, run: run);
      expect(written, (centers: 2, written: 0, rows: expected.length));
      expect(await rows(), expected);

      // A row changed by hand, a center gone, more days: rewritten to match.
      await c.execute(
        Sql.named('UPDATE admissions_hourly SET admissions = 99, acute_admissions = 99 WHERE run_id = @run AND hospital_id = @id'),
        parameters: {'run': run, 'id': a.id},
      );
      written = await writeAdmissionsHistory(c, [a], 5, run: run);
      expect(written.written, 1);
      expect(await rows(), [
        for (final h in historySeries(a, 5))
          [a.id, a.name, historyStart.add(Duration(hours: h.hour)), h.acute + h.chronic, h.acute, h.chronic],
      ]);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
