package datyx.catalog;

import java.sql.Connection;
import java.sql.SQLException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.openmetadata.OpenMetadataClient;
import datyx.openmetadata.OpenMetadataSession;
import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

/**
 * What a data steward says in OpenMetadata about a customer's data,
 * beyond what the source says about itself, written by datyx from a
 * document (Doc): who owns it (a team), the business domain and data
 * product it belongs to, a glossary of its terms and the terms each
 * table, column and topic stands for, its tier, the descriptions a
 * database, a schema and Kafka topics don't carry, checks of its values
 * (Quality), the TimeSeries roles to start from, and where the data comes
 * from (lineage, through the pipelines that move it). Each curated table
 * gets a data contract,
 * once: its schema as it is then, its checks as the quality expected, the
 * owners and the terms of use; every curation then validates it (the
 * source's columns still the contract's, every check passing) and writes
 * the result, as OpenMetadata can't run the checks itself here. A curated
 * table or topic is certified when it earns it: described down to every column
 * or field, owned, tiered and, for a table, with every check passing;
 * otherwise datyx takes the certification off and says why. Applying it
 * again changes only what differs, and keeps what people added: other
 * tags stay, and roles are set only on a table with none of the group.
 * Development data uses it for HealthHub (DevCatalog).
 */
@ApplicationScoped
public class Curation {

    private static final Logger LOG = Logger.getLogger(Curation.class);

    /** How long a certification holds before OpenMetadata shows it expired; renewed at every curation. */
    static final Duration CERTIFIED_FOR = Duration.ofDays(365);

    /** A certification closer than this to expiring is renewed. */
    static final Duration RENEW_BEFORE = Duration.ofDays(30);

    @Inject
    @RestClient
    OpenMetadataClient client;

    @Inject
    OpenMetadataSession session;

    @Inject
    Catalog catalog;

    @Inject
    ObjectMapper json;

    @RegisterForReflection
    public record Doc(Sources sources, Named team, Domain domain, Named dataProduct, Glossary glossary,
            String certification, String termsOfUse, DatabaseCuration database, Map<String, TableCuration> tables,
            Map<String, TopicCuration> topics, List<Series> timeSeries, List<Pipeline> pipelines, List<Edge> lineage) {
    }

    /** The data sources the document is about, by name: a database and a Kafka cluster. */
    @RegisterForReflection
    public record Sources(String database, String kafka) {
    }

    @RegisterForReflection
    public record Named(String name, String displayName, String description) {
    }

    @RegisterForReflection
    public record Domain(String name, String displayName, String description, String domainType) {
    }

    @RegisterForReflection
    public record Glossary(String name, String displayName, String description, List<Term> terms) {
    }

    @RegisterForReflection
    public record Term(String name, String description, List<String> synonyms, List<String> related) {
    }

    /** The database's description and tier, its schemas' tier too, and each schema's description by name. */
    @RegisterForReflection
    public record DatabaseCuration(String description, String tier, Map<String, String> schemas) {
    }

    /** A table's tier, glossary terms, its columns' terms and its checks; by schema.table in the document. */
    @RegisterForReflection
    public record TableCuration(String tier, List<String> terms, Map<String, List<String>> columns,
            List<Quality.Check> checks) {
    }

    /** A topic's description, tier, terms and its fields' descriptions (a nested field by its dotted path); by name. */
    @RegisterForReflection
    public record TopicCuration(String description, String tier, List<String> terms, Map<String, String> fields) {
    }

    /** A group of TimeSeries roles to start a table with, as PUT .../timeseries takes it, and how often to retrain. */
    @RegisterForReflection
    public record Series(Catalog.Roles roles, String retrain) {
    }

    /** A pipeline of a pipeline service (Flink, Airflow...), its tasks by name and description. */
    @RegisterForReflection
    public record Pipeline(Named service, String serviceType, String name, String displayName, String description,
            String sourceUrl, String tier, Map<String, String> tasks) {
    }

    /**
     * Data flowing from an entity to another: each "table:schema.name",
     * "topic:name" or "pipeline:service.name", through a pipeline
     * ("service.name") or none.
     */
    @RegisterForReflection
    public record Edge(String from, String to, String pipeline, String description) {
    }

    /** What a curation found: the certified tables and topics, and those that aren't, with why. */
    @RegisterForReflection
    public record Applied(List<String> certified, Map<String, String> uncertified, int checks, int failed) {
    }

    /**
     * Applies {@code doc} to a database source and a Kafka source already
     * synced ({@code synced} and {@code streamService}), reading the
     * database again for the document's checks.
     */
    public Applied apply(Doc doc, Catalog.Synced synced, DatabaseAccess access, String streamService)
            throws SQLException {
        JsonNode team = session.call(auth -> client.putTeam(auth, json.createObjectNode()
            .put("name", doc.team().name())
            .put("displayName", doc.team().displayName())
            .put("description", doc.team().description())
            .put("teamType", "Group")));
        ArrayNode owners = json.createArrayNode();
        owners.addObject().put("id", team.path("id").asText()).put("type", "team");
        session.call(auth -> client.putDomain(auth, json.createObjectNode()
            .put("name", doc.domain().name())
            .put("displayName", doc.domain().displayName())
            .put("description", doc.domain().description())
            .put("domainType", doc.domain().domainType())));
        ObjectNode product = json.createObjectNode()
            .put("name", doc.dataProduct().name())
            .put("displayName", doc.dataProduct().displayName())
            .put("description", doc.dataProduct().description());
        product.putArray("domains").add(doc.domain().name());
        product.set("owners", owners);
        session.call(auth -> client.putDataProduct(auth, product));
        glossary(doc.glossary(), owners);

        List<ObjectNode> assets = new ArrayList<>();
        Map<String, JsonNode> entities = new LinkedHashMap<>();
        Map<String, String> uncertified = new LinkedHashMap<>();
        List<String> certified = new ArrayList<>();

        // The database service, its database and schemas: owners, descriptions, tier.
        JsonNode dbService = session.call(auth -> client.databaseService(auth, synced.service()));
        ownerPatch(dbService, owners).ifPresent(p -> session.call(auth -> client.patchDatabaseService(auth, dbService.path("id").asText(), p)));
        assets.add(asset(dbService, "databaseService"));
        JsonNode database = session.call(auth -> client.database(auth, synced.database(), "owners,tags"));
        ArrayNode dbPatch = json.createArrayNode();
        describe(dbPatch, database, doc.database().description());
        ownerPatch(database, owners).ifPresent(p -> dbPatch.addAll(p));
        tagPatch(dbPatch, "/tags", database.path("tags"), doc.database().tier(), List.of(), doc.glossary().name());
        if (!dbPatch.isEmpty()) {
            session.call(auth -> client.patchDatabase(auth, database.path("id").asText(), dbPatch));
        }
        assets.add(asset(database, "database"));
        for (String schemaName : synced.schemas()) {
            JsonNode schema = session.call(auth -> client.databaseSchema(auth,
                synced.database() + "." + Catalog.fqn(schemaName), "owners,tags"));
            ArrayNode patch = json.createArrayNode();
            describe(patch, schema, doc.database().schemas().get(schemaName));
            ownerPatch(schema, owners).ifPresent(p -> patch.addAll(p));
            tagPatch(patch, "/tags", schema.path("tags"), doc.database().tier(), List.of(), doc.glossary().name());
            if (!patch.isEmpty()) {
                session.call(auth -> client.patchDatabaseSchema(auth, schema.path("id").asText(), patch));
            }
            assets.add(asset(schema, "databaseSchema"));
        }

        // Tables: tier, terms, owners; the document's checks; roles; certification.
        int checks = 0;
        int failedChecks = 0;
        Set<String> failing = new HashSet<>(synced.failing());
        List<SchemaReader.Table> sourceTables = SchemaReader.read(access);
        try (Connection c = SchemaReader.connect(access)) {
            for (JsonNode table : catalog.tablesOf(synced)) {
                String key = table.path("databaseSchema").path("name").asText() + "." + table.path("name").asText();
                String tableFqn = table.path("fullyQualifiedName").asText();
                entities.put("table:" + key, table);
                assets.add(asset(table, "table"));
                TableCuration curation = doc.tables().get(key);
                if (curation == null) {
                    LOG.infof("curation: %s isn't in the document", tableFqn);
                    uncertified.put(tableFqn, "not curated");
                    continue;
                }
                ArrayNode patch = json.createArrayNode();
                ownerPatch(table, owners).ifPresent(p -> patch.addAll(p));
                tagPatch(patch, "/tags", table.path("tags"), curation.tier(), curation.terms(), doc.glossary().name());
                JsonNode columns = table.path("columns");
                for (int i = 0; i < columns.size(); i++) {
                    List<String> terms = curation.columns() == null ? null : curation.columns().get(columns.get(i).path("name").asText());
                    if (terms != null) {
                        tagPatch(patch, "/columns/" + i + "/tags", columns.get(i).path("tags"), null, terms, doc.glossary().name());
                    }
                }
                List<Quality.Check> tableChecks = curation.checks() == null ? List.of() : curation.checks();
                if (!tableChecks.isEmpty()) {
                    SchemaReader.Table source = sourceTables.stream()
                        .filter(t -> (t.schema() + "." + t.name()).equals(key)).findFirst().orElse(null);
                    if (source != null) {
                        Catalog.Measured measured = catalog.check(c, table, source, tableChecks);
                        checks += measured.tests();
                        failedChecks += measured.failed();
                        if (measured.failed() > 0) {
                            failing.add(tableFqn);
                        }
                    }
                }
                String why = missing(table.path("description"), columns, "column")
                    + (failing.contains(tableFqn) ? "; a check fails" : "")
                    + (curation.tier() == null ? "; no tier" : "");
                certify(patch, table, doc.certification(), why, certified, uncertified);
                if (!patch.isEmpty()) {
                    session.call(auth -> client.patchTable(auth, table.path("id").asText(), patch));
                }
            }
        }
        for (Series series : doc.timeSeries() == null ? List.<Series>of() : doc.timeSeries()) {
            JsonNode table = entities.get("table:" + series.roles().table());
            if (table == null) {
                LOG.warnf("curation: the time series table %s isn't in the catalogue", series.roles().table());
                continue;
            }
            JsonNode fresh = catalog.table(table.path("fullyQualifiedName").asText());
            String group = TimeSeries.group(series.roles().group());
            boolean hasGroup = TimeSeries.specs(fresh).stream().anyMatch(spec -> spec.group().equals(group));
            if (!hasGroup) {
                catalog.applyRoles(fresh, series.roles());
                LOG.infof("curation: %s group %s given its roles", series.roles().table(), group);
            }
            if (series.retrain() != null && fresh.path("extension").path(TimeSeries.RETRAIN).isMissingNode()) {
                catalog.setRetrain(catalog.table(table.path("fullyQualifiedName").asText()), series.retrain());
            }
        }

        // The Kafka service and its topics: owners, descriptions, tier, terms, certification.
        if (streamService != null) {
            JsonNode kafkaService = session.call(auth -> client.messagingService(auth, streamService));
            ownerPatch(kafkaService, owners).ifPresent(p -> session.call(auth -> client.patchMessagingService(auth, kafkaService.path("id").asText(), p)));
            assets.add(asset(kafkaService, "messagingService"));
            for (JsonNode topic : catalog.topics(streamService, "messageSchema,tags,owners,certification")) {
                String name = topic.path("name").asText();
                String topicFqn = topic.path("fullyQualifiedName").asText();
                entities.put("topic:" + name, topic);
                assets.add(asset(topic, "topic"));
                TopicCuration curation = doc.topics().get(name);
                if (curation == null) {
                    LOG.infof("curation: the topic %s isn't in the document", topicFqn);
                    uncertified.put(topicFqn, "not curated");
                    continue;
                }
                ArrayNode patch = json.createArrayNode();
                describe(patch, topic, curation.description());
                ownerPatch(topic, owners).ifPresent(p -> patch.addAll(p));
                tagPatch(patch, "/tags", topic.path("tags"), curation.tier(), curation.terms(), doc.glossary().name());
                // Judged as patched: the document's descriptions count.
                ObjectNode described = topic.deepCopy();
                if (curation.description() != null) {
                    described.put("description", curation.description());
                }
                describeFields(patch, described.path("messageSchema").path("schemaFields"), "/messageSchema/schemaFields/", "",
                    curation.fields() == null ? Map.of() : curation.fields());
                String why = missing(described.path("description"), JsonFields.flatten(described.path("messageSchema").path("schemaFields")), "field")
                    + (curation.tier() == null ? "; no tier" : "");
                certify(patch, topic, doc.certification(), why, certified, uncertified);
                if (!patch.isEmpty()) {
                    session.call(auth -> client.patchTopic(auth, topic.path("id").asText(), patch));
                }
            }
        }

        // Pipelines, then lineage between what the document names.
        for (Pipeline pipeline : doc.pipelines() == null ? List.<Pipeline>of() : doc.pipelines()) {
            session.call(auth -> client.putPipelineService(auth, json.createObjectNode()
                .put("name", pipeline.service().name())
                .put("displayName", pipeline.service().displayName())
                .put("description", pipeline.service().description())
                .put("serviceType", pipeline.serviceType())));
            ObjectNode body = json.createObjectNode()
                .put("name", pipeline.name())
                .put("displayName", pipeline.displayName())
                .put("description", pipeline.description())
                .put("service", pipeline.service().name());
            if (pipeline.sourceUrl() != null) {
                body.put("sourceUrl", pipeline.sourceUrl());
            }
            ArrayNode tasks = body.putArray("tasks");
            pipeline.tasks().forEach((task, description) -> tasks.addObject().put("name", task).put("description", description));
            JsonNode put = session.call(auth -> client.putPipeline(auth, body));
            ArrayNode pipelinePatch = json.createArrayNode();
            ownerPatch(put, owners).ifPresent(pipelinePatch::addAll);
            tagPatch(pipelinePatch, "/tags", put.path("tags"), pipeline.tier(), List.of(), doc.glossary().name());
            if (!pipelinePatch.isEmpty()) {
                session.call(auth -> client.patchPipeline(auth, put.path("id").asText(), pipelinePatch));
            }
            entities.put("pipeline:" + pipeline.service().name() + "." + pipeline.name(), put);
            assets.add(asset(put, "pipeline"));
        }
        for (Edge edge : doc.lineage() == null ? List.<Edge>of() : doc.lineage()) {
            JsonNode from = entities.get(edge.from());
            JsonNode to = entities.get(edge.to());
            if (from == null || to == null) {
                LOG.warnf("curation: lineage %s -> %s skipped, %s isn't in the catalogue", edge.from(), edge.to(),
                    from == null ? edge.from() : edge.to());
                continue;
            }
            ObjectNode body = json.createObjectNode();
            ObjectNode e = body.putObject("edge");
            e.set("fromEntity", ref(from, edge.from()));
            e.set("toEntity", ref(to, edge.to()));
            ObjectNode details = e.putObject("lineageDetails").put("description", edge.description()).put("source", "Manual");
            if (edge.pipeline() != null) {
                JsonNode pipeline = entities.get("pipeline:" + edge.pipeline());
                if (pipeline != null) {
                    details.set("pipeline", ref(pipeline, "pipeline:"));
                }
            }
            session.run(auth -> client.putLineage(auth, body));
        }

        // Each curated table's contract.
        int contractsKept = 0;
        for (Map.Entry<String, JsonNode> entity : entities.entrySet()) {
            if (entity.getKey().startsWith("table:") && doc.tables().containsKey(entity.getKey().substring(6))) {
                contractsKept += contract(entity.getValue(), owners, doc.termsOfUse()) ? 1 : 0;
            }
        }

        ObjectNode add = json.createObjectNode();
        ArrayNode list = add.putArray("assets");
        assets.forEach(list::add);
        session.call(auth -> client.addDomainAssets(auth, doc.domain().name(), add));
        ObjectNode addToProduct = json.createObjectNode();
        ArrayNode productAssets = addToProduct.putArray("assets");
        assets.stream().filter(a -> !a.path("type").asText().endsWith("Service")).forEach(productAssets::add);
        session.call(auth -> client.addDataProductAssets(auth, doc.dataProduct().name(), addToProduct));
        LOG.infof("curation: %s and %s curated, %d certified, %d not (%s), %d checks (%d failed), %d contracts kept",
            synced.service(), streamService, certified.size(), uncertified.size(), uncertified, checks, failedChecks,
            contractsKept);
        return new Applied(certified, uncertified, checks, failedChecks);
    }

    /** The column fields a contract's schema keeps. */
    private static final List<String> CONTRACT_COLUMN_FIELDS = List.of("name", "dataType", "dataTypeDisplay",
        "dataLength", "arrayDataType", "constraint", "ordinalPosition", "description");

    /**
     * The table's data contract, made the first time with the table's
     * schema as it is then, its test cases kept up to date as the quality
     * expected; then its result: kept when the source still has each of
     * the contract's columns with the same type and every test passes.
     */
    boolean contract(JsonNode table, ArrayNode owners, String termsOfUse) {
        String id = table.path("id").asText();
        String fqn = table.path("fullyQualifiedName").asText();
        String name = table.path("name").asText();
        JsonNode tests = session.call(auth -> client.testCases(auth, Quality.entityLink(fqn, null), true,
            "testCaseResult", 1000)).path("data");
        JsonNode existing = catalog.find(auth -> client.dataContractOf(auth, id, "table", "owners"));
        ObjectNode body = json.createObjectNode()
            .put("name", name)
            .put("description", "What " + name + " promises its readers: its columns as this contract lists them, "
                + "and every data quality test of the table passing. datyx checks it at every curation.")
            .put("entityStatus", "Approved");
        body.putObject("entity").put("id", id).put("type", "table");
        body.set("owners", owners);
        if (termsOfUse != null) {
            body.put("termsOfUse", termsOfUse);
        }
        if (existing != null && existing.path("schema").isArray() && !existing.path("schema").isEmpty()) {
            body.set("schema", existing.path("schema"));
        } else {
            ArrayNode schema = body.putArray("schema");
            for (JsonNode column : table.path("columns")) {
                ObjectNode c = schema.addObject();
                CONTRACT_COLUMN_FIELDS.stream().filter(column::has).forEach(f -> c.set(f, column.get(f)));
            }
        }
        ArrayNode expected = body.putArray("qualityExpectations");
        tests.forEach(t -> expected.addObject().put("id", t.path("id").asText()).put("type", "testCase"));
        JsonNode contract = session.call(auth -> client.putDataContract(auth, body));

        Map<String, String> columns = new LinkedHashMap<>();
        table.path("columns").forEach(c -> columns.put(c.path("name").asText(), c.path("dataType").asText()));
        List<String> missingColumns = new ArrayList<>();
        List<String> mismatched = new ArrayList<>();
        for (JsonNode column : contract.path("schema")) {
            String type = columns.get(column.path("name").asText());
            if (type == null) {
                missingColumns.add(column.path("name").asText());
            } else if (!type.equals(column.path("dataType").asText())) {
                mismatched.add(column.path("name").asText());
            }
        }
        int schemaTotal = contract.path("schema").size();
        int schemaFailed = missingColumns.size() + mismatched.size();
        int passed = 0;
        for (JsonNode test : tests) {
            passed += "Success".equals(test.path("testCaseResult").path("testCaseStatus").asText()) ? 1 : 0;
        }
        int failed = tests.size() - passed;
        boolean kept = schemaFailed == 0 && failed == 0;
        ObjectNode result = json.createObjectNode()
            .put("dataContractFQN", contract.path("fullyQualifiedName").asText())
            .put("timestamp", System.currentTimeMillis())
            .put("contractExecutionStatus", kept ? "Success" : "Failed")
            .put("result", kept ? "The source has every column of the contract, and all " + tests.size() + " tests pass."
                : schemaFailed + " of the contract's columns changed or missing, " + failed + " of " + tests.size()
                    + " tests not passing.");
        ObjectNode schemaValidation = result.putObject("schemaValidation")
            .put("passed", schemaTotal - schemaFailed).put("failed", schemaFailed).put("total", schemaTotal);
        missingColumns.forEach(schemaValidation.putArray("failedFields")::add);
        mismatched.forEach(schemaValidation.putArray("typeMismatchFields")::add);
        result.putObject("qualityValidation")
            .put("passed", passed).put("failed", failed).put("total", tests.size())
            .put("qualityScore", tests.isEmpty() ? 100.0 : 100.0 * passed / tests.size());
        session.call(auth -> client.putDataContractResult(auth, contract.path("id").asText(), result));
        if (!kept) {
            LOG.infof("curation: %s breaks its contract: %s", fqn, result.path("result").asText());
        }
        return kept;
    }

    /** The glossary and its terms, then each term's related terms (which must exist first). */
    private void glossary(Glossary glossary, ArrayNode owners) {
        ObjectNode body = json.createObjectNode()
            .put("name", glossary.name())
            .put("displayName", glossary.displayName())
            .put("description", glossary.description());
        body.set("owners", owners);
        session.call(auth -> client.putGlossary(auth, body));
        for (boolean related : new boolean[] {false, true}) {
            for (Term term : glossary.terms()) {
                if (related && (term.related() == null || term.related().isEmpty())) {
                    continue;
                }
                ObjectNode t = json.createObjectNode()
                    .put("glossary", glossary.name())
                    .put("name", term.name())
                    .put("description", term.description());
                ArrayNode synonyms = t.putArray("synonyms");
                (term.synonyms() == null ? List.<String>of() : term.synonyms()).forEach(synonyms::add);
                if (related) {
                    ArrayNode r = t.putArray("relatedTerms");
                    term.related().forEach(name -> r.add(Catalog.fqn(glossary.name(), name)));
                }
                session.call(auth -> client.putGlossaryTerm(auth, t));
            }
        }
    }

    private ObjectNode asset(JsonNode entity, String type) {
        return json.createObjectNode().put("id", entity.path("id").asText()).put("type", type);
    }

    private ObjectNode ref(JsonNode entity, String key) {
        return json.createObjectNode().put("id", entity.path("id").asText()).put("type", key.substring(0, key.indexOf(':')));
    }

    /** A patch making the team the owner, empty when it is already the only one. */
    private Optional<ArrayNode> ownerPatch(JsonNode entity, ArrayNode owners) {
        JsonNode current = entity.path("owners");
        if (current.size() == 1 && current.get(0).path("id").asText().equals(owners.get(0).path("id").asText())) {
            return Optional.empty();
        }
        ArrayNode patch = json.createArrayNode();
        patch.addObject().put("op", "add").put("path", "/owners").set("value", owners);
        return Optional.of(patch);
    }

    /** Adds to {@code patch} the entity's description when the document gives one it doesn't have. */
    private void describe(ArrayNode patch, JsonNode entity, String description) {
        if (description != null && !description.equals(entity.path("description").asText(null))) {
            patch.addObject().put("op", "add").put("path", "/description").put("value", description);
        }
    }

    /**
     * Adds to {@code patch} the tags at {@code path}: those there, without
     * another tier, with {@code tier} and the glossary's {@code terms};
     * nothing when they are there already.
     */
    void tagPatch(ArrayNode patch, String path, JsonNode current, String tier, List<String> terms, String glossary) {
        ArrayNode tags = json.createArrayNode();
        Set<String> names = new LinkedHashSet<>();
        for (JsonNode tag : current) {
            String fqn = tag.path("tagFQN").asText();
            if (tier != null && fqn.startsWith("Tier.")) {
                continue;
            }
            tags.add(tag);
            names.add(fqn);
        }
        if (tier != null && names.add(tier)) {
            tags.addObject().put("tagFQN", tier).put("source", "Classification").put("labelType", "Manual")
                .put("state", "Confirmed");
        }
        for (String term : terms == null ? List.<String>of() : terms) {
            String fqn = Catalog.fqn(glossary, term);
            if (names.add(fqn)) {
                tags.addObject().put("tagFQN", fqn).put("source", "Glossary").put("labelType", "Manual")
                    .put("state", "Confirmed");
            }
        }
        Set<String> before = new HashSet<>();
        current.forEach(t -> before.add(t.path("tagFQN").asText()));
        if (!before.equals(names)) {
            patch.addObject().put("op", "add").put("path", path).set("value", tags);
        }
    }

    /**
     * Adds to {@code patch} the description of each field the document
     * describes and OpenMetadata has another for, and writes it into
     * {@code fields} too, so the topic is judged as patched.
     */
    private void describeFields(ArrayNode patch, JsonNode fields, String path, String prefix, Map<String, String> described) {
        for (int i = 0; i < fields.size(); i++) {
            JsonNode field = fields.get(i);
            String name = prefix + field.path("name").asText();
            String description = described.get(name);
            if (description != null && !description.equals(field.path("description").asText(null))) {
                patch.addObject().put("op", "add").put("path", path + i + "/description").put("value", description);
                ((ObjectNode) field).put("description", description);
            }
            describeFields(patch, field.path("children"), path + i + "/children/", name + ".", described);
        }
    }

    /** What isn't described: the entity, or its columns or fields by name; empty when all are. */
    static String missing(JsonNode description, JsonNode items, String kind) {
        List<String> parts = new ArrayList<>();
        if (description.asText("").isBlank()) {
            parts.add("no description");
        }
        List<String> bare = new ArrayList<>();
        items.forEach(item -> {
            if (item.path("description").asText("").isBlank()) {
                bare.add(item.path("name").asText());
            }
        });
        if (!bare.isEmpty()) {
            parts.add("no description of the " + kind + (bare.size() == 1 ? " " : "s ") + String.join(", ", bare));
        }
        return String.join("; ", parts);
    }

    /**
     * Certifies the entity ({@code why} empty) with {@code certification},
     * renewed, or takes a certification it has off ({@code why} says what
     * it lacks).
     */
    private void certify(ArrayNode patch, JsonNode entity, String certification, String why, List<String> certified,
            Map<String, String> uncertified) {
        String fqn = entity.path("fullyQualifiedName").asText();
        String reason = why.startsWith("; ") ? why.substring(2) : why;
        if (certification == null) {
            return;
        }
        if (reason.isEmpty()) {
            long now = System.currentTimeMillis();
            certified.add(fqn);
            JsonNode current = entity.path("certification");
            if (certification.equals(current.path("tagLabel").path("tagFQN").asText())
                    && current.path("expiryDate").asLong(0) > now + RENEW_BEFORE.toMillis()) {
                return;
            }
            ObjectNode value = json.createObjectNode()
                .put("appliedDate", now)
                .put("expiryDate", now + CERTIFIED_FOR.toMillis());
            value.putObject("tagLabel").put("tagFQN", certification).put("source", "Classification")
                .put("labelType", "Manual").put("state", "Confirmed");
            patch.addObject().put("op", "add").put("path", "/certification").set("value", value);
        } else {
            if (entity.path("certification").isObject()) {
                patch.addObject().put("op", "remove").put("path", "/certification");
            }
            uncertified.put(fqn, reason);
        }
    }

    /** A message schema's fields, nested ones too, as one array (each with its dotted name). */
    static final class JsonFields {

        private JsonFields() {
        }

        static ArrayNode flatten(JsonNode fields) {
            ArrayNode all = new ObjectMapper().createArrayNode();
            collect(fields, "", all);
            return all;
        }

        private static void collect(JsonNode fields, String prefix, ArrayNode into) {
            for (JsonNode field : fields) {
                ObjectNode copy = field.deepCopy();
                copy.put("name", prefix + field.path("name").asText());
                copy.remove("children");
                into.add(copy);
                collect(field.path("children"), prefix + field.path("name").asText() + ".", into);
            }
        }
    }
}
