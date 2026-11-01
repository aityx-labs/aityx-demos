package datyx.catalog;

import java.io.IOException;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.datasource.DataSource.KafkaAccess;
import io.quarkus.arc.profile.IfBuildProfile;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.WebApplicationException;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Development only: HealthHub's catalogue, ready in OpenMetadata without
 * anyone asking. Once HealthHub's data initialization is done (every
 * table the curation document names is there, described), datyx syncs
 * the seeded HealthHub sources of every profile (the database, with its
 * profiles and checks, and the Kafka cluster) and applies
 * devdata/healthhub-catalog.json to them (Curation): owners, domain, data
 * product, glossary, tiers, topic descriptions, more checks, TimeSeries
 * roles, the Flink pipeline and lineage, and the certifications earned.
 * At every start, so every check is set in OpenMetadata (made, updated,
 * the stale ones removed) and run, one line logging how many and how
 * many failed; then again every {@code datyx.dev-catalog.every} (10
 * minutes), so profiles and checks follow the simulation; until the
 * first success, every half minute. The first waits, at most
 * {@code datyx.dev-catalog.rows-wait} (5 minutes), for the tables whose
 * checks want rows to have some (a new HealthHub's admissions, Flink's
 * first counts), so a fresh start doesn't judge empty tables. After each, OpenMetadata's Data Insights run, so its
 * coverage reports (descriptions, owners, tiers) count the curation. Off with
 * {@code datyx.dev-catalog.enabled=false}.
 */
@IfBuildProfile("dev")
@ApplicationScoped
public class DevCatalog {

    private static final Logger LOG = Logger.getLogger(DevCatalog.class);

    static final String DOCUMENT = "devdata/healthhub-catalog.json";

    @Inject
    Catalog catalog;

    @Inject
    Curation curation;

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @ConfigProperty(name = "datyx.dev-catalog.enabled", defaultValue = "true")
    boolean enabled;

    @ConfigProperty(name = "datyx.dev-catalog.every", defaultValue = "10m")
    Duration every;

    @ConfigProperty(name = "datyx.dev-catalog.rows-wait", defaultValue = "5m")
    Duration rowsWait;

    private Instant emptySince;

    private Curation.Doc doc;
    private Instant lastDone = Instant.EPOCH;
    private String waiting;

    private record Pair(long databaseId, String databaseName, String databaseDescription,
            DatabaseAccess database, Long kafkaId, String kafkaName, String kafkaDescription, KafkaAccess kafka) {
    }

    @Scheduled(every = "30s", delayed = "10s", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void tick() {
        if (!enabled || Instant.now().isBefore(lastDone.plus(every))) {
            return;
        }
        try {
            if (doc == null) {
                try (InputStream in = Thread.currentThread().getContextClassLoader().getResourceAsStream(DOCUMENT)) {
                    doc = json.readValue(in, Curation.Doc.class);
                }
            }
            List<Pair> pairs = pairs();
            for (Pair pair : pairs) {
                String notReady = notReady(pair.database());
                if (notReady != null) {
                    if (!notReady.equals(waiting)) {
                        LOG.infof("dev catalogue: waiting for HealthHub's data initialization: %s", notReady);
                        waiting = notReady;
                    }
                    return;
                }
            }
            if (lastDone.equals(Instant.EPOCH)) {
                for (Pair pair : pairs) {
                    String empty = empty(pair.database());
                    if (empty == null) {
                        continue;
                    }
                    if (emptySince == null) {
                        emptySince = Instant.now();
                    }
                    if (Instant.now().isBefore(emptySince.plus(rowsWait))) {
                        if (!empty.equals(waiting)) {
                            LOG.infof("dev catalogue: waiting for HealthHub's data, at most %s: %s", rowsWait, empty);
                            waiting = empty;
                        }
                        return;
                    }
                    LOG.infof("dev catalogue: %s after %s: checked all the same", empty, rowsWait);
                }
            }
            waiting = null;
            for (Pair pair : pairs) {
                Catalog.Synced synced = catalog.sync(pair.databaseId(), pair.databaseName(), pair.databaseDescription(),
                    pair.database());
                String stream = null;
                if (pair.kafka() != null) {
                    try {
                        stream = catalog.syncStream(pair.kafkaId(), pair.kafkaName(), pair.kafkaDescription(), pair.kafka()).service();
                    } catch (StreamReader.Unreadable e) {
                        LOG.infof("dev catalogue: %s can't be read, curated without its topics: %s", pair.kafkaName(), e.getMessage());
                    }
                }
                Curation.Applied applied = curation.apply(doc, synced, pair.database(), stream);
                int checks = synced.tests() + applied.checks();
                int failed = synced.failed() + applied.failed();
                LOG.infof("dev catalogue: %s's checks set in OpenMetadata and run: %d (%d of the schema, %d of the document; "
                    + "test cases %d new, %d changed, %d removed), %d passed (or aborted, nothing to judge), %d failed", pair.databaseName(), checks,
                    synced.tests(), applied.checks(), synced.testsCreated() + applied.testsCreated(),
                    synced.testsUpdated() + applied.testsUpdated(), applied.testsRemoved(), checks - failed, failed);
            }
            lastDone = Instant.now();
            if (!pairs.isEmpty()) {
                catalog.runInsights();
            }
        } catch (SQLException e) {
            LOG.infof("dev catalogue: HealthHub's database can't be read yet: %s", e.getMessage());
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            LOG.infof("dev catalogue: OpenMetadata can't be reached or refused a call, tried again in half a minute: %s", e.getMessage());
        } catch (IOException | RuntimeException e) {
            LOG.warnf(e, "dev catalogue: failed");
            lastDone = Instant.now();
        }
    }

    /** Each profile's seeded HealthHub database, and its Kafka cluster when it has one, decrypted. */
    private List<Pair> pairs() {
        return QuarkusTransaction.requiringNew().call(() -> {
            List<Pair> pairs = new ArrayList<>();
            List<DataSource> databases = DataSource.list("lower(name) = lower(?1) and type = ?2", doc.sources().database(),
                DataSource.Type.DATABASE);
            for (DataSource db : databases) {
                DataSource kafka = DataSource.<DataSource>find("profile = ?1 and lower(name) = lower(?2) and type = ?3",
                    db.profile, doc.sources().kafka(), DataSource.Type.KAFKA).firstResult();
                DatabaseAccess access = AccessCodec.unseal(crypto, json, db.profile.id, db.profile.keyWrapped, db.access)
                    .database();
                KafkaAccess kafkaAccess = kafka == null ? null
                    : AccessCodec.unseal(crypto, json, kafka.profile.id, kafka.profile.keyWrapped, kafka.access).kafka();
                pairs.add(new Pair(db.id, db.name, db.description, access,
                    kafka == null ? null : kafka.id, kafka == null ? null : kafka.name,
                    kafka == null ? null : kafka.description, kafkaAccess));
            }
            return pairs;
        });
    }

    /**
     * The first table, of those the document gives a row count with a
     * minimum, that has no rows yet ("public.admissions_hourly has no rows
     * yet"), or null when each has some.
     */
    String empty(DatabaseAccess access) throws SQLException {
        try (Connection c = SchemaReader.connect(access)) {
            for (var entry : doc.tables().entrySet()) {
                boolean wantsRows = entry.getValue().checks() != null && entry.getValue().checks().stream()
                    .anyMatch(check -> check.test().startsWith("tableRowCount") && minimum(check) >= 1);
                if (!wantsRows) {
                    continue;
                }
                String[] name = entry.getKey().split("\\.", 2);
                try (PreparedStatement s = c.prepareStatement("SELECT EXISTS (SELECT 1 FROM " + Quality.quote(name[0])
                        + "." + Quality.quote(name[1]) + ")")) {
                    s.setQueryTimeout(Quality.TIMEOUT);
                    try (ResultSet r = s.executeQuery()) {
                        r.next();
                        if (!r.getBoolean(1)) {
                            return entry.getKey() + " has no rows yet";
                        }
                    }
                }
            }
        }
        return null;
    }

    private static double minimum(Quality.Check check) {
        Object min = check.parameters().getOrDefault("minValue", check.parameters().get("value"));
        return min instanceof Number n ? n.doubleValue() : min == null ? 0 : Double.parseDouble(min.toString());
    }

    /** Why the database isn't initialized yet (a curated table missing or undescribed), or null once it is. */
    String notReady(DatabaseAccess access) throws SQLException {
        Set<String> described = new HashSet<>();
        Set<String> present = new HashSet<>();
        for (SchemaReader.Table table : SchemaReader.read(access)) {
            String key = table.schema() + "." + table.name();
            present.add(key);
            if (table.comment() != null && !table.comment().isBlank()) {
                described.add(key);
            }
        }
        for (String table : doc.tables().keySet()) {
            if (!present.contains(table)) {
                return table + " isn't there";
            }
            if (!described.contains(table)) {
                return table + " has no description";
            }
        }
        return null;
    }
}
