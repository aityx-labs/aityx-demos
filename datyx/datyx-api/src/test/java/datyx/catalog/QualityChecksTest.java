package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.List;
import java.util.Map;

import io.agroal.api.AgroalDataSource;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Each of the test definitions datyx runs, on the Dev Services Postgres
 * standing in for a source: the SQL it runs, a check that passes and one
 * that fails, the values OpenMetadata is told; and a custom SQL check's
 * read-only transaction.
 */
@QuarkusTest
class QualityChecksTest {

    @Inject
    AgroalDataSource dataSource;

    private SchemaReader.Table stays;

    @BeforeEach
    void table() throws Exception {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("create schema if not exists ward");
            s.execute("drop table if exists ward.stays");
            s.execute("""
                create table ward.stays (id int primary key, patient text, level text, hours int, share double precision,
                  code text)""");
            s.execute("""
                insert into ward.stays values (1, 'Rosa', 'green', 2, 0.5, 'a-1'), (2, 'Carlos', 'blue', 4, 0.25, 'b-2'),
                  (3, '', 'green', 6, 0.75, 'c-3'), (4, null, 'red', 8, null, null)""");
        }
        try (Connection c = dataSource.getConnection()) {
            stays = SchemaReader.read(c).stream().filter(t -> t.schema().equals("ward") && t.name().equals("stays"))
                .findFirst().orElseThrow();
        }
    }

    private Quality.Result run(String test, String column, Map<String, Object> parameters) throws SQLException {
        try (Connection c = dataSource.getConnection()) {
            return Quality.evaluate(c, stays, new Quality.Check(test, column, parameters, "A check.", null));
        }
    }

    @Test
    void uniqueAndNotNull() throws Exception {
        assertTrue(run("columnValuesToBeUnique", "id", Map.of()).passed());
        Quality.Result levels = run("columnValuesToBeUnique", "level", Map.of());
        assertFalse(levels.passed());
        assertEquals("3", levels.values().get("uniqueCount"));
        assertTrue(run("columnValuesToBeNotNull", "level", Map.of()).passed());
        assertFalse(run("columnValuesToBeNotNull", "patient", Map.of()).passed());
    }

    @Test
    void missingCountsNullsAndEmptyText() throws Exception {
        Quality.Result patient = run("columnValuesMissingCount", "patient", Map.of("missingCountValue", 2));
        assertTrue(patient.passed(), patient.result());
        assertEquals("2", patient.values().get("missingCount"));
        assertFalse(run("columnValuesMissingCount", "patient", Map.of("missingCountValue", 0)).passed());
        Quality.Result also = run("columnValuesMissingCount", "patient",
            Map.of("missingCountValue", 3, "missingValueMatch", List.of("Carlos")));
        assertTrue(also.passed(), "Carlos counts as missing too: " + also.result());
        assertTrue(run("columnValuesMissingCount", "hours", Map.of("missingCountValue", 0)).passed());
    }

    @Test
    void lengthsAreBetween() throws Exception {
        Quality.Result names = run("columnValueLengthsToBeBetween", "patient", Map.of("minLength", 1, "maxLength", 6));
        assertFalse(names.passed(), "the empty name is shorter");
        assertEquals(1L, names.failedRows());
        assertEquals("0", names.values().get("minValueLength"));
        assertEquals("6", names.values().get("maxValueLength"));
        assertTrue(run("columnValueLengthsToBeBetween", "code", Map.of("minLength", 3, "maxLength", 3)).passed());
        assertFalse(run("columnValueLengthsToBeBetween", "code", Map.of("maxLength", 2)).passed());
    }

    @Test
    void aColumnsAggregatesAreBetween() throws Exception {
        Quality.Result min = run("columnValueMinToBeBetween", "hours", Map.of("minValueForMinInCol", 1, "maxValueForMinInCol", 2));
        assertTrue(min.passed(), min.result());
        assertEquals("2", min.values().get("min"));
        assertFalse(run("columnValueMinToBeBetween", "hours", Map.of("minValueForMinInCol", 3)).passed());
        assertTrue(run("columnValueMaxToBeBetween", "hours", Map.of("maxValueForMaxInCol", 8)).passed());
        assertFalse(run("columnValueMaxToBeBetween", "hours", Map.of("maxValueForMaxInCol", 7)).passed());
        Quality.Result mean = run("columnValueMeanToBeBetween", "share", Map.of("minValueForMeanInCol", 0.4,
            "maxValueForMeanInCol", 0.6));
        assertTrue(mean.passed(), mean.result());
        assertEquals("0.5", mean.values().get("mean"));
        assertFalse(run("columnValueMeanToBeBetween", "hours", Map.of("minValueForMeanInCol", 6)).passed());
        Quality.Result sum = run("columnValuesSumToBeBetween", "hours", Map.of("minValueForColSum", 20, "maxValueForColSum", 20));
        assertTrue(sum.passed(), sum.result());
        assertEquals("20", sum.values().get("sum"));
        assertFalse(run("columnValuesSumToBeBetween", "hours", Map.of("maxValueForColSum", 19)).passed());
        assertTrue(run("columnValueMedianToBeBetween", "hours", Map.of("minValueForMedianInCol", 5,
            "maxValueForMedianInCol", 5)).passed());
        assertTrue(run("columnValueStdDevToBeBetween", "hours", Map.of("maxValueForStdDevInCol", 3)).passed());
        assertThrows(IllegalArgumentException.class, () -> run("columnValueMinToBeBetween", "level",
            Map.of("minValueForMinInCol", 1)), "a text has no min to bound");
    }

    @Test
    void anEmptyTableHasNothingToJudge() throws Exception {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("delete from ward.stays");
        }
        for (String test : List.of("columnValueMaxToBeBetween", "columnValueMinToBeBetween", "columnValueMeanToBeBetween")) {
            String max = test.replace("columnValue", "maxValueFor").replace("ToBeBetween", "InCol");
            Quality.Result result = run(test, "hours", Map.of(max, 100));
            assertTrue(result.aborted() && !result.failed(), test + ": " + result.result());
        }
        assertTrue(run("columnValuesSumToBeBetween", "hours", Map.of("maxValueForColSum", 10)).passed(), "a sum of none is 0");
        assertTrue(run("tableRowCountToBeBetween", null, Map.of("minValue", 1)).failed(), "rows wanted: a failure");
    }

    @Test
    void aCheckThatCantRunFailsAndTheOthersRun() throws Exception {
        List<Quality.Check> checks = List.of(
            new Quality.Check("tableCustomSQLQuery", null, Map.of("sqlExpression", "SELECT id FROM ward.nowhere"), "Gone.", "gone"),
            new Quality.Check("tableCustomSQLQuery", null, Map.of("sqlExpression", "SELECT id, hours FROM ward.stays",
                "strategy", "COUNT"), "Two numbers.", "two"),
            new Quality.Check("columnValueMinToBeBetween", "level", Map.of("minValueForMinInCol", 1), "Text.", null),
            new Quality.Check("columnValuesToBeNotNull", "level", Map.of(), "Levels.", null),
            new Quality.Check("tableRowCountToBeBetween", null, Map.of("minValue", 4), "Rows.", null));
        int[] opened = {0};
        try (Quality.Link link = new Quality.Link(() -> {
            opened[0]++;
            return dataSource.getConnection();
        })) {
            List<Quality.Result> results = checks.stream().map(check -> Quality.run(link, stays, check)).toList();
            for (int i = 0; i < 3; i++) {
                assertTrue(results.get(i).failed(), results.get(i).result());
                assertTrue(results.get(i).result().startsWith("the check couldn't run: "), results.get(i).result());
            }
            assertTrue(results.get(0).result().contains("nowhere"), results.get(0).result());
            assertTrue(results.get(3).passed(), "the checks after an error run: " + results.get(3).result());
            assertTrue(results.get(4).passed(), results.get(4).result());
            assertEquals(1, opened[0], "the connection still answers: not opened again");
        }
    }

    @Test
    void aBrokenConnectionIsOpenedAgain() throws Exception {
        int[] opened = {0};
        try (Quality.Link link = new Quality.Link(() -> {
            opened[0]++;
            return dataSource.getConnection();
        })) {
            Quality.Check rows = new Quality.Check("tableRowCountToBeBetween", null, Map.of("minValue", 1), "Rows.", null);
            assertTrue(Quality.run(link, stays, rows).passed());
            link.get().close();
            assertTrue(Quality.run(link, stays, rows).failed(), "the closed connection fails the check");
            assertTrue(Quality.run(link, stays, rows).passed(), "and the next one has a new connection");
            assertEquals(2, opened[0]);
        }
    }

    @Test
    void setsAndPatterns() throws Exception {
        Quality.Result notIn = run("columnValuesToBeNotInSet", "level", Map.of("forbiddenValues", List.of("red", "black")));
        assertFalse(notIn.passed());
        assertEquals(1L, notIn.failedRows());
        assertEquals("1", notIn.values().get("countForbiddenValues"));
        assertTrue(run("columnValuesToBeNotInSet", "level", Map.of("forbiddenValues", List.of("black"))).passed());
        assertTrue(run("columnValuesToBeNotInSet", "hours", Map.of("forbiddenValues", List.of("0"))).passed(),
            "compared as text");
        assertTrue(run("columnValuesToNotMatchRegex", "code", Map.of("forbiddenRegex", "[{}]")).passed());
        assertFalse(run("columnValuesToNotMatchRegex", "code", Map.of("forbiddenRegex", "^c")).passed());
    }

    @Test
    void theTablesShape() throws Exception {
        assertTrue(run("tableColumnCountToEqual", null, Map.of("columnCount", 6)).passed());
        Quality.Result count = run("tableColumnCountToEqual", null, Map.of("columnCount", 7));
        assertFalse(count.passed());
        assertEquals("6", count.values().get("columnCount"));
        assertTrue(run("tableColumnCountToBeBetween", null, Map.of("minColValue", 5, "maxColValue", 6)).passed());
        assertTrue(run("tableColumnNameToExist", null, Map.of("columnName", "hours")).passed());
        Quality.Result gone = run("tableColumnNameToExist", null, Map.of("columnName", "minutes"));
        assertFalse(gone.passed());
        assertEquals("false", gone.values().get("columnNameExits"));
        assertTrue(run("tableColumnToMatchSet", null, Map.of("columnNames", "code, share, hours, level, patient, id")).passed());
        assertFalse(run("tableColumnToMatchSet", null, Map.of("columnNames", "code,share,hours,level,patient,id",
            "ordered", true)).passed());
        assertTrue(run("tableRowCountToEqual", null, Map.of("value", 4)).passed());
        assertFalse(run("tableRowCountToEqual", null, Map.of("value", 3)).passed());
    }

    @Test
    void customSqlCountsTheRowsThatBreakARule() throws Exception {
        Quality.Result none = run("tableCustomSQLQuery", null,
            Map.of("sqlExpression", "SELECT id FROM ward.stays WHERE hours < 0"));
        assertTrue(none.passed(), none.result());
        assertEquals("0", none.values().get("resultRowCount"));
        Quality.Result some = run("tableCustomSQLQuery", null,
            Map.of("sqlExpression", "SELECT id FROM ward.stays WHERE hours > 4 AND level = 'green'"));
        assertFalse(some.passed());
        assertEquals("1 row found, expected <= 0", some.result());
        assertTrue(run("tableCustomSQLQuery", null, Map.of("sqlExpression",
            "WITH long AS (SELECT * FROM ward.stays WHERE hours > 4) SELECT id FROM long", "operator", "<=",
            "threshold", 2)).passed(), "within a threshold");
        Quality.Result count = run("tableCustomSQLQuery", null, Map.of("sqlExpression",
            "SELECT count(*) FROM ward.stays WHERE level = 'green'", "strategy", "COUNT", "operator", "==", "threshold", 2));
        assertTrue(count.passed(), count.result());
        assertEquals("2", count.values().get("resultRowCount"));
        assertTrue(run("tableCustomSQLQuery", null, Map.of("sqlExpression", "SELECT count(*) FROM ward.stays",
            "strategy", "COUNT", "operator", ">=", "threshold", 0)).passed(), "information: always passes");
        assertThrows(IllegalArgumentException.class, () -> run("tableCustomSQLQuery", null, Map.of("sqlExpression",
            "SELECT id, hours FROM ward.stays", "strategy", "COUNT")), "COUNT wants one number");
    }

    @Test
    void customSqlRunsReadOnly() throws Exception {
        try (Connection c = dataSource.getConnection()) {
            SQLException refused = assertThrows(SQLException.class, () -> Quality.readOnly(c, () -> {
                try (Statement s = c.createStatement()) {
                    return s.executeUpdate("delete from ward.stays");
                }
            }));
            assertTrue(refused.getMessage().contains("read-only"), refused.getMessage());
            assertTrue(c.getAutoCommit(), "the connection is as it was");
            try (Statement s = c.createStatement(); var r = s.executeQuery("select count(*) from ward.stays")) {
                r.next();
                assertEquals(4, r.getInt(1), "nothing deleted");
            }
            String timeout = Quality.readOnly(c, () -> {
                try (Statement s = c.createStatement(); var r = s.executeQuery("show statement_timeout")) {
                    r.next();
                    return r.getString(1);
                }
            });
            assertEquals(Quality.TIMEOUT + "s", timeout);
        }
    }
}
