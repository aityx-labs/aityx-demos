/// The admissions history: days of admissions per hour at the care
/// centers the simulation's people use, generated rather than simulated,
/// so admissions_hourly holds series long and full enough for a forecast
/// (datyx's DeepAR) to learn the daily and weekly shape from. A live run
/// covers a simulated day in 24 real seconds but starts again at day 1 at
/// every start of the API, and its few people leave most hours empty.
///
/// The history is one run, [historyRun], written by the API at start in
/// dev mode (bin/server.dart) and by bin/history.dart, for the care
/// centers of the people the API draws ([populationSeed]). Every hour of
/// every day from 2026-01-01 (day 1, as the live runs' calendar), and
/// each care center's counts drawn from Poisson rates
/// ([historyRates]): a level of the center's ([historyLevel]) times the
/// daily profile of arrivals (simulation.dart's [arrivalWeight], peaking
/// at 13:00, the shape of a live run's acute and chronic admissions
/// alike) times a milder weekend. Deterministic: each center's random
/// numbers are seeded by its id, so generating again gives the same rows.
library;

import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';

import 'conditions.dart';
import 'simulation.dart';

/// The days of history by default, and at most.
const defaultHistoryDays = 90;
const maxHistoryDays = 730;

/// The day the history starts: day 1 of the simulated calendar, which
/// admissions_hourly writes as 2026-01-01.
final historyStart = DateTime.utc(2026, 1, 1);

/// The base of each care center's own seed ([historySeries]).
const historySeed = 20260101;

/// Saturdays' and Sundays' rates, against a weekday's.
const historyWeekendFactor = 0.85;

/// How many days of history to generate, from HEALTHHUB_HISTORY_DAYS:
/// [defaultHistoryDays] when unset or empty, 0 for none. Throws a
/// [FormatException] for anything but a whole number from 0 to
/// [maxHistoryDays].
int historyDaysFromEnvironment([Map<String, String>? env]) {
  env ??= Platform.environment;
  final value = (env['HEALTHHUB_HISTORY_DAYS'] ?? '').trim();
  if (value.isEmpty) return defaultHistoryDays;
  final days = RegExp(r'^\d{1,6}$').hasMatch(value) ? int.parse(value) : null;
  if (days == null || days > maxHistoryDays) {
    throw FormatException('HEALTHHUB_HISTORY_DAYS must be a whole number from 0 to $maxHistoryDays', value);
  }
  return days;
}

/// The daily profile, from 0 to 1: [arrivalWeight] over its peak, so 1 at
/// 13:00 and, with an amplitude of 1, 0 at 01:00.
double dailyProfile(int hour) => arrivalWeight(hour) / (1 + arrivalAmplitude);

/// A care center's level, its mean admissions in the peak hour of a
/// weekday, and the share of them that is acute.
typedef HistoryLevel = ({double peak, double acuteShare});

/// The level of [center], by its kind, varied within the kind's range by
/// [random]'s first draw: a hospital 3 to 8 admissions in the peak hour,
/// 60% acute; a health station 1.5 to 4, 35% acute (primary care is most
/// often planned); a clinic 1 to 3, half acute.
HistoryLevel historyLevel(Place center, Random random) {
  final u = random.nextDouble();
  return switch (center.kind) {
    'hospital' => (peak: 3 + 5 * u, acuteShare: 0.6),
    'health_station' => (peak: 1.5 + 2.5 * u, acuteShare: 0.35),
    _ => (peak: 1 + 2 * u, acuteShare: 0.5),
  };
}

/// The mean acute and chronic admissions of a center at [level] in an
/// hour starting at [hour] of the day, on a weekend or not:
///
///   acute   = peak × acuteShare × profile(hour) × weekly
///   chronic = peak × (1 − acuteShare) × profile(hour) × weekly
///
/// profile being [dailyProfile] and weekly 1 on weekdays,
/// [historyWeekendFactor] on weekends. One shape for both, a single
/// harmonic, the one a live run's acute and chronic admissions follow
/// ([arrivalHour]): highest at 13:00, where they add up to the peak, nil
/// at 01:00.
({double acute, double chronic}) historyRates(HistoryLevel level, int hour, {required bool weekend}) {
  final rate = level.peak * dailyProfile(hour) * (weekend ? historyWeekendFactor : 1.0);
  return (acute: rate * level.acuteShare, chronic: rate * (1 - level.acuteShare));
}

/// A count drawn from a Poisson distribution of mean [mean] (Knuth's
/// method: the means here are small).
int poisson(double mean, Random random) {
  if (mean <= 0) return 0;
  final limit = exp(-mean);
  var count = 0;
  var product = random.nextDouble();
  while (product > limit) {
    count++;
    product *= random.nextDouble();
  }
  return count;
}

/// One hour of a care center's history with an admission: the hour, in
/// hours since [historyStart], and its acute and chronic admissions.
typedef HistoryHour = ({int hour, int acute, int chronic});

/// Whether the day [day] (from 1) of the calendar is a Saturday or a
/// Sunday: day 1, 2026-01-01, is a Thursday.
bool isWeekend(int day) => historyStart.add(Duration(days: day - 1)).weekday >= DateTime.saturday;

/// [center]'s history over [days] days: every hour's acute and chronic
/// admissions drawn from [historyRates], the hours with none left out, as
/// admissions_hourly does. Seeded by the center's id, so the same center
/// always gets the same hours.
List<HistoryHour> historySeries(Place center, int days) {
  final random = Random(historySeed + center.id);
  final level = historyLevel(center, random);
  final hours = <HistoryHour>[];
  for (var day = 1; day <= days; day++) {
    final weekend = isWeekend(day);
    for (var hour = 0; hour < 24; hour++) {
      final rates = historyRates(level, hour, weekend: weekend);
      final acute = poisson(rates.acute, random);
      final chronic = poisson(rates.chronic, random);
      if (acute + chronic > 0) hours.add((hour: (day - 1) * 24 + hour, acute: acute, chronic: chronic));
    }
  }
  return hours;
}

/// The care centers the history covers, by id: those [people] use, their
/// hospital and the care center of every setting the visits of
/// [conditions] go to ([Person.careCenterFor]). The API's people
/// ([populationSeed]) are the same at every start, so are these.
List<Place> historyCenters(List<Person> people, List<MedicalCondition> conditions) {
  final settings = {
    for (final condition in conditions)
      for (final kind in VisitKind.values) condition.settingOf(kind),
  };
  final byId = <int, Place>{};
  for (final person in people) {
    for (final center in [person.hospital, for (final setting in settings) person.careCenterFor(setting)]) {
      byId[center.id] = center;
    }
  }
  return [...byId.values]..sort((a, b) => a.id.compareTo(b.id));
}

/// What a generation of the history did: the care centers it covers, how
/// many it wrote (the others were up to date), and the rows the history
/// holds.
typedef HistoryWritten = ({int centers, int written, int rows});

/// Makes admissions_hourly hold the history of [days] days for [centers]
/// under [run] ([historyRun]; a test's own otherwise), and nothing else
/// under it: a center whose rows already match ([historySeries]: their
/// count, admissions, acute admissions, last hour and name) is left
/// alone; any other's are replaced, in a transaction of its own (one
/// INSERT ... SELECT FROM unnest, the values as parameters); the rows of
/// centers no longer covered are deleted. So
/// it runs at every start at the cost of one query, and a change of
/// [days] or of the centers rewrites what changed.
Future<HistoryWritten> writeAdmissionsHistory(
  Connection connection,
  List<Place> centers,
  int days, {
  String run = historyRun,
}) async {
  final stored = <int, (int, int, int, DateTime?, String?)>{};
  final rows = await connection.execute(
    Sql.named('''
      SELECT hospital_id, count(*)::int, sum(admissions)::int, sum(acute_admissions)::int, max(hour_start),
        max(hospital_name)
      FROM admissions_hourly WHERE run_id = @run GROUP BY hospital_id
    '''),
    parameters: {'run': run},
  );
  for (final row in rows) {
    stored[row[0] as int] = (row[1] as int, row[2] as int, row[3] as int, row[4] as DateTime?, row[5] as String?);
  }
  await connection.execute(
    Sql.named('DELETE FROM admissions_hourly WHERE run_id = @run AND NOT (hospital_id = ANY(@ids))'),
    parameters: {
      'run': run,
      'ids': TypedValue(Type.integerArray, [for (final center in centers) center.id]),
    },
  );
  var written = 0;
  var total = 0;
  for (final center in centers) {
    final series = historySeries(center, days);
    total += series.length;
    final acute = series.fold(0, (sum, h) => sum + h.acute);
    final admissions = series.fold(0, (sum, h) => sum + h.acute + h.chronic);
    final last = series.isEmpty ? null : historyStart.add(Duration(hours: series.last.hour));
    final had = stored[center.id];
    if (had == (series.length, admissions, acute, last, center.name)) continue;
    await connection.runTx((tx) async {
      await tx.execute(
        Sql.named('DELETE FROM admissions_hourly WHERE run_id = @run AND hospital_id = @id'),
        parameters: {'run': run, 'id': center.id},
      );
      await tx.execute(
        Sql.named('''
          INSERT INTO admissions_hourly
            (run_id, hospital_id, hospital_name, hour_start, admissions, acute_admissions, chronic_admissions)
          SELECT @run, @id, @name, TIMESTAMP '2026-01-01 00:00:00' + u.h * INTERVAL '1 hour', u.a + u.c, u.a, u.c
          FROM unnest(@hours, @acute, @chronic) AS u(h, a, c)
          ON CONFLICT (run_id, hospital_id, hour_start) DO NOTHING
        '''),
        parameters: {
          'run': run,
          'id': center.id,
          'name': center.name,
          'hours': TypedValue(Type.integerArray, [for (final h in series) h.hour]),
          'acute': TypedValue(Type.integerArray, [for (final h in series) h.acute]),
          'chronic': TypedValue(Type.integerArray, [for (final h in series) h.chronic]),
        },
      );
    });
    written++;
  }
  return (centers: centers.length, written: written, rows: total);
}
