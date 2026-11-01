/// The API's database: PostgreSQL, the postgres service of compose.yaml.
/// One connection, opened when first needed and reopened after a failure,
/// so the API starts (and answers /api/health) whether or not the database
/// is up yet. The schema is the API's own: it makes its tables at start.
library;

import 'dart:io';

import 'package:postgres/postgres.dart';

import 'care_centers.dart';
import 'care_centers_seed.dart';
import 'conditions.dart';
import 'conditions_seed.dart';
import 'routes.dart' show Bbox;
import 'schema_comments.dart';
import 'simulation.dart' show LatLon, Place;

/// Where the database is, from the environment (scripts/api.sh and
/// compose.yaml set these):
///   HEALTHHUB_DB_HOST      (default 127.0.0.1)
///   HEALTHHUB_DB_PORT      (default 9803, where compose.yaml publishes it)
///   HEALTHHUB_DB_NAME      (default healthhub)
///   HEALTHHUB_DB_USER      (default healthhub)
///   HEALTHHUB_DB_PASSWORD  (secret; default healthhub, for development)
class DbSettings {
  DbSettings({
    required this.host,
    required this.port,
    required this.database,
    required this.user,
    required this.password,
  });

  factory DbSettings.fromEnvironment([Map<String, String>? env]) {
    env ??= Platform.environment;
    return DbSettings(
      host: env['HEALTHHUB_DB_HOST'] ?? '127.0.0.1',
      port: int.parse(env['HEALTHHUB_DB_PORT'] ?? '9803'),
      database: env['HEALTHHUB_DB_NAME'] ?? 'healthhub',
      user: env['HEALTHHUB_DB_USER'] ?? 'healthhub',
      password: env['HEALTHHUB_DB_PASSWORD'] ?? 'healthhub',
    );
  }

  final String host;
  final int port;
  final String database;
  final String user;
  final String password;

  /// For logs: never the password.
  @override
  String toString() => '$user@$host:$port/$database';
}

/// The greeting the app shows, kept in the database so the round trip is
/// real: one row, written at start if the table is empty.
const helloWorld = 'Hello, world';

class Db {
  Db(this.settings);

  final DbSettings settings;
  Connection? _connection;

  /// The connection being opened, so calls at the same time share it
  /// rather than open one each.
  Future<Connection>? _opening;

  /// The open connection, opened now if there is none.
  Future<Connection> _open() {
    final existing = _connection;
    if (existing != null && existing.isOpen) return Future.value(existing);
    return _opening ??= _connect().whenComplete(() => _opening = null);
  }

  Future<Connection> _connect() async {
    final connection = await Connection.open(
      Endpoint(
        host: settings.host,
        port: settings.port,
        database: settings.database,
        username: settings.user,
        password: settings.password,
      ),
      // Local development and the compose network: no TLS. Anywhere
      // shared, the database should be behind TLS and this should change.
      settings: const ConnectionSettings(
        sslMode: SslMode.disable,
        connectTimeout: Duration(seconds: 5),
        queryTimeout: Duration(seconds: 10),
      ),
    );
    _connection = connection;
    return connection;
  }

  /// The migration running, if one is: the one thing other calls wait
  /// for.
  Future<void>? _migrating;

  /// Runs [action] on the connection once no migration runs. The driver
  /// sends one statement at a time on the connection anyway, so health
  /// pings and reads never wait on each other here, nor behind an
  /// admission being retried; but a statement that waits behind the
  /// migration's long transaction can time out, and its failure would
  /// close the connection under the migration, so they wait for it here
  /// instead. On a failure of the connection (not an error the server
  /// answered, which leaves it usable) it is dropped, so the next call
  /// opens a new one; the error is rethrown.
  Future<T> _run<T>(Future<T> Function(Connection) action) async {
    for (var migrating = _migrating; migrating != null; migrating = _migrating) {
      try {
        await migrating;
      } catch (_) {}
    }
    return _runNow(action);
  }

  Future<T> _runNow<T>(Future<T> Function(Connection) action) async {
    Connection? used;
    try {
      used = await _open();
      return await action(used);
    } catch (error) {
      final broken = _connection;
      if (broken != null && identical(broken, used) && !(error is ServerException && broken.isOpen)) {
        _connection = null;
        try {
          await broken.close();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Whether [error] is the database refusing the data itself, which a
  /// retry can't fix: an SQLSTATE of class 22 (data exception: a value out
  /// of range, a NUL in a text) or 23 (integrity constraint violation: a
  /// check, a not-null).
  static bool isPermanentError(Object error) =>
      error is ServerException && (error.code?.startsWith('22') == true || error.code?.startsWith('23') == true);

  /// Makes the tables when they're missing, the greeting when it is, and
  /// seeds the care centers. Retried by the caller: at start the database
  /// may not be up yet. Every other call waits until it is done.
  Future<void> migrate() async {
    for (var migrating = _migrating; migrating != null; migrating = _migrating) {
      try {
        await migrating;
      } catch (_) {}
    }
    final migrating = _migrating = _runNow(_migrate);
    try {
      await migrating;
    } finally {
      if (identical(_migrating, migrating)) _migrating = null;
    }
  }

  Future<void> _migrate(Connection c) async {
    await c.execute('''
      CREATE TABLE IF NOT EXISTS greetings (
        id SERIAL PRIMARY KEY,
        message TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    await c.execute(
      Sql.named(
        'INSERT INTO greetings (message) '
        'SELECT @message WHERE NOT EXISTS (SELECT 1 FROM greetings)',
      ),
      parameters: {'message': helloWorld},
    );
    await c.execute('''
      CREATE TABLE IF NOT EXISTS care_centers (
        id SERIAL PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        kind TEXT NOT NULL CHECK (kind IN ('hospital', 'clinic', 'health_station')),
        subtype TEXT,
        address TEXT,
        postal_code TEXT,
        city TEXT NOT NULL,
        region TEXT NOT NULL,
        country CHAR(2) NOT NULL,
        latitude DOUBLE PRECISION,
        longitude DOUBLE PRECISION,
        phone TEXT,
        website TEXT,
        ownership TEXT NOT NULL CHECK (ownership IN ('public', 'private', 'unknown')),
        source TEXT NOT NULL,
        source_id TEXT,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    await c.execute(
      'CREATE INDEX IF NOT EXISTS care_centers_city_kind ON care_centers (country, city, kind)',
    );
    await seedCareCenters(c, careCenterSeed);
    await c.execute('''
      CREATE TABLE IF NOT EXISTS medical_conditions (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('acute', 'chronic')),
        prevalence DOUBLE PRECISION NOT NULL,
        min_age INT NOT NULL,
        max_age INT NOT NULL,
        summary TEXT NOT NULL,
        treatment TEXT NOT NULL,
        treatment_duration_days INT,
        duration TEXT NOT NULL,
        visit_count INT NOT NULL,
        visit_interval_days INT NOT NULL,
        stay_hours INT NOT NULL,
        female_share DOUBLE PRECISION NOT NULL DEFAULT 0.5,
        urgent BOOLEAN NOT NULL DEFAULT false,
        follow_up_stay_hours INT,
        course_gap_days INT,
        setting TEXT NOT NULL DEFAULT 'hospital',
        follow_up_setting TEXT NOT NULL DEFAULT 'hospital'
      )
    ''');
    // Added after the table was first made: a database from before has it
    // without them.
    for (final column in [
      'female_share DOUBLE PRECISION NOT NULL DEFAULT 0.5',
      'urgent BOOLEAN NOT NULL DEFAULT false',
      'follow_up_stay_hours INT',
      'course_gap_days INT',
      "setting TEXT NOT NULL DEFAULT 'hospital'",
      "follow_up_setting TEXT NOT NULL DEFAULT 'hospital'",
    ]) {
      await c.execute('ALTER TABLE medical_conditions ADD COLUMN IF NOT EXISTS $column');
    }
    await c.execute('''
      CREATE TABLE IF NOT EXISTS complaint_templates (
        id SERIAL PRIMARY KEY,
        condition_code TEXT NOT NULL REFERENCES medical_conditions (code) ON DELETE CASCADE,
        visit TEXT NOT NULL CHECK (visit IN ('first', 'repeat', 'last')),
        position INT NOT NULL,
        text TEXT NOT NULL,
        triage TEXT CHECK (triage IN ('red', 'orange', 'yellow', 'green', 'blue')),
        UNIQUE (condition_code, visit, position)
      )
    ''');
    // Added after the table was first made: the template's reference
    // triage level (lib/conditions.dart's triageLevels).
    await c.execute(
      "ALTER TABLE complaint_templates ADD COLUMN IF NOT EXISTS triage TEXT "
      "CHECK (triage IN ('red', 'orange', 'yellow', 'green', 'blue'))",
    );
    await seedConditions(c, conditionSeed);
    // The simulated people's arrivals at the hospital, as the feed reads
    // them from healthhub.admissions; their moves are not kept.
    await c.execute('''
      CREATE TABLE IF NOT EXISTS admissions (
        id SERIAL PRIMARY KEY,
        event_id TEXT NOT NULL UNIQUE,
        person_id TEXT NOT NULL,
        person_name TEXT NOT NULL,
        age INT NOT NULL,
        sex TEXT NOT NULL,
        occupation TEXT NOT NULL,
        city TEXT NOT NULL,
        condition_code TEXT NOT NULL,
        condition_name TEXT NOT NULL,
        condition_type TEXT NOT NULL,
        visit TEXT NOT NULL CHECK (visit IN ('first', 'repeat', 'last')),
        visit_number INT NOT NULL,
        complaint TEXT NOT NULL,
        template INT,
        hospital_id INT NOT NULL,
        hospital_name TEXT NOT NULL,
        sim_day INT NOT NULL,
        sim_time TEXT NOT NULL,
        recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
    // Added after the table was first made: which complaint template the
    // admission was said from, null for those recorded before.
    await c.execute('ALTER TABLE admissions ADD COLUMN IF NOT EXISTS template INT');
    // One person's admissions, for GET /api/people/{id}.
    await c.execute('CREATE INDEX IF NOT EXISTS admissions_person_idx ON admissions (person_id)');
    // One care center's admissions, the latest first, for GET /api/care-centers/{id}.
    await c.execute('CREATE INDEX IF NOT EXISTS admissions_hospital_idx ON admissions (hospital_id, id)');
    // Each admission's triage by aityx (lib/triage.dart): the level, the
    // wait, the area, the rules behind them, what Jev read, aityx's
    // receipt and the template's reference level; or why it failed.
    await c.execute('''
      CREATE TABLE IF NOT EXISTS admission_triage (
        event_id TEXT PRIMARY KEY REFERENCES admissions (event_id) ON DELETE CASCADE,
        level TEXT CHECK (level IN ('red', 'orange', 'yellow', 'green', 'blue')),
        wait_minutes INT,
        area TEXT,
        nurse_check BOOLEAN,
        level_rule INT,
        level_why TEXT,
        area_rule INT,
        area_why TEXT,
        signs JSONB,
        choices JSONB,
        receipt JSONB,
        reference TEXT CHECK (reference IN ('red', 'orange', 'yellow', 'green', 'blue')),
        error TEXT,
        input_tokens INT,
        millis INT,
        mode TEXT,
        triaged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        CHECK ((level IS NULL) <> (error IS NULL))
      )
    ''');
    // The admissions per run, hospital and simulated hour. The API only
    // makes it: the Flink job (flink/admissions-hourly.sql) writes it,
    // upserting by the key; an hour without admissions has no row.
    await c.execute('''
      CREATE TABLE IF NOT EXISTS admissions_hourly (
        run_id TEXT NOT NULL,
        hospital_id INT NOT NULL,
        hospital_name TEXT NOT NULL,
        hour_start TIMESTAMP NOT NULL,
        admissions INT NOT NULL,
        acute_admissions INT NOT NULL,
        chronic_admissions INT NOT NULL,
        PRIMARY KEY (run_id, hospital_id, hour_start)
      )
    ''');
    // Each person's days at the hospital, per run and simulated day (day 1
    // being 2026-01-01, as in admissions_hourly): the visits of the day,
    // the hours of care they take (each visit's stay, by its condition and
    // kind, as the simulation keeps people) and the person's facts, the
    // chronic condition being the one their run's admissions show. A view
    // of the admissions, so it is always up to date; a day without visits
    // has no row. Recreated at every start, as its definition may change.
    await c.execute('DROP VIEW IF EXISTS patient_days');
    await c.execute('''
      CREATE VIEW patient_days AS
      SELECT split_part(a.event_id, '-', 1) AS run_id,
             a.person_id,
             DATE '2026-01-01' + (a.sim_day - 1) AS day,
             max(a.age) AS age,
             max(a.sex) AS sex,
             max(a.city) AS city,
             max(a.hospital_id) AS hospital_id,
             coalesce(max(max(a.condition_code) FILTER (WHERE a.condition_type = 'chronic'))
               OVER (PARTITION BY split_part(a.event_id, '-', 1), a.person_id), 'none') AS chronic_condition,
             count(*)::int AS visits,
             (count(*) FILTER (WHERE a.condition_type = 'acute'))::int AS acute_visits,
             (count(*) FILTER (WHERE a.condition_type = 'chronic'))::int AS chronic_visits,
             sum(CASE WHEN a.visit = 'first' THEN m.stay_hours
                      ELSE coalesce(m.follow_up_stay_hours, m.stay_hours) END)::int AS stay_hours
      FROM admissions a
      LEFT JOIN medical_conditions m ON m.code = a.condition_code
      WHERE a.event_id ~ '^[0-9a-f]{8}-'
      GROUP BY split_part(a.event_id, '-', 1), a.person_id, a.sim_day
    ''');
    // What each table and column is, for a catalogue reading the schema.
    await commentSchema(c);
  }

  /// Makes medical_conditions and complaint_templates hold exactly
  /// [conditions], in one transaction: each condition and template
  /// inserted or updated by its key (the code; the code, visit and
  /// position), and the rows no longer in the seed deleted (a condition's
  /// templates with it).
  static Future<void> seedConditions(Connection connection, List<MedicalCondition> conditions) =>
      connection.runTx((tx) async {
        const columns = MedicalCondition.columns;
        final updates = [for (final column in columns.skip(1)) '$column = EXCLUDED.$column'].join(', ');
        final placeholders = [for (var i = 1; i <= columns.length; i++) '\$$i'].join(', ');
        final codes = <String>[];
        final visits = <String>[];
        final positions = <int>[];
        for (final condition in conditions) {
          await tx.execute(
            'INSERT INTO medical_conditions (${columns.join(', ')}) VALUES ($placeholders) '
            'ON CONFLICT (code) DO UPDATE SET $updates',
            parameters: condition.values,
          );
          for (final kind in VisitKind.values) {
            for (final (position, text) in condition.templates(kind).indexed) {
              await tx.execute(
                Sql.named(
                  'INSERT INTO complaint_templates (condition_code, visit, position, text, triage) '
                  'VALUES (@code, @visit, @position, @text, @triage) '
                  'ON CONFLICT (condition_code, visit, position) '
                  'DO UPDATE SET text = EXCLUDED.text, triage = EXCLUDED.triage',
                ),
                parameters: {
                  'code': condition.code,
                  'visit': kind.json,
                  'position': position,
                  'text': text,
                  'triage': condition.triageOf(kind)[position],
                },
              );
              codes.add(condition.code);
              visits.add(kind.json);
              positions.add(position);
            }
          }
        }
        await tx.execute(
          Sql.named('DELETE FROM medical_conditions WHERE NOT (code = ANY(@codes))'),
          parameters: {
            'codes': TypedValue(Type.textArray, [for (final c in conditions) c.code]),
          },
        );
        await tx.execute(
          Sql.named('''
            DELETE FROM complaint_templates t WHERE NOT EXISTS (
              SELECT 1 FROM unnest(@codes, @visits, @positions) AS k(code, visit, position)
              WHERE k.code = t.condition_code AND k.visit = t.visit AND k.position = t.position)
          '''),
          parameters: {
            'codes': TypedValue(Type.textArray, codes),
            'visits': TypedValue(Type.textArray, visits),
            'positions': TypedValue(Type.integerArray, positions),
          },
        );
      });

  /// Records [admission], an event the feed validated
  /// (PeopleFeed.isAdmission): true when it was inserted, false when one
  /// with its event id was already recorded and left as it is, so a retry
  /// or a replay never doubles it. Throws when the database doesn't answer
  /// or refuses it ([isPermanentError]).
  Future<bool> recordAdmission(Map<String, Object?> admission) => _run((c) async {
    final rows = await c.execute(
      Sql.named('''
        INSERT INTO admissions (event_id, person_id, person_name, age, sex, occupation, city,
          condition_code, condition_name, condition_type, visit, visit_number, complaint, template,
          hospital_id, hospital_name, sim_day, sim_time)
        VALUES (@eventId, @personId, @name, @age, @sex, @occupation, @city,
          @conditionCode, @conditionName, @conditionType, @visit, @visitNumber, @complaint, @template,
          @hospitalId, @hospitalName, @day, @simTime)
        ON CONFLICT (event_id) DO NOTHING
        RETURNING id
      '''),
      parameters: {
        for (final field in _admissionFields) field: admission[field],
        'template': TypedValue(Type.integer, admission['template']),
      },
    );
    return rows.isNotEmpty;
  });

  /// Records [triage], an admission's triage (lib/triage.dart's
  /// triageAdmission), once: a second for the same admission is left
  /// out. Throws when the database doesn't answer or refuses it.
  Future<void> recordTriage(Map<String, Object?> triage) => _run((c) async {
    Object? json(String field) => triage[field] == null ? null : TypedValue(Type.jsonb, triage[field]);
    await c.execute(
      Sql.named('''
        INSERT INTO admission_triage (event_id, level, wait_minutes, area, nurse_check, level_rule,
          level_why, area_rule, area_why, signs, choices, receipt, reference, error, input_tokens,
          millis, mode)
        VALUES (@eventId, @level, @waitMinutes, @area, @nurseCheck, @levelRule, @levelWhy,
          @areaRule, @areaWhy, @signs, @choices, @receipt, @reference, @error, @inputTokens,
          @millis, @mode)
        ON CONFLICT (event_id) DO NOTHING
      '''),
      parameters: {
        'eventId': triage['eventId'],
        'level': TypedValue(Type.text, triage['level']),
        'waitMinutes': TypedValue(Type.integer, triage['waitMinutes']),
        'area': TypedValue(Type.text, triage['area']),
        'nurseCheck': TypedValue(Type.boolean, triage['nurseCheck']),
        'levelRule': TypedValue(Type.integer, triage['levelRule']),
        'levelWhy': TypedValue(Type.text, triage['levelWhy']),
        'areaRule': TypedValue(Type.integer, triage['areaRule']),
        'areaWhy': TypedValue(Type.text, triage['areaWhy']),
        'signs': json('signs'),
        'choices': json('choices'),
        'receipt': json('receipt'),
        'reference': TypedValue(Type.text, triage['reference']),
        'error': TypedValue(Type.text, triage['error']),
        'inputTokens': TypedValue(Type.integer, triage['inputTokens']),
        'millis': TypedValue(Type.integer, triage['millis']),
        'mode': TypedValue(Type.text, triage['mode']),
      },
    );
  });

  /// The latest [limit] admissions triaged, newest first, each with what
  /// the desk heard and its triage, without the receipt: what GET
  /// /api/triage lists.
  Future<List<Map<String, Object?>>> latestTriage({required int limit}) => _run((c) async {
    final rows = await c.execute(
      Sql.named('''
        SELECT $_triageColumns
        FROM admission_triage t JOIN admissions a USING (event_id)
        ORDER BY t.triaged_at DESC, a.id DESC LIMIT @limit
      '''),
      parameters: {'limit': limit},
    );
    return [for (final row in rows) _triageRow(row)];
  });

  /// One admission's triage with aityx's receipt, or null when it has
  /// none: GET /api/triage/{eventId}.
  Future<Map<String, Object?>?> triageOf(String eventId) => _run((c) async {
    final rows = await c.execute(
      Sql.named('''
        SELECT $_triageColumns, t.receipt
        FROM admission_triage t JOIN admissions a USING (event_id)
        WHERE t.event_id = @eventId
      '''),
      parameters: {'eventId': eventId},
    );
    if (rows.isEmpty) return null;
    return {..._triageRow(rows.first), 'receipt': rows.first[_triageColumnCount]};
  });

  /// Every triage so far, counted: how many, by level, how many failed,
  /// how many matched the reference, were within one level of it, or
  /// less (under) or more (over) urgent than it, how many a nurse
  /// checks, and the time and tokens they took.
  Future<Map<String, Object?>> triageSummary() => _run((c) async {
    const rank = "array_position(ARRAY['red', 'orange', 'yellow', 'green', 'blue']::text[], %s)";
    final level = rank.replaceAll('%s', 'level');
    final reference = rank.replaceAll('%s', 'reference');
    final rows = await c.execute('''
      SELECT count(*), count(*) FILTER (WHERE error IS NOT NULL),
        count(*) FILTER (WHERE level IS NOT NULL AND reference IS NOT NULL),
        count(*) FILTER (WHERE level = reference),
        count(*) FILTER (WHERE abs($level - $reference) <= 1),
        count(*) FILTER (WHERE $level > $reference),
        count(*) FILTER (WHERE $level < $reference),
        count(*) FILTER (WHERE nurse_check),
        coalesce(sum(input_tokens), 0), percentile_disc(0.5) WITHIN GROUP (ORDER BY millis)
          FILTER (WHERE level IS NOT NULL),
        count(*) FILTER (WHERE level = 'red'), count(*) FILTER (WHERE level = 'orange'),
        count(*) FILTER (WHERE level = 'yellow'), count(*) FILTER (WHERE level = 'green'),
        count(*) FILTER (WHERE level = 'blue')
      FROM admission_triage
    ''');
    final r = rows.first;
    int n(int i) => (r[i] as int?) ?? 0;
    return {
      'total': n(0),
      'failed': n(1),
      'compared': n(2),
      'matched': n(3),
      'withinOne': n(4),
      'under': n(5),
      'over': n(6),
      'nurseChecks': n(7),
      'inputTokens': n(8),
      'medianMillis': r[9],
      'levels': {'red': n(10), 'orange': n(11), 'yellow': n(12), 'green': n(13), 'blue': n(14)},
    };
  });

  static const _triageColumns = '''
    t.event_id, a.person_name, a.age, a.sex, a.city, a.complaint, a.condition_name, a.condition_type,
    a.visit, a.visit_number, a.hospital_name, a.sim_day, a.sim_time, t.level, t.wait_minutes, t.area,
    t.nurse_check, t.level_rule, t.level_why, t.area_rule, t.area_why, t.signs, t.choices,
    t.reference, t.error, t.input_tokens, t.millis, t.triaged_at, a.person_id, a.hospital_id''';
  static const _triageColumnCount = 30;

  static Map<String, Object?> _triageRow(ResultRow row) => {
    'eventId': row[0],
    'name': row[1],
    'age': row[2],
    'sex': row[3],
    'city': row[4],
    'complaint': row[5],
    'conditionName': row[6],
    'conditionType': row[7],
    'visit': row[8],
    'visitNumber': row[9],
    'hospitalName': row[10],
    'day': row[11],
    'simTime': row[12],
    'level': row[13],
    'waitMinutes': row[14],
    'area': row[15],
    'nurseCheck': row[16],
    'levelRule': row[17],
    'levelWhy': row[18],
    'areaRule': row[19],
    'areaWhy': row[20],
    'signs': row[21],
    'choices': row[22],
    'reference': row[23],
    'error': row[24],
    'inputTokens': row[25],
    'millis': row[26],
    'triagedAt': (row[27] as DateTime).toUtc().toIso8601String(),
    'personId': row[28],
    'hospitalId': row[29],
  };

  static const _admissionFields = [
    'eventId', 'personId', 'name', 'age', 'sex', 'occupation', 'city', 'conditionCode',
    'conditionName', 'conditionType', 'visit', 'visitNumber', 'complaint', 'hospitalId',
    'hospitalName', 'day', 'simTime',
  ];

  /// How many of a person's admissions, and of their days,
  /// [personHistory] answers at most.
  static const personLimit = 200;

  /// One person of one run, as the database has them: their admissions,
  /// newest first, each with its triage when it has one (level, wait,
  /// area, nurse check, reference, error), and their days of care from
  /// patient_days, the latest first; at most [personLimit] of each. A
  /// person's id comes back in every run, a new person each time, so
  /// [run] says which: the newest run with an admission of theirs when
  /// null (none: no admissions, no days, run null).
  Future<Map<String, Object?>> personHistory(String personId, {String? run}) => _run((c) async {
    var chosen = run;
    if (chosen == null) {
      final newest = await c.execute(
        Sql.named(
          "SELECT split_part(event_id, '-', 1) FROM admissions WHERE person_id = @id ORDER BY id DESC LIMIT 1",
        ),
        parameters: {'id': personId},
      );
      if (newest.isEmpty) return {'run': null, 'admissions': const [], 'days': const []};
      chosen = newest.first[0] as String;
    }
    final admissions = await c.execute(
      Sql.named('''
        SELECT a.event_id, a.person_name, a.age, a.sex, a.occupation, a.city, a.condition_code,
               a.condition_name, a.condition_type, a.visit, a.visit_number, a.complaint,
               a.hospital_id, a.hospital_name, a.sim_day, a.sim_time, a.recorded_at,
               t.level, t.wait_minutes, t.area, t.nurse_check, t.reference, t.error, t.event_id IS NOT NULL
        FROM admissions a LEFT JOIN admission_triage t USING (event_id)
        WHERE a.person_id = @id AND split_part(a.event_id, '-', 1) = @run
        ORDER BY a.id DESC LIMIT @limit
      '''),
      parameters: {'id': personId, 'run': chosen, 'limit': personLimit},
    );
    final days = await c.execute(
      Sql.named('''
        SELECT day, visits, acute_visits, chronic_visits, stay_hours, chronic_condition
        FROM patient_days WHERE run_id = @run AND person_id = @id
        ORDER BY day DESC LIMIT @limit
      '''),
      parameters: {'id': personId, 'run': chosen, 'limit': personLimit},
    );
    return {
      'run': chosen,
      'admissions': [
        for (final row in admissions)
          {
            'eventId': row[0],
            'name': row[1],
            'age': row[2],
            'sex': row[3],
            'occupation': row[4],
            'city': row[5],
            'conditionCode': row[6],
            'conditionName': row[7],
            'conditionType': row[8],
            'visit': row[9],
            'visitNumber': row[10],
            'complaint': row[11],
            'hospitalId': row[12],
            'hospitalName': row[13],
            'day': row[14],
            'simTime': row[15],
            'recordedAt': (row[16] as DateTime).toUtc().toIso8601String(),
            'triage': row[23] == true
                ? {
                    'level': row[17],
                    'waitMinutes': row[18],
                    'area': row[19],
                    'nurseCheck': row[20],
                    'reference': row[21],
                    'error': row[22],
                  }
                : null,
          },
      ],
      'days': [
        for (final row in days)
          {
            'day': (row[0] as DateTime).toIso8601String().substring(0, 10),
            'visits': row[1],
            'acuteVisits': row[2],
            'chronicVisits': row[3],
            'stayHours': row[4],
            'chronicCondition': row[5],
          },
      ],
    };
  });

  /// How many of a care center's latest admissions [careCenterHistory]
  /// answers.
  static const careCenterLimit = 30;

  /// One care center as the database has it: its row (null when there is
  /// none), and its admissions: how many in [run] (the current run; none
  /// without one) and in all runs, acute and chronic, and the latest
  /// [careCenterLimit], newest first, each with its triage when it has
  /// one: of [run] when it has any there, else of any run.
  Future<Map<String, Object?>> careCenterHistory(int id, {String? run}) => _run((c) async {
    final centers = await c.execute(
      Sql.named('''
        SELECT id, key, name, kind, subtype, address, postal_code, city, region, country,
               latitude, longitude, phone, website, ownership, source
        FROM care_centers WHERE id = @id
      '''),
      parameters: {'id': id},
    );
    if (centers.isEmpty) return {'center': null};
    final row = centers.first;
    final counts = await c.execute(
      Sql.named('''
        SELECT count(*),
               count(*) FILTER (WHERE condition_type = 'acute'),
               count(*) FILTER (WHERE condition_type = 'chronic'),
               count(*) FILTER (WHERE split_part(event_id, '-', 1) = @run),
               count(*) FILTER (WHERE split_part(event_id, '-', 1) = @run AND condition_type = 'acute'),
               count(*) FILTER (WHERE split_part(event_id, '-', 1) = @run AND condition_type = 'chronic')
        FROM admissions WHERE hospital_id = @id
      '''),
      parameters: {'id': id, 'run': run ?? ''},
    );
    final [total, acute, chronic, thisRun, runAcute, runChronic] = [
      for (final value in counts.first) (value as int?) ?? 0,
    ];
    final onlyRun = thisRun > 0;
    final latest = await c.execute(
      Sql.named('''
        SELECT a.event_id, a.person_id, a.person_name, a.age, a.sex, a.city, a.condition_name,
               a.condition_type, a.visit, a.visit_number, a.complaint, a.sim_day, a.sim_time,
               t.level, t.wait_minutes, t.area, t.nurse_check, t.error, t.event_id IS NOT NULL
        FROM admissions a LEFT JOIN admission_triage t USING (event_id)
        WHERE a.hospital_id = @id AND (@onlyRun = false OR split_part(a.event_id, '-', 1) = @run)
        ORDER BY a.id DESC LIMIT @limit
      '''),
      parameters: {'id': id, 'run': run ?? '', 'onlyRun': onlyRun, 'limit': careCenterLimit},
    );
    return {
      'center': {
        'id': row[0],
        'key': row[1],
        'name': row[2],
        'kind': row[3],
        'subtype': row[4],
        'address': row[5],
        'postalCode': row[6],
        'city': row[7],
        'region': row[8],
        'country': (row[9] as String).trim(),
        'lat': row[10],
        'lon': row[11],
        'phone': row[12],
        'website': row[13],
        'ownership': row[14],
        'source': row[15],
      },
      'admissions': {
        'run': run,
        'thisRun': thisRun,
        'thisRunAcute': runAcute,
        'thisRunChronic': runChronic,
        'total': total,
        'acute': acute,
        'chronic': chronic,
        'latestOf': onlyRun ? 'run' : 'all',
        'latest': [
          for (final a in latest)
            {
              'eventId': a[0],
              'personId': a[1],
              'name': a[2],
              'age': a[3],
              'sex': a[4],
              'city': a[5],
              'conditionName': a[6],
              'conditionType': a[7],
              'visit': a[8],
              'visitNumber': a[9],
              'complaint': a[10],
              'day': a[11],
              'simTime': a[12],
              'triage': a[18] == true
                  ? {'level': a[13], 'waitMinutes': a[14], 'area': a[15], 'nurseCheck': a[16], 'error': a[17]}
                  : null,
            },
        ],
      },
    };
  });

  /// The latest [limit] admissions recorded, newest first: what GET
  /// /api/admissions answers.
  Future<List<Map<String, Object?>>> latestAdmissions({required int limit}) => _run((c) async {
    final rows = await c.execute(
      Sql.named('''
        SELECT id, event_id, person_id, person_name, age, sex, occupation, city,
               condition_code, condition_name, condition_type, visit, visit_number, complaint,
               hospital_id, hospital_name, sim_day, sim_time, recorded_at
        FROM admissions ORDER BY id DESC LIMIT @limit
      '''),
      parameters: {'limit': limit},
    );
    return [
      for (final row in rows)
        {
          'id': row[0],
          for (final (index, field) in _admissionFields.indexed) field: row[index + 1],
          'recordedAt': (row[18] as DateTime).toUtc().toIso8601String(),
        },
    ];
  });

  /// Makes care_centers hold exactly [centers], in one transaction: each
  /// inserted or updated by its key, in batches, and the rows of keys no
  /// longer in the seed deleted.
  static Future<void> seedCareCenters(
    Connection connection,
    List<CareCenter> centers, {
    int batch = 500,
  }) => connection.runTx((tx) async {
    const columns = CareCenter.columns;
    final updates = [
      for (final column in columns.skip(1)) '$column = EXCLUDED.$column',
      'updated_at = now()',
    ].join(', ');
    for (var start = 0; start < centers.length; start += batch) {
      final rows = centers.skip(start).take(batch).toList();
      final placeholders = [
        for (var r = 0; r < rows.length; r++)
          '(${[for (var i = 1; i <= columns.length; i++) '\$${r * columns.length + i}'].join(', ')})',
      ].join(', ');
      await tx.execute(
        'INSERT INTO care_centers (${columns.join(', ')}) VALUES $placeholders '
        'ON CONFLICT (key) DO UPDATE SET $updates',
        parameters: [for (final row in rows) ...row.values],
      );
    }
    await tx.execute(
      Sql.named('DELETE FROM care_centers WHERE NOT (key = ANY(@keys))'),
      parameters: {
        'keys': TypedValue(Type.textArray, [for (final c in centers) c.key]),
      },
    );
  });

  /// Whether the database answers a trivial query.
  Future<bool> ping() async {
    try {
      await _run((c) => c.execute('SELECT 1'));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The first greeting, with the server's version: what GET /api/hello
  /// answers. Throws when the database doesn't answer.
  Future<Map<String, Object?>> greeting() => _run((c) async {
    final rows = await c.execute(
      'SELECT g.message, g.created_at, version() '
      'FROM greetings g ORDER BY g.id LIMIT 1',
    );
    if (rows.isEmpty) throw StateError('no greeting in the database');
    final row = rows.first;
    return {
      'message': row[0] as String,
      'since': (row[1] as DateTime).toUtc().toIso8601String(),
      'postgres': row[2] as String,
    };
  });

  /// The care centers with a location inside [box] (anywhere without
  /// one), hospitals first, then health stations, then clinics, by name,
  /// at most [limit]: what GET /api/care-centers answers.
  Future<List<Map<String, Object?>>> careCenters(Bbox? box, {required int limit}) => _run((c) async {
    final rows = await c.execute(
      Sql.named('''
        SELECT id, name, kind, subtype, address, city, country, latitude, longitude,
               phone, website, ownership
        FROM care_centers
        WHERE latitude IS NOT NULL AND longitude IS NOT NULL
          AND (@inBox = false OR (latitude BETWEEN @south AND @north
                                  AND longitude BETWEEN @west AND @east))
        ORDER BY CASE kind WHEN 'hospital' THEN 0 WHEN 'health_station' THEN 1 ELSE 2 END, name, id
        LIMIT @limit
      '''),
      parameters: {
        'inBox': box != null,
        'south': TypedValue(Type.double, box?.south ?? 0),
        'north': TypedValue(Type.double, box?.north ?? 0),
        'west': TypedValue(Type.double, box?.west ?? 0),
        'east': TypedValue(Type.double, box?.east ?? 0),
        'limit': limit,
      },
    );
    return [for (final row in rows) _careCenter(row)];
  });

  /// The care center nearest [lat], [lon], of any kind, with its
  /// great-circle `distance` in metres; null when none has a location:
  /// what GET /api/care-centers/nearest answers.
  Future<Map<String, Object?>?> nearestCareCenter(double lat, double lon) => _run((c) async {
    final rows = await c.execute(
      Sql.named('''
        SELECT id, name, kind, subtype, address, city, country, latitude, longitude,
               phone, website, ownership,
               2 * 6371008.8 * asin(least(1, sqrt(
                 power(sin(radians(latitude - @lat) / 2), 2)
                 + cos(radians(@lat)) * cos(radians(latitude)) * power(sin(radians(longitude - @lon) / 2), 2)
               ))) AS distance
        FROM care_centers
        WHERE latitude IS NOT NULL AND longitude IS NOT NULL
        ORDER BY distance, id
        LIMIT 1
      '''),
      parameters: {'lat': TypedValue(Type.double, lat), 'lon': TypedValue(Type.double, lon)},
    );
    if (rows.isEmpty) return null;
    return {..._careCenter(rows.first), 'distance': (rows.first[12] as double).round()};
  });

  /// A care center as the API answers it, from a row of the columns
  /// [careCenters] selects, in its order.
  static Map<String, Object?> _careCenter(ResultRow row) => {
    'id': row[0],
    'name': row[1],
    'kind': row[2],
    'subtype': row[3],
    'address': row[4],
    'city': row[5],
    'country': (row[6] as String).trim(),
    'lat': row[7],
    'lon': row[8],
    'phone': row[9],
    'website': row[10],
    'ownership': row[11],
  };

  /// Every care center with a location, as the simulation places homes
  /// near them and sends people to the hospitals among them.
  Future<List<Place>> places() => _run((c) async {
    final rows = await c.execute(
      'SELECT id, name, kind, city, latitude, longitude, subtype FROM care_centers '
      'WHERE latitude IS NOT NULL AND longitude IS NOT NULL ORDER BY id',
    );
    return [
      for (final row in rows)
        Place(
          id: row[0] as int,
          name: row[1] as String,
          kind: row[2] as String,
          city: row[3] as String,
          at: LatLon(row[4] as double, row[5] as double),
          subtype: row[6] as String?,
        ),
    ];
  });

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
