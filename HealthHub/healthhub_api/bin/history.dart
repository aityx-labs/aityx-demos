/// Writes the two histories to a database without starting the server:
/// the admissions per hour drawn from rates (lib/history.dart) and the
/// simulated year of the people's visits (lib/simulated_history.dart),
/// what the API does at start in dev mode, for any database
/// HEALTHHUB_DB_* names (lib/db.dart), whose tables it makes and seeds
/// first, as the API does.
///
///   dart run bin/history.dart [--days N] [--sim-days N] [--dry-run]
///
///   --days N      the days of admissions per hour (default
///                 HEALTHHUB_HISTORY_DAYS, else 90; 0 to 730)
///   --sim-days N  the days of simulated visits (default
///                 HEALTHHUB_SIM_HISTORY_DAYS, else 365; 0 to 730)
///   --dry-run     only reads the care centers, and prints what it would
///                 write: the care centers, rows and admissions, and the
///                 mean admissions per care center by hour of day; of the
///                 simulated visits, the admissions, the people and care
///                 centers with one, the days of care (patient_days) and
///                 the hours with an admission (admissions_hourly)
///
/// The care centers are those the API's people use: HEALTHHUB_SIM_PEOPLE
/// a city, drawn with the same seed ([populationSeed]), who are also the
/// people of the simulated visits.
library;

import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/history.dart';
import 'package:healthhub_api/simulated_history.dart';
import 'package:healthhub_api/simulation.dart';

const _usage = 'usage: dart run bin/history.dart [--days N] [--sim-days N] [--dry-run]';

Future<void> main(List<String> args) async {
  var dryRun = false;
  int days;
  int simDays;
  try {
    days = historyDaysFromEnvironment();
    simDays = simulatedDaysFromEnvironment();
  } on FormatException catch (error) {
    stderr.writeln('error: ${error.message}');
    exit(64);
  }
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dry-run':
        dryRun = true;
      case '--days' when i + 1 < args.length:
        try {
          days = historyDaysFromEnvironment({'HEALTHHUB_HISTORY_DAYS': args[++i]});
        } on FormatException {
          stderr.writeln('error: --days must be a whole number from 0 to $maxHistoryDays');
          exit(64);
        }
      case '--sim-days' when i + 1 < args.length:
        try {
          simDays = simulatedDaysFromEnvironment({'HEALTHHUB_SIM_HISTORY_DAYS': args[++i]});
        } on FormatException {
          stderr.writeln('error: --sim-days must be a whole number from 0 to $maxSimulatedDays');
          exit(64);
        }
      case '--help' || '-h':
        stdout.writeln(_usage);
        return;
      default:
        stderr.writeln(_usage);
        exit(64);
    }
  }
  final db = Db(DbSettings.fromEnvironment());
  try {
    if (!dryRun) await db.migrate();
    final places = await db.places();
    final simulation = SimulationSettings.fromEnvironment();
    final perCity = simulation.peoplePerCity;
    // The API's people ([populationSeed]), so the API's care centers.
    final people = populate(places, perCity, simulation.minutesPerTurn, Random(populationSeed), conditions: conditionSeed);
    final centers = historyCenters(people, conditionSeed);
    stdout.writeln(
      'history: run $historyRun, $days days from ${historyStart.toIso8601String().substring(0, 10)}, '
      '${centers.length} care centers of $perCity people a city, database ${db.settings}',
    );
    _summary(centers, days);
    final watch = Stopwatch()..start();
    final simulated = simulateHistory(places, perCity, simulation.minutesPerTurn, simDays, conditionSeed);
    stdout.writeln(
      'simulated history: run $simulatedRun, $simDays days, ${people.length} people, '
      'simulated in ${watch.elapsedMilliseconds} ms',
    );
    _simulatedSummary(simulated);
    if (dryRun) {
      stdout.writeln('dry run: nothing written');
      return;
    }
    // A statement that times out on a busy database closes the connection:
    // the next attempt carries on, as the centers written are up to date.
    HistoryWritten? written;
    for (var attempt = 1; written == null; attempt++) {
      try {
        written = await db.writeHistory(centers, days);
      } catch (error) {
        if (attempt == 3) rethrow;
        stderr.writeln('history: attempt $attempt failed, trying again: $error');
      }
    }
    stdout.writeln(
      'written: ${written.written} care centers (the other ${written.centers - written.written} up to date), '
      '${written.rows} rows under run $historyRun',
    );
    SimulatedWritten? visits;
    for (var attempt = 1; visits == null; attempt++) {
      try {
        visits = await db.writeSimulated(simulated);
      } catch (error) {
        if (attempt == 3) rethrow;
        stderr.writeln('simulated history: attempt $attempt failed, trying again: $error');
      }
    }
    stdout.writeln(
      '${visits.written ? 'written' : 'up to date'}: ${visits.admissions} admissions under run $simulatedRun, '
      '${visits.hours} hours of admissions_hourly ${visits.hoursWritten ? 'counted from them' : 'up to date'}',
    );
  } catch (error) {
    stderr.writeln('error: $error');
    exitCode = 1;
  } finally {
    await db.close();
  }
}

/// Prints what the history of [centers] over [days] days holds.
void _summary(List<Place> centers, int days) {
  final byKind = <String, int>{};
  var rows = 0, acute = 0, chronic = 0;
  final byHour = List.filled(24, 0);
  for (final center in centers) {
    byKind[center.kind] = (byKind[center.kind] ?? 0) + 1;
    for (final h in historySeries(center, days)) {
      rows++;
      acute += h.acute;
      chronic += h.chronic;
      byHour[h.hour % 24] += h.acute + h.chronic;
    }
  }
  stdout.writeln('care centers: ${[for (final e in byKind.entries) '${e.value} ${e.key}'].join(', ')}');
  stdout.writeln('rows: $rows (of ${centers.length * days * 24} hours); admissions: ${acute + chronic} '
      '($acute acute, $chronic chronic)');
  if (centers.isEmpty || days == 0) return;
  stdout.writeln('mean admissions per care center by hour of day:');
  for (var h = 0; h < 24; h++) {
    final mean = byHour[h] / (centers.length * days);
    stdout.writeln('  ${h.toString().padLeft(2, '0')}:00 ${mean.toStringAsFixed(2).padLeft(5)} ${'#' * (mean * 20).round()}');
  }
}

/// Prints what the simulated history's [admissions] hold.
void _simulatedSummary(List<Map<String, Object?>> admissions) {
  final people = <Object?>{}, centers = <Object?>{}, patientDays = <(Object?, Object?)>{};
  var acute = 0;
  for (final a in admissions) {
    people.add(a['personId']);
    centers.add(a['hospitalId']);
    patientDays.add((a['personId'], a['day']));
    if (a['conditionType'] == 'acute') acute++;
  }
  stdout.writeln(
    'admissions: ${admissions.length} ($acute acute, ${admissions.length - acute} chronic) of ${people.length} people '
    'at ${centers.length} care centers; ${patientDays.length} days of care (patient_days), '
    '${hourlyCounts(admissions).hours} hours with an admission (admissions_hourly)',
  );
}
