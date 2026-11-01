package datyx.catalog;

import java.net.URI;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.smallrye.config.ConfigSourceContext;
import io.smallrye.config.ConfigSourceFactory;
import io.smallrye.config.ConfigValue;
import io.smallrye.config.PropertiesConfigSource;
import org.eclipse.microprofile.config.spi.ConfigSource;

/**
 * Lets OpenMetadata's webhook reach an API that listens on this host only.
 * Quarkus refuses a request whose Host header isn't a localhost name when
 * it listens on localhost (its host validation, against DNS rebinding);
 * OpenMetadata, in Docker, posts to host.docker.internal. So when the API
 * listens on localhost and {@code datyx.openmetadata.callback-url} names
 * another host, that host is allowed beside the localhost names
 * ({@code quarkus.http.host-validation.allowed-hosts}). Listening on every
 * interface (a container), Quarkus validates no host and nothing changes.
 * Registered in META-INF/services/io.smallrye.config.ConfigSourceFactory.
 */
public class CallbackHostConfigSourceFactory implements ConfigSourceFactory {

    static final Set<String> LOCAL = Set.of("localhost", "127.0.0.1", "::1", "[::1]");

    @Override
    public Iterable<ConfigSource> getConfigSources(ConfigSourceContext context) {
        String allowed = allowedHosts(value(context, "quarkus.http.host"), value(context, "datyx.openmetadata.callback-url"));
        if (allowed == null || value(context, "quarkus.http.host-validation.allowed-hosts") != null) {
            return List.of();
        }
        // Below the environment and system properties, so an explicit setting wins.
        return List.of(new PropertiesConfigSource(Map.of("quarkus.http.host-validation.allowed-hosts", allowed), "datyx-callback-host", 260));
    }

    /** The hosts to allow: the localhost names and the callback's, or null when Quarkus needs none. */
    static String allowedHosts(String listenOn, String callbackUrl) {
        if (listenOn == null || !LOCAL.contains(listenOn.strip()) || callbackUrl == null || callbackUrl.isBlank()) {
            return null;
        }
        String host;
        try {
            host = URI.create(callbackUrl.strip()).getHost();
        } catch (IllegalArgumentException e) {
            return null;
        }
        if (host == null || LOCAL.contains(host)) {
            return null;
        }
        return "localhost,127.0.0.1,[::1]," + host;
    }

    private static String value(ConfigSourceContext context, String name) {
        ConfigValue value = context.getValue(name);
        return value == null || value.getValue() == null || value.getValue().isBlank() ? null : value.getValue();
    }
}
