package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.notNullValue;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * /api/health against a Dev Services Postgres (a test container; Docker
 * must be up): UP with the database, and the API's own check saying how it
 * runs. OpenMetadata's check is off in tests.
 */
@QuarkusTest
class HealthTest {

    @Test
    void isHealthyWithTheDatabase() {
        given()
            .when().get("/api/health")
            .then()
            .statusCode(200)
            .body("status", is("UP"))
            .body("checks.find { it.name == 'Database connections health check' }.status", is("UP"));
    }

    @Test
    void saysHowItRunsInTheLivenessCheck() {
        given()
            .when().get("/api/health/live")
            .then()
            .statusCode(200)
            .body("checks.find { it.name == 'datyx' }.status", is("UP"))
            .body("checks.find { it.name == 'datyx' }.data.profile", is("test"))
            .body("checks.find { it.name == 'datyx' }.data.launchMode", is("test"))
            .body("checks.find { it.name == 'datyx' }.data.image", is("jvm"))
            .body("checks.find { it.name == 'datyx' }.data.version", notNullValue())
            .body("checks.find { it.name == 'datyx' }.data.startedAt", notNullValue());
    }
}
