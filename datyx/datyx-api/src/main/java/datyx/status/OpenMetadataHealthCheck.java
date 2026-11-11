package datyx.status;

import java.util.Optional;

import datyx.openmetadata.OpenMetadataClient;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.HealthCheckResponseBuilder;
import org.eclipse.microprofile.health.Readiness;
import org.eclipse.microprofile.rest.client.inject.RestClient;

/**
 * OpenMetadata in /api/health (and /api/health/ready), beside the
 * database's check: {"name":"OpenMetadata","status":"UP",
 * "data":{"version":"2.0.7","url":"http://localhost:9902"}}, or DOWN with
 * the error. The API is ready only with its catalogue, as process-compose
 * and compose.yaml already start it. The URL is where a browser opens
 * OpenMetadata ({@code datyx.openmetadata.public-url}, the dashboard's
 * links): the address the API calls unless DATYX_OPENMETADATA_PUBLIC_URL
 * names another, as where the API reaches it by a name of the cluster's
 * or the Compose network's.
 */
@Readiness
@ApplicationScoped
public class OpenMetadataHealthCheck implements HealthCheck {

    @Inject
    @RestClient
    OpenMetadataClient openMetadata;

    @ConfigProperty(name = "quarkus.rest-client.openmetadata.url")
    String apiUrl;

    @ConfigProperty(name = "datyx.openmetadata.public-url")
    Optional<String> publicUrl;

    @Override
    public HealthCheckResponse call() {
        HealthCheckResponseBuilder response = HealthCheckResponse.named("OpenMetadata")
                .withData("url", publicUrl.map(String::strip).filter(u -> !u.isEmpty()).orElse(apiUrl));
        try {
            return response.up().withData("version", openMetadata.version().version()).build();
        } catch (Exception e) {
            return response.down().withData("error", String.valueOf(e.getMessage())).build();
        }
    }
}
