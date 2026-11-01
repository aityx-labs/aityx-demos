/// Writes the admissions history (lib/history.dart) to a database without
/// starting the server: what the API does at start in dev mode, for any
/// database HEALTHHUB_DB_* names (lib/db.dart), whose tables it makes
/// and seeds first, as the API does.
///
///   dart run bin/history.dart [--days N] [--dry-run]
///
///   --days N    the days of history (default HEALTHHUB_HISTORY_DAYS, else
///               90; 0 to 730)
///   --dry-run   only reads the care centers, and prints what it would
///               write: the care centers, rows and admissions, and the
///               mean admissions per care center by hour of day
///
/// The care centers are those the API's people use: HEALTHHUB_SIM_PEOPLE
/// a city, drawn with the same seed ([populationSeed]).
library;

import 'dart:io';
import 'dart:math';

import 'package:healthhub_api/conditions_seed.dart';
import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/history.dart';
import 'package:healthhub_api/simulation.dart';

const _usage = 'usage: dart run bin/history.dart [--days N] [--dry-run]';

Future<void> main(List<String> args) async {
  var dryRun = false;
  int days;
  try {
    days = historyDaysFromEnvironment();
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
