package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.Test;

/**
 * OpenMetadata's webhook as datyx reads it, no server: the signature, and
 * which groups a change event switched. The events are shaped as
 * OpenMetadata 2.0.7 posts them: the table as a JSON string in
 * {@code entity}, each change's tag labels as a JSON string.
 */
class CatalogEventsTest {

    private final ObjectMapper json = new ObjectMapper();

    private CatalogEvents events() {
        CatalogEvents events = new CatalogEvents();
        events.json = json;
        return events;
    }

    /** OpenMetadata's change event of a table: {@code change} its changeDescription's fields. */
    static ObjectNode event(ObjectMapper json, String service, String table, String change) throws Exception {
        String fqn = service + ".healthhub.public." + table;
        ObjectNode entity = json.createObjectNode()
            .put("id", "595eaee3-6e6f-4f71-a967-1e0408cf92f3")
            .put("name", table)
            .put("fullyQualifiedName", fqn)
            .put("version", 0.6)
            .put("updatedBy", "admin")
            .put("updatedAt", 1793531744149L);
        entity.putObject("service").put("type", "databaseService").put("name", service);
        entity.putObject("databaseSchema").put("name", "public");
        entity.putArray("tags");
        entity.putArray("columns");
        ObjectNode event = json.createObjectNode()
            .put("id", "bb6caf5b-ac24-4648-9ff6-2d9fc9143435")
            .put("eventType", "entityUpdated")
            .put("entityType", "table")
            .put("entityId", "595eaee3-6e6f-4f71-a967-1e0408cf92f3")
            .put("entityFullyQualifiedName", fqn)
            .put("previousVersion", 0.1)
            .put("currentVersion", 0.6)
            .put("userName", "admin")
            .put("timestamp", 1793531744149L);
        event.set("changeDescription", json.readTree(change));
        event.put("entity", json.writeValueAsString(entity));
        return event;
    }

    /** A change's tag labels as OpenMetadata writes them: a JSON string. */
    static String labels(ObjectMapper json, String... fqns) throws Exception {
        List<Map<String, String>> labels = java.util.Arrays.stream(fqns)
            .map(f -> Map.of("tagFQN", f, "source", "Classification", "labelType", "Manual", "state", "Confirmed")).toList();
        return json.writeValueAsString(json.writeValueAsString(labels));
    }

    @Test
    void readsTheGroupsAChangeSwitched() throws Exception {
        CatalogEvents events = events();
        // On: the chronic group's Disabled tag deleted from the table.
        List<CatalogEvents.TagSwitch> on = events.switches(event(json, "datyx-ds-1", "admissions_hourly",
            "{\"fieldsAdded\":[],\"fieldsUpdated\":[],\"fieldsDeleted\":[{\"name\":\"tags\",\"oldValue\":"
                + labels(json, "TimeSeries.chronic.Disabled") + "}],\"previousVersion\":0.5}"));
        assertEquals(1, on.size());
        CatalogEvents.TagSwitch s = on.get(0);
        assertEquals(1, s.sourceId());
        assertEquals("datyx-ds-1.healthhub.public.admissions_hourly", s.table());
        assertEquals("chronic", s.group());
        assertTrue(s.enabled());
        assertEquals("0.6", s.version());
        assertEquals("admin", s.by());
        assertEquals(Instant.ofEpochMilli(1793531744149L), s.at());
        assertEquals("bb6caf5b-ac24-4648-9ff6-2d9fc9143435:chronic", s.eventId());
        assertNotNull(s.entity(), "the table the event carries");
        assertEquals("admissions_hourly", s.entity().path("name").asText());

        // Off: Disabled tags added, the default group's and another's, beside an unrelated tag.
        List<CatalogEvents.TagSwitch> off = events.switches(event(json, "datyx-ds-12", "patient_days",
            "{\"fieldsAdded\":[{\"name\":\"tags\",\"newValue\":" + labels(json, "PII.None", "TimeSeries.Disabled", "TimeSeries.care.Disabled")
                + "}]}"));
        assertEquals(List.of("default", "care"), off.stream().map(CatalogEvents.TagSwitch::group).toList());
        assertTrue(off.stream().noneMatch(CatalogEvents.TagSwitch::enabled));
        assertEquals(12, off.get(0).sourceId());

        // Replaced in one go: one group on, another off; an algorithm's tag is no switch.
        List<CatalogEvents.TagSwitch> both = events.switches(event(json, "datyx-ds-1", "admissions_hourly",
            "{\"fieldsUpdated\":[{\"name\":\"tags\",\"oldValue\":" + labels(json, "TimeSeries.acute.Disabled", "Tier.Tier2")
                + ",\"newValue\":" + labels(json, "Tier.Tier2", "TimeSeries.chronic.Disabled", "TimeSeries.chronic.XGBoost") + "}]}"));
        assertEquals(2, both.size());
        assertEquals("acute", both.get(0).group());
        assertTrue(both.get(0).enabled());
        assertEquals("chronic", both.get(1).group());
        assertFalse(both.get(1).enabled());
    }

    @Test
    void otherChangesSwitchNothing() throws Exception {
        CatalogEvents events = events();
        String chronicOn = "{\"fieldsDeleted\":[{\"name\":\"tags\",\"oldValue\":" + labels(json, "TimeSeries.chronic.Disabled") + "}]}";
        assertTrue(events.switches(event(json, "datyx-ds-1", "admissions_hourly",
            "{\"fieldsAdded\":[{\"name\":\"tags\",\"newValue\":" + labels(json, "PII.None", "TimeSeries.XGBoost") + "}]}")).isEmpty(),
            "an unrelated tag, and an algorithm's");
        assertTrue(events.switches(event(json, "datyx-ds-1", "admissions_hourly",
            "{\"fieldsAdded\":[{\"name\":\"columns.day.tags\",\"newValue\":" + labels(json, "TimeSeries.Disabled") + "}]}")).isEmpty(),
            "a column's tag");
        assertTrue(events.switches(event(json, "datyx-events-scratch", "admissions_hourly", chronicOn)).isEmpty(),
            "another service's table");
        assertTrue(events.switches(event(json, "datyx-ds-1x", "admissions_hourly", chronicOn)).isEmpty());
        assertTrue(events.switches(event(json, "datyx-ds-07", "admissions_hourly", chronicOn)).isEmpty(),
            "datyx-ds-07 isn't source 7's service, datyx-ds-7");
        assertTrue(events.switches(event(json, "datyx-ds-007", "admissions_hourly", chronicOn)).isEmpty());
        ObjectNode elsewhere = event(json, "datyx-ds-7", "admissions_hourly", chronicOn)
            .put("entityFullyQualifiedName", "datyx-ds-8.healthhub.public.admissions_hourly");
        assertTrue(events.switches(elsewhere).isEmpty(), "a table that isn't its service's");
        ObjectNode noService = event(json, "datyx-ds-07", "admissions_hourly", chronicOn);
        noService.put("entity", "{}");
        assertTrue(events.switches(noService).isEmpty(), "datyx-ds-07 from the FQN alone");
        noService.put("entityFullyQualifiedName", "datyx-ds-7.healthhub.public.admissions_hourly");
        assertEquals(7, events.switches(noService).get(0).sourceId(), "datyx-ds-7 from the FQN alone");
        ObjectNode topic = event(json, "datyx-ds-1", "admissions_hourly", chronicOn).put("entityType", "topic");
        assertTrue(events.switches(topic).isEmpty(), "a topic");
        assertTrue(events.switches(event(json, "datyx-ds-1", "admissions_hourly",
            "{\"fieldsUpdated\":[{\"name\":\"tags\",\"oldValue\":" + labels(json, "TimeSeries.Disabled")
                + ",\"newValue\":" + labels(json, "TimeSeries.Disabled", "Tier.Tier1") + "}]}")).isEmpty(), "still off");
        assertTrue(events.switches(event(json, "datyx-ds-1", "admissions_hourly",
            "{\"fieldsDeleted\":[{\"name\":\"tags\",\"oldValue\":\"not json\"}]}")).isEmpty());
    }

    @Test
    void checksOpenMetadatasSignature() {
        byte[] secret = "a-secret".getBytes(StandardCharsets.UTF_8);
        byte[] body = "{\"eventType\":\"entityUpdated\"}".getBytes(StandardCharsets.UTF_8);
        String signature = CatalogEvents.sign(secret, body);
        assertTrue(signature.startsWith("sha256="));
        assertTrue(CatalogEvents.verify(secret, body, signature));
        assertFalse(CatalogEvents.verify(secret, body, null), "missing");
        assertFalse(CatalogEvents.verify(secret, body, ""));
        assertFalse(CatalogEvents.verify(secret, body, signature.substring("sha256=".length())), "no sha256= prefix");
        assertFalse(CatalogEvents.verify("another".getBytes(StandardCharsets.UTF_8), body, signature), "another secret");
        assertFalse(CatalogEvents.verify(secret, "{}".getBytes(StandardCharsets.UTF_8), signature), "another body");
        // As OpenMetadata 2.0.7 signs: sha256= and the HMAC's base64, not hex (Python's hmac agrees).
        assertEquals("sha256=SrzXXxO1OtthZLE3adGr2Aw6tUY3/qvFJ2YqrNNItxc=",
            CatalogEvents.sign("probe".getBytes(StandardCharsets.UTF_8), "{}".getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    void letsOpenMetadataReachAnApiOnLocalhost() {
        String callback = "http://host.docker.internal:9900/api/catalog/openmetadata-events";
        assertEquals("localhost,127.0.0.1,[::1],host.docker.internal", CallbackHostConfigSourceFactory.allowedHosts("localhost", callback));
        assertEquals("localhost,127.0.0.1,[::1],host.docker.internal", CallbackHostConfigSourceFactory.allowedHosts("127.0.0.1", callback));
        assertEquals(null, CallbackHostConfigSourceFactory.allowedHosts("0.0.0.0", callback), "every interface: Quarkus checks no host");
        assertEquals(null, CallbackHostConfigSourceFactory.allowedHosts("localhost", null), "no webhook");
        assertEquals(null, CallbackHostConfigSourceFactory.allowedHosts("localhost", "http://localhost:9900/x"), "a localhost name already");
    }

    @Test
    void asksOpenMetadataForTablesUpdatesSigned() {
        JsonNode body = events().subscriptionBody("datyx-catalog-events", "http://host.docker.internal:9900/api/catalog/openmetadata-events",
            "s3cret".getBytes(StandardCharsets.UTF_8));
        assertEquals("datyx-catalog-events", body.path("name").asText());
        assertEquals("Notification", body.path("alertType").asText());
        assertEquals("[\"table\"]", body.path("resources").toString());
        assertEquals("filterByEventType", body.path("input").path("filters").get(0).path("name").asText());
        assertEquals("[\"entityUpdated\"]", body.path("input").path("filters").get(0).path("arguments").get(0).path("input").toString());
        JsonNode destination = body.path("destinations").get(0);
        assertEquals("Webhook", destination.path("type").asText());
        assertEquals("http://host.docker.internal:9900/api/catalog/openmetadata-events", destination.path("config").path("endpoint").asText());
        assertEquals("bearer", destination.path("config").path("authType").path("type").asText());
        assertEquals("s3cret", destination.path("config").path("authType").path("secretKey").asText());
    }
}
