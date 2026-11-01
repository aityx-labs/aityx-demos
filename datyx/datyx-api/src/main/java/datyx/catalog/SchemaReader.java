package datyx.catalog;

import java.sql.Connection;
import java.sql.DatabaseMetaData;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Set;
import java.util.TreeMap;

import datyx.datasource.DataSource.DatabaseAccess;

/**
 * What a database source holds, read through JDBC's DatabaseMetaData:
 * every table and view outside the system schemas, its columns in order
 * and its primary key. Only what the database says about itself, and no
 * rows: datyx learns a source's model without the source doing anything
 * for it. PostgreSQL only so far, the one driver the API carries.
 */
public final class SchemaReader {

    /** Schemas that are the database's own, never the source's data. */
    static final Set<String> SYSTEM_SCHEMAS = Set.of("information_schema", "pg_catalog", "pg_toast");

    private static final String[] TABLE_TYPES = {"TABLE", "VIEW", "MATERIALIZED VIEW", "PARTITIONED TABLE"};

    private SchemaReader() {
    }

    public record Column(String name, int jdbcType, String typeName, int size, int scale, boolean nullable,
            String comment, int position) {
    }

    /** A table or view: its type as JDBC names it (TABLE, VIEW, ...), its columns in order, its primary key's columns. */
    public record Table(String schema, String name, String type, String comment, List<Column> columns,
            List<String> primaryKey) {
    }

    /** The JDBC URL of a database source, for the engines datyx can read; an IllegalArgumentException for the others. */
    public static String jdbcUrl(DatabaseAccess access) {
        if (!"postgresql".equals(access.engine())) {
            throw new IllegalArgumentException("datyx reads only PostgreSQL databases so far, not " + access.engine());
        }
        // Host and database go in the URL: a host with a slash or a database
        // with a '?' would change what it means.
        if (access.host().matches(".*[/?#@\\s].*") || access.database().matches(".*[/?#\\s].*")) {
            throw new IllegalArgumentException("the source's host or database name isn't one a JDBC URL can carry");
        }
        return "jdbc:postgresql://" + access.host() + ":" + access.port() + "/" + access.database();
    }

    /** Reads the source's tables, signed in as its user, within a few seconds' timeouts. */
    public static List<Table> read(DatabaseAccess access) throws SQLException {
        try (Connection c = connect(access)) {
            return read(c);
        }
    }

    /** A read-only connection to the source, signed in as its user: 5 s to connect, 60 s a read. */
    public static Connection connect(DatabaseAccess access) throws SQLException {
        Properties props = new Properties();
        if (access.username() != null) {
            props.setProperty("user", access.username());
        }
        if (access.password() != null) {
            props.setProperty("password", access.password());
        }
        props.setProperty("connectTimeout", "5");
        props.setProperty("socketTimeout", "60");
        props.setProperty("readOnly", "true");
        props.setProperty("ApplicationName", "datyx catalogue");
        return DriverManager.getConnection(jdbcUrl(access), props);
    }

    /** Reads the tables of an open connection: what {@link #read(DatabaseAccess)} does once connected. */
    public static List<Table> read(Connection c) throws SQLException {
        DatabaseMetaData meta = c.getMetaData();
        Map<String, Table> tables = new TreeMap<>();
        try (ResultSet r = meta.getTables(c.getCatalog(), null, "%", TABLE_TYPES)) {
            while (r.next()) {
                String schema = r.getString("TABLE_SCHEM");
                if (schema == null || SYSTEM_SCHEMAS.contains(schema) || schema.startsWith("pg_temp")
                        || schema.startsWith("pg_toast")) {
                    continue;
                }
                String name = r.getString("TABLE_NAME");
                tables.put(schema + "." + name, new Table(schema, name, r.getString("TABLE_TYPE"),
                    r.getString("REMARKS"), new ArrayList<>(), new ArrayList<>()));
            }
        }
        for (Table table : tables.values()) {
            try (ResultSet r = meta.getColumns(c.getCatalog(), table.schema(), table.name(), "%")) {
                while (r.next()) {
                    table.columns().add(new Column(r.getString("COLUMN_NAME"), r.getInt("DATA_TYPE"),
                        r.getString("TYPE_NAME"), r.getInt("COLUMN_SIZE"), r.getInt("DECIMAL_DIGITS"),
                        r.getInt("NULLABLE") != DatabaseMetaData.columnNoNulls, r.getString("REMARKS"),
                        r.getInt("ORDINAL_POSITION")));
                }
            }
            Map<Integer, String> key = new TreeMap<>();
            try (ResultSet r = meta.getPrimaryKeys(c.getCatalog(), table.schema(), table.name())) {
                while (r.next()) {
                    key.put(r.getInt("KEY_SEQ"), r.getString("COLUMN_NAME"));
                }
            }
            table.primaryKey().addAll(key.values());
        }
        return List.copyOf(tables.values());
    }
}
