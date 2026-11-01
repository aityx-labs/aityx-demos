package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.hasItem;

import java.util.Map;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import org.junit.jupiter.api.Test;

/**
 * The development data (db/devdata, dev mode's extra Flyway location,
 * added here by a test profile): the HealthHub database and its Kafka are
 * data sources of the local profile, readable through the API, so the
 * seed encrypts as the API does.
 */
@QuarkusTest
@TestProfile(DevDataTest.Profile.class)
class DevDataTest {

    public static class Profile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of("quarkus.flyway.locations", "db/migration,db/devdata");
        }
    }

    @Test
    void seedsHealthHubsDatabase() {
        given()
            .when().get("/api/datasources")
            .then()
            .statusCode(200)
            .body("name", hasItem("HealthHub"))
            .body("name", hasItem("HealthHub Kafka"));
        given()
            .when().get("/api/profile")
            .then()
            .statusCode(200)
            .body("name", is("Local"))
            .body("dataSources", is(2));
        int id = given().when().get("/api/datasources").then().extract().path("find { it.name == 'HealthHub' }.id");
        given()
            .when().get("/api/datasources/" + id)
            .then()
            .statusCode(200)
            .body("type", is("database"))
            .body("createdByName", is("dev data"))
            .body("database.engine", is("postgresql"))
            .body("database.host", is("localhost"))
            .body("database.port", is(9803))
            .body("database.database", is("healthhub"))
            .body("database.username", is("healthhub"))
            .body("database.passwordSet", is(true));
        int kafka = given().when().get("/api/datasources").then().extract().path("find { it.name == 'HealthHub Kafka' }.id");
        given()
            .when().get("/api/datasources/" + kafka)
            .then()
            .statusCode(200)
            .body("type", is("kafka"))
            .body("kafka.bootstrapServers", is("localhost:9804"))
            .body("kafka.securityProtocol", is("PLAINTEXT"))
            .body("kafka.passwordSet", is(false));
    }
}
