package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.notNullValue;
import static org.hamcrest.CoreMatchers.nullValue;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/** Without OIDC_CLIENT_ID authentication is off: every path is open and nobody is signed in. */
@QuarkusTest
class AuthOffTest {

    @Test
    void reportsAuthenticationOff() {
        given()
            .when().get("/api/auth/config")
            .then()
            .statusCode(200)
            .body("enabled", is(false))
            .body("issuer", is("https://accounts.google.com"))
            .body("clientId", nullValue());
    }

    @Test
    void nobodyIsSignedIn() {
        given()
            .when().get("/api/me")
            .then()
            .statusCode(200)
            .body("authenticated", is(false))
            .body("profileId", notNullValue());
        // The local profile, the one every call uses while authentication is off.
        given()
            .when().get("/api/profile")
            .then()
            .statusCode(200)
            .body("name", is("Local"))
            .body("identities[0].issuer", is("local"))
            .body("identities[0].subject", is("anonymous"));
    }
}
