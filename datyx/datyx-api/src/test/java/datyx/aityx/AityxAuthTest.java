package datyx.aityx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertEquals;

import java.sql.Connection;
import java.sql.Statement;
import java.util.List;
import java.util.Map;

import io.agroal.api.AgroalDataSource;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.oidc.server.OidcWiremockTestResource;
import io.restassured.http.ContentType;
import io.smallrye.jwt.build.Jwt;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * The gateway with authentication on (the OIDC test server as the
 * issuer): a signed-in user's calls are their profile's and only theirs
 * to see, a service's token stands in for a sign-in on the gateway alone,
 * and the services' calls are every profile's to see (shared).
 */
@QuarkusTest
@TestProfile(AityxAuthTest.Profile.class)
class AityxAuthTest {

    static final String CLIENT_ID = "datyx-test-client";
    static final String KEY = "test-aityx-key-auth-5e6f";
    static final String TOKEN = "test-service-token-auth-1a2b";

    public static class Profile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of(
                "datyx.oidc.client-id", CLIENT_ID,
                "datyx.oidc.issuer", "${keycloak.url}/realms/quarkus",
                "%test.datyx.aityx.key", KEY,
                "%test.datyx.service-token", TOKEN,
                "datyx.aityx.share-service-calls", "true");
        }

        @Override
        public List<TestResourceEntry> testResources() {
            return List.of(new TestResourceEntry(OidcWiremockTestResource.class), new TestResourceEntry(AityxStub.class));
        }
    }

    static String token(String email) {
        return Jwt.issuer("https://server.example.com").subject("sub-" + email).audience(CLIENT_ID)
            .claim("email", email).claim("name", email).jws().keyId("1").sign("privateKey.jwk");
    }

    static final String BODY = "{\"model\":\"jev-latest\",\"questions\":{},\"state\":{\"age\":40}}";

    @ConfigProperty(name = "datyx.aityx.url")
    String aityx;

    @Inject
    AgroalDataSource dataSource;

    @BeforeEach
    void clean() throws Exception {
        AityxStub.reset(aityx);
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("delete from aityx_call");
        }
    }

    @Test
    void wantsASignInOrTheServiceToken() throws Exception {
        given().contentType(ContentType.JSON).body(BODY).when().post("/api/aityx/v1/systemone").then().statusCode(401);
        given().auth().oauth2("not-a-token").contentType(ContentType.JSON).body(BODY)
            .when().post("/api/aityx/v1/systemone").then().statusCode(401);
        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", "wrong")
            .when().post("/api/aityx/v1/systemone").then().statusCode(401);
        // A wrong token is refused even for a signed-in user.
        given().auth().oauth2(token("alice@example.com")).contentType(ContentType.JSON).body(BODY)
            .header("X-Datyx-Service-Token", "wrong").when().post("/api/aityx/v1/systemone").then().statusCode(403);
        given().when().get("/api/aityx").then().statusCode(401);
        given().when().get("/api/aityx/calls/1").then().statusCode(401);
        // The token opens the gateway alone, not the account.
        given().header("X-Datyx-Service-Token", TOKEN).when().get("/api/aityx").then().statusCode(401);
        given().header("X-Datyx-Service-Token", TOKEN).when().get("/api/datasources").then().statusCode(401);
        assertEquals(0, AityxStub.count(aityx));

        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", TOKEN)
            .header("X-Datyx-Purpose", "triage").when().post("/api/aityx/v1/systemone").then().statusCode(200);
        assertEquals(1, AityxStub.count(aityx));
    }

    /** The status says whether datyx has a key, to the token or a user, and calls and records nothing. */
    @Test
    void theStatusWantsTheTokenOrASignIn() throws Exception {
        given().when().get("/api/aityx/v1/status").then().statusCode(401);
        given().header("X-Datyx-Service-Token", "wrong").when().get("/api/aityx/v1/status").then().statusCode(401);
        given().header("X-Datyx-Service-Token", TOKEN).when().get("/api/aityx/v1/status")
            .then().statusCode(200).body("configured", is(true));
        given().auth().oauth2(token("alice@example.com")).when().get("/api/aityx/v1/status")
            .then().statusCode(200).body("configured", is(true));
        assertEquals(0, AityxStub.count(aityx));
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement();
                java.sql.ResultSet r = s.executeQuery("select count(*) from aityx_call")) {
            r.next();
            assertEquals(0, r.getInt(1));
        }
    }

    @Test
    void aUsersCallsAreTheirsAlone() throws Exception {
        String alice = token("alice@example.com");
        String bob = token("bob@example.com");
        given().auth().oauth2(alice).contentType(ContentType.JSON).body(BODY).header("X-Datyx-Purpose", "triage")
            .when().post("/api/aityx/v1/systemone").then().statusCode(200);
        assertEquals("Bearer " + KEY, AityxStub.last(aityx).path("headers").path("authorization").asText(),
            "datyx's key, not the user's token");
        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", TOKEN)
            .when().post("/api/aityx/v1/systemone").then().statusCode(200);

        int aliceCall = given().auth().oauth2(alice).when().get("/api/aityx").then().statusCode(200)
            .body("calls", hasSize(2))
            .body("calls[1].caller", is("alice@example.com")).body("calls[1].service", is(false))
            .body("calls[0].caller", is("HealthHub")).body("calls[0].service", is(true))
            .extract().path("calls[1].id");
        int serviceCall = given().auth().oauth2(bob).when().get("/api/aityx").then().statusCode(200)
            .body("calls", hasSize(1)).body("calls[0].caller", is("HealthHub")).body("totals.calls", is(1))
            .extract().path("calls[0].id");
        given().auth().oauth2(alice).when().get("/api/aityx/calls/" + aliceCall).then().statusCode(200)
            .body("request.model", is("jev-latest"));
        given().auth().oauth2(bob).when().get("/api/aityx/calls/" + aliceCall).then().statusCode(404);
        given().auth().oauth2(bob).when().get("/api/aityx/calls/" + serviceCall).then().statusCode(200);
    }
}
