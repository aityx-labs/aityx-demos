package datyx.catalog;

import java.math.BigDecimal;
import java.math.MathContext;
import java.sql.Array;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import com.fasterxml.jackson.databind.JsonNode;
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
 * through a curation document (a range, a set of values, a pattern, a
 * length, a column's min, max, mean or sum, the table's columns, and SQL
 * counting the rows that break a rule). PostgreSQL's SQL.
 */
public final class Quality {

    /**
     * A test definition's parameters, as OpenMetadata 2.0.7 names them:
     * those it takes, those it requires, and whether it needs at least
     * one of them (a range with either bound).
     */
    record Definition(List<String> parameters, Set<String> required, boolean oneAtLeast) {
    }

    private static Definition none() {
        return new Definition(List.of(), Set.of(), false);
    }

    private static Definition range(String min, String max) {
        return new Definition(List.of(min, max), Set.of(), true);
    }

    private static Definition required(String... names) {
        return new Definition(List.of(names), Set.of(names), false);
    }

    /** The test definitions datyx can run, OpenMetadata's names, with their parameters. */
    static final Map<String, Definition> DEFINITIONS = Map.ofEntries(
        Map.entry("columnValuesToBeNotNull", none()),
        Map.entry("columnValuesToBeUnique", none()),
        Map.entry("columnValuesToBeBetween", range("minValue", "maxValue")),
        Map.entry("columnValuesToBeInSet", new Definition(List.of("allowedValues", "matchEnum"), Set.of("allowedValues"), false)),
        Map.entry("columnValuesToBeNotInSet", required("forbiddenValues")),
        Map.entry("columnValuesToMatchRegex", required("regex")),
        Map.entry("columnValuesToNotMatchRegex", required("forbiddenRegex")),
        Map.entry("columnValuesMissingCount", new Definition(List.of("missingCountValue", "missingValueMatch"),
            Set.of("missingCountValue"), false)),
        Map.entry("columnValueLengthsToBeBetween", range("minLength", "maxLength")),
        Map.entry("columnValueMinToBeBetween", range("minValueForMinInCol", "maxValueForMinInCol")),
        Map.entry("columnValueMaxToBeBetween", range("minValueForMaxInCol", "maxValueForMaxInCol")),
        Map.entry("columnValueMeanToBeBetween", range("minValueForMeanInCol", "maxValueForMeanInCol")),
        Map.entry("columnValueMedianToBeBetween", range("minValueForMedianInCol", "maxValueForMedianInCol")),
        Map.entry("columnValueStdDevToBeBetween", range("minValueForStdDevInCol", "maxValueForStdDevInCol")),
        Map.entry("columnValuesSumToBeBetween", range("minValueForColSum", "maxValueForColSum")),
        Map.entry("tableRowCountToBeBetween", range("minValue", "maxValue")),
        Map.entry("tableRowCountToEqual", required("value")),
        Map.entry("tableColumnCountToEqual", required("columnCount")),
        Map.entry("tableColumnCountToBeBetween", range("minColValue", "maxColValue")),
        Map.entry("tableColumnNameToExist", required("columnName")),
        Map.entry("tableColumnToMatchSet", new Definition(List.of("columnNames", "ordered"), Set.of("columnNames"), false)),
        Map.entry("tableCustomSQLQuery", new Definition(List.of("sqlExpression", "strategy", "operator", "threshold"),
            Set.of("sqlExpression"), false)));

    /** The test definitions datyx can run, OpenMetadata's names. */
    public static final Set<String> TESTS = DEFINITIONS.keySet();

    /** A column aggregate a test bounds: the SQL aggregate, and the name OpenMetadata gives its value. */
    private record Aggregate(String sql, String value) {
    }

    private static final Map<String, Aggregate> AGGREGATES = Map.of(
        "columnValueMinToBeBetween", new Aggregate("min(%s)", "min"),
        "columnValueMaxToBeBetween", new Aggregate("max(%s)", "max"),
        "columnValueMeanToBeBetween", new Aggregate("avg(%s)", "mean"),
        "columnValueMedianToBeBetween", new Aggregate("percentile_cont(0.5) WITHIN GROUP (ORDER BY %s)", "median"),
        "columnValueStdDevToBeBetween", new Aggregate("stddev_pop(%s)", "stddev"),
        "columnValuesSumToBeBetween", new Aggregate("coalesce(sum(%s), 0)", "sum"));

    /** A custom SQL check's comparisons of its result with the threshold. */
    private static final Set<String> OPERATORS = Set.of("==", "!=", ">", ">=", "<", "<=");

    /** OpenMetadata types with an order and a mean. */
    private static final Set<String> NUMERIC = ColumnTypes.NUMERIC;

    /** OpenMetadata types with a length. */
    private static final Set<String> TEXTUAL = Set.of("TEXT", "VARCHAR", "CHAR", "STRING");

    /** OpenMetadata types PostgreSQL can't count the distinct values of (json has no equality), or that mean nothing counted. */
    private static final Set<String> UNCOUNTABLE = Set.of("JSON", "BYTEA", "XML", "ARRAY", "UNKNOWN");

    /** The longest custom SQL a check may carry. */
    static final int SQL_MAX = 4000;

    /**
     * The seconds a check's or a profile's query may take: below the
     * connection's 60 s socket timeout, so a slow query is cancelled by
     * PostgreSQL and the connection stays usable.
     */
    static final int TIMEOUT = 50;

    /**
     * Words a custom SQL check may not hold outside its quoted names and
     * strings: anything but reading (a data-modifying WITH, SELECT INTO,
     * row locks), transaction and session control, and functions that
     * reach beyond the query (sleeping, signalling, files, settings,
     * sequences, other databases).
     */
    private static final Pattern FORBIDDEN = Pattern.compile("\\b(insert|update|delete|merge|upsert|truncate|drop|alter"
        + "|create|grant|revoke|copy|call|do|execute|exec|prepare|deallocate|vacuum|analyze|analyse|cluster|reindex"
        + "|refresh|lock|share|nowait|into|set|reset|begin|commit|rollback|savepoint|listen|unlisten|notify"
        + "|discard|load|import|security|comment|checkpoint|declare"
        + "|nextval|setval|set_config|current_setting|query_to_xml\\w*|table_to_xml\\w*|cursor_to_xml\\w*"
        + "|schema_to_xml\\w*|database_to_xml\\w*|pg_\\w*|lo_\\w*|dblink\\w*)\\b", Pattern.CASE_INSENSITIVE);

    /** A quoted name or a string, as PostgreSQL reads them without backslash escapes. */
    private static final Pattern QUOTED = Pattern.compile("\"(?:[^\"]|\"\")*\"|'(?:[^']|'')*'");

    /** Unicode escapes (U&"..." and U&'...', UESCAPE), which would make a name or a string read otherwise. */
    private static final Pattern UNICODE = Pattern.compile("(?i)\\bu&|\\buescape\\b");

    /** A check's own key: letters, digits and underscores. */
    private static final Pattern KEY = Pattern.compile("[A-Za-z0-9_]{1,64}");

    /** The classification whose tag marks the test cases datyx sets. */
    public static final String MARK_CLASSIFICATION = "Datyx";

    /** The tag, in {@link #MARK_CLASSIFICATION}, that marks the test cases datyx sets. */
    public static final String MARK_TAG = "Managed";

    /**
     * The mark of datyx's own test cases, a tag each one it sets carries:
     * datyx removes a test case only when it has it.
     */
    public static final String MARK = MARK_CLASSIFICATION + "." + MARK_TAG;

    private Quality() {
    }

    /**
     * A check on a table, or on one of its columns: an OpenMetadata test
     * definition and its parameters (OpenMetadata's names: minValue and
     * maxValue, allowedValues, regex, sqlExpression...), with what it means
     * in words, and a key telling it from another of the same test on the
     * same table or column (a custom SQL check's rule). Its parameters are
     * checked against the definition, and a custom SQL check's SQL is
     * read-only, one SELECT.
     */
    @RegisterForReflection
    public record Check(String test, String column, Map<String, Object> parameters, String description, String key) {

        public Check {
            Definition definition = DEFINITIONS.get(test);
            if (definition == null) {
                throw new IllegalArgumentException("datyx can't run the test " + test + ": only " + TESTS);
            }
            boolean onColumn = test.startsWith("column");
            if (onColumn && (column == null || column.isBlank())) {
                throw new IllegalArgumentException(test + " needs a column");
            }
            if (!onColumn && column != null) {
                throw new IllegalArgumentException(test + " is a table's test, on no column");
            }
            if (key != null && !KEY.matcher(key).matches()) {
                throw new IllegalArgumentException("a check's key is letters, digits and underscores, not " + key);
            }
            parameters = parameters == null ? Map.of() : Map.copyOf(parameters);
            for (String name : parameters.keySet()) {
                if (!definition.parameters().contains(name)) {
                    throw new IllegalArgumentException(test + " takes " + definition.parameters() + ", not " + name);
                }
            }
            for (String name : definition.required()) {
                if (!parameters.containsKey(name)) {
                    throw new IllegalArgumentException(test + " needs " + name);
                }
            }
            if (definition.oneAtLeast() && definition.parameters().stream().noneMatch(parameters::containsKey)) {
                throw new IllegalArgumentException(test + " needs " + String.join(" or ", definition.parameters()));
            }
            for (String name : definition.parameters()) {
                Object value = parameters.get(name);
                if (value != null && definition.oneAtLeast()) {
                    number(value, test + "'s " + name);
                }
            }
            if (test.equals("tableCustomSQLQuery")) {
                customSql(parameters.get("sqlExpression"));
                String strategy = strategy(parameters);
                if (!strategy.equals("ROWS") && !strategy.equals("COUNT")) {
                    throw new IllegalArgumentException("a custom SQL check's strategy is ROWS or COUNT, not " + strategy);
                }
                String operator = parameters.getOrDefault("operator", "<=").toString();
                if (!OPERATORS.contains(operator)) {
                    throw new IllegalArgumentException("a custom SQL check's operator is one of " + OPERATORS);
                }
                number(parameters.getOrDefault("threshold", 0), "the threshold");
            }
        }

        /** A check with no key of its own. */
        public Check(String test, String column, Map<String, Object> parameters, String description) {
            this(test, column, parameters, description, null);
        }

        /**
         * The test case's name, unique within its table: the column, if
         * any, the test, and the key, if any (a column's name for
         * tableColumnNameToExist).
         */
        public String name() {
            String base = column == null ? test : column + "_" + test;
            String k = key;
            if (k == null && test.equals("tableColumnNameToExist")) {
                k = parameters.get("columnName").toString().replaceAll("[^A-Za-z0-9_]", "_");
            }
            return k == null ? base : base + "_" + k;
        }
    }

    /**
     * A check's outcome: passed or not, in words, the values OpenMetadata
     * shows, and the rows that passed and failed; aborted when there was
     * nothing to judge (an aggregate of no values: an empty table), which
     * OpenMetadata shows as Aborted and isn't a failure.
     */
    @RegisterForReflection
    public record Result(Check check, boolean passed, String result, Map<String, String> values, Long passedRows,
            Long failedRows, boolean aborted) {

        public Result(Check check, boolean passed, String result, Map<String, String> values, Long passedRows,
                Long failedRows) {
            this(check, passed, result, values, passedRows, failedRows, false);
        }

        /** Whether it failed: neither passed nor aborted. */
        public boolean failed() {
            return !passed && !aborted;
        }
    }

    /** A column's profile; null where it doesn't apply (no range for text, no length for numbers). */
    public record ColumnProfile(String name, long values, long nulls, Long distinct, Double min, Double max,
            Double mean, Double sum, Double stddev, Integer minLength, Integer maxLength) {
    }

    public record Profile(long rows, int columnCount, List<ColumnProfile> columns) {
    }

    /** Whether OpenMetadata's test case is one datyx set: it has datyx's mark, the tag {@link #MARK}. */
    public static boolean isDatyxs(JsonNode testCase) {
        for (JsonNode tag : testCase.path("tags")) {
            if (MARK.equals(tag.path("tagFQN").asText())) {
                return true;
            }
        }
        return false;
    }

    /**
     * Of a table's test cases in OpenMetadata, those datyx set
     * ({@link #isDatyxs}) and no longer checks ({@code keep} has the names
     * of the checks it has): the ones to remove. A test case without the
     * mark is someone else's, and stays whatever its name.
     */
    public static List<JsonNode> stale(Iterable<JsonNode> testCases, Set<String> keep) {
        List<JsonNode> stale = new ArrayList<>();
        for (JsonNode testCase : testCases) {
            if (isDatyxs(testCase) && !keep.contains(testCase.path("name").asText())) {
                stale.add(testCase);
            }
        }
        return stale;
    }

    /**
     * Custom SQL a check may run: one SELECT (or WITH) statement, at most
     * {@link #SQL_MAX} characters. Outside its quoted names and strings,
     * no semicolon, comment or dollar quote, no Unicode escape, and none of
     * the words that write, lock, control the session or reach beyond the
     * query ({@link #FORBIDDEN}); no backslash but in a quoted name; and no
     * quoted name of one of those functions called ({@code "pg_sleep"(1)}).
     * A quoted name may hold anything else (a column {@code "amount$usd"}
     * or {@code "update"}). An IllegalArgumentException says why not. It
     * runs in a read-only transaction besides.
     */
    public static String customSql(Object sqlExpression) {
        if (!(sqlExpression instanceof String sql) || sql.isBlank()) {
            throw new IllegalArgumentException("a custom SQL check needs its sqlExpression, a SELECT");
        }
        if (sql.length() > SQL_MAX) {
            throw new IllegalArgumentException("a custom SQL check's SQL is at most " + SQL_MAX + " characters");
        }
        StringBuilder code = new StringBuilder();
        Matcher quoted = QUOTED.matcher(sql);
        int at = 0;
        while (quoted.find()) {
            code.append(sql, at, quoted.start()).append(' ');
            String token = quoted.group();
            if (token.startsWith("'") && token.contains("\\")) {
                throw new IllegalArgumentException("a custom SQL check has no backslash in a string");
            }
            if (token.startsWith("\"")) {
                String name = token.substring(1, token.length() - 1).replace("\"\"", "\"");
                Matcher forbidden = FORBIDDEN.matcher(name);
                if (sql.substring(quoted.end()).matches("(?s)^\\s*\\(.*") && forbidden.find()) {
                    throw new IllegalArgumentException("a custom SQL check only reads: '" + forbidden.group(1)
                        + "' isn't allowed");
                }
            }
            at = quoted.end();
        }
        code.append(sql.substring(at));
        String outside = code.toString();
        if (outside.contains("'") || outside.contains("\"")) {
            throw new IllegalArgumentException("a custom SQL check's quotes are unbalanced");
        }
        if (outside.contains(";")) {
            throw new IllegalArgumentException("a custom SQL check is one statement, without a semicolon");
        }
        if (outside.contains("--") || outside.contains("/*") || outside.contains("$") || outside.contains("\\")) {
            throw new IllegalArgumentException("a custom SQL check has no comment, dollar quote or backslash");
        }
        if (UNICODE.matcher(outside).find()) {
            throw new IllegalArgumentException("a custom SQL check has no Unicode escape (U&, UESCAPE)");
        }
        String start = outside.stripLeading().toLowerCase(Locale.ROOT);
        if (!start.matches("(?s)^(select|with)\\b.*")) {
            throw new IllegalArgumentException("a custom SQL check is a SELECT, or a WITH ... SELECT");
        }
        Matcher forbidden = FORBIDDEN.matcher(outside);
        if (forbidden.find()) {
            throw new IllegalArgumentException("a custom SQL check only reads: '" + forbidden.group(1) + "' isn't allowed");
        }
        return sql;
    }

    private static String strategy(Map<String, Object> parameters) {
        Object strategy = parameters.getOrDefault("strategy", "ROWS");
        if (strategy instanceof List<?> list && list.size() == 1) {
            strategy = list.get(0);
        }
        return strategy.toString();
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
                "strategy", "ROWS", "operator", "==", "threshold", 0),
                "No two rows have the same " + String.join(", ", table.primaryKey()) + ", the table's primary key.",
                "primary_key"));
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
            String type = type(column);
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

    private static String type(SchemaReader.Column column) {
        return ColumnTypes.of(column.jdbcType(), column.typeName());
    }

    /** Profiles a table, in one query. */
    public static Profile profile(Connection c, SchemaReader.Table table) throws SQLException {
        try (PreparedStatement s = c.prepareStatement(profileSql(table))) {
            s.setQueryTimeout(TIMEOUT);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long rows = r.getLong(1);
                int i = 2;
                List<ColumnProfile> columns = new ArrayList<>();
                for (SchemaReader.Column column : table.columns()) {
                    String type = type(column);
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

    /** A parameter as a number: a JSON number, or text that reads as one; an IllegalArgumentException otherwise. */
    private static double number(Object value, String what) {
        if (value instanceof Number n) {
            return n.doubleValue();
        }
        try {
            return Double.parseDouble(String.valueOf(value));
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(what + " is a number, not " + value);
        }
    }

    private static Double bound(Check check, String name) {
        Object value = check.parameters().get(name);
        return value == null ? null : number(value, check.test() + "'s " + name);
    }

    /** Whether the table has the column a check is on (a table's check always applies). */
    public static boolean applies(SchemaReader.Table table, Check check) {
        return check.column() == null || table.columns().stream().anyMatch(c -> c.name().equals(check.column()));
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

    /** A value found, in words: a whole one without its ".0", another to four significant digits. */
    private static String shown(double value) {
        if (!Double.isInfinite(value) && value == Math.rint(value)) {
            return Long.toString((long) value);
        }
        return new BigDecimal(value).round(new MathContext(4)).stripTrailingZeros().toPlainString();
    }

    private static String count(long n, String one, String many) {
        return n + " " + (n == 1 ? one : many);
    }

    private static String range(Double min, Double max) {
        return (min == null ? "" : text(min)) + ".." + (max == null ? "" : text(max));
    }

    private static boolean within(double value, Double min, Double max) {
        return (min == null || value >= min) && (max == null || value <= max);
    }

    /** Runs a check on the source: one query, counting the rows that break it, or none for the table's shape. */
    public static Result evaluate(Connection c, SchemaReader.Table table, Check check) throws SQLException {
        String from = " FROM " + relation(table);
        if (check.column() != null) {
            String col = quote(column(table, check).name());
            return switch (check.test()) {
                case "columnValuesToBeNotNull" -> {
                    long[] r = longs(c, "SELECT count(*), count(*) FILTER (WHERE " + col + " IS NULL)" + from);
                    yield new Result(check, r[1] == 0, count(r[1], "null", "nulls") + " in " + count(r[0], "row", "rows"),
                        Map.of("nullCount", Long.toString(r[1])), r[0] - r[1], r[1]);
                }
                case "columnValuesToBeUnique" -> {
                    long[] r = longs(c, "SELECT count(" + col + "), count(DISTINCT " + col + ")" + from);
                    long duplicates = r[0] - r[1];
                    yield new Result(check, duplicates == 0, count(r[1], "distinct value", "distinct values") + " in "
                        + count(r[0], "value", "values"), Map.of("valuesCount", Long.toString(r[0]), "uniqueCount",
                        Long.toString(r[1])), r[1], duplicates);
                }
                case "columnValuesToBeBetween" -> between(c, check, col, from);
                case "columnValuesToBeInSet", "columnValuesToBeNotInSet" -> set(c, check, col, from);
                case "columnValuesToMatchRegex", "columnValuesToNotMatchRegex" -> regex(c, check, col, from);
                case "columnValuesMissingCount" -> missing(c, check, col, from);
                case "columnValueLengthsToBeBetween" -> lengths(c, check, col, from);
                default -> aggregate(c, table, check, col, from);
            };
        }
        return switch (check.test()) {
            case "tableRowCountToBeBetween", "tableRowCountToEqual" -> {
                long rows = longs(c, "SELECT count(*)" + from)[0];
                Double min = check.test().equals("tableRowCountToEqual") ? bound(check, "value") : bound(check, "minValue");
                Double max = check.test().equals("tableRowCountToEqual") ? min : bound(check, "maxValue");
                yield new Result(check, within(rows, min, max), count(rows, "row", "rows") + ", expected " + range(min, max),
                    Map.of("rowCount", Long.toString(rows)), null, null);
            }
            case "tableColumnCountToEqual", "tableColumnCountToBeBetween" -> {
                int columns = table.columns().size();
                Double min = check.test().equals("tableColumnCountToEqual") ? bound(check, "columnCount")
                    : bound(check, "minColValue");
                Double max = check.test().equals("tableColumnCountToEqual") ? min : bound(check, "maxColValue");
                yield new Result(check, within(columns, min, max), count(columns, "column", "columns") + ", expected "
                    + range(min, max), Map.of("columnCount", Integer.toString(columns)), null, null);
            }
            case "tableColumnNameToExist" -> {
                String name = check.parameters().get("columnName").toString();
                boolean exists = table.columns().stream().anyMatch(col -> col.name().equals(name));
                yield new Result(check, exists, exists ? "the column " + name + " is there" : "no column " + name,
                    Map.of("columnNameExits", Boolean.toString(exists)), null, null);
            }
            case "tableColumnToMatchSet" -> {
                List<String> expected = List.of(check.parameters().get("columnNames").toString().split("\\s*,\\s*"));
                List<String> actual = table.columns().stream().map(SchemaReader.Column::name).toList();
                boolean ordered = Boolean.parseBoolean(String.valueOf(check.parameters().getOrDefault("ordered", false)));
                boolean matches = ordered ? actual.equals(expected)
                    : new LinkedHashSet<>(actual).equals(new LinkedHashSet<>(expected));
                yield new Result(check, matches, matches ? "the columns are " + String.join(", ", expected)
                    : "the columns are " + String.join(", ", actual) + ", expected " + String.join(", ", expected),
                    Map.of("columnNames", String.join(",", actual)), null, null);
            }
            case "tableCustomSQLQuery" -> custom(c, check);
            default -> throw new IllegalArgumentException("datyx can't run the test " + check.test());
        };
    }

    private static Result between(Connection c, Check check, String col, String from) throws SQLException {
        Double min = bound(check, "minValue");
        Double max = bound(check, "maxValue");
        List<String> outside = new ArrayList<>();
        if (min != null) {
            outside.add(col + " < ?");
        }
        if (max != null) {
            outside.add(col + " > ?");
        }
        String sql = "SELECT count(" + col + "), count(*) FILTER (WHERE " + String.join(" OR ", outside)
            + "), min(" + col + ")::float8, max(" + col + ")::float8" + from;
        try (PreparedStatement s = c.prepareStatement(sql)) {
            s.setQueryTimeout(TIMEOUT);
            int p = 1;
            if (min != null) {
                s.setDouble(p++, min);
            }
            if (max != null) {
                s.setDouble(p, max);
            }
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long values = r.getLong(1);
                long out = r.getLong(2);
                Map<String, String> found = new LinkedHashMap<>();
                found.put("minValue", text(number(r, 3)));
                found.put("maxValue", text(number(r, 4)));
                found.values().removeIf(v -> v == null);
                return new Result(check, out == 0, count(out, "value", "values") + " of " + values + " outside "
                    + range(min, max), found, values - out, out);
            }
        }
    }

    private static Result set(Connection c, Check check, String col, String from) throws SQLException {
        boolean allowed = check.test().equals("columnValuesToBeInSet");
        List<String> values = strings(check.parameters().get(allowed ? "allowedValues" : "forbiddenValues"));
        try (PreparedStatement s = c.prepareStatement("SELECT count(" + col + "), count(*) FILTER (WHERE "
                + col + " IS NOT NULL AND " + (allowed ? col + "::text <> ALL (?)" : col + "::text = ANY (?)") + ")" + from)) {
            s.setQueryTimeout(TIMEOUT);
            Array array = c.createArrayOf("text", values.toArray());
            s.setArray(1, array);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long all = r.getLong(1);
                long out = r.getLong(2);
                return allowed
                    ? new Result(check, out == 0, count(out, "value", "values") + " of " + all + " not in " + values,
                        Map.of("allowedValueCount", Long.toString(all - out)), all - out, out)
                    : new Result(check, out == 0, count(out, "value", "values") + " of " + all + " in " + values,
                        Map.of("countForbiddenValues", Long.toString(out)), all - out, out);
            }
        }
    }

    private static Result regex(Connection c, Check check, String col, String from) throws SQLException {
        boolean match = check.test().equals("columnValuesToMatchRegex");
        String regex = check.parameters().get(match ? "regex" : "forbiddenRegex").toString();
        try (PreparedStatement s = c.prepareStatement("SELECT count(" + col + "), count(*) FILTER (WHERE "
                + col + " IS NOT NULL AND " + col + "::text " + (match ? "!~" : "~") + " ?)" + from)) {
            s.setQueryTimeout(TIMEOUT);
            s.setString(1, regex);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long values = r.getLong(1);
                long out = r.getLong(2);
                return new Result(check, out == 0, count(out, "value", "values") + " of " + values
                    + (match ? " not matching " : " matching ") + regex,
                    Map.of(match ? "likeCount" : "notLikeCount", Long.toString(values - out)), values - out, out);
            }
        }
    }

    /** Missing: null, empty or blank text, or one of missingValueMatch's strings. */
    private static Result missing(Connection c, Check check, String col, String from) throws SQLException {
        long expected = (long) number(check.parameters().get("missingCountValue"), "missingCountValue");
        Object match = check.parameters().get("missingValueMatch");
        List<String> also = match == null ? List.of() : match instanceof List<?> ? strings(match) : List.of(match.toString());
        try (PreparedStatement s = c.prepareStatement("SELECT count(*), count(*) FILTER (WHERE " + col + " IS NULL OR btrim("
                + col + "::text) = '' OR " + col + "::text = ANY (?))" + from)) {
            s.setQueryTimeout(TIMEOUT);
            s.setArray(1, c.createArrayOf("text", also.toArray()));
            try (ResultSet r = s.executeQuery()) {
                r.next();
                long rows = r.getLong(1);
                long missing = r.getLong(2);
                return new Result(check, missing == expected, count(missing, "value", "values") + " missing in "
                    + count(rows, "row", "rows") + ", expected " + expected, Map.of("missingCount", Long.toString(missing)),
                    null, null);
            }
        }
    }

    private static Result lengths(Connection c, Check check, String col, String from) throws SQLException {
        Double min = bound(check, "minLength");
        Double max = bound(check, "maxLength");
        String length = "char_length(" + col + "::text)";
        List<String> outside = new ArrayList<>();
        if (min != null) {
            outside.add(length + " < " + (long) Math.ceil(min));
        }
        if (max != null) {
            outside.add(length + " > " + (long) Math.floor(max));
        }
        long[] r = longs(c, "SELECT count(" + col + "), count(*) FILTER (WHERE " + String.join(" OR ", outside)
            + "), coalesce(min(" + length + "), 0), coalesce(max(" + length + "), 0)" + from);
        return new Result(check, r[1] == 0, count(r[1], "value", "values") + " of " + r[0] + " with a length outside "
            + range(min, max), Map.of("minValueLength", Long.toString(r[2]), "maxValueLength", Long.toString(r[3])),
            r[0] - r[1], r[1]);
    }

    /** A column's min, max, mean, median, standard deviation or sum, within bounds; a number's only. */
    private static Result aggregate(Connection c, SchemaReader.Table table, Check check, String col, String from)
            throws SQLException {
        Aggregate aggregate = AGGREGATES.get(check.test());
        if (!NUMERIC.contains(type(column(table, check)))) {
            throw new IllegalArgumentException(check.test() + " is for a number's column, not " + check.column());
        }
        List<String> names = DEFINITIONS.get(check.test()).parameters();
        Double min = bound(check, names.get(0));
        Double max = bound(check, names.get(1));
        try (PreparedStatement s = c.prepareStatement("SELECT (" + aggregate.sql().formatted(col) + ")::float8" + from)) {
            s.setQueryTimeout(TIMEOUT);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                Double value = number(r, 1);
                if (value == null) {
                    return new Result(check, false, "no values to take the " + aggregate.value() + " of yet: nothing to judge",
                        Map.of(), null, null, true);
                }
                return new Result(check, within(value, min, max), aggregate.value() + " " + shown(value) + ", expected "
                    + range(min, max), Map.of(aggregate.value(), shown(value)), null, null);
            }
        }
    }

    /**
     * A custom SQL check: its SQL, checked again ({@link #customSql}), runs
     * in a read-only transaction with the statement timeout. ROWS counts
     * the rows it returns, COUNT reads the one number it returns; it
     * passes when that compares with the threshold by the operator ({@code
     * <=} 0 unless said).
     */
    private static Result custom(Connection c, Check check) throws SQLException {
        String sql = customSql(check.parameters().get("sqlExpression"));
        boolean rows = strategy(check.parameters()).equals("ROWS");
        String operator = check.parameters().getOrDefault("operator", "<=").toString();
        double threshold = number(check.parameters().getOrDefault("threshold", 0), "the threshold");
        long found = readOnly(c, () -> {
            String query = rows ? "SELECT count(*) FROM (" + sql + ") AS custom" : "SELECT * FROM (" + sql + ") AS custom LIMIT 2";
            try (PreparedStatement s = c.prepareStatement(query)) {
                s.setQueryTimeout(TIMEOUT);
                try (ResultSet r = s.executeQuery()) {
                    if (!r.next() || r.getMetaData().getColumnCount() != 1) {
                        throw new IllegalArgumentException(check.name() + "'s SQL doesn't answer one number");
                    }
                    long value = r.getLong(1);
                    if (r.wasNull() || r.next()) {
                        throw new IllegalArgumentException(check.name() + "'s SQL doesn't answer one number");
                    }
                    return value;
                }
            }
        });
        boolean passed = switch (operator) {
            case "==" -> found == threshold;
            case "!=" -> found != threshold;
            case ">" -> found > threshold;
            case ">=" -> found >= threshold;
            case "<" -> found < threshold;
            default -> found <= threshold;
        };
        String what = rows ? count(found, "row", "rows") + " found" : "the count is " + found;
        return new Result(check, passed, what + (passed ? "" : ", expected " + operator + " " + text(threshold)),
            Map.of("resultRowCount", Long.toString(found)), null, null);
    }

    @FunctionalInterface
    interface Read<T> {
        T run() throws SQLException;
    }

    /** Runs {@code read} in a read-only transaction, {@link #TIMEOUT} seconds at most a statement, rolled back after. */
    static <T> T readOnly(Connection c, Read<T> read) throws SQLException {
        boolean autoCommit = c.getAutoCommit();
        c.setAutoCommit(false);
        try {
            try (Statement s = c.createStatement()) {
                s.execute("SET TRANSACTION READ ONLY");
                s.execute("SET LOCAL statement_timeout = '" + TIMEOUT + "s'");
            }
            return read.run();
        } finally {
            try {
                c.rollback();
            } finally {
                c.setAutoCommit(autoCommit);
            }
        }
    }

    /** Connects to the source. */
    @FunctionalInterface
    public interface Connect {
        Connection open() throws SQLException;
    }

    /**
     * The source's connection for a sync or a curation: opened when first
     * needed, and again after an error left it unusable (a dropped
     * socket), so one check's trouble doesn't stop the others.
     */
    public static final class Link implements AutoCloseable {

        private final Connect connect;
        private Connection connection;

        public Link(Connect connect) {
            this.connect = connect;
        }

        /** The connection, opened if it isn't. */
        public Connection get() throws SQLException {
            if (connection == null) {
                connection = connect.open();
            }
            return connection;
        }

        /** After an error: drops the connection when it no longer answers, so the next {@link #get} opens another. */
        public void recover() {
            try {
                if (connection != null && !connection.isValid(5)) {
                    close();
                }
            } catch (SQLException e) {
                close();
            }
        }

        @Override
        public void close() {
            if (connection != null) {
                try {
                    connection.close();
                } catch (SQLException e) {
                    // closed already, or never to be used again
                } finally {
                    connection = null;
                }
            }
        }
    }

    /**
     * Runs a check, and never fails: an error (a query past its timeout,
     * SQL that doesn't answer one number, a view that can't be read) is
     * the check's Failed result, the error its message; and the
     * connection is opened again for the next check when the error broke
     * it.
     */
    public static Result run(Link link, SchemaReader.Table table, Check check) {
        try {
            return evaluate(link.get(), table, check);
        } catch (SQLException | RuntimeException e) {
            link.recover();
            String message = e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
            if (message.length() > 500) {
                message = message.substring(0, 500) + "...";
            }
            return new Result(check, false, "the check couldn't run: " + message, Map.of(), null, null);
        }
    }

    private static long[] longs(Connection c, String sql) throws SQLException {
        try (PreparedStatement s = c.prepareStatement(sql)) {
            s.setQueryTimeout(TIMEOUT);
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
        throw new IllegalArgumentException("a set of values is a list of values");
    }

    /** OpenMetadata's link to a table, or to one of its columns. */
    public static String entityLink(String tableFqn, String column) {
        return "<#E::table::" + tableFqn + (column == null ? "" : "::columns::" + column) + ">";
    }

    /** The test case as OpenMetadata's create request wants it, its parameters in the definition's order. */
    public static ObjectNode testCase(String tableFqn, Check check) {
        JsonNodeFactory nodes = JsonNodeFactory.instance;
        ObjectNode body = nodes.objectNode()
            .put("name", check.name())
            .put("entityLink", entityLink(tableFqn, check.column()))
            .put("testDefinition", check.test())
            .put("description", check.description());
        body.putArray("tags").addObject()
            .put("tagFQN", MARK)
            .put("source", "Classification")
            .put("labelType", "Automated")
            .put("state", "Confirmed");
        ArrayNode parameters = body.putArray("parameterValues");
        for (String name : DEFINITIONS.get(check.test()).parameters()) {
            Object value = check.parameters().get(name);
            if (value != null) {
                parameters.addObject().put("name", name).put("value", value instanceof List<?> list ? listText(list) : text(value));
            }
        }
        return body;
    }

    /**
     * Whether OpenMetadata's test case ({@code existing}, read with its
     * tags) says something else than the one datyx would put
     * ({@code wanted}): its description or a parameter's value, or it
     * lacks datyx's mark (one set before datyx marked them).
     */
    public static boolean differs(JsonNode existing, JsonNode wanted) {
        if (!isDatyxs(existing)) {
            return true;
        }
        if (!existing.path("description").asText("").equals(wanted.path("description").asText(""))) {
            return true;
        }
        return !parameters(existing).equals(parameters(wanted));
    }

    private static Map<String, String> parameters(JsonNode testCase) {
        Map<String, String> values = new LinkedHashMap<>();
        testCase.path("parameterValues").forEach(p -> values.put(p.path("name").asText(), p.path("value").asText()));
        return values;
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
            .put("testCaseStatus", result.passed() ? "Success" : result.aborted() ? "Aborted" : "Failed")
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
