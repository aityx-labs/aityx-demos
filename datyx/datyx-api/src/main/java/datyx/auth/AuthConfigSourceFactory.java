package datyx.auth;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.smallrye.config.ConfigSourceContext;
import io.smallrye.config.ConfigSourceFactory;
import io.smallrye.config.ConfigValue;
import io.smallrye.config.PropertiesConfigSource;
import org.eclipse.microprofile.config.spi.ConfigSource;

/**
 * Turns authentication on when a client id is set, and off otherwise, so
 * the API runs with no setup and locks down once OIDC_CLIENT_ID lands:
 * {@code datyx.oidc.client-id} (application.properties, from OIDC_CLIENT_ID)
 * decides {@code quarkus.oidc.tenant-enabled} and the policy of the secured
 * paths ({@code authenticated}, or {@code permit} without a client id), and
 * the accepted audiences: the client id plus {@code datyx.oidc.extra-audiences}
 * (OIDC_EXTRA_AUDIENCES, other clients of the same issuer, HealthHub's, whose
 * tokens come through unchanged). Registered in
 * META-INF/services/io.smallrye.config.ConfigSourceFactory.
 */
public class AuthConfigSourceFactory implements ConfigSourceFactory {

    static final String CLIENT_ID = "datyx.oidc.client-id";
    static final String EXTRA_AUDIENCES = "datyx.oidc.extra-audiences";
    static final String ENABLED = "datyx.oidc.enabled";

    @Override
    public Iterable<ConfigSource> getConfigSources(ConfigSourceContext context) {
        ConfigValue clientId = context.getValue(CLIENT_ID);
        boolean enabled = clientId != null && clientId.getValue() != null && !clientId.getValue().isBlank();
        Map<String, String> derived = new HashMap<>();
        derived.put(ENABLED, Boolean.toString(enabled));
        derived.put("quarkus.oidc.tenant-enabled", Boolean.toString(enabled));
        derived.put("quarkus.http.auth.permission.secured.policy", enabled ? "authenticated" : "permit");
        if (enabled) {
            List<String> audiences = new ArrayList<>();
            audiences.add(clientId.getValue().strip());
            ConfigValue extra = context.getValue(EXTRA_AUDIENCES);
            if (extra != null && extra.getValue() != null) {
                for (String audience : extra.getValue().split(",")) {
                    if (!audience.isBlank()) {
                        audiences.add(audience.strip());
                    }
                }
            }
            derived.put("quarkus.oidc.token.audience", String.join(",", audiences));
        }
        // Below the environment and system properties (400 and 300), so an
        // explicit setting still wins; above application.properties (250).
        return List.of(new PropertiesConfigSource(derived, "datyx-auth", 260));
    }
}
