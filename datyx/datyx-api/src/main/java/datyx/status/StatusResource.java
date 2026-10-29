package datyx.status;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.sql.DataSource;

import datyx.hello.Greeting;
import datyx.openmetadata.OpenMetadataClient;
import datyx.profile.Profile;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

/**
 * GET /api/status: the system as the API sees it, what the dashboard
 * shows. One JSON document:
 * {"name":"datyx","version":"0.1.202610281300","startedAt":"...","uptimeSeconds":12,
 *  "database":{"ok":true,"version":"PostgreSQL 17..."},
 *  "openmetadata":{"ok":true,"version":"2.0.7","url":"http://localhost:9902"},
 *  "greetings":3,"dataSources":2,"profiles":1}
 * A dependency that fails reports {"ok":false,"error":"..."}, and the
 * counts are null while the database is out.
 */
@Path("/api/status")
@Produces(MediaType.APPLICATION_JSON)
public class StatusResource {

    private static final Logger LOG = Logger.getLogger(StatusResource.class);

    @Inject
    DataSource dataSource;

    @Inject
    @RestClient
    OpenMetadataClient openMetadata;

    @ConfigProperty(name = "quarkus.application.name")
    String name;

    @ConfigProperty(name = "quarkus.application.version")
    String version;

    @ConfigProperty(name = "quarkus.rest-client.openmetadata.url")
    String openMetadataUrl;

    private Instant startedAt = Instant.now();

    void started(@Observes StartupEvent event) {
        startedAt = Instant.now();
    }

    @GET
    public Map<String, Object> status() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", name);
        body.put("version", version);
        body.put("startedAt", startedAt.toString());
        body.put("uptimeSeconds", Duration.between(startedAt, Instant.now()).toSeconds());
        body.put("database", database());
        body.put("openmetadata", openMetadata());
        // Counted together: all null when the database is out, and the
        // call still answers (database.ok says why).
        Long greetings = null;
        Long dataSources = null;
        Long profiles = null;
        try {
            greetings = Greeting.count();
            dataSources = datyx.datasource.DataSource.count();
            profiles = Profile.count();
        } catch (Exception e) {
            LOG.warnf("counting records failed: %s", e.getMessage());
        }
        body.put("greetings", greetings);
        body.put("dataSources", dataSources);
        body.put("profiles", profiles);
        return body;
    }

    private Map<String, Object> database() {
        try (Connection connection = dataSource.getConnection();
                Statement statement = connection.createStatement();
                ResultSet result = statement.executeQuery("select version()")) {
            result.next();
            Map<String, Object> map = ok();
            map.put("version", result.getString(1));
            return map;
        } catch (Exception e) {
            LOG.warnf("database check failed: %s", e.getMessage());
            return failed(e);
        }
    }

    private Map<String, Object> openMetadata() {
        Map<String, Object> map;
        try {
            map = ok();
            map.put("version", openMetadata.version().version());
        } catch (Exception e) {
            LOG.warnf("OpenMetadata check failed: %s", e.getMessage());
            map = failed(e);
        }
        map.put("url", openMetadataUrl);
        return map;
    }

    private static Map<String, Object> ok() {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("ok", true);
        return map;
    }

    private static Map<String, Object> failed(Exception e) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("ok", false);
        map.put("error", e.getMessage());
        return map;
    }
}
