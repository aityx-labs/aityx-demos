package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.containsInAnyOrder;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.oidc.server.OidcWiremockTestResource;
import org.junit.jupiter.api.Test;

/**
 * The development data with authentication on: a profile made by a first
 * sign-in, after the Flyway migration seeded those there at start, gets
 * HealthHub's two data sources as it is made, at the addresses the
 * configuration gives (here a cluster's Services, not a laptop's ports),
 * and each profile has its own.
 */
@QuarkusTest
@TestProfile(DevDataProfileTest.Profile.class)
class DevDataProfileTest {

    public static class Profile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            Map<String, String> config = new HashMap<>(new AuthOnTest.Profile().getConfigOverrides());
            config.put("quarkus.flyway.locations", "db/migration,db/devdata");
            config.put("datyx.devdata.enabled", "true");
            config.put("datyx.devdata.healthhub.db-host", "healthhub-postgres");
            config.put("datyx.devdata.healthhub.db-port", "5432");
            config.put("datyx.devdata.healthhub.kafka", " healthhub-kafka:19092 ");
            return config;
        }

        @Override
        public List<TestResourceEntry> testResources() {
            return List.of(new TestResourceEntry(OidcWiremockTestResource.class));
        }
    }

    @Test
    void aNewProfileIsMadeWithHealthHubsSources() {
        String alice = AuthOnTest.token("alice@example.com", "Alice");
        given().auth().oauth2(alice)
            .when().get("/api/datasources")
            .then()
            .statusCode(200)
            .body("name", containsInAnyOrder("HealthHub", "HealthHub Kafka"));
        given().auth().oauth2(alice)
            .when().get("/api/profile")
            .then()
            .statusCode(200)
            .body("name", is("Alice"))
            .body("dataSources", is(2));
        int id = given().auth().oauth2(alice).when().get("/api/datasources").then().extract()
            .path("find { it.name == 'HealthHub' }.id");
        given().auth().oauth2(alice)
            .when().get("/api/datasources/" + id)
            .then()
            .statusCode(200)
            .body("type", is("database"))
            .body("createdByName", is("dev data"))
            .body("database.engine", is("postgresql"))
            .body("database.host", is("healthhub-postgres"))
            .body("database.port", is(5432))
            .body("database.database", is("healthhub"))
            .body("database.username", is("healthhub"))
            .body("database.passwordSet", is(true));
        int kafka = given().auth().oauth2(alice).when().get("/api/datasources").then().extract()
            .path("find { it.name == 'HealthHub Kafka' }.id");
        given().auth().oauth2(alice)
            .when().get("/api/datasources/" + kafka)
            .then()
            .statusCode(200)
            .body("type", is("kafka"))
            .body("kafka.bootstrapServers", is("healthhub-kafka:19092"))
            .body("kafka.securityProtocol", is("PLAINTEXT"));

        // Another person: a profile of their own, with sources of its own.
        String bob = AuthOnTest.token("bob@example.com", "Bob");
        given().auth().oauth2(bob)
            .when().get("/api/datasources")
            .then()
            .statusCode(200)
            .body("name", containsInAnyOrder("HealthHub", "HealthHub Kafka"));
        given().auth().oauth2(bob)
            .when().get("/api/datasources/" + id)
            .then()
            .statusCode(404);
        // Signing in again makes nothing more.
        given().auth().oauth2(alice)
            .when().get("/api/profile")
            .then()
            .statusCode(200)
            .body("dataSources", is(2));
    }
}
