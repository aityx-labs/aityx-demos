package datyx.catalog;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import com.fasterxml.jackson.databind.JsonNode;
import io.quarkus.runtime.annotations.RegisterForReflection;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.openmetadata.OpenMetadataClient;
import datyx.openmetadata.OpenMetadataSession;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

/**
 * A database source in OpenMetadata, the catalogue: datyx reads the
 * source's tables (SchemaReader) and writes them there as a database
 * service named datyx-ds-{id}, its database, schemas and tables, columns
 * and primary keys. No credentials go to OpenMetadata: datyx reads the
 * source, OpenMetadata only keeps what it read. A sync again updates
 * the same entities and keeps what people added in OpenMetadata (tags,
 * descriptions, owners); a table the source no longer has is
 * soft-deleted. The TimeSeries vocabulary (TimeSeries) is made with the
 * first sync, then read back from the tags to find the time series.
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
            List<String> removed) {
    }

    /** Reads the source and writes what it holds to OpenMetadata. */
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
        session.call(auth -> client.putDatabase(auth, json.createObjectNode()
            .put("name", access.database())
            .put("service", service)));
        Set<String> schemas = new LinkedHashSet<>();
        for (SchemaReader.Table table : tables) {
            if (schemas.add(table.schema())) {
                session.call(auth -> client.putDatabaseSchema(auth, json.createObjectNode()
                    .put("name", table.schema())
                    .put("database", database)));
            }
        }
        // What OpenMetadata has already: a PUT without a description clears
        // one, so the descriptions people wrote there are sent back where
        // the source has no comment.
        Map<String, JsonNode> known = new LinkedHashMap<>();
        for (JsonNode schema : schemasOf(database)) {
            for (JsonNode table : tablesOf(schema.path("fullyQualifiedName").asText(), "columns")) {
                known.put(table.path("fullyQualifiedName").asText(), table);
            }
        }
        int columns = 0;
        Set<String> present = new HashSet<>();
        for (SchemaReader.Table table : tables) {
            String schemaFqn = fqn(service, access.database(), table.schema());
            ObjectNode body = tableBody(schemaFqn, table, known.get(fqn(service, access.database(), table.schema(), table.name())));
            JsonNode put = session.call(auth -> client.putTable(auth, body));
            present.add(put.path("fullyQualifiedName").asText());
            columns += table.columns().size();
        }
        List<String> removed = new ArrayList<>();
        for (JsonNode table : known.values()) {
            String tableFqn = table.path("fullyQualifiedName").asText();
            if (!present.contains(tableFqn)) {
                session.run(auth -> client.deleteTable(auth, table.path("id").asText()));
                removed.add(tableFqn);
            }
        }
        LOG.infof("catalogue: %s synced, %d tables, %d columns, %d removed", service, tables.size(), columns, removed.size());
        return new Synced(service, database, List.copyOf(schemas), tables.size(), columns, removed);
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

    private static String described(String comment, String known) {
        if (comment != null && !comment.isBlank()) {
            return comment;
        }
        return known == null || known.isBlank() ? null : known;
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
     * default group when none), each role's columns, and the table's
     * frequency and missing rows, which its groups share.
     */
    public record Roles(String table, String group, String timestamp, String target, List<String> seriesKey,
            List<String> staticCategorical, List<String> staticReal, List<String> knownCovariates,
            List<String> pastCovariates, String frequency, String missing) {

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
     * group replaced, its other tags (other groups' too) kept; the frequency
     * and missing set when given and removed when not. An
     * IllegalArgumentException names columns the table doesn't have, or why
     * the group's name can't be one.
     */
    ArrayNode rolesPatch(JsonNode table, Roles roles) {
        String group = TimeSeries.group(roles.group());
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
        ObjectNode extension = table.path("extension").isObject()
            ? ((ObjectNode) table.path("extension")).deepCopy() : json.createObjectNode();
        setOrRemove(extension, TimeSeries.FREQUENCY, roles.frequency());
        setOrRemove(extension, TimeSeries.MISSING, roles.missing());
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

    /** Removes the source's service and everything under it from OpenMetadata; nothing when there is none. */
    public void forget(long sourceId) {
        try {
            JsonNode service = session.call(auth -> client.databaseService(auth, serviceName(sourceId)));
            session.run(auth -> client.deleteDatabaseService(auth, service.path("id").asText(), true, true));
        } catch (WebApplicationException e) {
            if (e.getResponse().getStatus() != 404) {
                throw e;
            }
        }
    }

    /** A group's tag, TimeSeries.{group}, and a child tag of it per role; nothing for the default group, whose roles are the classification's own. */
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
    }

    /** The TimeSeries classification, its tags and the table's two custom properties, made when missing. */
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
        JsonNode tableType = session.call(auth -> client.type(auth, "table", "customProperties"));
        Set<String> existing = new HashSet<>();
        tableType.path("customProperties").forEach(p -> existing.add(p.path("name").asText()));
        Map<String, String> wanted = new LinkedHashMap<>();
        wanted.put(TimeSeries.FREQUENCY, "How often a time series table's rows come, as a pandas offset: 15min, 1h, 1D, 1W, 1MS.");
        wanted.put(TimeSeries.MISSING, "What a missing row of a time series table means: zero (nothing happened, as with counts) or unknown (not observed).");
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
