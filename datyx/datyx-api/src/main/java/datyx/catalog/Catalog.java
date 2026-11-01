package datyx.catalog;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.runtime.annotations.RegisterForReflection;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import datyx.datasource.DataSource;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.datasource.DataSource.KafkaAccess;
import datyx.openmetadata.OpenMetadataClient;
import datyx.openmetadata.OpenMetadataSession;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

/**
 * A data source in OpenMetadata, the catalogue. A database: datyx reads
 * the source's tables (SchemaReader) and writes them there as a database
 * service named datyx-ds-{id}, its database, schemas and tables, columns
 * and primary keys. A Kafka cluster: datyx reads its topics
 * (StreamReader) and writes them as a messaging service of the same
 * name, its topics with their partitions, settings and the fields of
 * their records. No credentials go to OpenMetadata: datyx reads the
 * source, OpenMetadata only keeps what it read. A sync again updates
 * the same entities and keeps what people added in OpenMetadata (tags,
 * descriptions, owners); a table or topic the source no longer has is
 * soft-deleted. Every column and every field of a record, nested ones
 * too, gets a PII tag, and a PersonalData one when it holds personal
 * data in the GDPR's terms (Pii), from the names alone; a person's own
 * tags in those classifications win. The TimeSeries vocabulary
 * (TimeSeries) is made with the first sync, then read back from the
 * tags to find the time series.
 */
@ApplicationScoped
public class Catalog {

    private static final Logger LOG = Logger.getLogger(Catalog.class);

    private static final int PAGE = 100;

    @Inject
    @RestClient
    OpenMetadataClient client;

    @Inject
    OpenMetadataSession session;

    @Inject
    ObjectMapper json;

    /** The OpenMetadata service of a data source: datyx-ds-{id}, unique across profiles. */
    public static String serviceName(long sourceId) {
        return "datyx-ds-" + sourceId;
    }

    /** An OpenMetadata fully qualified name: the parts joined by dots, a part holding a dot in double quotes. */
    public static String fqn(String... parts) {
        List<String> quoted = new ArrayList<>();
        for (String part : parts) {
            quoted.add(part.contains(".") ? "\"" + part + "\"" : part);
        }
        return String.join(".", quoted);
    }

    @RegisterForReflection
    public record Synced(String service, String database, List<String> schemas, int tables, int columns,
            int personal, int special, int tests, int failed, List<String> failing, List<String> removed) {
    }

    /**
     * Reads the source and writes what it holds to OpenMetadata, then each
     * table's profile and the checks its schema implies, with their results
     * (Quality).
     */
    public Synced sync(long sourceId, String name, String description, DatabaseAccess access) throws SQLException {
        List<SchemaReader.Table> tables = SchemaReader.read(access);
        ensureVocabulary();
        String service = serviceName(sourceId);
        String database = fqn(service, access.database());
        ObjectNode serviceBody = json.createObjectNode()
            .put("name", service)
            .put("displayName", name)
            .put("serviceType", "Postgres");
        if (description != null) {
            serviceBody.put("description", description);
        }
        session.call(auth -> client.putDatabaseService(auth, serviceBody));
        ObjectNode databaseBody = json.createObjectNode()
            .put("name", access.database())
            .put("service", service);
        keep(databaseBody, find(auth -> client.database(auth, database, KEPT)));
        session.call(auth -> client.putDatabase(auth, databaseBody));
        Set<String> schemas = new LinkedHashSet<>();
        for (SchemaReader.Table table : tables) {
            if (schemas.add(table.schema())) {
                ObjectNode schemaBody = json.createObjectNode()
                    .put("name", table.schema())
                    .put("database", database);
                keep(schemaBody, find(auth -> client.databaseSchema(auth, fqn(service, access.database(), table.schema()), KEPT)));
                session.call(auth -> client.putDatabaseSchema(auth, schemaBody));
            }
        }
        // What OpenMetadata has already: a PUT without a description clears
        // one, so the descriptions people wrote there are sent back where
        // the source has no comment; it clears data products and the
        // certification too, which go back as they were.
        Map<String, JsonNode> known = new LinkedHashMap<>();
        for (JsonNode schema : schemasOf(database)) {
            for (JsonNode table : tablesOf(schema.path("fullyQualifiedName").asText(), "columns," + KEPT)) {
                known.put(table.path("fullyQualifiedName").asText(), table);
            }
        }
        int columns = 0;
        int personal = 0;
        int special = 0;
        int tests = 0;
        int failed = 0;
        List<String> failing = new ArrayList<>();
        Set<String> present = new HashSet<>();
        try (Connection c = SchemaReader.connect(access)) {
            for (SchemaReader.Table table : tables) {
                String schemaFqn = fqn(service, access.database(), table.schema());
                JsonNode before = known.get(fqn(service, access.database(), table.schema(), table.name()));
                ObjectNode body = tableBody(schemaFqn, table, before);
                JsonNode put = session.call(auth -> client.putTable(auth, body));
                present.add(put.path("fullyQualifiedName").asText());
                columns += table.columns().size();
                // A PUT merges tags, and PII's are mutually exclusive: a patch replaces them.
                Classified pii = classify(table.name(), put.path("columns"), "/columns/");
                restoreCertification(pii.patch(), before);
                if (!pii.patch().isEmpty()) {
                    session.call(auth -> client.patchTable(auth, put.path("id").asText(), pii.patch()));
                }
                personal += pii.personal();
                special += pii.special();
                Measured measured = measure(c, put, table, Quality.fromSchema(table));
                tests += measured.tests();
                failed += measured.failed();
                if (measured.failed() > 0) {
                    failing.add(put.path("fullyQualifiedName").asText());
                }
            }
        }
        List<String> removed = new ArrayList<>();
        for (JsonNode table : known.values()) {
            String tableFqn = table.path("fullyQualifiedName").asText();
            if (!present.contains(tableFqn)) {
                session.run(auth -> client.deleteTable(auth, table.path("id").asText()));
                removed.add(tableFqn);
            }
        }
        LOG.infof("catalogue: %s synced, %d tables, %d columns (%d personal, %d special category), %d checks (%d failed), %d removed",
            service, tables.size(), columns, personal, special, tests, failed, removed.size());
        return new Synced(service, database, List.copyOf(schemas), tables.size(), columns, personal, special, tests,
            failed, failing, removed);
    }

    /** The fields of an entity a PUT would lose, read before it to be sent back. */
    static final String KEPT = "certification,dataProducts,domains";

    /** How many checks ran on a table, and how many of them failed. */
    public record Measured(int tests, int failed) {
    }

    /**
     * Profiles a table ({@code table}, as OpenMetadata answered its PUT)
     * and runs {@code checks} on it, writing the profile, each check as a
     * test case and its result to OpenMetadata.
     */
    public Measured measure(Connection c, JsonNode table, SchemaReader.Table source, List<Quality.Check> checks)
            throws SQLException {
        Quality.Profile profile = Quality.profile(c, source);
        session.call(auth -> client.putTableProfile(auth, table.path("id").asText(),
            Quality.profileBody(profile, System.currentTimeMillis())));
        return check(c, table, source, checks);
    }

    /** Runs {@code checks} on a table, writing each as a test case and its result to OpenMetadata. */
    public Measured check(Connection c, JsonNode table, SchemaReader.Table source, List<Quality.Check> checks)
            throws SQLException {
        long now = System.currentTimeMillis();
        String tableFqn = table.path("fullyQualifiedName").asText();
        int failed = 0;
        for (Quality.Check check : checks) {
            Quality.Result result = Quality.evaluate(c, source, check);
            session.call(auth -> client.putTestCase(auth, Quality.testCase(tableFqn, check)));
            session.call(auth -> client.addTestCaseResult(auth, Quality.testCaseFqn(tableFqn, check),
                Quality.testResult(result, now)));
            if (!result.passed()) {
                failed++;
                LOG.infof("catalogue: %s failed %s: %s", tableFqn, check.name(), result.result());
            }
        }
        return new Measured(checks.size(), failed);
    }

    /** An entity OpenMetadata has, or null when it has none of the name (404). */
    JsonNode find(Function<String, JsonNode> get) {
        try {
            return session.call(get);
        } catch (WebApplicationException e) {
            if (e.getResponse().getStatus() == 404) {
                return null;
            }
            throw e;
        }
    }

    /**
     * Sends back in a create request what OpenMetadata has ({@code known},
     * null for a new entity) and the request doesn't say: the description
     * and the data products, which a PUT would clear, with the domains
     * they must match.
     */
    static void keep(ObjectNode body, JsonNode known) {
        if (known == null) {
            return;
        }
        String description = known.path("description").asText(null);
        if (!body.hasNonNull("description") && description != null && !description.isBlank()) {
            body.put("description", description);
        }
        if (known.path("dataProducts").isArray() && !known.path("dataProducts").isEmpty()) {
            ArrayNode products = body.putArray("dataProducts");
            known.path("dataProducts").forEach(p -> products.add(p.path("fullyQualifiedName").asText()));
        }
        if (known.path("domains").isArray() && !known.path("domains").isEmpty()) {
            ArrayNode domains = body.putArray("domains");
            known.path("domains").forEach(d -> domains.add(d.path("fullyQualifiedName").asText()));
        }
    }

    /** Adds to {@code patch} the certification {@code known} had, which a PUT clears. */
    static void restoreCertification(ArrayNode patch, JsonNode known) {
        if (known != null && known.path("certification").path("tagLabel").isObject()) {
            patch.addObject().put("op", "add").put("path", "/certification").set("value", known.path("certification"));
        }
    }

    /**
     * A table as OpenMetadata's create request wants it. A description is
     * the source's comment, else what OpenMetadata already has
     * ({@code known}, null for a new table): the source's comment wins.
     */
    ObjectNode tableBody(String schemaFqn, SchemaReader.Table table, JsonNode known) {
        Map<String, String> knownColumns = new LinkedHashMap<>();
        if (known != null) {
            known.path("columns").forEach(c -> knownColumns.put(c.path("name").asText(), c.path("description").asText(null)));
        }
        ObjectNode body = json.createObjectNode()
            .put("name", table.name())
            .put("databaseSchema", schemaFqn)
            .put("tableType", switch (table.type()) {
                case "VIEW" -> "View";
                case "MATERIALIZED VIEW" -> "MaterializedView";
                case "PARTITIONED TABLE" -> "Partitioned";
                default -> "Regular";
            });
        String description = described(table.comment(), known == null ? null : known.path("description").asText(null));
        if (description != null) {
            body.put("description", description);
        }
        keep(body, known);
        ArrayNode columns = body.putArray("columns");
        for (SchemaReader.Column column : table.columns()) {
            String type = ColumnTypes.of(column.jdbcType(), column.typeName());
            ObjectNode c = columns.addObject()
                .put("name", column.name())
                .put("dataType", type)
                .put("dataTypeDisplay", column.typeName())
                .put("ordinalPosition", column.position());
            if (ColumnTypes.hasLength(type)) {
                // A length JDBC doesn't know (varchar without one) is reported huge or zero.
                c.put("dataLength", column.size() > 0 && column.size() < Integer.MAX_VALUE ? column.size() : 1);
            }
            if ("ARRAY".equals(type)) {
                c.put("arrayDataType", "UNKNOWN");
            }
            if (table.primaryKey().size() == 1 && table.primaryKey().contains(column.name())) {
                c.put("constraint", "PRIMARY_KEY");
            } else if (!column.nullable()) {
                c.put("constraint", "NOT_NULL");
            }
            String columnDescription = described(column.comment(), knownColumns.get(column.name()));
            if (columnDescription != null) {
                c.put("description", columnDescription);
            }
        }
        if (table.primaryKey().size() > 1) {
            ArrayNode key = body.putArray("tableConstraints").addObject()
                .put("constraintType", "PRIMARY_KEY")
                .putArray("columns");
            table.primaryKey().forEach(key::add);
        }
        return body;
    }

    /**
     * A classification of a table's columns or a topic's fields (Pii): the
     * JSON Patch that gives each its PII and PersonalData tags, nothing for
     * those whose tags say so already, and how many of the top-level ones
     * hold personal data, and special category data, once patched.
     */
    record Classified(ArrayNode patch, int personal, int special) {
    }

    /** Classifies {@code items}, a table's columns or a topic's schemaFields as OpenMetadata answers them, found at {@code path}. */
    Classified classify(String entity, JsonNode items, String path) {
        ArrayNode patch = json.createArrayNode();
        int personal = 0;
        int special = 0;
        for (Map.Entry<String, Pii.Label> label : Pii.labels(entity, items).entrySet()) {
            JsonNode current = items.at("/" + label.getKey()).path("tags");
            ArrayNode tags = Pii.tags(current, label.getValue());
            if (!Pii.same(tags, current)) {
                patch.addObject().put("op", "add").put("path", path + label.getKey() + "/tags").set("value", tags);
            }
            if (!label.getKey().contains("/")) {
                Set<String> names = tagNames(tags);
                personal += names.stream().anyMatch(n -> n.startsWith(Pii.PERSONAL_DATA + ".")) ? 1 : 0;
                special += names.contains(Pii.Category.SPECIAL.personalData) ? 1 : 0;
            }
        }
        return new Classified(patch, personal, special);
    }

    private static String described(String comment, String known) {
        if (comment != null && !comment.isBlank()) {
            return comment;
        }
        return known == null || known.isBlank() ? null : known;
    }

    @RegisterForReflection
    public record StreamSynced(String service, int topics, int fields, int sampled, int personal, int special,
            List<String> removed) {
    }

    /** Reads a Kafka cluster and writes its topics to OpenMetadata. */
    public StreamSynced syncStream(long sourceId, String name, String description, KafkaAccess access)
            throws StreamReader.Unreadable {
        List<StreamReader.Topic> topics = StreamReader.read(access);
        String service = serviceName(sourceId);
        ObjectNode serviceBody = json.createObjectNode()
            .put("name", service)
            .put("displayName", name)
            .put("serviceType", "Kafka");
        if (description != null) {
            serviceBody.put("description", description);
        }
        session.call(auth -> client.putMessagingService(auth, serviceBody));
        // What OpenMetadata has already, to send back what people wrote
        // there (descriptions, field tags) and what no record says now.
        Map<String, JsonNode> known = new LinkedHashMap<>();
        for (JsonNode topic : topicsOf(service, "messageSchema,tags," + KEPT)) {
            known.put(topic.path("fullyQualifiedName").asText(), topic);
        }
        int fields = 0;
        int sampled = 0;
        int personal = 0;
        int special = 0;
        Set<String> present = new HashSet<>();
        for (StreamReader.Topic topic : topics) {
            JsonNode before = known.get(fqn(service, topic.name()));
            ObjectNode body = topicBody(service, topic, before);
            JsonNode put = session.call(auth -> client.putTopic(auth, body));
            present.add(put.path("fullyQualifiedName").asText());
            fields += topic.fields() == null ? 0 : topic.fields().size();
            sampled += topic.sampled() ? 1 : 0;
            Classified pii = classify(topic.name(), put.path("messageSchema").path("schemaFields"), "/messageSchema/schemaFields/");
            restoreCertification(pii.patch(), before);
            if (!pii.patch().isEmpty()) {
                session.call(auth -> client.patchTopic(auth, put.path("id").asText(), pii.patch()));
            }
            personal += pii.personal();
            special += pii.special();
        }
        List<String> removed = new ArrayList<>();
        for (JsonNode topic : known.values()) {
            String topicFqn = topic.path("fullyQualifiedName").asText();
            if (!present.contains(topicFqn)) {
                session.run(auth -> client.deleteTopic(auth, topic.path("id").asText()));
                removed.add(topicFqn);
            }
        }
        LOG.infof("catalogue: %s synced, %d topics, %d fields (%d personal, %d special category), %d removed",
            service, topics.size(), fields, personal, special, removed.size());
        return new StreamSynced(service, topics.size(), fields, sampled, personal, special, removed);
    }

    /**
     * A topic as OpenMetadata's create request wants it: its partitions and
     * settings, and the fields of its records as a JSON message schema.
     * With no record to read them from, the schema OpenMetadata has stays;
     * descriptions and tags people gave the topic or its fields stay too
     * ({@code known}, null for a new topic).
     */
    ObjectNode topicBody(String service, StreamReader.Topic topic, JsonNode known) {
        ObjectNode body = json.createObjectNode()
            .put("name", topic.name())
            .put("service", service)
            .put("partitions", Math.max(1, topic.partitions()))
            .put("replicationFactor", topic.replicationFactor());
        ArrayNode policies = body.putArray("cleanupPolicies");
        topic.cleanupPolicies().stream().filter(p -> p.equals("delete") || p.equals("compact")).forEach(policies::add);
        if (topic.retentionMs() != null) {
            body.put("retentionTime", topic.retentionMs());
        }
        if (topic.retentionBytes() != null) {
            body.put("retentionSize", topic.retentionBytes());
        }
        if (topic.maxMessageBytes() != null) {
            body.put("maximumMessageSize", topic.maxMessageBytes());
        }
        if (topic.minInSyncReplicas() != null) {
            body.put("minimumInSyncReplicas", topic.minInSyncReplicas());
        }
        ObjectNode config = body.putObject("topicConfig");
        topic.config().forEach(config::put);
        keep(body, known);
        if (topic.fields() != null) {
            Map<String, JsonNode> knownFields = new LinkedHashMap<>();
            if (known != null) {
                collectFields(known.path("messageSchema").path("schemaFields"), "", knownFields);
            }
            ObjectNode schema = body.putObject("messageSchema")
                .put("schemaType", "JSON")
                .put("schemaText", jsonSchema(topic.fields()).toString());
            schema.set("schemaFields", fieldsNode(topic.fields(), "", knownFields));
        } else if (known != null && known.path("messageSchema").isObject()) {
            body.set("messageSchema", known.path("messageSchema"));
        }
        return body;
    }

    private static void collectFields(JsonNode fields, String prefix, Map<String, JsonNode> into) {
        for (JsonNode field : fields) {
            String path = prefix + field.path("name").asText();
            into.put(path, field);
            collectFields(field.path("children"), path + ".", into);
        }
    }

    private ArrayNode fieldsNode(List<StreamReader.Field> fields, String prefix, Map<String, JsonNode> known) {
        ArrayNode array = json.createArrayNode();
        for (StreamReader.Field field : fields) {
            String path = prefix + field.name();
            ObjectNode node = array.addObject()
                .put("name", field.name())
                .put("dataType", field.dataType());
            JsonNode before = known.get(path);
            if (before != null) {
                String description = before.path("description").asText(null);
                if (description != null && !description.isBlank()) {
                    node.put("description", description);
                }
                if (before.path("tags").isArray() && !before.path("tags").isEmpty()) {
                    node.set("tags", before.path("tags"));
                }
            }
            if (field.children() != null) {
                node.set("children", fieldsNode(field.children(), path + ".", known));
            }
        }
        return array;
    }

    /** A JSON Schema of the fields, the message schema's text as OpenMetadata shows it. */
    ObjectNode jsonSchema(List<StreamReader.Field> fields) {
        ObjectNode schema = json.createObjectNode()
            .put("$schema", "http://json-schema.org/draft-07/schema#")
            .put("type", "object");
        schema.set("properties", properties(fields));
        return schema;
    }

    private ObjectNode properties(List<StreamReader.Field> fields) {
        ObjectNode properties = json.createObjectNode();
        for (StreamReader.Field field : fields) {
            ObjectNode property = properties.putObject(field.name());
            switch (field.dataType()) {
                case "RECORD" -> {
                    property.put("type", "object");
                    property.set("properties", properties(field.children()));
                }
                case "ARRAY" -> {
                    property.put("type", "array");
                    if (field.children() != null) {
                        property.putObject("items").put("type", "object").set("properties", properties(field.children()));
                    }
                }
                case "STRING" -> property.put("type", "string");
                case "INT", "LONG" -> property.put("type", "integer");
                case "DOUBLE" -> property.put("type", "number");
                case "BOOLEAN" -> property.put("type", "boolean");
                case "NULL" -> property.put("type", "null");
                default -> {
                }
            }
        }
        return properties;
    }

    /** A Kafka source's topics as OpenMetadata knows them, with their message schemas and tags; empty before a sync. */
    public List<JsonNode> topics(long sourceId) {
        String service = serviceName(sourceId);
        try {
            session.call(auth -> client.messagingService(auth, service));
        } catch (WebApplicationException e) {
            if (e.getResponse().getStatus() == 404) {
                return new ArrayList<>();
            }
            throw e;
        }
        return topicsOf(service, "messageSchema,tags");
    }

    /** A messaging service's topics with the fields asked for (messageSchema, tags, owners...). */
    public List<JsonNode> topics(String serviceFqn, String fields) {
        return topicsOf(serviceFqn, fields);
    }

    /** A synced database's tables, with their columns, tags, owners and certification. */
    public List<JsonNode> tablesOf(Synced synced) {
        List<JsonNode> tables = new ArrayList<>();
        for (String schema : synced.schemas()) {
            tables.addAll(tablesOf(synced.database() + "." + fqn(schema), "columns,tags,owners,certification"));
        }
        return tables;
    }

    private List<JsonNode> topicsOf(String serviceFqn, String fields) {
        List<JsonNode> topics = new ArrayList<>();
        String after = null;
        do {
            String cursor = after;
            JsonNode page = session.call(auth -> client.topics(auth, serviceFqn, fields, PAGE, cursor));
            page.path("data").forEach(topics::add);
            after = page.path("paging").path("after").asText(null);
        } while (after != null);
        return topics;
    }

    /** The source's tables as OpenMetadata knows them, with their columns, tags and custom properties; empty before a sync. */
    public List<JsonNode> tables(long sourceId) {
        String service = serviceName(sourceId);
        List<JsonNode> tables = new ArrayList<>();
        JsonNode found;
        try {
            found = session.call(auth -> client.databaseService(auth, service));
        } catch (WebApplicationException e) {
            if (e.getResponse().getStatus() == 404) {
                return tables;
            }
            throw e;
        }
        String serviceFqn = found.path("fullyQualifiedName").asText(service);
        for (JsonNode database : databasesOf(serviceFqn)) {
            for (JsonNode schema : schemasOf(database.path("fullyQualifiedName").asText())) {
                tables.addAll(tablesOf(schema.path("fullyQualifiedName").asText(), "columns,tags,extension,tableConstraints"));
            }
        }
        return tables;
    }

    private List<JsonNode> databasesOf(String serviceFqn) {
        List<JsonNode> databases = new ArrayList<>();
        String after = null;
        do {
            String cursor = after;
            JsonNode page = session.call(auth -> client.databases(auth, serviceFqn, PAGE, cursor));
            page.path("data").forEach(databases::add);
            after = page.path("paging").path("after").asText(null);
        } while (after != null);
        return databases;
    }

    private List<JsonNode> schemasOf(String databaseFqn) {
        List<JsonNode> schemas = new ArrayList<>();
        String after = null;
        do {
            String cursor = after;
            JsonNode page = session.call(auth -> client.databaseSchemas(auth, databaseFqn, PAGE, cursor));
            page.path("data").forEach(schemas::add);
            after = page.path("paging").path("after").asText(null);
        } while (after != null);
        return schemas;
    }

    private List<JsonNode> tablesOf(String schemaFqn, String fields) {
        List<JsonNode> tables = new ArrayList<>();
        String after = null;
        do {
            String cursor = after;
            JsonNode page = session.call(auth -> client.tables(auth, schemaFqn, fields, PAGE, cursor));
            page.path("data").forEach(tables::add);
            after = page.path("paging").path("after").asText(null);
        } while (after != null);
        return tables;
    }

    /**
     * What PUT /api/datasources/{id}/timeseries asks: a group's roles (the
     * default group when none), each role's columns, the algorithm that
     * trains on the group (none: DeepAR), and the table's frequency,
     * missing rows and horizon, which its groups share.
     */
    public record Roles(String table, String group, String timestamp, String target, List<String> seriesKey,
            List<String> staticCategorical, List<String> staticReal, List<String> knownCovariates,
            List<String> pastCovariates, String frequency, String missing, String algorithm, String horizon) {

        Map<TimeSeries.Role, List<String>> columns() {
            Map<TimeSeries.Role, List<String>> map = new LinkedHashMap<>();
            map.put(TimeSeries.Role.TIMESTAMP, timestamp == null ? List.of() : List.of(timestamp));
            map.put(TimeSeries.Role.TARGET, target == null ? List.of() : List.of(target));
            map.put(TimeSeries.Role.SERIES_KEY, seriesKey == null ? List.of() : seriesKey);
            map.put(TimeSeries.Role.STATIC_CATEGORICAL, staticCategorical == null ? List.of() : staticCategorical);
            map.put(TimeSeries.Role.STATIC_REAL, staticReal == null ? List.of() : staticReal);
            map.put(TimeSeries.Role.KNOWN_COVARIATE, knownCovariates == null ? List.of() : knownCovariates);
            map.put(TimeSeries.Role.PAST_COVARIATE, pastCovariates == null ? List.of() : pastCovariates);
            return map;
        }
    }

    /**
     * The JSON Patch that makes a table's TimeSeries tags of the group and
     * custom properties what {@code roles} says: every column's tags of the
     * group replaced, its other tags (other groups' too) kept; the group's
     * algorithm tag on the table replaced, none when no algorithm is named
     * or the group has no roles left; the frequency, missing and horizon set
     * when given and removed when not. An IllegalArgumentException names
     * columns the table doesn't have, an algorithm there isn't, or why the
     * group's name can't be one.
     */
    ArrayNode rolesPatch(JsonNode table, Roles roles) {
        String group = TimeSeries.group(roles.group());
        TimeSeries.Algorithm algorithm = TimeSeries.Algorithm.named(roles.algorithm());
        Map<String, List<TimeSeries.Role>> wanted = new LinkedHashMap<>();
        roles.columns().forEach((role, names) -> names.forEach(
            name -> wanted.computeIfAbsent(name, n -> new ArrayList<>()).add(role)));
        Set<String> unknown = new LinkedHashSet<>(wanted.keySet());
        ArrayNode patch = json.createArrayNode();
        JsonNode columns = table.path("columns");
        for (int i = 0; i < columns.size(); i++) {
            JsonNode column = columns.get(i);
            String name = column.path("name").asText();
            unknown.remove(name);
            ArrayNode tags = json.createArrayNode();
            for (JsonNode tag : column.path("tags")) {
                TimeSeries.Tagged tagged = TimeSeries.ofFqn(tag.path("tagFQN").asText());
                if (tagged == null || !tagged.group().equals(group)) {
                    tags.add(tag);
                }
            }
            for (TimeSeries.Role role : wanted.getOrDefault(name, List.of())) {
                tags.addObject()
                    .put("tagFQN", role.fqn(group))
                    .put("source", "Classification")
                    .put("labelType", "Manual")
                    .put("state", "Confirmed");
            }
            // By name, in any order: OpenMetadata's tags carry more than datyx writes.
            if (!tagNames(tags).equals(tagNames(column.path("tags")))) {
                patch.addObject().put("op", "add").put("path", "/columns/" + i + "/tags").set("value", tags);
            }
        }
        if (!unknown.isEmpty()) {
            throw new IllegalArgumentException(table.path("name").asText() + " has no column " + String.join(", ", unknown));
        }
        ArrayNode tableTags = json.createArrayNode();
        for (JsonNode tag : table.path("tags")) {
            TimeSeries.Trained trained = TimeSeries.algorithmOf(tag.path("tagFQN").asText());
            if (trained == null || !trained.group().equals(group)) {
                tableTags.add(tag);
            }
        }
        if (algorithm != null && !wanted.isEmpty()) {
            tableTags.addObject()
                .put("tagFQN", algorithm.fqn(group))
                .put("source", "Classification")
                .put("labelType", "Manual")
                .put("state", "Confirmed");
        }
        if (!tagNames(tableTags).equals(tagNames(table.path("tags")))) {
            patch.addObject().put("op", "add").put("path", "/tags").set("value", tableTags);
        }
        ObjectNode extension = table.path("extension").isObject()
            ? ((ObjectNode) table.path("extension")).deepCopy() : json.createObjectNode();
        setOrRemove(extension, TimeSeries.FREQUENCY, roles.frequency());
        setOrRemove(extension, TimeSeries.MISSING, roles.missing());
        setOrRemove(extension, TimeSeries.HORIZON, roles.horizon());
        JsonNode before = table.path("extension").isObject() ? table.path("extension") : json.createObjectNode();
        if (!extension.equals(before)) {
            patch.addObject().put("op", "add").put("path", "/extension").set("value", extension);
        }
        return patch;
    }

    private static Set<String> tagNames(JsonNode tags) {
        Set<String> names = new HashSet<>();
        tags.forEach(tag -> names.add(tag.path("tagFQN").asText()));
        return names;
    }

    private static void setOrRemove(ObjectNode extension, String property, String value) {
        if (value == null || value.isBlank()) {
            extension.remove(property);
        } else {
            extension.put(property, value.strip());
        }
    }

    /** Applies {@code roles} to one of the source's tables ({@link #rolesPatch}) and answers its group read again as a time series. */
    public TimeSeries.Spec applyRoles(JsonNode table, Roles roles) {
        String group = TimeSeries.group(roles.group());
        ArrayNode patch = rolesPatch(table, roles);
        ensureVocabulary();
        ensureGroup(group);
        String fqn = table.path("fullyQualifiedName").asText();
        if (!patch.isEmpty()) {
            session.call(auth -> client.patchTable(auth, table.path("id").asText(), patch));
        }
        return TimeSeries.spec(session.call(auth -> client.table(auth, fqn, "columns,tags,extension,tableConstraints")), group);
    }

    /** A table by its FQN, with its columns, tags, custom properties and constraints. */
    public JsonNode table(String fqn) {
        return session.call(auth -> client.table(auth, fqn, "columns,tags,extension,tableConstraints"));
    }

    /**
     * Sets how often the table's groups are trained again (its
     * timeSeriesRetrain), removing it for null or blank, which is the
     * default's; other properties stay. An IllegalArgumentException says
     * what isn't a span or never.
     */
    public void setRetrain(JsonNode table, String retrain) {
        String value = retrain == null || retrain.isBlank() ? null : retrain.strip();
        if (value != null && !TimeSeries.NEVER.equals(value) && Span.parse(value) == null) {
            throw new IllegalArgumentException("retrain is a span such as 6h, 1D or 1W, or never: not '" + value + "'");
        }
        ensureVocabulary();
        ObjectNode extension = table.path("extension").isObject()
            ? ((ObjectNode) table.path("extension")).deepCopy() : json.createObjectNode();
        setOrRemove(extension, TimeSeries.RETRAIN, value);
        if (!extension.equals(table.path("extension").isObject() ? table.path("extension") : json.createObjectNode())) {
            ArrayNode patch = json.createArrayNode();
            patch.addObject().put("op", "add").put("path", "/extension").set("value", extension);
            session.call(auth -> client.patchTable(auth, table.path("id").asText(), patch));
        }
    }

    /** Runs OpenMetadata's Data Insights now, so its reports (descriptions, owners, tiers covered) count the latest changes. */
    public void runInsights() {
        session.run(auth -> client.triggerApp(auth, "DataInsightsApplication", json.createObjectNode()));
    }

    /** Removes the source's service and everything under it from OpenMetadata; nothing when there is none. */
    public void forget(long sourceId, DataSource.Type type) {
        try {
            if (type == DataSource.Type.KAFKA) {
                JsonNode service = session.call(auth -> client.messagingService(auth, serviceName(sourceId)));
                session.run(auth -> client.deleteMessagingService(auth, service.path("id").asText(), true, true));
            } else {
                JsonNode service = session.call(auth -> client.databaseService(auth, serviceName(sourceId)));
                session.run(auth -> client.deleteDatabaseService(auth, service.path("id").asText(), true, true));
            }
        } catch (WebApplicationException e) {
            if (e.getResponse().getStatus() != 404) {
                throw e;
            }
        }
    }

    /**
     * A group's tag, TimeSeries.{group}, and a child tag of it per role and
     * per algorithm; nothing for the default group, whose roles and
     * algorithms are the classification's own.
     */
    void ensureGroup(String group) {
        if (TimeSeries.DEFAULT_GROUP.equals(group)) {
            return;
        }
        session.call(auth -> client.putTag(auth, json.createObjectNode()
            .put("name", group)
            .put("classification", TimeSeries.CLASSIFICATION)
            .put("description", "The roles of the time series dataset named " + group + ", one of a table's: a column tagged "
                + TimeSeries.Role.TARGET.fqn(group) + " is that dataset's Target, and so on.")));
        for (TimeSeries.Role role : TimeSeries.Role.values()) {
            session.call(auth -> client.putTag(auth, json.createObjectNode()
                .put("name", role.tag)
                .put("classification", TimeSeries.CLASSIFICATION)
                .put("parent", TimeSeries.CLASSIFICATION + "." + group)
                .put("description", role.description)));
        }
        for (TimeSeries.Algorithm algorithm : TimeSeries.Algorithm.values()) {
            session.call(auth -> client.putTag(auth, json.createObjectNode()
                .put("name", algorithm.tag)
                .put("classification", TimeSeries.CLASSIFICATION)
                .put("parent", TimeSeries.CLASSIFICATION + "." + group)
                .put("description", algorithm.description)));
        }
    }

    /** The TimeSeries classification, its role and algorithm tags and the table's custom properties, made when missing. */
    void ensureVocabulary() {
        session.call(auth -> client.putClassification(auth, json.createObjectNode()
            .put("name", TimeSeries.CLASSIFICATION)
            .put("description", TimeSeries.CLASSIFICATION_DESCRIPTION)
            .put("mutuallyExclusive", false)));
        for (TimeSeries.Role role : TimeSeries.Role.values()) {
            session.call(auth -> client.putTag(auth, json.createObjectNode()
                .put("name", role.tag)
                .put("classification", TimeSeries.CLASSIFICATION)
                .put("description", role.description)));
        }
        for (TimeSeries.Algorithm algorithm : TimeSeries.Algorithm.values()) {
            session.call(auth -> client.putTag(auth, json.createObjectNode()
                .put("name", algorithm.tag)
                .put("classification", TimeSeries.CLASSIFICATION)
                .put("description", algorithm.description)));
        }
        JsonNode tableType = session.call(auth -> client.type(auth, "table", "customProperties"));
        Set<String> existing = new HashSet<>();
        tableType.path("customProperties").forEach(p -> existing.add(p.path("name").asText()));
        Map<String, String> wanted = new LinkedHashMap<>();
        wanted.put(TimeSeries.FREQUENCY, "How often a time series table's rows come, as a pandas offset: 15min, 1h, 1D, 1W, 1MS.");
        wanted.put(TimeSeries.MISSING, "What a missing row of a time series table means: zero (nothing happened, as with counts) or unknown (not observed).");
        wanted.put(TimeSeries.HORIZON, "How far ahead a time series table's groups predict, as a pandas offset: 24h, 30D, 4W. "
            + "DeepAR forecasts each step of it; XGBoost scores the Target summed over it, and needs it.");
        wanted.put(TimeSeries.RETRAIN, "How often datyx trains a time series table's groups again: a span such as 6h, 1D or 1W, "
            + "or never (trained once). 1D when not set.");
        String stringType = null;
        for (Map.Entry<String, String> property : wanted.entrySet()) {
            if (existing.contains(property.getKey())) {
                continue;
            }
            if (stringType == null) {
                stringType = session.call(auth -> client.type(auth, "string", null)).path("id").asText();
            }
            ObjectNode body = json.createObjectNode()
                .put("name", property.getKey())
                .put("description", property.getValue());
            body.putObject("propertyType").put("id", stringType).put("type", "type");
            session.call(auth -> client.putCustomProperty(auth, tableType.path("id").asText(), body));
        }
    }
}
