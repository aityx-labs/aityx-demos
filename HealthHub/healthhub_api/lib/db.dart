/// The API's database: PostgreSQL, the postgres service of compose.yaml.
/// One connection, opened when first needed and reopened after a failure,
/// so the API starts (and answers /api/health) whether or not the database
/// is up yet. The schema is the API's own: it makes its tables at start.
library;

import 'dart:io';

import 'package:postgres/postgres.dart';

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

  /// The open connection, opened now if there is none.
  Future<Connection> _open() async {
    final existing = _connection;
    if (existing != null && existing.isOpen) return existing;
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

  /// Runs [action] on the connection; on a failure the connection is
  /// dropped, so the next call opens a new one, and the error is rethrown.
  Future<T> _run<T>(Future<T> Function(Connection) action) async {
    try {
      return await action(await _open());
    } catch (_) {
      final broken = _connection;
      _connection = null;
      if (broken != null) {
        try {
          await broken.close();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Makes the tables when they're missing, and the greeting when it is.
  /// Retried by the caller: at start the database may not be up yet.
  Future<void> migrate() => _run((c) async {
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

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
  }
}
