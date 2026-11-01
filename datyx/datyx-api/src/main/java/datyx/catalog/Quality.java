package datyx.catalog;

import java.sql.Array;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.quarkus.runtime.annotations.RegisterForReflection;

/**
 * How good a database source's data is, in OpenMetadata's terms: a
 * table's profile (its rows, and each column's nulls, distinct values,
 * range and lengths) and data quality checks with their results, each
 * one of OpenMetadata's test definitions. datyx reads them from the
 * source with SQL aggregates, counts and bounds and never a row's values,
 * and OpenMetadata keeps them: it runs no ingestion and has no
 * credentials here. The schema gives every table its checks (a NOT NULL
 * column has no nulls, a primary key no duplicates); people add others
 * (a range, a set of values, a row count, a pattern). PostgreSQL's SQL.
 */
public final class Quality {

    /** The test definitions datyx can run, OpenMetadata's names. */
    public static final Set<String> TESTS = Set.of("columnValuesToBeNotNull", "columnValuesToBeUnique",
        "columnValuesToBeBetween", "columnValuesToBeInSet", "columnValuesToMatchRegex", "tableRowCountToBeBetween",
        "tableCustomSQLQuery");

    /** OpenMetadata types with an order and a mean. */
    private static final Set<String> NUMERIC = ColumnTypes.NUMERIC;

    /** OpenMetadata types with a length. */
    private static final Set<String> TEXTUAL = Set.of("TEXT", "VARCHAR", "CHAR", "STRING");

    /** OpenMetadata types PostgreSQL can't count the distinct values of (json has no equality), or that mean nothing counted. */
    private static final Set<String> UNCOUNTABLE = Set.of("JSON", "BYTEA", "XML", "ARRAY", "UNKNOWN");

    private Quality() {
    }

    /**
     * A check on a table, or on one of its columns: an OpenMetadata test
     * definition and its parameters (minValue and maxValue, allowedValues,
     * regex, sqlExpression), with what it means in words.
     */
    @RegisterForReflection
    public record Check(String test, String column, Map<String, Object> parameters, String description) {

        public Check {
            if (!TESTS.contains(test)) {
                throw new IllegalArgumentException("datyx can't run the test " + test + ": only " + TESTS);
            }
            if (test.startsWith("column") && (column == null || column.isBlank())) {
                throw new IllegalArgumentException(test + " needs a column");
            }
            parameters = parameters == null ? Map.of() : Map.copyOf(parameters);
        }

        /** The test case's name, unique within its table: the column, if any, and the test. */
        public String name() {
            return column == null ? test : column + "_" + test;
        }
    }

    /** A check's outcome: passed or not, in words, the values OpenMetadata shows, and the rows that passed and failed. */
    @RegisterForReflection
    public record Result(Check check, boolean passed, String result, Map<String, String> values, Long passedRows,
            Long failedRows) {
    }

    /** A column's profile; null where it doesn't apply (no range for text, no length for numbers). */
    public record ColumnProfile(String name, long values, long nulls, Long distinct, Double min, Double max,
            Double mean, Double sum, Double stddev, Integer minLength, Integer maxLength) {
    }

    public record Profile(long rows, int columnCount, List<ColumnProfile> columns) {
    }

    /** What a table's schema says must hold: no nulls where NOT NULL, no duplicates of the primary key. */
    public static List<Check> fromSchema(SchemaReader.Table table) {
        List<Check> checks = new ArrayList<>();
        for (SchemaReader.Column column : table.columns()) {
            if (!column.nullable() || table.primaryKey().contains(column.name())) {
                checks.add(new Check("columnValuesToBeNotNull", column.name(), Map.of(),
                    "Every row has a " + column.name() + ": the column is NOT NULL in the source."));
            }
        }
        if (table.primaryKey().size() == 1) {
            String key = table.primaryKey().get(0);
            checks.add(new Check("columnValuesToBeUnique", key, Map.of(),
                "No two rows have the same " + key + ", the table's primary key."));
        } else if (table.primaryKey().size() > 1) {
            String key = table.primaryKey().stream().map(Quality::quote).collect(Collectors.joining(", "));
            checks.add(new Check("tableCustomSQLQuery", null, Map.of(
                "sqlExpression", "SELECT " + key + " FROM " + quote(table.schema()) + "." + quote(table.name())
                    + " GROUP BY " + key + " HAVING count(*) > 1",
                "strategy", "ROWS", "operator", "==", "threshold", "0"),
                "No two rows have the same " + String.join(", ", table.primaryKey()) + ", the table's primary key."));
        }
        return checks;
    }

    /** An identifier as PostgreSQL quotes it. */
    static String quote(String identifier) {
        return "\"" + identifier.replace("\"", "\"\"") + "\"";
    }

    private static String relation(SchemaReader.Table table) {
        return quote(table.schema()) + "." + quote(table.name());
    }

    /** The one query that profiles a table: its row count, then per column the aggregates its type has. */
    static String profileSql(SchemaReader.Table table) {
        StringBuilder sql = new StringBuilder("SELECT count(*)");
        for (SchemaReader.Column column : table.columns()) {
            String type = ColumnTypes.of(column.jdbcType(), column.typeName());
            String c = quote(column.name());
            sql.append(", count(").append(c).append(")");
            if (!UNCOUNTABLE.contains(type)) {
                sql.append(", count(DISTINCT ").append(c).append(")");
            }
            if (NUMERIC.contains(type)) {
                sql.append(", min(").append(c).append(")::float8, max(").append(c).append(")::float8, avg(")
                    .append(c).append(")::float8, sum(").append(c).append(")::float8, stddev_pop(").append(c)
                    .append(")::float8");
            }
            if (TEXTUAL.contains(type)) {
                sql.append(", min(length(").append(c).append(")), max(length(").append(c).append("))");
            }
        }
        return sql.append(" FROM ").append(relation(table)).toString();
    }

    /** Profiles a table, in one query. */
    public static Profile profile(Connection c, SchemaReader.Table table) throws SQLException {
        try (PreparedStatement s = c.prepareStatement(profileSql(table))) {
            s.setQueryTimeout(60);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long rows = r.getLong(1);
                int i = 2;
                List<ColumnProfile> columns = new ArrayList<>();
                for (SchemaReader.Column column : table.columns()) {
                    String type = ColumnTypes.of(column.jdbcType(), column.typeName());
                    long values = r.getLong(i++);
                    Long distinct = UNCOUNTABLE.contains(type) ? null : r.getLong(i++);
                    Double min = null;
                    Double max = null;
                    Double mean = null;
                    Double sum = null;
                    Double stddev = null;
                    if (NUMERIC.contains(type)) {
                        min = number(r, i++);
                        max = number(r, i++);
                        mean = number(r, i++);
                        sum = number(r, i++);
                        stddev = number(r, i++);
                    }
                    Integer minLength = null;
                    Integer maxLength = null;
                    if (TEXTUAL.contains(type)) {
                        minLength = (Integer) r.getObject(i++);
                        maxLength = (Integer) r.getObject(i++);
                    }
                    columns.add(new ColumnProfile(column.name(), values, rows - values, distinct, min, max, mean, sum,
                        stddev, minLength, maxLength));
                }
                return new Profile(rows, table.columns().size(), columns);
            }
        }
    }

    private static Double number(ResultSet r, int i) throws SQLException {
        double value = r.getDouble(i);
        return r.wasNull() ? null : value;
    }

    /** The column a check is on, as the table has it; an IllegalArgumentException when it has none of the name. */
    private static SchemaReader.Column column(SchemaReader.Table table, Check check) {
        return table.columns().stream().filter(c -> c.name().equals(check.column())).findFirst()
            .orElseThrow(() -> new IllegalArgumentException(table.name() + " has no column " + check.column()));
    }

    /** A parameter or a bound in words: a whole double without its ".0". */
    private static String text(Object value) {
        if (value instanceof Double d && !d.isInfinite() && d == Math.rint(d)) {
            return Long.toString(d.longValue());
        }
        return value == null ? null : value.toString();
    }

    private static String count(long n, String one, String many) {
        return n + " " + (n == 1 ? one : many);
    }

    /** Runs a check on the source: one query, counting the rows that break it. */
    public static Result evaluate(Connection c, SchemaReader.Table table, Check check) throws SQLException {
        String from = " FROM " + relation(table);
        switch (check.test()) {
            case "columnValuesToBeNotNull" -> {
                String col = quote(column(table, check).name());
                long[] r = longs(c, "SELECT count(*), count(*) FILTER (WHERE " + col + " IS NULL)" + from);
                return new Result(check, r[1] == 0, count(r[1], "null", "nulls") + " in " + count(r[0], "row", "rows"),
                    Map.of("nullCount", Long.toString(r[1])), r[0] - r[1], r[1]);
            }
            case "columnValuesToBeUnique" -> {
                String col = quote(column(table, check).name());
                long[] r = longs(c, "SELECT count(" + col + "), count(DISTINCT " + col + ")" + from);
                long duplicates = r[0] - r[1];
                return new Result(check, duplicates == 0, count(r[1], "distinct value", "distinct values") + " in "
                    + count(r[0], "value", "values"), Map.of("valuesCount", Long.toString(r[0]), "uniqueCount",
                    Long.toString(r[1])), r[1], duplicates);
            }
            case "columnValuesToBeBetween" -> {
                String col = quote(column(table, check).name());
                Object min = check.parameters().get("minValue");
                Object max = check.parameters().get("maxValue");
                List<String> outside = new ArrayList<>();
                if (min != null) {
                    outside.add(col + " < ?");
                }
                if (max != null) {
                    outside.add(col + " > ?");
                }
                if (outside.isEmpty()) {
                    throw new IllegalArgumentException(check.name() + " needs a minValue or a maxValue");
                }
                String sql = "SELECT count(" + col + "), count(*) FILTER (WHERE " + String.join(" OR ", outside)
                    + "), min(" + col + ")::float8, max(" + col + ")::float8" + from;
                try (PreparedStatement s = c.prepareStatement(sql)) {
                    s.setQueryTimeout(60);
                    int p = 1;
                    if (min != null) {
                        s.setDouble(p++, ((Number) min).doubleValue());
                    }
                    if (max != null) {
                        s.setDouble(p, ((Number) max).doubleValue());
                    }
                    try (ResultSet r = s.executeQuery()) {
                        r.next();
                        long values = r.getLong(1);
                        long out = r.getLong(2);
                        Map<String, String> found = new LinkedHashMap<>();
                        found.put("minValue", text(number(r, 3)));
                        found.put("maxValue", text(number(r, 4)));
                        found.values().removeIf(v -> v == null);
                        return new Result(check, out == 0, count(out, "value", "values") + " of " + values
                            + " outside " + (min == null ? "" : text(min)) + ".." + (max == null ? "" : text(max)),
                            found, values - out, out);
                    }
                }
            }
            case "columnValuesToBeInSet" -> {
                String col = quote(column(table, check).name());
                List<String> allowed = strings(check.parameters().get("allowedValues"));
                try (PreparedStatement s = c.prepareStatement("SELECT count(" + col + "), count(*) FILTER (WHERE "
                        + col + " IS NOT NULL AND " + col + "::text <> ALL (?))" + from)) {
                    s.setQueryTimeout(60);
                    Array array = c.createArrayOf("text", allowed.toArray());
                    s.setArray(1, array);
                    try (ResultSet r = s.executeQuery()) {
                        r.next();
                        long values = r.getLong(1);
                        long out = r.getLong(2);
                        return new Result(check, out == 0, count(out, "value", "values") + " of " + values
                            + " not in " + allowed, Map.of("allowedValueCount", Long.toString(values - out)),
                            values - out, out);
                    }
                }
            }
            case "columnValuesToMatchRegex" -> {
                String col = quote(column(table, check).name());
                Object regex = check.parameters().get("regex");
                if (regex == null) {
                    throw new IllegalArgumentException(check.name() + " needs a regex");
                }
                try (PreparedStatement s = c.prepareStatement("SELECT count(" + col + "), count(*) FILTER (WHERE "
                        + col + " IS NOT NULL AND " + col + "::text !~ ?)" + from)) {
                    s.setQueryTimeout(60);
                    s.setString(1, regex.toString());
                    try (ResultSet r = s.executeQuery()) {
                        r.next();
                        long values = r.getLong(1);
                        long out = r.getLong(2);
                        return new Result(check, out == 0, count(out, "value", "values") + " of " + values
                            + " not matching " + regex, Map.of("likeCount", Long.toString(values - out)),
                            values - out, out);
                    }
                }
            }
            case "tableRowCountToBeBetween" -> {
                Object min = check.parameters().get("minValue");
                Object max = check.parameters().get("maxValue");
                long rows = longs(c, "SELECT count(*)" + from)[0];
                boolean passed = (min == null || rows >= ((Number) min).longValue())
                    && (max == null || rows <= ((Number) max).longValue());
                return new Result(check, passed, count(rows, "row", "rows") + ", expected "
                    + (min == null ? "" : text(min)) + ".." + (max == null ? "" : text(max)),
                    Map.of("rowCount", Long.toString(rows)), null, null);
            }
            case "tableCustomSQLQuery" -> {
                // Only the checks datyx writes from the schema: the SQL is its own.
                String sql = check.parameters().get("sqlExpression").toString();
                long found = longs(c, "SELECT count(*) FROM (" + sql + ") broken")[0];
                return new Result(check, found == 0, count(found, "row breaks", "rows break") + " it",
                    Map.of("resultRowCount", Long.toString(found)), null, found);
            }
            default -> throw new IllegalArgumentException("datyx can't run the test " + check.test());
        }
    }

    private static long[] longs(Connection c, String sql) throws SQLException {
        try (PreparedStatement s = c.prepareStatement(sql)) {
            s.setQueryTimeout(60);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long[] values = new long[r.getMetaData().getColumnCount()];
                for (int i = 0; i < values.length; i++) {
                    values[i] = r.getLong(i + 1);
                }
                return values;
            }
        }
    }

    private static List<String> strings(Object value) {
        if (value instanceof List<?> list && !list.isEmpty()) {
            return list.stream().map(Object::toString).toList();
        }
        throw new IllegalArgumentException("allowedValues is a list of values");
    }

    /** OpenMetadata's link to a table, or to one of its columns. */
    public static String entityLink(String tableFqn, String column) {
        return "<#E::table::" + tableFqn + (column == null ? "" : "::columns::" + column) + ">";
    }

    /** The test case as OpenMetadata's create request wants it. */
    public static ObjectNode testCase(String tableFqn, Check check) {
        JsonNodeFactory nodes = JsonNodeFactory.instance;
        ObjectNode body = nodes.objectNode()
            .put("name", check.name())
            .put("entityLink", entityLink(tableFqn, check.column()))
            .put("testDefinition", check.test())
            .put("description", check.description());
        ArrayNode parameters = body.putArray("parameterValues");
        check.parameters().forEach((name, value) -> parameters.addObject()
            .put("name", name)
            .put("value", value instanceof List<?> list ? listText(list) : text(value)));
        return body;
    }

    private static String listText(List<?> list) {
        ArrayNode array = JsonNodeFactory.instance.arrayNode();
        list.forEach(v -> array.add(v.toString()));
        return array.toString();
    }

    /** The test case's FQN: its table's, its column if any, its name. */
    public static String testCaseFqn(String tableFqn, Check check) {
        String column = check.column() == null ? "" : "." + (check.column().contains(".") ? "\"" + check.column() + "\"" : check.column());
        return tableFqn + column + "." + check.name();
    }

    /** A result as OpenMetadata's create request wants it, at {@code timestamp} (epoch ms). */
    public static ObjectNode testResult(Result result, long timestamp) {
        ObjectNode body = JsonNodeFactory.instance.objectNode()
            .put("timestamp", timestamp)
            .put("testCaseStatus", result.passed() ? "Success" : "Failed")
            .put("result", result.result());
        ArrayNode values = body.putArray("testResultValue");
        result.values().forEach((name, value) -> values.addObject().put("name", name).put("value", value));
        if (result.passedRows() != null && result.failedRows() != null) {
            long total = result.passedRows() + result.failedRows();
            body.put("passedRows", result.passedRows()).put("failedRows", result.failedRows());
            if (total > 0) {
                body.put("passedRowsPercentage", 100.0 * result.passedRows() / total)
                    .put("failedRowsPercentage", 100.0 * result.failedRows() / total);
            }
        }
        return body;
    }

    /** A profile as OpenMetadata's create request wants it, at {@code timestamp} (epoch ms). */
    public static ObjectNode profileBody(Profile profile, long timestamp) {
        ObjectNode body = JsonNodeFactory.instance.objectNode();
        body.putObject("tableProfile")
            .put("timestamp", timestamp)
            .put("rowCount", profile.rows())
            .put("columnCount", profile.columnCount());
        ArrayNode columns = body.putArray("columnProfile");
        for (ColumnProfile c : profile.columns()) {
            ObjectNode node = columns.addObject()
                .put("name", c.name())
                .put("timestamp", timestamp)
                .put("valuesCount", c.values())
                .put("nullCount", c.nulls())
                .put("nullProportion", profile.rows() == 0 ? 0.0 : (double) c.nulls() / profile.rows());
            if (c.distinct() != null) {
                node.put("distinctCount", c.distinct())
                    .put("distinctProportion", c.values() == 0 ? 0.0 : (double) c.distinct() / c.values());
            }
            putIfSet(node, "min", c.min());
            putIfSet(node, "max", c.max());
            putIfSet(node, "mean", c.mean());
            putIfSet(node, "sum", c.sum());
            putIfSet(node, "stddev", c.stddev());
            if (c.minLength() != null) {
                node.put("minLength", c.minLength());
            }
            if (c.maxLength() != null) {
                node.put("maxLength", c.maxLength());
            }
        }
        return body;
    }

    private static void putIfSet(ObjectNode node, String name, Double value) {
        if (value != null && !value.isNaN() && !value.isInfinite()) {
            node.put(name, value);
        }
    }
}
