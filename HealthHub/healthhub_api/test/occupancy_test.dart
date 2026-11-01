import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/occupancy_alarms.dart' show ObservedOccupancy;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

/// Rolls back what a test wrote.
class _Rollback implements Exception {}

void main() {
  /// Against the real database (the postgres service of compose.yaml, at
  /// HEALTHHUB_DB_* or 127.0.0.1:9803), when it is up; skipped otherwise,
  /// so the suite passes without Docker. Its admissions are rolled back.
  test('occupancy_hourly counts each stay in every hour it covers, up to the run\'s latest arrival', () async {
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
    // A condition whose first visit stays 3 hours or more, and one whose follow-ups stay 1 to 2.
    final long = await c.execute('SELECT code FROM medical_conditions WHERE stay_hours >= 3 ORDER BY code LIMIT 1');
    final short = await c.execute(
      'SELECT code FROM medical_conditions WHERE follow_up_stay_hours BETWEEN 1 AND 2 ORDER BY code LIMIT 1',
    );
    const run = 'fffffff0';
    Map<String, int>? hours;
    ObservedOccupancy? observed;
    try {
      await c.runTx((tx) async {
        Future<void> admit(String person, int hospital, String code, String visit, String time) => tx.execute(
          Sql.named('''
            INSERT INTO admissions (event_id, person_id, person_name, age, sex, occupation, city, condition_code,
              condition_name, condition_type, visit, visit_number, complaint, hospital_id, hospital_name, sim_day, sim_time)
            VALUES (@event, @person, 'Test', 40, 'woman', 'nurse', 'Reus', @code, 'Test', 'acute', @visit, 1, 'test',
              @hospital, 'Test hospital', 1, @time)
          '''),
          parameters: {
            'event': '$run-$person-d1-t${time.replaceAll(':', '')}',
            'person': person,
            'code': code,
            'visit': visit,
            'hospital': hospital,
            'time': time,
          },
        );
        // At 09:10, someone staying the long condition's first-visit hours; at 10:30, someone's short follow-up.
        await admit('reus-1', 900001, long.first[0] as String, 'first', '09:10');
        await admit('reus-2', 900001, short.first[0] as String, 'repeat', '10:30');
        // The run's latest arrival, elsewhere: 11:05, so hours after 11:00 aren't counted yet.
        await admit('reus-3', 900002, short.first[0] as String, 'repeat', '11:05');
        final rows = await tx.execute(
          Sql.named(
            "SELECT to_char(hour_start, 'HH24:MI'), occupancy FROM occupancy_hourly "
            'WHERE run_id = @run AND hospital_id = 900001 ORDER BY hour_start',
          ),
          parameters: {'run': run},
        );
        hours = {for (final row in rows) row[0] as String: row[1] as int};
        observed = await Db.readObserved(tx, run);
        throw _Rollback();
      });
    } on _Rollback {
      // Nothing stays in the database.
    }
    // reus-1 from 09:10 for 3 hours or more, cut at the run's 11:00; reus-2 from 10:30 for 1 or 2 hours, into 11:00.
    expect(hours, {'09:00': 1, '10:00': 2, '11:00': 2});
    // The occupancy alarms' actual level reads the run's latest hour, 11:00: both care centers in care then.
    expect(observed?.end, DateTime.utc(2026, 1, 1, 11));
    expect(observed?.occupancy, {900001: 2, 900002: 1});
    final left = await c.execute(
      Sql.named('SELECT count(*) FROM admissions WHERE event_id LIKE @run'),
      parameters: {'run': '$run-%'},
    );
    expect(left.first[0], 0);
  });
}
