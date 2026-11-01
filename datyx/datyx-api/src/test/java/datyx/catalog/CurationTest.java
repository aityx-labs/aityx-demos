package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import org.junit.jupiter.api.Test;

/**
 * Curation without a server: the tags written (another tier replaced,
 * terms added, other tags kept, nothing when they're there), what keeps
 * an entity from its certification, and HealthHub's document: it reads,
 * names terms its glossary has, and checks only what datyx runs; it and
 * the test fixture have every table and view HealthHub's API makes.
 */
class CurationTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    private static Curation curation() {
        Curation curation = new Curation();
        curation.json = JSON;
        return curation;
    }

    private static ArrayNode tags(String... fqns) {
        ArrayNode tags = JSON.createArrayNode();
        for (String fqn : fqns) {
            tags.addObject().put("tagFQN", fqn).put("labelType", "Automated");
        }
        return tags;
    }

    @Test
    void aTierReplacesAnotherAndTermsAreAdded() {
        ArrayNode patch = JSON.createArrayNode();
        curation().tagPatch(patch, "/tags", tags("PII.Sensitive", "Tier.Tier3"), "Tier.Tier1", List.of("Admission"), "HealthHub");
        assertEquals(1, patch.size());
        List<String> written = new ArrayList<>();
        patch.get(0).path("value").forEach(t -> written.add(t.path("tagFQN").asText()));
        assertEquals(List.of("PII.Sensitive", "Tier.Tier1", "HealthHub.Admission"), written);
        assertEquals("Glossary", patch.get(0).path("value").get(2).path("source").asText());
        assertEquals("Automated", patch.get(0).path("value").get(0).path("labelType").asText(), "a tag kept is kept as it was");
    }

    @Test
    void nothingIsPatchedWhenTheTagsAreThere() {
        ArrayNode patch = JSON.createArrayNode();
        curation().tagPatch(patch, "/columns/2/tags", tags("HealthHub.Admission", "PII.None"), null, List.of("Admission"), "HealthHub");
        assertTrue(patch.isEmpty());
    }

    @Test
    void aTermWithADotIsQuoted() {
        ArrayNode patch = JSON.createArrayNode();
        curation().tagPatch(patch, "/tags", tags(), null, List.of("v1.2"), "HealthHub");
        assertEquals("HealthHub.\"v1.2\"", patch.get(0).path("value").get(0).path("tagFQN").asText());
    }

    @Test
    void sayWhatIsUndescribed() throws Exception {
        JsonNode columns = JSON.readTree("[{\"name\":\"a\",\"description\":\"A.\"},{\"name\":\"b\"},{\"name\":\"c\",\"description\":\" \"}]");
        assertEquals("no description of the columns b, c", Curation.missing(JSON.readTree("\"T.\""), columns, "column"));
        assertEquals("no description; no description of the field b",
            Curation.missing(JSON.readTree("null"), JSON.readTree("[{\"name\":\"b\"}]"), "field"));
        assertEquals("", Curation.missing(JSON.readTree("\"T.\""), JSON.readTree("[{\"name\":\"a\",\"description\":\"A.\"}]"), "column"));
    }

    @Test
    void nestedFieldsAreFlattenedByPath() throws Exception {
        ArrayNode all = Curation.JsonFields.flatten(JSON.readTree(
            "[{\"name\":\"a\",\"children\":[{\"name\":\"b\",\"description\":\"B.\"}]}]"));
        assertEquals(2, all.size());
        assertEquals("a.b", all.get(1).path("name").asText());
    }

    @Test
    void healthHubsDocumentHolds() throws Exception {
        Curation.Doc doc;
        try (InputStream in = getClass().getClassLoader().getResourceAsStream(DevCatalog.DOCUMENT)) {
            doc = JSON.readValue(in, Curation.Doc.class);
        }
        List<String> terms = doc.glossary().terms().stream().map(Curation.Term::name).toList();
        doc.glossary().terms().forEach(t -> (t.related() == null ? List.<String>of() : t.related())
            .forEach(r -> assertTrue(terms.contains(r), t.name() + " relates to " + r + ", not a term")));
        doc.tables().forEach((table, c) -> {
            c.terms().forEach(t -> assertTrue(terms.contains(t), table + ": " + t));
            if (c.columns() != null) {
                c.columns().forEach((column, ts) -> ts.forEach(t -> assertTrue(terms.contains(t), table + "." + column + ": " + t)));
            }
            assertTrue(c.tier().startsWith("Tier.Tier"), table);
        });
        doc.topics().forEach((topic, c) -> {
            assertTrue(c.description() != null && !c.description().isBlank(), topic);
            c.terms().forEach(t -> assertTrue(terms.contains(t), topic + ": " + t));
        });
        List<String> entities = new ArrayList<>();
        doc.tables().keySet().forEach(t -> entities.add("table:" + t));
        doc.topics().keySet().forEach(t -> entities.add("topic:" + t));
        List<String> pipelines = doc.pipelines().stream().map(p -> p.service().name() + "." + p.name()).toList();
        for (Curation.Edge edge : doc.lineage()) {
            assertTrue(entities.contains(edge.from()), edge.from());
            assertTrue(entities.contains(edge.to()), edge.to());
            assertTrue(edge.pipeline() == null || pipelines.contains(edge.pipeline()), edge.pipeline());
        }
        doc.timeSeries().forEach(s -> assertTrue(doc.tables().containsKey(s.roles().table()), s.roles().table()));
        String all = JSON.writeValueAsString(JSON.readTree(getClass().getClassLoader().getResourceAsStream(DevCatalog.DOCUMENT)));
        assertTrue(!all.contains("—"), "no em dashes");
    }

    /** The relations an SQL text creates, by the names {@code pattern}'s first group catches. */
    private static Set<String> created(String sql, Pattern pattern) {
        Set<String> names = new TreeSet<>();
        Matcher m = pattern.matcher(sql);
        while (m.find()) {
            names.add(m.group(1));
        }
        return names;
    }

    /**
     * The document curates, and the fixture HealthHubChecksTest runs its
     * checks on has, every table and view HealthHub's API makes
     * (HealthHub/healthhub_api/lib/db.dart, beside datyx in this
     * repository; skipped when it isn't there): a table HealthHub adds
     * would otherwise be synced with its schema's checks only.
     */
    @Test
    void healthHubsDocumentAndFixtureHaveEveryTableHealthHubMakes() throws Exception {
        Path db = Path.of("../../HealthHub/healthhub_api/lib/db.dart");
        assumeTrue(Files.isRegularFile(db), "HealthHub isn't beside datyx");
        Set<String> healthHub = created(Files.readString(db),
            Pattern.compile("CREATE (?:TABLE IF NOT EXISTS|(?:OR REPLACE )?VIEW) (\\w+)"));
        assertTrue(healthHub.contains("admissions") && healthHub.contains("occupancy_hourly"), healthHub.toString());
        String fixture;
        try (InputStream in = getClass().getClassLoader().getResourceAsStream("catalog/healthhub-fixture.sql")) {
            fixture = new String(in.readAllBytes(), StandardCharsets.UTF_8);
        }
        assertEquals(healthHub, created(fixture, Pattern.compile("CREATE (?:TABLE|VIEW) (\\w+)")), "the fixture's");
        Curation.Doc doc;
        try (InputStream in = getClass().getClassLoader().getResourceAsStream(DevCatalog.DOCUMENT)) {
            doc = JSON.readValue(in, Curation.Doc.class);
        }
        Set<String> curated = new TreeSet<>();
        doc.tables().keySet().forEach(t -> curated.add(t.substring(t.indexOf('.') + 1)));
        assertEquals(healthHub, curated, "the document's");
    }
}
