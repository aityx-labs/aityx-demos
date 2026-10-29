package datyx.status;

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
 * and compose.yaml already start it.
 */
@Readiness
@ApplicationScoped
public class OpenMetadataHealthCheck implements HealthCheck {

    @Inject
    @RestClient
    OpenMetadataClient openMetadata;

    @ConfigProperty(name = "quarkus.rest-client.openmetadata.url")
    String url;

    @Override
    public HealthCheckResponse call() {
        HealthCheckResponseBuilder response = HealthCheckResponse.named("OpenMetadata")
                .withData("url", url);
        try {
            return response.up().withData("version", openMetadata.version().version()).build();
        } catch (Exception e) {
            return response.down().withData("error", String.valueOf(e.getMessage())).build();
        }
    }
}
