import 'package:healthhub_api/db.dart';
import 'package:healthhub_api/schema_comments.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  test('quotes a comment as an SQL literal', () {
    expect(sqlLiteral('plain'), "'plain'");
    expect(sqlLiteral("the greeting's id"), "'the greeting''s id'");
    expect(sqlLiteral(r'a \n stays'), r"'a \n stays'");
  });

  test('comments a table, then each of its columns', () {
    final statements = commentStatements({
      't': (table: "a table's", columns: {'a': 'first', 'b': 'second'}),
    });
    expect(statements, [
      "COMMENT ON TABLE t IS 'a table''s'",
      "COMMENT ON COLUMN t.a IS 'first'",
      "COMMENT ON COLUMN t.b IS 'second'",
    ]);
  });

  test('every table and column has a description', () {
    for (final MapEntry(key: table, value: c) in schemaComments.entries) {
      expect(c.table.trim(), isNotEmpty, reason: table);
      expect(c.columns, isNotEmpty, reason: table);
      for (final MapEntry(key: column, value: text) in c.columns.entries) {
        expect(text.trim(), isNotEmpty, reason: '$table.$column');
        expect(text, isNot(contains('—')), reason: '$table.$column: no em dashes');
      }
    }
  });

  /// Against the real database (the postgres service of compose.yaml, at
  /// HEALTHHUB_DB_* or 127.0.0.1:9803), when it is up; skipped otherwise,
  /// so the suite passes without Docker.
  test('after the migration, every column of the schema has its comment', () async {
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
    // Every table and view of the schema is described: one added without
    // an entry in schemaComments fails here.
    final relations = await c.execute(
      "SELECT relname FROM pg_class WHERE relnamespace = 'public'::regnamespace AND relkind IN ('r', 'v', 'm', 'p')",
    );
    expect({for (final r in relations) r[0] as String}, schemaComments.keys.toSet());
    for (final MapEntry(key: table, value: comments) in schemaComments.entries) {
      final rows = await c.execute(
        Sql.named('''
          SELECT a.attname, col_description(a.attrelid, a.attnum), obj_description(a.attrelid, 'pg_class')
          FROM pg_attribute a
          WHERE a.attrelid = to_regclass(@table) AND a.attnum > 0 AND NOT a.attisdropped
          ORDER BY a.attnum
        '''),
        parameters: {'table': 'public.$table'},
      );
      expect(rows, isNotEmpty, reason: '$table exists');
      expect(rows.first[2], comments.table, reason: table);
      // The schema's columns are exactly the described ones: a column added
      // to the table without a description fails here.
      expect({for (final r in rows) r[0] as String}, comments.columns.keys.toSet(), reason: table);
      for (final r in rows) {
        expect(r[1], comments.columns[r[0]], reason: '$table.${r[0]}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
