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
  'threshold': 0.9,
  'thresholdPlaces': 7.2,
  'occupancy': 6,
  'occupancyShare': 0.75,
  'observedAt': '2026-06-03T09:00',
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
    expect(parameters['threshold']!.value, 0.9);
    expect(parameters['occupancy']!.value, 6);
    expect(parameters['observedAt']!.value, DateTime.utc(2026, 6, 3, 9));
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
        // The actual level, which the table's check takes since it was made again.
        final actual = await insert({
          ..._event, 'id': 'fffffff0-1-4', 'level': 'actual', 'previous': 'expected', 'occupancy': 8,
          'overflowAt': '2026-06-03T09:00', 'leadHours': 0, 'mean': null, 'p90': null,
        });
        expect(actual, 1);
        // A level that isn't one is refused.
        await tx.execute('SAVEPOINT level');
        await expectLater(
          tx.execute(Sql.named(Db.insertAlarmSql), parameters: Db.alarmParameters({..._event, 'id': 'fffffff0-1-5', 'level': 'over'})),
          throwsA(isA<ServerException>()),
        );
        await tx.execute('ROLLBACK TO SAVEPOINT level');
        // A cleared event with a level is refused by the table's check.
        await tx.execute('SAVEPOINT bad');
        await expectLater(
          tx.execute(Sql.named(Db.insertAlarmSql), parameters: Db.alarmParameters({..._event, 'id': 'fffffff0-1-3', 'kind': 'cleared'})),
          throwsA(isA<ServerException>().having((e) => Db.isPermanentError(e), 'permanent', isTrue)),
        );
        await tx.execute('ROLLBACK TO SAVEPOINT bad');
        final rows = await tx.execute(
          Sql.named('''
            SELECT kind, run_id, hospital_id, hospital_name, care_center_kind, level, previous_level, threshold,
                   occupancy, observed_at, overflow_at, lead_hours, mean, p90, peak_at, peak_mean, peak_p90, capacity,
                   unit, series_end, horizon_hours, training_run, sim_day, sim_time, raised_at
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
      'alarm', 'fffffff0', 1, "Hospital de l'Esperança", 'hospital', 'expected', null, 0.9, 6,
      DateTime.utc(2026, 6, 3, 9), DateTime.utc(2026, 6, 3, 16), 7, 10.2, 12.0, DateTime.utc(2026, 6, 3, 18), 11.3, 13.0, 8, 'beds',
      DateTime.utc(2026, 6, 3, 9), 24, 4, 154, '09:12', DateTime.utc(2026, 11, 1, 14, 3, 5, 120),
    ]);
    final left = await c.execute("SELECT count(*) FROM occupancy_alarm WHERE run_id = 'fffffff0'");
    expect(left.single[0], 0);
  });

  test('a forecast\'s steps as occupancy_forecast\'s rows: the series\' end and each step\'s lead', () {
    final rows = Db.forecastRows({
      12: [
        {'at': '2026-01-02T02:00', 'mean': 3.5, 'p10': 2, 'p50': 3, 'p90': 5},
        {'at': '2026-01-02T01:00', 'mean': 3.0, 'p10': 1, 'p50': 3, 'p90': 4},
        'nonsense',
      ],
      13: const [],
    });
    expect(rows, [
      {'hospital_id': 12, 'hour_start': '2026-01-02T01:00:00', 'series_end': '2026-01-02T00:00:00', 'lead_hours': 1,
        'mean': 3.0, 'p10': 1.0, 'p90': 4.0},
      {'hospital_id': 12, 'hour_start': '2026-01-02T02:00:00', 'series_end': '2026-01-02T00:00:00', 'lead_hours': 2,
        'mean': 3.5, 'p10': 2.0, 'p90': 5.0},
    ]);
    // Every value a parameter: the rows one JSON parameter.
    for (final sql in [Db.upsertForecastSql, Db.predictedOccupancySql, Db.runEndSql, Db.occupancyAtSql, Db.pruneForecastsSql]) {
      expect(sql, isNot(contains("'")));
    }
    final parameters = Db.forecastParameters('abcd1234', rows, 4, DateTime.utc(2026, 11, 1, 14));
    for (final name in RegExp(r'@(\w+)').allMatches(Db.upsertForecastSql).map((m) => m[1]!)) {
      expect(parameters, contains(name), reason: name);
    }
    expect(parameters['rows']!.value, rows);
  });

  /// Against a scratch database (HEALTHHUB_DB_*), when it is up; skipped
  /// otherwise. Its rows are rolled back.
  test('what was predicted of each hour: the forecast made closest to it wins, and is read back by hour', () async {
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
    const run = 'fffffff0';
    List<Map<String, Object?>> forecast(int fromHour, List<num> means) => [
      for (var i = 0; i < means.length; i++)
        {
          'at': DateTime.utc(2026, 1, 2, fromHour + i + 1).toIso8601String().substring(0, 16),
          'mean': means[i],
          'p10': means[i] - 1,
          'p50': means[i],
          'p90': means[i] + 1,
        },
    ];
    List<List<Object?>>? read;
    try {
      await c.runTx((tx) async {
        Future<void> keep(Map<int, List<Object?>> forecasts, int trainingRun) => tx.execute(
          Sql.named(Db.upsertForecastSql),
          parameters: Db.forecastParameters(run, Db.forecastRows(forecasts), trainingRun, DateTime.utc(2026, 11, 1, 14)),
        );
        // From 00:00: 01:00 to 04:00. Then from 02:00: 03:00 to 05:00, closer, so they win.
        await keep({900001: forecast(0, [1, 2, 3, 4]), 900002: forecast(0, [9])}, 4);
        await keep({900001: forecast(2, [30, 40, 50])}, 5);
        // An older forecast, from 01:00, comes late: it changes 02:00 (closer than 00:00's) but not 03:00 or 04:00.
        await keep({900001: forecast(1, [200, 300, 400])}, 6);
        // The same forecast asked again writes nothing: no new row version.
        Future<List<Object?>> versions() async => [
          for (final row in await tx.execute(
            Sql.named('SELECT ctid::text FROM occupancy_forecast WHERE run_id = @run ORDER BY hospital_id, hour_start'),
            parameters: {'run': run},
          )) row[0],
        ];
        final before = await versions();
        await keep({900001: forecast(2, [30, 40, 50])}, 5);
        await keep({900001: forecast(1, [200, 300, 400])}, 6);
        expect(await versions(), before);
        // From the same end with other numbers (a model retrained): replaced.
        await keep({900002: forecast(0, [8])}, 7);
        expect(await versions(), isNot(before));
        final rows = await tx.execute(
          Sql.named(Db.predictedOccupancySql),
          parameters: {
            'run': run,
            'id': 900001,
            'from': TypedValue(Type.timestampWithoutTimezone, DateTime.utc(2026, 1, 2)),
            'to': TypedValue(Type.timestampWithoutTimezone, DateTime.utc(2026, 1, 2, 4)),
          },
        );
        read = [for (final row in rows) row.toList()];
        throw _Rollback();
      });
    } on _Rollback {
      // Nothing written stays.
    }
    expect(read, [
      [DateTime.utc(2026, 1, 2, 1), 1.0, 0.0, 2.0, 1],
      [DateTime.utc(2026, 1, 2, 2), 200.0, 199.0, 201.0, 1],
      [DateTime.utc(2026, 1, 2, 3), 30.0, 29.0, 31.0, 1],
      [DateTime.utc(2026, 1, 2, 4), 40.0, 39.0, 41.0, 2],
    ]);
    final left = await c.execute("SELECT count(*) FROM occupancy_forecast WHERE run_id = 'fffffff0'");
    expect(left.single[0], 0);
  });

  /// Against a scratch database (HEALTHHUB_DB_*), when it is up; skipped
  /// otherwise. Its rows are rolled back.
  test('pruned: all but the runs forecast last, and their hours long before their latest', () async {
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
    List<List<Object?>>? read;
    int? deleted;
    try {
      await c.runTx((tx) async {
        // Only these runs' rows count here.
        await tx.execute('DELETE FROM occupancy_forecast');
        // Four runs, forecast an hour apart, each 6 hours of one care center.
        for (var r = 0; r < 4; r++) {
          await tx.execute(
            Sql.named(Db.upsertForecastSql),
            parameters: Db.forecastParameters('fffffff$r', Db.forecastRows({
              900001: [
                for (var h = 1; h <= 6; h++)
                  {'at': DateTime.utc(2026, 1, 2, h).toIso8601String().substring(0, 16), 'mean': 1, 'p10': 0, 'p50': 1, 'p90': 2},
              ],
            }), 4, DateTime.utc(2026, 11, 1, 10 + r)),
          );
        }
        final result = await tx.execute(
          Sql.named(Db.pruneForecastsSql),
          parameters: {'keepRuns': TypedValue(Type.integer, 2), 'keepHours': TypedValue(Type.integer, 2)},
        );
        deleted = result.affectedRows;
        final rows = await tx.execute('SELECT run_id, hour_start FROM occupancy_forecast ORDER BY run_id, hour_start');
        read = [for (final row in rows) row.toList()];
        throw _Rollback();
      });
    } on _Rollback {
      // Nothing written stays.
    }
    // The two runs forecast last, the 2 hours before their latest (06:00) and it.
    expect(read, [
      for (final run in ['fffffff2', 'fffffff3'])
        for (final h in [4, 5, 6]) [run, DateTime.utc(2026, 1, 2, h)],
    ]);
    expect(deleted, 24 - 6);
  });
}
