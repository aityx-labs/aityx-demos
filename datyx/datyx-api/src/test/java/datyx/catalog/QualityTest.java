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
        assertEquals("tableCustomSQLQuery", key.name());
        assertEquals("SELECT \"run_id\", \"hour_start\" FROM \"public\".\"admissions_hourly\" GROUP BY \"run_id\", \"hour_start\" HAVING count(*) > 1",
            key.parameters().get("sqlExpression"));
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
    }
}
