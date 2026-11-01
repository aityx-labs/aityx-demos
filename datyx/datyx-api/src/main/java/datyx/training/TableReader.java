package datyx.training;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

import datyx.catalog.SchemaReader;
import datyx.catalog.TimeSeries;
import datyx.datasource.DataSource.DatabaseAccess;

/**
 * Reads a group's columns from the source's table, signed in as the
 * source's user, read-only and streamed: the Timestamp, the Target, the
 * SeriesKey, the static columns and the covariates, nothing else. The
 * names come from the catalogue and go into the query quoted, as
 * identifiers; no value does. A table of more than {@link #MAX_ROWS} rows
 * is refused.
 */
final class TableReader {

    static final int MAX_ROWS = 5_000_000;

    private TableReader() {
    }

    /** The query that reads the group's columns, in the order {@link #read} takes them. */
    static String query(TimeSeries.Spec spec) {
        List<String> columns = new ArrayList<>();
        columns.add(spec.timestamp());
        columns.add(spec.target());
        columns.addAll(spec.seriesKey());
        columns.addAll(spec.staticCategorical());
        columns.addAll(spec.staticReal());
        columns.addAll(spec.pastCovariates());
        columns.addAll(spec.knownCovariates());
        return "SELECT " + String.join(", ", columns.stream().map(TableReader::quote).toList()) + " FROM "
            + quote(spec.schema()) + "." + quote(spec.name());
    }

    static String quote(String identifier) {
        return "\"" + identifier.replace("\"", "\"\"") + "\"";
    }

    /** Adds every row of the group's table to {@code builder}; an IllegalArgumentException when there are too many. */
    static void read(DatabaseAccess access, TimeSeries.Spec spec, Dataset.Builder builder) throws SQLException {
        Properties props = new Properties();
        if (access.username() != null) {
            props.setProperty("user", access.username());
        }
        if (access.password() != null) {
            props.setProperty("password", access.password());
        }
        props.setProperty("connectTimeout", "5");
        props.setProperty("socketTimeout", "600");
        props.setProperty("readOnly", "true");
        props.setProperty("ApplicationName", "datyx training");
        try (Connection c = DriverManager.getConnection(SchemaReader.jdbcUrl(access), props)) {
            read(c, spec, builder);
        }
    }

    /** Reads the group's table on an open connection, streamed in a transaction it rolls back. */
    static void read(Connection c, TimeSeries.Spec spec, Dataset.Builder builder) throws SQLException {
        boolean autoCommit = c.getAutoCommit();
        c.setAutoCommit(false);
        try (Statement s = c.createStatement()) {
            s.setFetchSize(10_000);
            s.setQueryTimeout(600);
            try (ResultSet rs = s.executeQuery(query(spec))) {
                read(rs, spec, builder);
            }
        } finally {
            c.rollback();
            c.setAutoCommit(autoCommit);
        }
    }

    static void read(ResultSet rs, TimeSeries.Spec spec, Dataset.Builder builder) throws SQLException {
        int timeType = rs.getMetaData().getColumnType(1);
        int keys = spec.seriesKey().size();
        int cats = spec.staticCategorical().size();
        int reals = spec.staticReal().size();
        int past = spec.pastCovariates().size();
        int known = spec.knownCovariates().size();
        while (rs.next()) {
            if (builder.rows() >= MAX_ROWS) {
                throw new IllegalArgumentException("the table has over " + MAX_ROWS + " rows: too many to train on in the API");
            }
            Long at = epochSecond(rs, timeType);
            if (at == null) {
                continue;
            }
            int col = 2;
            double target = number(rs, col);
            List<String> key = new ArrayList<>(keys);
            for (int i = 0; i < keys; i++) {
                key.add(rs.getString(++col));
            }
            String[] categories = new String[cats];
            for (int i = 0; i < cats; i++) {
                categories[i] = rs.getString(++col);
            }
            double[] r = new double[reals];
            for (int i = 0; i < reals; i++) {
                r[i] = number(rs, ++col);
            }
            double[] p = new double[past];
            for (int i = 0; i < past; i++) {
                p[i] = number(rs, ++col);
            }
            double[] k = new double[known];
            for (int i = 0; i < known; i++) {
                k[i] = number(rs, ++col);
            }
            builder.add(new Dataset.Row(at, List.copyOf(key), categories, r, target, p, k));
        }
    }

    /** A date as its midnight, a timestamp without a zone as UTC, one with a zone as its instant; null for null. */
    private static Long epochSecond(ResultSet rs, int type) throws SQLException {
        return switch (type) {
            case Types.DATE -> {
                LocalDate d = rs.getObject(1, LocalDate.class);
                yield d == null ? null : d.atStartOfDay().toEpochSecond(ZoneOffset.UTC);
            }
            case Types.TIMESTAMP_WITH_TIMEZONE -> {
                OffsetDateTime t = rs.getObject(1, OffsetDateTime.class);
                yield t == null ? null : t.toEpochSecond();
            }
            default -> {
                LocalDateTime t = rs.getObject(1, LocalDateTime.class);
                yield t == null ? null : t.toEpochSecond(ZoneOffset.UTC);
            }
        };
    }

    private static double number(ResultSet rs, int col) throws SQLException {
        double v = rs.getDouble(col);
        return rs.wasNull() ? Double.NaN : v;
    }
}
