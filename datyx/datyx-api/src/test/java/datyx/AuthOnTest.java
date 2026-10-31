package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.nullValue;

import java.util.List;
import java.util.Map;

import io.quarkus.test.common.QuarkusTestResource;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.oidc.server.OidcWiremockTestResource;
import io.restassured.http.ContentType;
import io.smallrye.jwt.build.Jwt;
import org.junit.jupiter.api.Test;

/**
 * With a client id authentication is on: the secured paths want a bearer
 * token the issuer signed, for the client id, and the identity it carries
 * reaches the records. The issuer here is the OIDC test server (WireMock),
 * standing in for Google.
 */
@QuarkusTest
@TestProfile(AuthOnTest.Profile.class)
class AuthOnTest {

    static final String CLIENT_ID = "datyx-test-client";
    /** Another client of the issuer whose tokens are accepted too (HealthHub's). */
    static final String OTHER_CLIENT_ID = "healthhub-test-client";

    public static class Profile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of(
                "datyx.oidc.client-id", CLIENT_ID,
                "datyx.oidc.extra-audiences", OTHER_CLIENT_ID + ", ",
                "datyx.oidc.issuer", "${keycloak.url}/realms/quarkus");
        }

        @Override
        public List<TestResourceEntry> testResources() {
            return List.of(new TestResourceEntry(OidcWiremockTestResource.class));
        }
    }

    static String token(String email, String name) {
        return token(email, name, CLIENT_ID);
    }

    static String token(String email, String name, String audience) {
        return Jwt.issuer("https://server.example.com")
            .subject("sub-" + email)
            .audience(audience)
            .claim("email", email)
            .claim("name", name)
            .jws().keyId("1")
            .sign("privateKey.jwk");
    }

    @Test
    void publishesTheClientId() {
        given()
            .when().get("/api/auth/config")
            .then()
            .statusCode(200)
            .body("enabled", is(true))
            .body("clientId", is(CLIENT_ID));
    }

    @Test
    void securedPathsWantAToken() {
        given().when().get("/api/me").then().statusCode(401);
        given().when().get("/api/datasources").then().statusCode(401);
        given().auth().oauth2("not-a-token").when().get("/api/datasources").then().statusCode(401);
        // A token for another client is refused.
        String other = Jwt.issuer("https://server.example.com").subject("s").audience("someone-else")
            .claim("email", "x@example.com").jws().keyId("1").sign("privateKey.jwk");
        given().auth().oauth2(other).when().get("/api/me").then().statusCode(401);
        // The open paths stay open.
        given().when().get("/api/health").then().statusCode(200);
    }

    @Test
    void tellsWhoIsSignedIn() {
        given()
            .auth().oauth2(token("alice@example.com", "Alice"))
            .when().get("/api/me")
            .then()
            .statusCode(200)
            .body("authenticated", is(true))
            .body("email", is("alice@example.com"))
            .body("name", is("Alice"))
            .body("subject", is("sub-alice@example.com"))
            .body("picture", nullValue());
    }

    @Test
    void acceptsTheOtherClientsTokens() {
        given()
            .auth().oauth2(token("bob@example.com", "Bob", OTHER_CLIENT_ID))
            .when().get("/api/me")
            .then()
            .statusCode(200)
            .body("email", is("bob@example.com"));
    }

    @Test
    void recordsWhoAddedADataSource() {
        given()
            .auth().oauth2(token("alice@example.com", "Alice"))
            .contentType(ContentType.JSON)
            .body("{\"name\":\"alice-folder\",\"type\":\"filesystem\",\"filesystem\":{\"path\":\"/home/alice\"}}")
            .when().post("/api/datasources")
            .then()
            .statusCode(201)
            .body("createdBy", is("alice@example.com"))
            .body("createdByName", is("Alice"));
    }
}
