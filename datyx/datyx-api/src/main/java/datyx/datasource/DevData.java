package datyx.datasource;

import java.util.List;

import datyx.datasource.DataSource.Access;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.datasource.DataSource.KafkaAccess;
import org.eclipse.microprofile.config.Config;

/**
 * The development data: HealthHub as two data sources, its PostgreSQL
 * named HealthHub and its Kafka named HealthHub Kafka, which every
 * profile gets in dev mode ({@code datyx.devdata.enabled}): those there
 * at start from the Flyway migration (db.devdata), one made later when
 * it is made (datyx.profile.ProfileMaker). Where HealthHub is comes from
 * the configuration, so the same API reads it on a laptop, where
 * HealthHub publishes its ports on this host (localhost:9803 and
 * localhost:9804, the defaults, HealthHub/.env.example), and where it is
 * reached by name (Docker Compose, Kubernetes): DATYX_HEALTHHUB_DB_HOST,
 * DATYX_HEALTHHUB_DB_PORT, DATYX_HEALTHHUB_DB_PASSWORD and
 * DATYX_HEALTHHUB_KAFKA. The database and its user are HealthHub's
 * development ones, healthhub.
 */
public final class DevData {

    public static final String NAME = "HealthHub";

    public static final String KAFKA_NAME = "HealthHub Kafka";

    /** What the seeded sources say of who added them. */
    public static final String CREATED_BY_NAME = "dev data";

    /** A source to seed: its name, type, description and access details. */
    public record Seed(String name, DataSource.Type type, String description, Access access) {
    }

    private DevData() {
    }

    /** Whether profiles get the development data: dev mode, or a test that says so. */
    public static boolean enabled(Config config) {
        return config.getOptionalValue("datyx.devdata.enabled", Boolean.class).orElse(false);
    }

    /** HealthHub's two sources, at the addresses the configuration gives (an empty setting is its default). */
    public static List<Seed> healthHub(Config config) {
        String host = text(config, "datyx.devdata.healthhub.db-host", "localhost");
        int port = Integer.parseInt(text(config, "datyx.devdata.healthhub.db-port", "9803"));
        String password = text(config, "datyx.devdata.healthhub.db-password", "healthhub");
        String kafka = text(config, "datyx.devdata.healthhub.kafka", "localhost:9804");
        return List.of(
            new Seed(NAME, DataSource.Type.DATABASE,
                "HealthHub's PostgreSQL, the development one (compose.yaml of HealthHub/)",
                new Access(new DatabaseAccess("postgresql", host, port, "healthhub", "healthhub", password), null, null,
                    null)),
            new Seed(KAFKA_NAME, DataSource.Type.KAFKA,
                "HealthHub's Kafka, the development one (compose.yaml of HealthHub/): admissions, moves and hourly counts",
                new Access(null, null, null, new KafkaAccess(kafka, "PLAINTEXT", null, null, null))));
    }

    private static String text(Config config, String name, String fallback) {
        return config.getOptionalValue(name, String.class).map(String::strip).filter(s -> !s.isEmpty()).orElse(fallback);
    }
}
