package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * /api/hello and the health endpoint, against a Dev Services Postgres (a
 * test container; Docker must be up).
 */
@QuarkusTest
class HelloResourceTest {

    @Test
    void saysHelloWorld() {
        given()
            .when().get("/api/hello")
            .then()
            .statusCode(200)
            .body("message", is("Hello, World!"));
    }

    @Test
    void saysHelloByName() {
        given()
            .queryParam("name", "datyx")
            .when().get("/api/hello")
            .then()
            .statusCode(200)
            .body("message", is("Hello, datyx!"));
    }

    @Test
    void isHealthyWithTheDatabase() {
        given()
            .when().get("/api/health")
            .then()
            .statusCode(200)
            .body("status", is("UP"));
    }
}
