package datyx.catalog;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.StreamReader.Field;
import datyx.datasource.DataSource.KafkaAccess;
import org.junit.jupiter.api.Test;

/**
 * StreamReader without a cluster: the fields learnt from records, and the
 * client settings; and a topic as the catalogue writes it (Catalog.topicBody).
 */
class StreamReaderTest {

    private static byte[] json(String text) {
        return text.getBytes(StandardCharsets.UTF_8);
    }

    @Test
    void learnsTheFieldsOfJsonRecords() {
        List<Field> fields = StreamReader.fields(List.of(json("""
            {"id":"a-1","age":55,"big":12345678901,"lat":-22.9,"ok":true,"condition":null,
             "where":{"city":"Rio","geo":{"lat":1.5}},"visits":[{"day":3}],"tags":["x"]}""")));
        assertEquals(List.of(
            new Field("id", "STRING", null),
            new Field("age", "INT", null),
            new Field("big", "LONG", null),
            new Field("lat", "DOUBLE", null),
            new Field("ok", "BOOLEAN", null),
            new Field("condition", "NULL", null),
            new Field("where", "RECORD", List.of(
                new Field("city", "STRING", null),
                new Field("geo", "RECORD", List.of(new Field("lat", "DOUBLE", null))))),
            new Field("visits", "ARRAY", List.of(new Field("day", "INT", null))),
            new Field("tags", "ARRAY", null)), fields);
    }

    @Test
    void mergesRecordsTheNewestFirst() {
        List<Field> fields = StreamReader.fields(java.util.Arrays.asList(
            json("{\"id\":\"a\",\"condition\":null,\"where\":{\"city\":\"Rio\"}}"),
            null,
            json("not json"),
            json("[1,2]"),
            json("{\"id\":7,\"condition\":\"flu\",\"where\":{\"state\":\"RJ\"},\"extra\":1}")));
        assertEquals(List.of(
            new Field("id", "STRING", null),
            new Field("condition", "STRING", null),
            new Field("where", "RECORD", List.of(new Field("city", "STRING", null), new Field("state", "STRING", null))),
            new Field("extra", "INT", null)), fields);
    }

    @Test
    void hasNoFieldsWithoutAJsonObject() {
        assertNull(StreamReader.fields(List.of(json("plain text"))));
        assertNull(StreamReader.fields(java.util.Arrays.asList((byte[]) null)));
    }

    @Test
    void signsInWithSaslOnlyWhenAsked() {
        Properties plain = StreamReader.clientConfig(new KafkaAccess("b:9092", "PLAINTEXT", null, null, null));
        assertEquals("b:9092", plain.get("bootstrap.servers"));
        assertEquals("PLAINTEXT", plain.get("security.protocol"));
        assertFalse(plain.containsKey("sasl.jaas.config"));

        Properties scram = StreamReader.clientConfig(
            new KafkaAccess("b:9092", "SASL_SSL", "SCRAM-SHA-256", "reader", "pa\"ss\\word"));
        assertEquals("SCRAM-SHA-256", scram.get("sasl.mechanism"));
        assertEquals("org.apache.kafka.common.security.scram.ScramLoginModule required username=\"reader\""
            + " password=\"pa\\\"ss\\\\word\";", scram.get("sasl.jaas.config"));
        Properties plainSasl = StreamReader.clientConfig(new KafkaAccess("b:9092", "SASL_PLAINTEXT", "PLAIN", "u", null));
        assertEquals("org.apache.kafka.common.security.plain.PlainLoginModule required username=\"u\" password=\"\";",
            plainSasl.get("sasl.jaas.config"));
    }

    @Test
    void writesATopicKeepingWhatPeopleAdded() throws Exception {
        ObjectMapper json = new ObjectMapper();
        Catalog catalog = new Catalog();
        catalog.json = json;
        JsonNode known = json.readTree("""
            {"fullyQualifiedName":"datyx-ds-1.\\"h.hourly\\"","description":"Hourly admissions",
             "messageSchema":{"schemaType":"JSON","schemaFields":[
               {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"PII.None"}]},
               {"name":"where","dataType":"RECORD","children":[{"name":"city","dataType":"STRING","description":"Where"}]}]}}""");
        StreamReader.Topic topic = new StreamReader.Topic("h.hourly", 3, 1, List.of("compact", "delete"), 86_400_000L, null,
            1_048_588, 1, Map.of("cleanup.policy", "compact,delete"), true, List.of(
                new Field("hospital_id", "INT", null),
                new Field("where", "RECORD", List.of(new Field("city", "STRING", null))),
                new Field("admissions", "INT", null)));
        JsonNode body = catalog.topicBody("datyx-ds-1", topic, known);
        assertEquals("h.hourly", body.path("name").asText());
        assertEquals("datyx-ds-1", body.path("service").asText());
        assertEquals(3, body.path("partitions").asInt());
        assertEquals("[\"compact\",\"delete\"]", body.path("cleanupPolicies").toString());
        assertEquals(86_400_000L, body.path("retentionTime").asLong());
        assertFalse(body.has("retentionSize"));
        assertEquals("Hourly admissions", body.path("description").asText());
        JsonNode fields = body.path("messageSchema").path("schemaFields");
        assertEquals("PII.None", fields.get(0).path("tags").get(0).path("tagFQN").asText());
        assertEquals("Where", fields.get(1).path("children").get(0).path("description").asText());
        assertEquals("admissions", fields.get(2).path("name").asText());
        assertEquals("integer", json.readTree(body.path("messageSchema").path("schemaText").asText())
            .path("properties").path("admissions").path("type").asText());

        // No record read this time: the schema OpenMetadata has stays.
        StreamReader.Topic empty = new StreamReader.Topic("h.hourly", 3, 1, List.of(), null, null, null, null, Map.of(),
            false, null);
        assertEquals(known.path("messageSchema"), catalog.topicBody("datyx-ds-1", empty, known).path("messageSchema"));
        assertFalse(catalog.topicBody("datyx-ds-1", empty, null).has("messageSchema"));
    }
}
