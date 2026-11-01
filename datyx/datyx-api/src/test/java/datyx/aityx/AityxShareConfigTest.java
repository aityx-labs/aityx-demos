package datyx.aityx;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.Map;

import io.smallrye.config.PropertiesConfigSource;
import io.smallrye.config.SmallRyeConfig;
import io.smallrye.config.SmallRyeConfigBuilder;
import io.smallrye.config.common.MapBackedConfigSource;
import org.junit.jupiter.api.Test;

/**
 * Whether every profile sees the services' calls (HealthHub's triage,
 * health data): true in dev mode only, false in a packaged (prod) API,
 * also when Docker Compose runs it and passes the setting through empty.
 */
class AityxShareConfigTest {

    static final String KEY = "datyx.aityx.share-service-calls";
    static final String ENV = "DATYX_AITYX_SHARE_SERVICE_CALLS";

    static boolean shares(String profile, String env) throws IOException {
        URL properties = AityxShareConfigTest.class.getClassLoader().getResource("application.properties");
        Map<String, String> vars = new HashMap<>();
        if (env != null) {
            vars.put(ENV, env);
        }
        SmallRyeConfig config = new SmallRyeConfigBuilder()
                .withProfile(profile)
                .addDefaultInterceptors()
                .withSources(new PropertiesConfigSource(properties, 250))
                .withSources(new MapBackedConfigSource("env", vars, 300) {})
                .build();
        return AityxResource.sharesServiceCalls(config.getOptionalValue(KEY, Boolean.class),
                config.getOptionalValue(KEY + "-by-default", Boolean.class).orElse(false));
    }

    @Test
    void sharedInDevModeOnly() throws IOException {
        assertEquals(true, shares("dev", null));
        assertEquals(false, shares("prod", null));
    }

    @Test
    void composePassingItEmptyKeepsTheProfilesDefault() throws IOException {
        assertEquals(true, shares("dev", ""));
        assertEquals(false, shares("prod", ""));
    }

    @Test
    void anExplicitValueWins() throws IOException {
        assertEquals(true, shares("prod", "true"));
        assertEquals(false, shares("dev", "false"));
    }

    /** compose.yaml passes the setting through with no default of its own. */
    @Test
    void composeHasNoDefaultOfItsOwn() throws IOException {
        String compose = Files.readString(Path.of("..", "compose.yaml"));
        assertTrue(compose.contains(ENV + ": ${" + ENV + ":-}"), "compose.yaml passes " + ENV + " through empty");
    }
}
