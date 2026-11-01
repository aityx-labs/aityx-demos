package datyx.aityx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;
import java.util.Map;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.http.ContentType;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.Test;

/**
 * Without an aityx key the gateway answers 503 and calls nothing; without
 * a service token configured, no token opens it.
 */
@QuarkusTest
@TestProfile(AityxNoKeyTest.Profile.class)
class AityxNoKeyTest {

    public static class Profile implements QuarkusTestProfile {
        @Override
        public List<TestResourceEntry> testResources() {
            return List.of(new TestResourceEntry(AityxStub.class));
        }

        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of("datyx.aityx.share-service-calls", "false");
        }
    }

    @ConfigProperty(name = "datyx.aityx.url")
    String aityx;

    @Test
    void answers503WithoutAKey() throws Exception {
        given().contentType(ContentType.JSON).body("{\"model\":\"jev-latest\"}")
            .when().post("/api/aityx/v1/systemone").then().statusCode(503).body("error", is("datyx has no aityx key"));
        given().when().get("/api/aityx").then().statusCode(200).body("configured", is(false))
            .body("sharesServiceCalls", is(false)).body("totals.calls", is(0));
        given().when().get("/api/aityx/v1/status").then().statusCode(200).body("configured", is(false));
        assertEquals(0, AityxStub.count(aityx));
    }

    @Test
    void refusesServicesWithoutAToken() throws Exception {
        given().contentType(ContentType.JSON).body("{}").header("X-Datyx-Service-Token", "")
            .when().post("/api/aityx/v1/systemone").then().statusCode(401);
        given().contentType(ContentType.JSON).body("{}").header("X-Datyx-Service-Token", "anything")
            .when().post("/api/aityx/v1/systemone").then().statusCode(401);
        assertEquals(0, AityxStub.count(aityx));
    }
}
