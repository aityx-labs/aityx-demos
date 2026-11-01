package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import datyx.catalog.Pii.Category;
import org.junit.jupiter.api.Test;

/**
 * Pii without a server: HealthHub's tables and topics classified by their
 * names, records of things and of counts holding no personal data, nested
 * fields, the tags written (a person's kept, datyx's replaced), and the
 * patch the catalogue sends (Catalog.classify).
 */
class PiiTest {

    private static final ObjectMapper JSON = new ObjectMapper();

    /** Columns by name, as OpenMetadata answers them. */
    private static ArrayNode columns(String... names) {
        ArrayNode columns = JSON.createArrayNode();
        for (String name : names) {
            columns.addObject().put("name", name);
        }
        return columns;
    }

    /** Each column's category, by name. */
    private static Map<String, Category> categories(String entity, ArrayNode items) {
        Map<String, Category> byName = new LinkedHashMap<>();
        Pii.labels(entity, items).forEach((pointer, label) ->
            byName.put(items.at("/" + pointer).path("name").asText(), label.category()));
        return byName;
    }

    @Test
    void splitsNamesIntoWords() {
        assertEquals(List.of("patient", "id"), Pii.words("patient_id"));
        assertEquals(List.of("home", "lat"), Pii.words("homeLat"));
        assertEquals(List.of("ip", "address"), Pii.words("IPAddress"));
        assertEquals(List.of("healthhub", "people", "moves"), Pii.words("healthhub.people.moves"));
        assertEquals(List.of("address", "1"), Pii.words("address1"));
    }

    @Test
    void classifiesAHealthCareRecord() {
        Map<String, Category> admissions = categories("admissions", columns("id", "event_id", "person_id",
            "person_name", "age", "sex", "occupation", "city", "condition_code", "condition_name", "visit",
            "visit_number", "complaint", "hospital_id", "hospital_name", "recorded_at"));
        Map<String, Category> expected = new LinkedHashMap<>();
        expected.put("id", Category.IDENTIFIER);
        expected.put("event_id", Category.IDENTIFIER);
        expected.put("person_id", Category.IDENTIFIER);
        expected.put("person_name", Category.DIRECT);
        expected.put("age", Category.QUASI);
        expected.put("sex", Category.QUASI);
        expected.put("occupation", Category.QUASI);
        expected.put("city", Category.QUASI);
        expected.put("condition_code", Category.SPECIAL);
        expected.put("condition_name", Category.SPECIAL);
        // Any fact of a health care record is health data (Recital 35).
        expected.put("visit", Category.SPECIAL);
        expected.put("visit_number", Category.IDENTIFIER);
        expected.put("complaint", Category.SPECIAL);
        expected.put("hospital_id", Category.IDENTIFIER);
        expected.put("hospital_name", Category.SPECIAL);
        expected.put("recorded_at", Category.SPECIAL);
        assertEquals(expected, admissions);

        // A patient's number is health data too; a key of something else isn't.
        Map<String, Category> visits = categories("patient_visits", columns("patient_id", "run_id", "day"));
        assertEquals(Category.SPECIAL, visits.get("patient_id"));
        assertEquals(Category.IDENTIFIER, visits.get("run_id"));
        assertEquals(Category.SPECIAL, visits.get("day"));
    }

    @Test
    void findsNoPersonInRecordsOfThingsOrOfCounts() {
        // A care center's phone and address are an organisation's (Recital 14).
        categories("care_centers", columns("id", "name", "address", "postal_code", "city", "latitude", "phone"))
            .values().forEach(c -> assertEquals(Category.NONE, c));
        categories("medical_conditions", columns("code", "name", "min_age", "female_share", "treatment"))
            .values().forEach(c -> assertEquals(Category.NONE, c));
        categories("admissions_hourly", columns("run_id", "hospital_id", "hour_start", "admissions"))
            .values().forEach(c -> assertEquals(Category.NONE, c));
        categories("healthhub.admissions.hourly", columns("hospital_name", "acute_admissions"))
            .values().forEach(c -> assertEquals(Category.NONE, c));
    }

    @Test
    void findsAPersonByAColumnThatNamesOne() {
        Map<String, Category> orders = categories("orders", columns("order_id", "customer_id", "customer_email",
            "total", "shipping_address", "store_address"));
        assertEquals(Category.IDENTIFIER, orders.get("customer_id"));
        assertEquals(Category.DIRECT, orders.get("customer_email"));
        assertEquals(Category.PERSONAL, orders.get("total"));
        assertEquals(Category.DIRECT, orders.get("shipping_address"));
        // The store's address is the store's.
        assertEquals(Category.PERSONAL, orders.get("store_address"));

        Map<String, Category> signups = categories("signups", columns("first_name", "date_of_birth", "religion",
            "ip_address", "criminal_record"));
        assertEquals(Category.DIRECT, signups.get("first_name"));
        assertEquals(Category.QUASI, signups.get("date_of_birth"));
        assertEquals(Category.SPECIAL, signups.get("religion"));
        assertEquals(Category.DIRECT, signups.get("ip_address"));
        assertEquals(Category.SPECIAL, signups.get("criminal_record"));

        categories("settings", columns("key", "value", "birth_rate", "parent_id"))
            .values().forEach(c -> assertEquals(Category.NONE, c));
    }

    @Test
    void classifiesNestedFieldsAndTheRecordsThatHoldThem() throws Exception {
        JsonNode fields = JSON.readTree("""
            [{"name":"id"},{"name":"name"},{"name":"lat"},{"name":"homeLon"},{"name":"hospitalName"},
             {"name":"conditionName"},{"name":"state"}]""");
        Map<String, Pii.Label> moves = Pii.labels("healthhub.people.moves", fields);
        assertEquals(Category.IDENTIFIER, moves.get("0").category());
        assertEquals(Category.DIRECT, moves.get("1").category());
        assertEquals(Category.DIRECT, moves.get("2").category());
        assertEquals(Category.DIRECT, moves.get("3").category());
        assertEquals(Category.PERSONAL, moves.get("4").category());
        assertEquals(Category.SPECIAL, moves.get("5").category());
        assertEquals(Category.PERSONAL, moves.get("6").category());

        // A topic of events: the patient record in it is about a person, the record holding it is as protected.
        JsonNode events = JSON.readTree("""
            [{"name":"type"},
             {"name":"patient","children":[{"name":"name"},{"name":"diagnosis"}]},
             {"name":"site","children":[{"name":"city"}]}]""");
        Map<String, Pii.Label> labels = Pii.labels("events", events);
        assertEquals(Category.NONE, labels.get("0").category());
        assertEquals(Category.DIRECT, labels.get("1/children/0").category());
        assertEquals(Category.SPECIAL, labels.get("1/children/1").category());
        assertEquals(Category.SPECIAL, labels.get("1").category());
        assertTrue(labels.get("1").reason().startsWith("holds health data"));
        assertEquals(Category.NONE, labels.get("2").category());
        assertEquals(Category.NONE, labels.get("2/children/0").category());
    }

    @Test
    void keepsAPersonsTagsAndReplacesDatyxs() throws Exception {
        Pii.Label direct = new Pii.Label(Category.DIRECT, "why");
        JsonNode before = JSON.readTree("""
            [{"tagFQN":"TimeSeries.SeriesKey","labelType":"Manual"},
             {"tagFQN":"PII.None","labelType":"Automated","reason":"old"},
             {"tagFQN":"PersonalData.SpecialCategory","labelType":"Manual"}]""");
        ArrayNode tags = Pii.tags(before, direct);
        assertEquals(3, tags.size());
        assertEquals("TimeSeries.SeriesKey", tags.get(0).path("tagFQN").asText());
        assertEquals("PersonalData.SpecialCategory", tags.get(1).path("tagFQN").asText());
        assertEquals("PII.Sensitive", tags.get(2).path("tagFQN").asText());
        assertEquals("Automated", tags.get(2).path("labelType").asText());
        assertEquals("why", tags.get(2).path("reason").asText());
        assertFalse(Pii.same(tags, before));
        assertTrue(Pii.same(Pii.tags(tags, direct), tags));

        // Not personal: PII.None, and datyx's PersonalData tag goes.
        ArrayNode none = Pii.tags(JSON.readTree("""
            [{"tagFQN":"PII.Sensitive","labelType":"Automated"},{"tagFQN":"PersonalData.Personal","labelType":"Automated"}]"""),
            new Pii.Label(Category.NONE, "not"));
        assertEquals(1, none.size());
        assertEquals("PII.None", none.get(0).path("tagFQN").asText());
    }

    @Test
    void patchesOnlyWhatChanged() throws Exception {
        Catalog catalog = new Catalog();
        catalog.json = JSON;
        ArrayNode items = columns("person_id", "diagnosis", "hospital_id");
        Catalog.Classified first = catalog.classify("patients", items, "/columns/");
        assertEquals(3, first.patch().size());
        assertEquals("/columns/1/tags", first.patch().get(1).path("path").asText());
        assertEquals(3, first.personal());
        assertEquals(1, first.special());
        // Once written, nothing to patch.
        for (JsonNode op : first.patch()) {
            int i = Integer.parseInt(op.path("path").asText().split("/")[2]);
            ((com.fasterxml.jackson.databind.node.ObjectNode) items.get(i)).set("tags", op.path("value"));
        }
        assertEquals(0, catalog.classify("patients", items, "/columns/").patch().size());

        JsonNode fields = JSON.readTree("[{\"name\":\"site\",\"children\":[{\"name\":\"patient_name\"}]}]");
        Catalog.Classified nested = catalog.classify("events", fields, "/messageSchema/schemaFields/");
        assertEquals("/messageSchema/schemaFields/0/children/0/tags", nested.patch().get(0).path("path").asText());
        assertEquals("/messageSchema/schemaFields/0/tags", nested.patch().get(1).path("path").asText());
        assertEquals(1, nested.personal());
    }
}
