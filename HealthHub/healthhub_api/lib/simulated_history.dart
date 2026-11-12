/// The simulated history: a year of the simulation's people going for
/// care, lived at once rather than turn by turn, so the admissions table
/// holds, from the first start, what a live run takes a real day to make.
/// patient_days and occupancy_hourly are views of the admissions, so they
/// get long series with it: a person's days of care over a year, the kind
/// datyx's XGBoost needs before it can train (several horizons of 30
/// days), and each care center's people in care hour by hour, for its
/// DeepAR.
///
/// It is one run, [simulatedRun], written by the API at start in dev mode
/// (bin/server.dart) and by bin/history.dart: the people the API draws
/// ([populationSeed]) living [advance] turn after turn from 06:00 on day 1
/// (2026-01-01, as a live run) to the end of the last day, their random
/// numbers seeded ([simulatedSeed]), so the same settings always make the
/// same admissions. They never go through Kafka: nothing is published, so
/// nothing is triaged, and the Flink job counts none of them; the run's
/// rows of admissions_hourly are counted here from its admissions, as the
/// job would.
library;

import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';

import 'conditions.dart';
import 'simulation.dart';

/// The days of simulated history by default, and at most.
const defaultSimulatedDays = 365;
const maxSimulatedDays = 730;

/// The seed of what the people do in the simulated history.
const simulatedSeed = 20260102;

/// How many admissions go in one INSERT.
const _batch = 2000;

/// How many days of history to simulate, from HEALTHHUB_SIM_HISTORY_DAYS:
/// [defaultSimulatedDays] when unset or empty, 0 for none. Throws a
/// [FormatException] for anything but a whole number from 0 to
/// [maxSimulatedDays].
int simulatedDaysFromEnvironment([Map<String, String>? env]) {
  env ??= Platform.environment;
  final value = (env['HEALTHHUB_SIM_HISTORY_DAYS'] ?? '').trim();
  if (value.isEmpty) return defaultSimulatedDays;
  final days = RegExp(r'^\d{1,6}$').hasMatch(value) ? int.parse(value) : null;
  if (days == null || days > maxSimulatedDays) {
    throw FormatException('HEALTHHUB_SIM_HISTORY_DAYS must be a whole number from 0 to $maxSimulatedDays', value);
  }
  return days;
}

/// The admissions of [days] days of the simulation, as [advance] makes
/// them (the events a live run publishes), in the order they happen:
/// [perCity] people a city of [places], the API's ([populationSeed]),
/// each living every turn of [minutesPerTurn] minutes from the start of
/// the clock to the end of day [days], under [run]. Seeded, so the same
/// arguments give the same admissions.
List<Map<String, Object?>> simulateHistory(
  List<Place> places,
  int perCity,
  int minutesPerTurn,
  int days,
  List<MedicalCondition> conditions, {
  String run = simulatedRun,
}) {
  if (days <= 0) return const [];
  final people = populate(places, perCity, minutesPerTurn, Random(populationSeed), conditions: conditions);
  final random = Random(simulatedSeed);
  final end = days * minutesPerDay;
  final admissions = <Map<String, Object?>>[];
  // The minute each person next has something to do: most turns they are
  // at home or in care with nothing due, where [advance] changes nothing
  // and draws no number, so those turns are passed over ([_idleUntil]).
  final wake = List.filled(people.length, 0);
  for (var turn = 0; simMinutes(turn, minutesPerTurn) < end; turn++) {
    final now = simMinutes(turn, minutesPerTurn);
    for (var i = 0; i < people.length; i++) {
      if (now < wake[i]) continue;
      final person = people[i];
      final admission = advance(
        person,
        turn: turn,
        minutesPerTurn: minutesPerTurn,
        random: random,
        conditions: conditions,
        run: run,
      );
      // An arrival is timed to the minute, so one in the last turn can
      // fall just past the end: it isn't the history's.
      if (admission != null && (admission['day'] as int) <= days) admissions.add(admission);
      wake[i] = _idleUntil(person, now);
    }
  }
  return admissions;
}

/// The minute until which [advance] leaves [person] as they are, after
/// their turn at [now]: at home, the next visit due or the next acute
/// episode's onset, whichever comes first; in care, the end of the stay or
/// that onset (an episode starts wherever they are); on the way, the next
/// turn.
int _idleUntil(Person person, int now) {
  const never = 1 << 62;
  final onset = person.acuteOnsetAt ?? never;
  return switch (person.state) {
    PersonState.home => [onset, person.chronic?.dueAt ?? never, person.acute?.dueAt ?? never].reduce(min),
    PersonState.atHospital => min(onset, person.leaveAt ?? now),
    _ => now,
  };
}

/// What tells one set of admissions from another without comparing every
/// row: how many, and sums over them that a change of the people, the
/// conditions, the care centers, the seeds or the days moves. The same
/// numbers [_storedMark] reads from the table.
typedef HistoryMark = ({int count, int days, int visits, int centers, int ages, int text});

/// The mark of [admissions].
HistoryMark historyMark(List<Map<String, Object?>> admissions) {
  var days = 0, visits = 0, centers = 0, ages = 0, text = 0;
  for (final a in admissions) {
    days += a['day'] as int;
    visits += a['visitNumber'] as int;
    centers += a['hospitalId'] as int;
    ages += a['age'] as int;
    // In characters, as PostgreSQL's length() counts them.
    text += (a['complaint'] as String).runes.length +
        (a['hospitalName'] as String).runes.length +
        (a['conditionName'] as String).runes.length +
        (a['simTime'] as String).length;
  }
  return (count: admissions.length, days: days, visits: visits, centers: centers, ages: ages, text: text);
}

/// The mark of the admissions the table holds under [run].
Future<HistoryMark> _storedMark(Session session, String run) async {
  final rows = await session.execute(
    Sql.named('''
      SELECT count(*)::bigint, coalesce(sum(sim_day), 0)::bigint, coalesce(sum(visit_number), 0)::bigint,
             coalesce(sum(hospital_id), 0)::bigint, coalesce(sum(age), 0)::bigint,
             coalesce(sum(length(complaint) + length(hospital_name) + length(condition_name) + length(sim_time)), 0)::bigint
      FROM admissions WHERE split_part(event_id, '-', 1) = @run
    '''),
    parameters: {'run': run},
  );
  final row = rows.first;
  return (
    count: row[0] as int,
    days: row[1] as int,
    visits: row[2] as int,
    centers: row[3] as int,
    ages: row[4] as int,
    text: row[5] as int,
  );
}

/// The admissions per care center and hour of [admissions], as the Flink
/// job counts a live run's: how many hours have one, and how many
/// admissions in all.
({int hours, int admissions}) hourlyCounts(List<Map<String, Object?>> admissions) {
  final hours = <(int, int, String)>{};
  for (final a in admissions) {
    hours.add((a['hospitalId'] as int, a['day'] as int, (a['simTime'] as String).substring(0, 2)));
  }
  return (hours: hours.length, admissions: admissions.length);
}

/// What a writing of the simulated history did: the admissions it holds,
/// whether they were written now (false: they were there already), and
/// the hours of admissions_hourly counted from them, written now or not.
typedef SimulatedWritten = ({int admissions, bool written, int hours, bool hoursWritten});

/// Makes the admissions table hold exactly [admissions] under [run]
/// ([simulateHistory]'s, of [simulatedRun]; a test's own otherwise), and
/// admissions_hourly their counts per care center and hour. Admissions
/// whose mark ([historyMark]) the table already has are left alone;
/// otherwise the run's are deleted and inserted again, [_batch] an INSERT
/// (the values as parameters), in the order given, so their ids follow
/// the simulated time. A writing that stops half way leaves a mark that
/// doesn't match, and the next one starts over. The hourly counts are
/// made again, in one transaction, when the admissions were, or when
/// theirs don't add up to the admissions'.
Future<SimulatedWritten> writeSimulatedHistory(
  Connection connection,
  List<Map<String, Object?>> admissions, {
  String run = simulatedRun,
}) async {
  final mark = historyMark(admissions);
  final written = await _storedMark(connection, run) != mark;
  if (written) {
    await connection.execute(
      Sql.named("DELETE FROM admissions WHERE split_part(event_id, '-', 1) = @run"),
      parameters: {'run': run},
    );
    for (var from = 0; from < admissions.length; from += _batch) {
      final batch = admissions.sublist(from, min(from + _batch, admissions.length));
      List<T> column<T>(String field) => [for (final a in batch) a[field] as T];
      await connection.execute(
        Sql.named('''
          INSERT INTO admissions (event_id, person_id, person_name, age, sex, occupation, city,
            condition_code, condition_name, condition_type, visit, visit_number, complaint, template,
            hospital_id, hospital_name, sim_day, sim_time)
          SELECT * FROM unnest(@eventId, @personId, @name, @age, @sex, @occupation, @city,
            @conditionCode, @conditionName, @conditionType, @visit, @visitNumber, @complaint, @template,
            @hospitalId, @hospitalName, @day, @simTime)
          ON CONFLICT (event_id) DO NOTHING
        '''),
        parameters: {
          for (final field in const [
            'eventId', 'personId', 'name', 'sex', 'occupation', 'city', 'conditionCode', 'conditionName',
            'conditionType', 'visit', 'complaint', 'hospitalName', 'simTime',
          ])
            field: TypedValue(Type.textArray, column<String>(field)),
          for (final field in const ['age', 'visitNumber', 'template', 'hospitalId', 'day'])
            field: TypedValue(Type.integerArray, column<int?>(field)),
        },
      );
    }
  }
  final counts = hourlyCounts(admissions);
  final stored = await connection.execute(
    Sql.named('SELECT count(*)::bigint, coalesce(sum(admissions), 0)::bigint FROM admissions_hourly WHERE run_id = @run'),
    parameters: {'run': run},
  );
  final hoursWritten = written || stored.first[0] != counts.hours || stored.first[1] != counts.admissions;
  if (hoursWritten) {
    await connection.runTx((tx) async {
      await tx.execute(Sql.named('DELETE FROM admissions_hourly WHERE run_id = @run'), parameters: {'run': run});
      await tx.execute(
        Sql.named('''
          INSERT INTO admissions_hourly
            (run_id, hospital_id, hospital_name, hour_start, admissions, acute_admissions, chronic_admissions)
          SELECT @run, hospital_id, max(hospital_name),
                 TIMESTAMP '2026-01-01' + (sim_day - 1) * INTERVAL '1 day'
                   + split_part(sim_time, ':', 1)::int * INTERVAL '1 hour',
                 count(*)::int,
                 (count(*) FILTER (WHERE condition_type = 'acute'))::int,
                 (count(*) FILTER (WHERE condition_type = 'chronic'))::int
          FROM admissions WHERE split_part(event_id, '-', 1) = @run
          GROUP BY hospital_id, 4
          ON CONFLICT (run_id, hospital_id, hour_start) DO NOTHING
        '''),
        parameters: {'run': run},
      );
    });
  }
  return (admissions: admissions.length, written: written, hours: counts.hours, hoursWritten: hoursWritten);
}
