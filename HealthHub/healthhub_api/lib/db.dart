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
        course_gap_days INT
      )
    ''');
    // Added after the table was first made: a database from before has it
    // without them.
    for (final column in [
      'female_share DOUBLE PRECISION NOT NULL DEFAULT 0.5',
      'urgent BOOLEAN NOT NULL DEFAULT false',
      'follow_up_stay_hours INT',
      'course_gap_days INT',
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
        UNIQUE (condition_code, visit, position)
      )
    ''');
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
        hospital_id INT NOT NULL,
        hospital_name TEXT NOT NULL,
        sim_day INT NOT NULL,
        sim_time TEXT NOT NULL,
        recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    ''');
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
                  'INSERT INTO complaint_templates (condition_code, visit, position, text) '
                  'VALUES (@code, @visit, @position, @text) '
                  'ON CONFLICT (condition_code, visit, position) DO UPDATE SET text = EXCLUDED.text',
                ),
                parameters: {'code': condition.code, 'visit': kind.json, 'position': position, 'text': text},
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
          condition_code, condition_name, condition_type, visit, visit_number, complaint,
          hospital_id, hospital_name, sim_day, sim_time)
        VALUES (@eventId, @personId, @name, @age, @sex, @occupation, @city,
          @conditionCode, @conditionName, @conditionType, @visit, @visitNumber, @complaint,
          @hospitalId, @hospitalName, @day, @simTime)
        ON CONFLICT (event_id) DO NOTHING
        RETURNING id
      '''),
      parameters: {for (final field in _admissionFields) field: admission[field]},
    );
    return rows.isNotEmpty;
  });

  static const _admissionFields = [
    'eventId', 'personId', 'name', 'age', 'sex', 'occupation', 'city', 'conditionCode',
    'conditionName', 'conditionType', 'visit', 'visitNumber', 'complaint', 'hospitalId',
    'hospitalName', 'day', 'simTime',
  ];

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
    return [
      for (final row in rows)
        {
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
        },
    ];
  });

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
