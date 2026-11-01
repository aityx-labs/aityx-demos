package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Types;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;

/**
 * Quality without a database: the checks a schema implies, the profile's
 * query, the test cases, results and profiles as OpenMetadata takes them,
 * and the curation's checks read from JSON. CatalogResourceTest runs them
 * on a real PostgreSQL.
 */
class QualityTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static SchemaReader.Column column(String name, int type, String typeName, boolean nullable, int position) {
        return new SchemaReader.Column(name, type, typeName, 0, 0, nullable, null, position);
    }

    private static final SchemaReader.Table ADMISSIONS = new SchemaReader.Table("public", "admissions", "TABLE", null,
        List.of(column("id", Types.INTEGER, "serial", false, 1), column("age", Types.INTEGER, "int4", false, 2),
            column("complaint", Types.VARCHAR, "text", true, 3), column("signs", Types.OTHER, "jsonb", true, 4)),
        List.of("id"));

    private static final SchemaReader.Table HOURLY = new SchemaReader.Table("public", "admissions_hourly", "TABLE", null,
        List.of(column("run_id", Types.VARCHAR, "text", false, 1), column("hour_start", Types.TIMESTAMP, "timestamp", false, 2),
            column("admissions", Types.INTEGER, "int4", false, 3)),
        List.of("run_id", "hour_start"));

    @Test
    void theSchemaGivesNotNullAndKeyChecks() {
        List<Quality.Check> checks = Quality.fromSchema(ADMISSIONS);
        assertEquals(List.of("id_columnValuesToBeNotNull", "age_columnValuesToBeNotNull", "id_columnValuesToBeUnique"),
            checks.stream().map(Quality.Check::name).toList());
    }

    @Test
    void aCompositeKeyIsCheckedBySql() {
        Quality.Check key = Quality.fromSchema(HOURLY).stream()
            .filter(c -> c.test().equals("tableCustomSQLQuery")).findFirst().orElseThrow();
        assertEquals("tableCustomSQLQuery_primary_key", key.name());
        assertEquals("0", Quality.testCase("s.d.p.t", key).path("parameterValues").get(3).path("value").asText());
        assertEquals("SELECT \"run_id\", \"hour_start\" FROM \"public\".\"admissions_hourly\" GROUP BY \"run_id\", \"hour_start\" HAVING count(*) > 1",
            key.parameters().get("sqlExpression"));
    }

    @Test
    void aCompositeKeyOfAnyNamesIsChecked() {
        // Names PostgreSQL allows, quoted or not: a dollar, a semicolon, a dash pair, a backslash, a keyword, pg_.
        SchemaReader.Table odd = new SchemaReader.Table("pg_odd", "price;list", "TABLE", null,
            List.of(column("amount$usd", Types.INTEGER, "int4", false, 1), column("a--b", Types.VARCHAR, "text", false, 2),
                column("back\\slash", Types.VARCHAR, "text", false, 3), column("update", Types.VARCHAR, "text", false, 4),
                column("pg_day", Types.DATE, "date", false, 5), column("say \"hi\"", Types.VARCHAR, "text", false, 6)),
            List.of("amount$usd", "a--b", "back\\slash", "update", "pg_day", "say \"hi\""));
        Quality.Check key = Quality.fromSchema(odd).stream()
            .filter(c -> c.test().equals("tableCustomSQLQuery")).findFirst().orElseThrow();
        assertTrue(key.parameters().get("sqlExpression").toString().contains("\"say \"\"hi\"\"\""));
    }

    @Test
    void theProfileQueryFitsEachType() {
        String sql = Quality.profileSql(ADMISSIONS);
        assertTrue(sql.startsWith("SELECT count(*), count(\"id\"), count(DISTINCT \"id\"), min(\"id\")::float8"), sql);
        assertTrue(sql.contains("min(length(\"complaint\")), max(length(\"complaint\"))"), sql);
        assertTrue(sql.contains("count(\"signs\")") && !sql.contains("DISTINCT \"signs\""), "json isn't counted distinct: " + sql);
        assertTrue(sql.endsWith(" FROM \"public\".\"admissions\""), sql);
    }

    @Test
    void identifiersAreQuoted() {
        assertEquals("\"a\"\"b\"", Quality.quote("a\"b"));
    }

    @Test
    void aTestCaseLinksItsColumn() {
        Quality.Check check = new Quality.Check("columnValuesToBeInSet", "sex", Map.of("allowedValues", List.of("woman", "man")),
            "Woman or man.");
        ObjectNode body = Quality.testCase("datyx-ds-1.healthhub.public.admissions", check);
        assertEquals("sex_columnValuesToBeInSet", body.path("name").asText());
        assertEquals("<#E::table::datyx-ds-1.healthhub.public.admissions::columns::sex>", body.path("entityLink").asText());
        assertEquals("allowedValues", body.path("parameterValues").get(0).path("name").asText());
        assertEquals("[\"woman\",\"man\"]", body.path("parameterValues").get(0).path("value").asText());
        assertEquals("datyx-ds-1.healthhub.public.admissions.sex.sex_columnValuesToBeInSet",
            Quality.testCaseFqn("datyx-ds-1.healthhub.public.admissions", check));
    }

    @Test
    void aTableCheckLinksTheTable() {
        Quality.Check check = new Quality.Check("tableRowCountToBeBetween", null, Map.of("minValue", 1), "Rows.");
        assertEquals("<#E::table::s.d.p.t>", Quality.testCase("s.d.p.t", check).path("entityLink").asText());
        assertEquals("1", Quality.testCase("s.d.p.t", check).path("parameterValues").get(0).path("value").asText());
        assertEquals("s.d.p.t.tableRowCountToBeBetween", Quality.testCaseFqn("s.d.p.t", check));
    }

    @Test
    void aResultCountsRows() {
        Quality.Check check = new Quality.Check("columnValuesToBeNotNull", "age", Map.of(), "Ages.");
        ObjectNode failed = Quality.testResult(new Quality.Result(check, false, "1 null in 4 rows",
            Map.of("nullCount", "1"), 3L, 1L), 1000L);
        assertEquals("Failed", failed.path("testCaseStatus").asText());
        assertEquals(1000L, failed.path("timestamp").asLong());
        assertEquals(25.0, failed.path("failedRowsPercentage").asDouble());
        assertEquals("nullCount", failed.path("testResultValue").get(0).path("name").asText());
        ObjectNode passed = Quality.testResult(new Quality.Result(check, true, "0 rows", Map.of(), null, null), 1000L);
        assertEquals("Success", passed.path("testCaseStatus").asText());
        Quality.Result nothing = new Quality.Result(check, false, "no values", Map.of(), null, null, true);
        assertFalse(nothing.failed());
        assertEquals("Aborted", Quality.testResult(nothing, 1000L).path("testCaseStatus").asText());
        assertFalse(passed.has("passedRows"));
    }

    @Test
    void aProfileHasProportions() {
        ObjectNode body = Quality.profileBody(new Quality.Profile(4, 2, List.of(
            new Quality.ColumnProfile("age", 3, 1, 2L, 18.0, 90.0, 50.0, 150.0, Double.NaN, null, null),
            new Quality.ColumnProfile("complaint", 4, 0, 4L, null, null, null, null, null, 3, 40))), 1000L);
        assertEquals(4, body.path("tableProfile").path("rowCount").asLong());
        JsonNode age = body.path("columnProfile").get(0);
        assertEquals(0.25, age.path("nullProportion").asDouble());
        assertEquals(18.0, age.path("min").asDouble());
        assertFalse(age.has("stddev"), "NaN isn't sent");
        assertEquals(40, body.path("columnProfile").get(1).path("maxLength").asInt());
    }

    @Test
    void checksAreReadFromTheDocument() throws Exception {
        Quality.Check check = JSON.readValue("""
            {"test":"columnValuesToBeBetween","column":"age","parameters":{"minValue":18,"maxValue":90},"description":"Adults."}""",
            Quality.Check.class);
        assertEquals("age_columnValuesToBeBetween", check.name());
        assertEquals(90, ((Number) check.parameters().get("maxValue")).intValue());
        assertThrows(Exception.class, () -> JSON.readValue("{\"test\":\"columnValuesToBeNotNull\"}", Quality.Check.class),
            "a column test needs its column");
        assertThrows(Exception.class, () -> JSON.readValue("{\"test\":\"dropTable\"}", Quality.Check.class));
        Quality.Check custom = JSON.readValue("""
            {"test":"tableCustomSQLQuery","key":"counts_add_up","parameters":{"sqlExpression":"SELECT 1"},"description":"Sums."}""",
            Quality.Check.class);
        assertEquals("tableCustomSQLQuery_counts_add_up", custom.name());
    }

    @Test
    void parametersAreTheDefinitions() {
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("columnValuesToBeBetween", "age",
            Map.of("min", 1), "A typo."), "OpenMetadata's names only");
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("columnValuesToBeBetween", "age",
            Map.of(), "No bound."));
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("columnValueMeanToBeBetween", "age",
            Map.of("minValueForMeanInCol", "old"), "Not a number."));
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("columnValuesMissingCount", "name",
            Map.of(), "Needs its count."));
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("tableColumnCountToEqual", "age",
            Map.of("columnCount", 3), "A table's test on a column."));
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("tableColumnNameToExist", null,
            Map.of("columnName", "age"), "A key with a space.", "two words"));
        assertThrows(IllegalArgumentException.class, () -> new Quality.Check("tableCustomSQLQuery", null,
            Map.of("sqlExpression", "SELECT 1", "operator", "~"), "An operator OpenMetadata hasn't."));
        assertEquals("tableColumnNameToExist_hour_start", new Quality.Check("tableColumnNameToExist", null,
            Map.of("columnName", "hour_start"), "Its timestamp.").name());
        assertEquals("age_columnValueMeanToBeBetween_adults", new Quality.Check("columnValueMeanToBeBetween", "age",
            Map.of("minValueForMeanInCol", 18), "Adults.", "adults").name());
    }

    @Test
    void customSqlOnlyReads() {
        for (String sql : List.of(
                "SELECT id FROM t WHERE amount < 0",
                "select count(*) from t",
                "WITH late AS (SELECT * FROM t WHERE at > now()) SELECT id FROM late",
                "SELECT id FROM t WHERE note = 'delete or drop it' AND \"update\" > 0",
                "SELECT updated_at, female_share FROM t",
                "SELECT \"amount$usd\", \"a;b\", \"c--d\", \"back\\slash\" FROM \"pg_odd\".\"t\" WHERE \"pg_day\" > now()",
                "SELECT id FROM t WHERE note = 'a; b -- c /* d $1'")) {
            assertEquals(sql, Quality.customSql(sql), sql);
        }
        for (String sql : List.of(
                "SELECT 1; DROP TABLE t",
                "SELECT 1;",
                "DELETE FROM t",
                "UPDATE t SET a = 1",
                "WITH gone AS (DELETE FROM t RETURNING *) SELECT * FROM gone",
                "SELECT * INTO copy FROM t",
                "SELECT * FROM t FOR UPDATE",
                "SELECT * FROM t FOR SHARE",
                "SELECT pg_sleep(100)",
                "SELECT set_config('statement_timeout', '0', false)",
                "SELECT nextval('s')",
                "SELECT * FROM dblink('other', 'DELETE FROM t')",
                "SELECT pg_read_file('/etc/passwd')",
                "SELECT count(\"pg_terminate_backend\"(pid)) FROM \"pg_stat_activity\" WHERE usename = current_user",
                "SELECT \"pg_sleep\"(55)",
                "SELECT \"pg_catalog\".\"pg_sleep\" (55)",
                "SELECT count(*) FROM \"dblink_exec\"('other', 'DELETE FROM t')",
                "SELECT \"set_config\"('statement_timeout', '0', false)",
                "SELECT \"nextval\"('s')",
                "SELECT U&\"\\0070g_sleep\"(55)",
                "SELECT U&\"!0070g_sleep\" UESCAPE '!' (55)",
                "SELECT U&'d!0061ta' UESCAPE '!'",
                "SELECT 'a\\' FROM t",
                "SELECT 1 -- comment",
                "SELECT 1 /* comment */",
                "SELECT $$x$$",
                "SELECT E'\\x'",
                "SELECT 'unbalanced",
                "TRUNCATE t",
                "COPY t TO PROGRAM 'rm -rf /'",
                "CALL p()",
                "VALUES (1)",
                "EXPLAIN ANALYZE DELETE FROM t",
                "",
                "SELECT " + "x".repeat(Quality.SQL_MAX))) {
            assertThrows(IllegalArgumentException.class, () -> Quality.customSql(sql), sql);
            assertThrows(IllegalArgumentException.class, () -> new Quality.Check("tableCustomSQLQuery", null,
                Map.of("sqlExpression", sql), "Refused.", "refused"), sql);
        }
        assertThrows(IllegalArgumentException.class, () -> Quality.customSql(null));
    }

    @Test
    void datyxsTestCasesCarryItsMark() {
        Quality.Check check = new Quality.Check("columnValuesToBeBetween", "age", Map.of("minValue", 18), "Adults.");
        ObjectNode testCase = Quality.testCase("s.d.p.t", check);
        assertEquals(Quality.MARK, testCase.path("tags").get(0).path("tagFQN").asText());
        assertTrue(Quality.isDatyxs(testCase));
    }

    /** A test case as OpenMetadata answers it: its name, and its tags (the table's and column's inherited too). */
    private static JsonNode answered(String name, String... tags) {
        ObjectNode testCase = JSON.createObjectNode().put("name", name).put("id", name);
        for (String tag : tags) {
            testCase.withArray("tags").addObject().put("tagFQN", tag);
        }
        return testCase;
    }

    @Test
    void onlyDatyxsMarkedTestCasesArePruned() {
        List<JsonNode> cases = List.of(
            answered("age_columnValuesToBeBetween", "PII.None", Quality.MARK),
            answered("tableCustomSQLQuery_dropped_rule", "Tier.Tier1", Quality.MARK),
            answered("age_columnValuesToBeBetween_aB3d", "PII.None"),
            answered("hospital_id_columnValuesToBeNotNull_manual"),
            answered("tableCustomSQLQuery_my_rule", "Tier.Tier1"),
            answered("tableRowCountToBeBetween"));
        List<String> stale = Quality.stale(cases, java.util.Set.of("age_columnValuesToBeBetween"))
            .stream().map(t -> t.path("name").asText()).toList();
        assertEquals(List.of("tableCustomSQLQuery_dropped_rule"), stale,
            "a name like datyx's without its mark is someone else's test case, and stays");
    }

    @Test
    void aTestCaseDiffersByDescriptionOrParameter() {
        Quality.Check check = new Quality.Check("columnValuesToBeBetween", "age", Map.of("minValue", 18, "maxValue", 90),
            "Adults.");
        ObjectNode wanted = Quality.testCase("s.d.p.t", check);
        assertFalse(Quality.differs(wanted.deepCopy(), wanted));
        ObjectNode older = wanted.deepCopy();
        ((ObjectNode) older.path("parameterValues").get(1)).put("value", "99");
        assertTrue(Quality.differs(older, wanted));
        assertTrue(Quality.differs(wanted.deepCopy().put("description", "Grown ups."), wanted));
        assertTrue(Quality.differs(Quality.testCase("s.d.p.t", new Quality.Check("columnValuesToBeBetween", "age",
            Map.of("minValue", 18), "Adults.")), wanted), "a bound dropped");
        ObjectNode unmarked = wanted.deepCopy();
        unmarked.remove("tags");
        assertTrue(Quality.differs(unmarked, wanted), "one set before datyx marked them gets the mark");
    }
}
