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
        TimeSeries.Spec spec = TimeSeries.spec(hourly("{\"timeSeriesFrequency\":\"1h\",\"timeSeriesMissing\":\"zero\"}"));
        assertTrue(spec.ready(), spec.problems().toString());
        assertEquals("hour_start", spec.timestamp());
        assertEquals("admissions", spec.target());
        assertEquals(List.of("run_id", "hospital_id"), spec.seriesKey());
        assertEquals(List.of("hospital_id"), spec.staticCategorical());
        assertEquals("1h", spec.frequency());
        assertEquals("zero", spec.missing());
        assertEquals("public", spec.schema());
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
        TimeSeries.Spec spec = TimeSeries.spec(table);
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
        TimeSeries.Spec spec = TimeSeries.spec(hourly("null"));
        assertFalse(spec.ready());
        assertEquals(List.of("the table has no timeSeriesFrequency (such as 1h, 1D or 1W)"), spec.problems());
        assertEquals("unknown", spec.missing());
    }

    @Test
    void anUntaggedTableIsNoSeries() throws Exception {
        assertTrue(TimeSeries.tagged(hourly("null")));
        assertFalse(TimeSeries.tagged(json.readTree("{\"columns\":[{\"name\":\"a\",\"tags\":[{\"tagFQN\":\"PII.None\"}]}]}")));
    }

    @Test
    void rolesReplaceTheTimeSeriesTagsAndKeepTheOthers() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = json;
        Catalog.Roles roles = new Catalog.Roles("admissions_hourly", "hour_start", "acute_admissions",
            List.of("hospital_id"), null, null, null, null, "1D", null);
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
        Catalog.Roles roles = new Catalog.Roles("admissions_hourly", "when", null, null, null, null, null, null, null, null);
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
