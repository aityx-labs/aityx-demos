package datyx.status;

import java.time.Instant;

import io.quarkus.runtime.ImageMode;
import io.quarkus.runtime.LaunchMode;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.Liveness;

/**
 * The API itself in /api/health (and /api/health/live), always UP, saying
 * how it runs: {"name":"datyx","status":"UP","data":{"version":"0.1.202610281300",
 * "profile":"dev","launchMode":"development","image":"jvm",
 * "startedAt":"2026-10-30T12:00:00Z"}}. The profile is the configuration's
 * (dev, test, prod, or several, comma-separated); the launch mode is how
 * Quarkus started it (development for quarkus:dev, test, normal for a
 * packaged jar or native executable); the image is jvm or native.
 */
@Liveness
@ApplicationScoped
public class ModeHealthCheck implements HealthCheck {

    @Inject
    LaunchMode launchMode;

    @ConfigProperty(name = "quarkus.profile")
    String profile;

    @ConfigProperty(name = "quarkus.application.name")
    String name;

    @ConfigProperty(name = "quarkus.application.version")
    String version;

    private Instant startedAt = Instant.now();

    void started(@Observes StartupEvent event) {
        startedAt = Instant.now();
    }

    @Override
    public HealthCheckResponse call() {
        return HealthCheckResponse.named(name)
                .up()
                .withData("version", version)
                .withData("profile", profile)
                .withData("launchMode", launchMode.name().toLowerCase())
                .withData("image", ImageMode.current().isNativeImage() ? "native" : "jvm")
                .withData("startedAt", startedAt.toString())
                .build();
    }
}
