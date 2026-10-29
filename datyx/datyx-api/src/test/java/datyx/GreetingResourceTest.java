package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.notNullValue;
import static org.hamcrest.Matchers.hasItem;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.Test;

/** /api/greetings against the Dev Services Postgres. */
@QuarkusTest
class GreetingResourceTest {

    @Test
    void storesAndListsAGreeting() {
        given()
            .contentType(ContentType.JSON)
            .body("{\"message\":\"  Hello, tests!  \"}")
            .when().post("/api/greetings")
            .then()
            .statusCode(201)
            .body("id", notNullValue())
            .body("message", is("Hello, tests!"))
            .body("createdAt", notNullValue());

        given()
            .when().get("/api/greetings")
            .then()
            .statusCode(200)
            .body("message", hasItem("Hello, tests!"));
    }

    @Test
    void rejectsABlankMessage() {
        given()
            .contentType(ContentType.JSON)
            .body("{\"message\":\"   \"}")
            .when().post("/api/greetings")
            .then()
            .statusCode(400);
    }
}
