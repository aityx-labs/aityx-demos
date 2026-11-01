import 'package:healthhub_api/db.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// Rolls back what a test wrote.
class _Rollback implements Exception {}

final _event = <String, Object?>{
  'kind': 'alarm',
  'id': 'fffffff0-1-1',
  'run': 'fffffff0',
  'hospitalId': 1,
  'hospitalName': "Hospital de l'Esperança",
  'careCenterKind': 'hospital',
  'level': 'expected',
  'overflowAt': '2026-06-03T16:00',
  'overflowDay': 154,
  'leadHours': 7,
  'mean': 10.2,
  'p90': 12,
  'peak': {'at': '2026-06-03T18:00', 'day': 154, 'mean': 11.3, 'p90': 13.0},
  'capacity': 8,
  'unit': 'beds',
  'end': '2026-06-03T09:00',
  'horizonHours': 24,
  'trainingRun': 4,
  'now': {'day': 154, 'simTime': '09:12', 'date': '2026-06-03'},
  'previous': null,
  'raisedAt': '2026-11-01T14:03:05.120Z',
};

void main() {
  test('every value of an alarm event is a typed parameter', () {
    expect(Db.insertAlarmSql, isNot(contains("'")));
    final parameters = Db.alarmParameters(_event);
    for (final name in RegExp(r'@(\w+)').allMatches(Db.insertAlarmSql).map((m) => m[1]!)) {
      expect(parameters, contains(name), reason: name);
    }
    expect(parameters['overflowAt']!.value, DateTime.utc(2026, 6, 3, 16));
    expect(parameters['p90']!.value, 12.0);
    expect(parameters['simDay']!.value, 154);
    expect(parameters['simTime']!.value, '09:12');
    expect(parameters['trainingRun']!.value, 4);
    expect(parameters['raisedAt']!.value, DateTime.utc(2026, 11, 1, 14, 3, 5, 120));
    // A cleared event: no level, no overflow.
    final cleared = Db.alarmParameters({..._event, 'kind': 'cleared', 'level': null, 'overflowAt': null, 'peak': null, 'now': null});
    expect((cleared['level']!.value, cleared['overflowAt']!.value, cleared['peakAt']!.value), (null, null, null));
    expect(cleared['simDay']!.value, isNull);
  });

  /// Against a database (HEALTHHUB_DB_*, a scratch one: the migration runs
  /// on it), when it is up; skipped otherwise. Its rows are rolled back.
  test('an alarm event is stored once by its id, a cleared one without a level', () async {
    final settings = DbSettings.fromEnvironment();
    final db = Db(settings);
    addTearDown(db.close);
    if (!await db.ping()) {
      markTestSkipped('PostgreSQL not answering at $settings');
      return;
    }
    await db.migrate();
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
    List<Object?>? row;
    late int first, again, cleared;
    try {
      await c.runTx((tx) async {
        Future<int> insert(Map<String, Object?> event) async =>
            (await tx.execute(Sql.named(Db.insertAlarmSql), parameters: Db.alarmParameters(event))).length;
        first = await insert(_event);
        again = await insert(_event);
        cleared = await insert({
          ..._event, 'id': 'fffffff0-1-2', 'kind': 'cleared', 'level': null, 'previous': 'expected',
          'overflowAt': null, 'leadHours': null, 'mean': null, 'p90': null,
        });
        // A cleared event with a level is refused by the table's check.
        await tx.execute('SAVEPOINT bad');
        await expectLater(
          tx.execute(Sql.named(Db.insertAlarmSql), parameters: Db.alarmParameters({..._event, 'id': 'fffffff0-1-3', 'kind': 'cleared'})),
          throwsA(isA<ServerException>().having((e) => Db.isPermanentError(e), 'permanent', isTrue)),
        );
        await tx.execute('ROLLBACK TO SAVEPOINT bad');
        final rows = await tx.execute(
          Sql.named('''
            SELECT kind, run_id, hospital_id, hospital_name, care_center_kind, level, previous_level, overflow_at,
                   lead_hours, mean, p90, peak_at, peak_mean, peak_p90, capacity, unit, series_end, horizon_hours,
                   training_run, sim_day, sim_time, raised_at
            FROM occupancy_alarm WHERE id = @id
          '''),
          parameters: {'id': _event['id']},
        );
        row = rows.single.toList();
        throw _Rollback();
      });
    } on _Rollback {
      // Nothing written stays.
    }
    expect((first, again, cleared), (1, 0, 1));
    expect(row, [
      'alarm', 'fffffff0', 1, "Hospital de l'Esperança", 'hospital', 'expected', null,
      DateTime.utc(2026, 6, 3, 16), 7, 10.2, 12.0, DateTime.utc(2026, 6, 3, 18), 11.3, 13.0, 8, 'beds',
      DateTime.utc(2026, 6, 3, 9), 24, 4, 154, '09:12', DateTime.utc(2026, 11, 1, 14, 3, 5, 120),
    ]);
    final left = await c.execute("SELECT count(*) FROM occupancy_alarm WHERE run_id = 'fffffff0'");
    expect(left.single[0], 0);
  });
}
