import 'dart:math';

import 'package:healthhub_api/conditions.dart';
import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/simulated_history.dart';
import 'package:healthhub_api/simulation.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'simulation_test.dart' show throwingKafka;

Place _place(int id, String city, String kind, LatLon at, [String? subtype]) =>
    Place(id: id, name: '$kind $id', kind: kind, city: city, at: at, subtype: subtype);

/// Two cities with a care center of every kind the visits go to.
final _places = [
  _place(10, 'Reus', 'hospital', const LatLon(41.1554, 1.1076), 'Hospitales Generales'),
  _place(11, 'Reus', 'health_station', const LatLon(41.1600, 1.1050)),
  _place(12, 'Reus', 'clinic', const LatLon(41.1500, 1.1100), 'CUAP'),
  _place(13, 'Reus', 'clinic', const LatLon(41.1520, 1.1000), 'CSMA'),
  _place(14, 'Reus', 'hospital', const LatLon(41.1480, 1.1200), 'Hospitales de salud mental y tratamiento de toxicomanías'),
  _place(20, 'Barcelona', 'hospital', const LatLon(41.3843, 2.1941), 'Hospitales Generales'),
  _place(21, 'Barcelona', 'health_station', const LatLon(41.4036, 2.1744)),
];

/// [simulateHistory] without passing over the idle turns: every person
/// advanced at every turn, as a live run does.
List<Map<String, Object?>> _everyTurn(List<Place> places, int perCity, int minutesPerTurn, int days, String run) {
  final people = populate(places, perCity, minutesPerTurn, Random(populationSeed), conditions: conditionSeed);
  final random = Random(simulatedSeed);
  final admissions = <Map<String, Object?>>[];
  for (var turn = 0; simMinutes(turn, minutesPerTurn) < days * minutesPerDay; turn++) {
    for (final person in people) {
      final admission = advance(
        person,
        turn: turn,
        minutesPerTurn: minutesPerTurn,
        random: random,
        conditions: conditionSeed,
        run: run,
      );
      if (admission != null && (admission['day'] as int) <= days) admissions.add(admission);
    }
  }
  return admissions;
}

void main() {
  group('settings', () {
    test('HEALTHHUB_SIM_HISTORY_DAYS: a year by default, 0 for none, a whole number up to the most', () {
      expect(simulatedDaysFromEnvironment({}), 365);
      expect(simulatedDaysFromEnvironment({'HEALTHHUB_SIM_HISTORY_DAYS': ''}), 365);
      expect(simulatedDaysFromEnvironment({'HEALTHHUB_SIM_HISTORY_DAYS': '0'}), 0);
      expect(simulatedDaysFromEnvironment({'HEALTHHUB_SIM_HISTORY_DAYS': ' 120 '}), 120);
      expect(simulatedDaysFromEnvironment({'HEALTHHUB_SIM_HISTORY_DAYS': '$maxSimulatedDays'}), maxSimulatedDays);
      for (final bad in ['-1', '+5', 'a year', '1.5', '${maxSimulatedDays + 1}', '0x10', '99999999999999999999']) {
        expect(
          () => simulatedDaysFromEnvironment({'HEALTHHUB_SIM_HISTORY_DAYS': bad}),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test("the simulated run is a run id of its own, neither the history's nor a live run's", () {
      expect(simulatedRun, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(simulatedRun, isNot(historyRun));
      final simulation = Simulation(const [], const SimulationSettings(), throwingKafka)..start();
      addTearDown(simulation.stop);
      expect(simulation.run, isNot(simulatedRun));
    });
  });

  group('the care centers by what they take', () {
    test('answers as the lists do, for any home', () {
      final random = Random(7);
      final lists = [
        _places,
        // No general hospital: a specialised one takes the hospital's visits.
        [_places[4], _places[1]],
        // Nothing but hospitals: every setting falls back on one.
        [_places[0], _places[5]],
        // No hospital at all.
        [_places[1], _places[2]],
        <Place>[],
      ];
      for (final places in lists) {
        final index = CareIndex(places);
        for (var i = 0; i < 200; i++) {
          final home = LatLon(41 + random.nextDouble(), 1 + random.nextDouble() * 1.5);
          expect(index.hospital(home), nearestHospital(home, places));
          for (final setting in CareSetting.values) {
            expect(index.nearest(home, setting), nearestCareCenter(home, setting, places), reason: '$setting');
          }
        }
      }
    });
  });

  group('the simulated history', () {
    test('none for no days', () {
      expect(simulateHistory(_places, 10, 15, 0, conditionSeed), isEmpty);
    });

    test('the same admissions every time, those of every turn lived, in the order they happen', () {
      const days = 120;
      final admissions = simulateHistory(_places, 20, 15, days, conditionSeed);
      expect(admissions, isNotEmpty);
      // Passing over the idle turns changes nothing.
      expect(admissions, _everyTurn(_places, 20, 15, days, simulatedRun));
      expect(simulateHistory(_places, 20, 15, days, conditionSeed), admissions);
      // A longer history starts with the same days.
      final longer = simulateHistory(_places, 20, 15, days + 30, conditionSeed);
      expect(longer.take(admissions.length), admissions);
      expect(longer.length, greaterThan(admissions.length));

      final people = {for (final p in populate(_places, 20, 15, Random(populationSeed), conditions: conditionSeed)) p.id};
      final ids = <Object?>{};
      var last = 0;
      for (final a in admissions) {
        // An event of the simulation's shape, of the simulated run, valid
        // as the feed takes a live run's.
        expect(PeopleFeed.isAdmission(a), isTrue, reason: '$a');
        final id = a['eventId'] as String;
        expect(id, startsWith('$simulatedRun-${a['personId']}-d${a['day']}-t'));
        expect(ids.add(id), isTrue, reason: 'twice: $id');
        expect(people, contains(a['personId']));
        expect(a['day'], inInclusiveRange(1, days));
        expect(a['template'], inInclusiveRange(0, 2));
        // In the order they happen, turn after turn.
        final turn = a['turn'] as int;
        expect(turn, greaterThanOrEqualTo(last));
        last = turn;
      }
      // Visits to the end of it, by most of the people, at every kind of
      // care center.
      expect(admissions.last['day'] as int, greaterThan(days - 7));
      expect({for (final a in admissions) a['personId']}.length, greaterThan(people.length * 3 ~/ 4));
      expect({for (final a in admissions) a['careCenterKind']}, {'hospital', 'health_station', 'clinic'});
      expect({for (final a in admissions) a['conditionType']}, {'acute', 'chronic'});
    });

    test("another turn's length gives another history, as a live run's", () {
      final quarter = simulateHistory(_places, 10, 15, 60, conditionSeed);
      final hour = simulateHistory(_places, 10, 60, 60, conditionSeed);
      expect(hour, isNotEmpty);
      expect([for (final a in hour) a['eventId']], isNot([for (final a in quarter) a['eventId']]));
    });

    test('its mark tells one history from another, and its hours are the admissions per care center and hour', () {
      final admissions = simulateHistory(_places, 10, 15, 60, conditionSeed);
      final mark = historyMark(admissions);
      expect(mark.count, admissions.length);
      expect(historyMark(simulateHistory(_places, 10, 15, 60, conditionSeed)), mark);
      expect(historyMark(simulateHistory(_places, 10, 15, 61, conditionSeed)), isNot(mark));
      expect(historyMark(simulateHistory(_places, 11, 15, 60, conditionSeed)), isNot(mark));
      // A care center under another name, a visit on another day.
      final renamed = [for (final a in admissions) {...a}];
      renamed.first['hospitalName'] = '${renamed.first['hospitalName']} Nou';
      expect(historyMark(renamed), isNot(mark));
      final moved = [for (final a in admissions) {...a}];
      moved.last['day'] = (moved.last['day'] as int) + 1;
      expect(historyMark(moved), isNot(mark));

      final counts = hourlyCounts(admissions);
      expect(counts.admissions, admissions.length);
      expect(counts.hours, {
        for (final a in admissions) '${a['hospitalId']} ${a['day']} ${(a['simTime'] as String).substring(0, 2)}',
      }.length);
      expect(hourlyCounts(const []), (hours: 0, admissions: 0));
    });

    /// Against the database HEALTHHUB_DB_* names (127.0.0.1:9803 by
    /// default), when it is up and has the admissions tables; skipped
    /// otherwise. Into temporary tables of the same names and
    /// definitions, which hide the real ones from this connection only
    /// and go with it: nothing is written to the real tables.
    test('written to admissions once with its hourly counts, written again when it changes', () async {
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
      for (final table in ['admissions', 'admissions_hourly']) {
        if ((await c.execute("SELECT to_regclass('public.$table')")).single[0] == null) {
          markTestSkipped('no $table at $settings');
          return;
        }
        await c.execute('CREATE TEMPORARY TABLE $table (LIKE public.$table INCLUDING ALL)');
        expect(
          (await c.execute("SELECT relnamespace = pg_my_temp_schema() FROM pg_class WHERE oid = '$table'::regclass"))
              .single[0],
          true,
        );
      }
      const run = 'fffffff2';
      Future<List<List<Object?>>> stored() async => [
        for (final r in await c.execute(
          Sql.named('''
            SELECT event_id, person_id, person_name, age, sex, occupation, city, condition_code, condition_name,
                   condition_type, visit, visit_number, complaint, template, hospital_id, hospital_name, sim_day, sim_time
            FROM admissions WHERE split_part(event_id, '-', 1) = @run ORDER BY id
          '''),
          parameters: {'run': run},
        ))
          [...r],
      ];
      List<List<Object?>> rows(List<Map<String, Object?>> admissions) => [
        for (final a in admissions)
          [
            for (final field in const [
              'eventId', 'personId', 'name', 'age', 'sex', 'occupation', 'city', 'conditionCode', 'conditionName',
              'conditionType', 'visit', 'visitNumber', 'complaint', 'template', 'hospitalId', 'hospitalName', 'day',
              'simTime',
            ])
              a[field],
          ],
      ];
      Future<List<List<Object?>>> hours() async => [
        for (final r in await c.execute(
          Sql.named('''
            SELECT hospital_id, hour_start, admissions, acute_admissions, chronic_admissions
            FROM admissions_hourly WHERE run_id = @run ORDER BY hospital_id, hour_start
          '''),
          parameters: {'run': run},
        ))
          [...r],
      ];
      List<List<Object?>> counted(List<Map<String, Object?>> admissions) {
        final byHour = <(int, DateTime), List<int>>{};
        for (final a in admissions) {
          final hour = simEpoch.add(
            Duration(days: (a['day'] as int) - 1, hours: int.parse((a['simTime'] as String).substring(0, 2))),
          );
          final counts = byHour.putIfAbsent((a['hospitalId'] as int, hour), () => [0, 0, 0]);
          counts[0]++;
          counts[a['conditionType'] == 'acute' ? 1 : 2]++;
        }
        final keys = byHour.keys.toList()
          ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
        return [for (final k in keys) [k.$1, k.$2, ...byHour[k]!]];
      }

      // More than one INSERT's worth of admissions.
      final admissions = simulateHistory(_places, 200, 15, 365, conditionSeed, run: run);
      expect(admissions.length, greaterThan(2000));
      var written = await writeSimulatedHistory(c, admissions, run: run);
      expect(written.written, isTrue);
      expect(written.hoursWritten, isTrue);
      expect(written.admissions, admissions.length);
      expect(await stored(), rows(admissions));
      expect(await hours(), counted(admissions));
      expect(written.hours, (await hours()).length);

      // Again: up to date, nothing written.
      written = await writeSimulatedHistory(c, admissions, run: run);
      expect(written.written, isFalse);
      expect(written.hoursWritten, isFalse);
      expect(await stored(), rows(admissions));

      // Its hourly counts changed by hand: counted again, the admissions left.
      await c.execute(Sql.named('DELETE FROM admissions_hourly WHERE run_id = @run AND admissions = 1'), parameters: {'run': run});
      written = await writeSimulatedHistory(c, admissions, run: run);
      expect(written.written, isFalse);
      expect(written.hoursWritten, isTrue);
      expect(await hours(), counted(admissions));

      // An admission lost, another run's untouched: written again to match.
      await c.execute(
        Sql.named('DELETE FROM admissions WHERE event_id = @id'),
        parameters: {'id': admissions[admissions.length ~/ 2]['eventId']},
      );
      final other = simulateHistory(_places, 2, 15, 30, conditionSeed, run: 'fffffff3');
      await writeSimulatedHistory(c, other, run: 'fffffff3');
      written = await writeSimulatedHistory(c, admissions, run: run);
      expect(written.written, isTrue);
      expect(await stored(), rows(admissions));
      expect(await hours(), counted(admissions));

      // Fewer days: the days past them go.
      final shorter = simulateHistory(_places, 200, 15, 100, conditionSeed, run: run);
      written = await writeSimulatedHistory(c, shorter, run: run);
      expect(written.written, isTrue);
      expect(await stored(), rows(shorter));
      expect(await hours(), counted(shorter));
      expect(
        (await c.execute("SELECT count(*)::int FROM admissions WHERE split_part(event_id, '-', 1) = 'fffffff3'")).single[0],
        other.length,
      );

      // None: nothing left under the run.
      written = await writeSimulatedHistory(c, const [], run: run);
      expect(await stored(), isEmpty);
      expect(await hours(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
