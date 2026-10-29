package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.startsWith;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * /api/status against the Dev Services Postgres. OpenMetadata isn't
 * started for the tests: its part reports the failure and the rest stands.
 */
@QuarkusTest
class StatusResourceTest {

    @Test
    void reportsTheDatabaseAndOpenMetadata() {
        given()
            .when().get("/api/status")
            .then()
            .statusCode(200)
            .body("name", is("datyx"))
            .body("database.ok", is(true))
            .body("database.version", startsWith("PostgreSQL"))
            .body("openmetadata.ok", is(false));
    }
}
