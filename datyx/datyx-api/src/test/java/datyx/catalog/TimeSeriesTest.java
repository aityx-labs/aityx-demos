package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Types;
import java.util.List;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import org.junit.jupiter.api.Test;

/** The TimeSeries vocabulary read from, and written to, OpenMetadata's tables; no server. */
class TimeSeriesTest {

    private final ObjectMapper json = new ObjectMapper();

    /** OpenMetadata's admissions_hourly as GET /tables answers it, tagged as the HealthHub demo tags it. */
    private JsonNode hourly(String extension) throws Exception {
        return json.readTree("""
            {"id":"t-1","name":"admissions_hourly","fullyQualifiedName":"datyx-ds-1.healthhub.public.admissions_hourly",
             "databaseSchema":{"name":"public"},
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.SeriesKey"}]},
              {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"TimeSeries.SeriesKey"},{"tagFQN":"TimeSeries.StaticCategorical"},{"tagFQN":"PII.None"}]},
              {"name":"hospital_name","dataType":"TEXT","tags":[]},
              {"name":"hour_start","dataType":"TIMESTAMP","tags":[{"tagFQN":"TimeSeries.Timestamp"}]},
              {"name":"admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.Target"}]},
              {"name":"acute_admissions","dataType":"INT"}
             ],
             "extension":%s}
            """.formatted(extension));
    }

    @Test
    void readsATaggedTableAsASeries() throws Exception {
        TimeSeries.Spec spec = TimeSeries.spec(hourly("{\"timeSeriesFrequency\":\"1h\",\"timeSeriesMissing\":\"zero\"}"), "default");
        assertTrue(spec.ready(), spec.problems().toString());
        assertEquals("hour_start", spec.timestamp());
        assertEquals("admissions", spec.target());
        assertEquals(List.of("run_id", "hospital_id"), spec.seriesKey());
        assertEquals(List.of("hospital_id"), spec.staticCategorical());
        assertEquals("1h", spec.frequency());
        assertEquals("zero", spec.missing());
        assertEquals("public", spec.schema());
        assertEquals("default", spec.group());
        assertEquals("DeepAR", spec.algorithm(), "a group without an algorithm tag is DeepAR's");
        assertNull(spec.horizon());
    }

    /** HealthHub's patient_days, its care group tagged for XGBoost on the table, beside another tag of the table's. */
    private JsonNode patientDays(String tableTags, String extension) throws Exception {
        return json.readTree("""
            {"id":"t-2","name":"patient_days","fullyQualifiedName":"datyx-ds-1.healthhub.public.patient_days",
             "databaseSchema":{"name":"public"},
             "tags":%s,
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"person_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"day","dataType":"DATE","tags":[{"tagFQN":"TimeSeries.care.Timestamp"}]},
              {"name":"age","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.StaticReal"}]},
              {"name":"chronic_condition","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.StaticCategorical"}]},
              {"name":"visits","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.PastCovariate"}]},
              {"name":"stay_hours","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.Target"}]}
             ],
             "extension":%s}
            """.formatted(tableTags, extension));
    }

    @Test
    void readsAGroupsAlgorithmAndTheHorizonFromTheTable() throws Exception {
        JsonNode table = patientDays("[{\"tagFQN\":\"Tier.Tier2\"},{\"tagFQN\":\"TimeSeries.care.XGBoost\"}]",
            "{\"timeSeriesFrequency\":\"1D\",\"timeSeriesMissing\":\"zero\",\"timeSeriesHorizon\":\"30D\"}");
        List<TimeSeries.Spec> specs = TimeSeries.specs(table);
        assertEquals(1, specs.size());
        TimeSeries.Spec care = specs.get(0);
        assertTrue(care.ready(), care.problems().toString());
        assertEquals("care", care.group());
        assertEquals("XGBoost", care.algorithm());
        assertEquals("30D", care.horizon());
        assertEquals("stay_hours", care.target());
        assertEquals(List.of("run_id", "person_id"), care.seriesKey());
        assertEquals("TimeSeries.care.XGBoost", TimeSeries.Algorithm.XGBOOST.fqn("care"));
        assertEquals("TimeSeries.XGBoost", TimeSeries.Algorithm.XGBOOST.fqn("default"));
    }

    @Test
    void xgboostWantsAHorizonAndAGroupOneAlgorithm() throws Exception {
        TimeSeries.Spec noHorizon = TimeSeries.spec(patientDays("[{\"tagFQN\":\"TimeSeries.care.XGBoost\"}]",
            "{\"timeSeriesFrequency\":\"1D\",\"timeSeriesMissing\":\"zero\"}"), "care");
        assertEquals(List.of("the table has no timeSeriesHorizon, how far ahead XGBoost scores (such as 30D)"), noHorizon.problems());
        TimeSeries.Spec deepAr = TimeSeries.spec(patientDays("[]",
            "{\"timeSeriesFrequency\":\"1D\",\"timeSeriesHorizon\":\"a month\"}"), "care");
        assertEquals("DeepAR", deepAr.algorithm());
        assertEquals(List.of("timeSeriesHorizon 'a month' isn't a span such as 24h, 30D or 4W"), deepAr.problems());
        TimeSeries.Spec both = TimeSeries.spec(patientDays(
            "[{\"tagFQN\":\"TimeSeries.care.XGBoost\"},{\"tagFQN\":\"TimeSeries.care.DeepAR\"},{\"tagFQN\":\"TimeSeries.XGBoost\"}]",
            "{\"timeSeriesFrequency\":\"1D\",\"timeSeriesHorizon\":\"30D\"}"), "care");
        assertEquals(List.of("the table is tagged TimeSeries.care.XGBoost and TimeSeries.care.DeepAR; "
            + "one algorithm trains a group (tag another group for the other)"), both.problems());
    }

    @Test
    void aGroupWithOnlyItsAlgorithmIsASeriesToFix() throws Exception {
        JsonNode table = json.readTree("""
            {"name":"t","tags":[{"tagFQN":"TimeSeries.long.XGBoost"},{"tagFQN":"TimeSeries.Target.XGBoost"}],
             "columns":[{"name":"a","dataType":"INT","tags":[]}],"extension":{"timeSeriesFrequency":"1D","timeSeriesHorizon":"90D"}}
            """);
        assertEquals(List.of("long"), TimeSeries.groups(table), "a role can't be a group, even before an algorithm");
        assertEquals(List.of("no column is tagged TimeSeries.long.Timestamp, the time index",
            "no column is tagged TimeSeries.long.Target, the value to forecast"), TimeSeries.spec(table, "long").problems());
    }

    @Test
    void namesAlgorithms() {
        assertEquals(TimeSeries.Algorithm.XGBOOST, TimeSeries.Algorithm.named(" xgboost "));
        assertEquals(TimeSeries.Algorithm.DEEPAR, TimeSeries.Algorithm.named("DeepAR"));
        assertNull(TimeSeries.Algorithm.named(""));
        assertEquals("the algorithm is DeepAR or XGBoost, not 'Prophet'",
            assertThrows(IllegalArgumentException.class, () -> TimeSeries.Algorithm.named("Prophet")).getMessage());
    }

    @Test
    void rolesSetTheGroupsAlgorithmOnTheTableAndTheHorizon() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = json;
        JsonNode table = patientDays("[{\"tagFQN\":\"Tier.Tier2\"},{\"tagFQN\":\"TimeSeries.XGBoost\"}]",
            "{\"timeSeriesFrequency\":\"1D\",\"timeSeriesMissing\":\"zero\"}");
        Catalog.Roles roles = new Catalog.Roles("patient_days", "care", "day", "stay_hours", List.of("run_id", "person_id"),
            List.of("chronic_condition"), List.of("age"), null, List.of("visits"), "1D", "zero", "xgboost", "30D");
        JsonNode byPath = byPath(catalog.rolesPatch(table, roles));
        assertEquals(List.of("Tier.Tier2", "TimeSeries.XGBoost", "TimeSeries.care.XGBoost"), fqns(byPath.path("/tags")),
            "the care group's algorithm beside the table's other tags, the default group's too");
        assertEquals("{\"timeSeriesFrequency\":\"1D\",\"timeSeriesMissing\":\"zero\",\"timeSeriesHorizon\":\"30D\"}",
            byPath.path("/extension").toString());
        assertEquals(2, byPath.size(), "no column changes");

        JsonNode tagged = patientDays("[{\"tagFQN\":\"Tier.Tier2\"},{\"tagFQN\":\"TimeSeries.care.XGBoost\"}]",
            "{\"timeSeriesFrequency\":\"1D\",\"timeSeriesMissing\":\"zero\",\"timeSeriesHorizon\":\"30D\"}");
        assertTrue(catalog.rolesPatch(tagged, roles).isEmpty(), "nothing changes, nothing is patched");
        Catalog.Roles deepAr = new Catalog.Roles("patient_days", "care", "day", "stay_hours", List.of("run_id", "person_id"),
            List.of("chronic_condition"), List.of("age"), null, List.of("visits"), "1D", "zero", null, "30D");
        assertEquals(List.of("Tier.Tier2"), fqns(byPath(catalog.rolesPatch(tagged, deepAr)).path("/tags")),
            "no algorithm named: DeepAR, by its tag's absence");
        Catalog.Roles removed = new Catalog.Roles("patient_days", "care", null, null, null, null, null, null, null,
            "1D", "zero", "XGBoost", "30D");
        JsonNode emptied = byPath(catalog.rolesPatch(tagged, removed));
        assertEquals(List.of("Tier.Tier2"), fqns(emptied.path("/tags")), "a group without roles loses its algorithm too");
        assertEquals("[]", emptied.path("/columns/6/tags").toString());
        Catalog.Roles unknown = new Catalog.Roles("patient_days", "care", "day", null, null, null, null, null, null,
            null, null, "Prophet", null);
        assertThrows(IllegalArgumentException.class, () -> catalog.rolesPatch(tagged, unknown));
    }

    private JsonNode byPath(ArrayNode patch) {
        com.fasterxml.jackson.databind.node.ObjectNode byPath = json.createObjectNode();
        patch.forEach(op -> byPath.set(op.path("path").asText(), op.path("value")));
        return byPath;
    }

    /** admissions_hourly with two more groups: acute (ready, sharing the default's columns) and chronic (no Timestamp). */
    private JsonNode grouped() throws Exception {
        return json.readTree("""
            {"name":"admissions_hourly","columns":[
              {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"TimeSeries.SeriesKey"},{"tagFQN":"TimeSeries.acute.SeriesKey"},{"tagFQN":"TimeSeries.chronic.SeriesKey"}]},
              {"name":"hour_start","dataType":"TIMESTAMP","tags":[{"tagFQN":"TimeSeries.Timestamp"},{"tagFQN":"TimeSeries.acute.Timestamp"},{"tagFQN":"TimeSeries.acute"}]},
              {"name":"admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.Target"},{"tagFQN":"TimeSeries.acute.PastCovariate"}]},
              {"name":"acute_admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.chronic.Target"},{"tagFQN":"TimeSeries.acute.Target"}]},
              {"name":"chronic_admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.chronic.Target"},{"tagFQN":"Other.acute.Target"}]}],
             "extension":{"timeSeriesFrequency":"1h","timeSeriesMissing":"zero"}}
            """);
    }

    @Test
    void readsEachGroupAsASeriesOfItsOwn() throws Exception {
        List<TimeSeries.Spec> specs = TimeSeries.specs(grouped());
        assertEquals(List.of("default", "acute", "chronic"), specs.stream().map(TimeSeries.Spec::group).toList());
        TimeSeries.Spec admissions = specs.get(0);
        assertTrue(admissions.ready(), admissions.problems().toString());
        assertEquals("admissions", admissions.target());
        assertEquals(List.of(), admissions.pastCovariates());
        TimeSeries.Spec acute = specs.get(1);
        assertTrue(acute.ready(), acute.problems().toString());
        assertEquals("hour_start", acute.timestamp());
        assertEquals("acute_admissions", acute.target());
        assertEquals(List.of("hospital_id"), acute.seriesKey());
        assertEquals(List.of("admissions"), acute.pastCovariates());
        assertEquals("1h", acute.frequency());
        TimeSeries.Spec chronic = specs.get(2);
        assertFalse(chronic.ready());
        assertEquals(List.of("no column is tagged TimeSeries.chronic.Timestamp, the time index",
            "2 columns are tagged TimeSeries.chronic.Target (acute_admissions, chronic_admissions); one is the value to forecast"),
            chronic.problems());
    }

    @Test
    void namesGroups() {
        assertEquals("default", TimeSeries.group(null));
        assertEquals("default", TimeSeries.group(" default "));
        assertEquals("acute_2", TimeSeries.group("acute_2"));
        assertEquals("TimeSeries.acute.Target", TimeSeries.Role.TARGET.fqn("acute"));
        assertEquals("TimeSeries.Target", TimeSeries.Role.TARGET.fqn("default"));
        assertEquals("'target' is a role or an algorithm, so it can't name a group",
            assertThrows(IllegalArgumentException.class, () -> TimeSeries.group("target")).getMessage());
        assertThrows(IllegalArgumentException.class, () -> TimeSeries.group("xgboost"));
        assertThrows(IllegalArgumentException.class, () -> TimeSeries.group("a.b"));
        assertThrows(IllegalArgumentException.class, () -> TimeSeries.group("x".repeat(65)));
    }

    @Test
    void aGroupsRolesLeaveTheOtherGroupsAlone() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = json;
        Catalog.Roles roles = new Catalog.Roles("admissions_hourly", "acute", "hour_start", "acute_admissions",
            List.of("hospital_id"), null, null, null, null, "1h", "zero", null, null);
        ArrayNode patch = catalog.rolesPatch(grouped(), roles);
        JsonNode byPath = json.createObjectNode();
        patch.forEach(op -> ((com.fasterxml.jackson.databind.node.ObjectNode) byPath).set(op.path("path").asText(), op.path("value")));
        assertTrue(byPath.path("/columns/0/tags").isMissingNode(), "hospital_id stays the key of all three");
        assertTrue(byPath.path("/columns/1/tags").isMissingNode(), "hour_start stays the Timestamp");
        assertEquals(List.of("TimeSeries.Target"), fqns(byPath.path("/columns/2/tags")));
        assertTrue(byPath.path("/columns/3/tags").isMissingNode(), "acute_admissions stays the Target");
        assertTrue(byPath.path("/columns/4/tags").isMissingNode(), "another classification's tag isn't a group's");
        assertTrue(byPath.path("/extension").isMissingNode());
        assertEquals(1, patch.size());
    }

    @Test
    void saysWhatKeepsATableFromBeingASeries() throws Exception {
        JsonNode table = json.readTree("""
            {"name":"t","columns":[
              {"name":"at","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.Timestamp"}]},
              {"name":"a","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.Target"}]},
              {"name":"b","dataType":"INT","tags":[{"tagFQN":"TimeSeries.Target"},{"tagFQN":"TimeSeries.SeriesKey"}]},
              {"name":"c","dataType":"INT","tags":[{"tagFQN":"TimeSeries.KnownCovariate"},{"tagFQN":"TimeSeries.PastCovariate"}]}],
             "extension":{"timeSeriesFrequency":"hourly","timeSeriesMissing":"nothing"}}
            """);
        TimeSeries.Spec spec = TimeSeries.spec(table, "default");
        assertFalse(spec.ready());
        assertNull(spec.target());
        String problems = String.join("\n", spec.problems());
        assertTrue(problems.contains("the Timestamp column at is TEXT"), problems);
        assertTrue(problems.contains("2 columns are tagged TimeSeries.Target (a, b)"), problems);
        assertTrue(problems.contains("the Target column a is TEXT, not a number"), problems);
        assertTrue(problems.contains("b is the Target and can't also be SeriesKey"), problems);
        assertTrue(problems.contains("c is tagged both KnownCovariate and PastCovariate"), problems);
        assertTrue(problems.contains("'hourly' isn't a frequency"), problems);
        assertTrue(problems.contains("'nothing' is neither zero"), problems);
    }

    @Test
    void wantsAFrequencyAndTakesMissingRowsAsUnknown() throws Exception {
        TimeSeries.Spec spec = TimeSeries.spec(hourly("null"), "default");
        assertFalse(spec.ready());
        assertEquals(List.of("the table has no timeSeriesFrequency (such as 1h, 1D or 1W)"), spec.problems());
        assertEquals("unknown", spec.missing());
    }

    @Test
    void anUntaggedTableIsNoSeries() throws Exception {
        assertEquals(List.of("default"), TimeSeries.groups(hourly("null")));
        assertTrue(TimeSeries.groups(json.readTree("{\"columns\":[{\"name\":\"a\",\"tags\":[{\"tagFQN\":\"PII.None\"}]}]}")).isEmpty());
    }

    @Test
    void rolesReplaceTheTimeSeriesTagsAndKeepTheOthers() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = json;
        Catalog.Roles roles = new Catalog.Roles("admissions_hourly", null, "hour_start", "acute_admissions",
            List.of("hospital_id"), null, null, null, null, "1D", null, null, null);
        ArrayNode patch = catalog.rolesPatch(hourly("{\"timeSeriesFrequency\":\"1h\",\"timeSeriesMissing\":\"zero\",\"owner\":\"x\"}"), roles);
        JsonNode byPath = json.createObjectNode();
        patch.forEach(op -> ((com.fasterxml.jackson.databind.node.ObjectNode) byPath).set(op.path("path").asText(), op.path("value")));
        // run_id loses its role; hospital_id keeps SeriesKey and PII, loses StaticCategorical.
        assertEquals("[]", byPath.path("/columns/0/tags").toString());
        assertEquals(List.of("PII.None", "TimeSeries.SeriesKey"), fqns(byPath.path("/columns/1/tags")));
        assertTrue(byPath.path("/columns/2/tags").isMissingNode(), "an unchanged column isn't patched");
        assertTrue(byPath.path("/columns/3/tags").isMissingNode(), "hour_start stays the Timestamp");
        assertEquals("[]", byPath.path("/columns/4/tags").toString());
        assertEquals(List.of("TimeSeries.Target"), fqns(byPath.path("/columns/5/tags")));
        assertEquals("{\"timeSeriesFrequency\":\"1D\",\"owner\":\"x\"}", byPath.path("/extension").toString());
    }

    @Test
    void rolesNameColumnsTheTableHas() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = json;
        Catalog.Roles roles = new Catalog.Roles("admissions_hourly", null, "when", null, null, null, null, null, null, null, null, null, null);
        IllegalArgumentException e = assertThrows(IllegalArgumentException.class, () -> catalog.rolesPatch(hourly("null"), roles));
        assertEquals("admissions_hourly has no column when", e.getMessage());
    }

    @Test
    void aSyncKeepsWhatOpenMetadataSaysWhereTheSourceSaysNothing() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = json;
        SchemaReader.Table table = new SchemaReader.Table("public", "visits", "TABLE", null, List.of(
            new SchemaReader.Column("id", Types.INTEGER, "int4", 10, 0, false, null, 1),
            new SchemaReader.Column("note", Types.VARCHAR, "text", Integer.MAX_VALUE, 0, true, "From the source", 2),
            new SchemaReader.Column("at", Types.TIMESTAMP, "timestamp", 29, 6, true, null, 3)), List.of("id"));
        JsonNode known = json.readTree("""
            {"description":"Written in OpenMetadata","columns":[
              {"name":"id","description":"The visit"},{"name":"note","description":"Overwritten"},{"name":"at"}]}""");
        JsonNode body = catalog.tableBody("s.db.public", table, known);
        assertEquals("Written in OpenMetadata", body.path("description").asText());
        assertEquals("The visit", body.path("columns").get(0).path("description").asText());
        assertEquals("From the source", body.path("columns").get(1).path("description").asText());
        assertTrue(body.path("columns").get(2).path("description").isMissingNode());
        assertEquals("PRIMARY_KEY", body.path("columns").get(0).path("constraint").asText());
        assertEquals("TEXT", body.path("columns").get(1).path("dataType").asText());
        assertTrue(catalog.tableBody("s.db.public", table, null).path("description").isMissingNode());
    }

    @Test
    void mapsColumnTypes() {
        assertEquals("TEXT", ColumnTypes.of(Types.VARCHAR, "text"));
        assertEquals("VARCHAR", ColumnTypes.of(Types.VARCHAR, "varchar"));
        assertEquals("TIMESTAMPZ", ColumnTypes.of(Types.TIMESTAMP, "timestamptz"));
        assertEquals("TIMESTAMP", ColumnTypes.of(Types.TIMESTAMP, "timestamp"));
        assertEquals("INT", ColumnTypes.of(Types.INTEGER, "serial"));
        assertEquals("BOOLEAN", ColumnTypes.of(Types.BIT, "bool"));
        assertEquals("JSON", ColumnTypes.of(Types.OTHER, "jsonb"));
        assertEquals("DOUBLE", ColumnTypes.of(Types.DOUBLE, "float8"));
        assertEquals("UNKNOWN", ColumnTypes.of(Types.OTHER, "tsrange"));
    }

    @Test
    void quotesNamesWithDots() {
        assertEquals("datyx-ds-1.\"my.db\".public", Catalog.fqn("datyx-ds-1", "my.db", "public"));
    }

    private static List<String> fqns(JsonNode tags) {
        return java.util.stream.StreamSupport.stream(tags.spliterator(), false).map(t -> t.path("tagFQN").asText()).toList();
    }
}
