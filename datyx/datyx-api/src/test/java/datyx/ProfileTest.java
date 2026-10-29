package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.notNullValue;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import javax.sql.DataSource;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;

/**
 * Profiles, with authentication on (AuthOnTest's profile): a sign-in
 * makes a profile and finds it again; each profile sees its own data
 * sources only; what the database holds of a source's access details is
 * encrypted.
 */
@QuarkusTest
@TestProfile(AuthOnTest.Profile.class)
class ProfileTest {

    @Inject
    DataSource db;

    @Test
    void makesAProfileOnTheFirstCallAndFindsItAgain() {
        String carol = AuthOnTest.token("carol@example.com", "Carol");
        int id = given().auth().oauth2(carol).when().get("/api/me")
            .then().statusCode(200).body("profileId", notNullValue()).extract().path("profileId");
        given().auth().oauth2(carol).when().get("/api/profile")
            .then()
            .statusCode(200)
            .body("id", is(id))
            .body("name", is("Carol"))
            .body("createdAt", notNullValue())
            .body("dataSources", is(0))
            .body("identities", hasSize(1))
            .body("identities[0].issuer", is("https://server.example.com"))
            .body("identities[0].subject", is("sub-carol@example.com"))
            .body("identities[0].email", is("carol@example.com"))
            .body("identities[0].name", is("Carol"))
            .body("identities[0].lastSeenAt", notNullValue());
        // Another token of the same identity, with a new name: the same profile, the claim updated.
        given().auth().oauth2(AuthOnTest.token("carol@example.com", "Carol Jones")).when().get("/api/profile")
            .then().statusCode(200).body("id", is(id)).body("identities[0].name", is("Carol Jones"));
        // Someone else gets a profile of their own.
        given().auth().oauth2(AuthOnTest.token("dave@example.com", "Dave")).when().get("/api/profile")
            .then().statusCode(200).body("id", not(is(id))).body("name", is("Dave"));
        // Without a token: no profile.
        given().when().get("/api/profile").then().statusCode(401);
    }

    @Test
    void keepsEachProfilesDataSourcesApart() {
        String erin = AuthOnTest.token("erin@example.com", "Erin");
        String frank = AuthOnTest.token("frank@example.com", "Frank");
        String body = "{\"name\":\"Shared name\",\"type\":\"filesystem\",\"filesystem\":{\"path\":\"/erin\"}}";
        int erins = given().auth().oauth2(erin).contentType(ContentType.JSON).body(body)
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        // The same name in another profile is fine; in the same one, a 409.
        given().auth().oauth2(frank).contentType(ContentType.JSON).body(body.replace("/erin", "/frank"))
            .when().post("/api/datasources").then().statusCode(201);
        given().auth().oauth2(erin).contentType(ContentType.JSON).body(body.replace("Shared", "shared"))
            .when().post("/api/datasources").then().statusCode(409);
        // Each lists their own; Erin's is not Frank's to read or remove.
        given().auth().oauth2(erin).when().get("/api/datasources").then().statusCode(200)
            .body("id", hasItem(erins)).body("filesystem.path", hasItem("/erin")).body("filesystem.path", not(hasItem("/frank")));
        given().auth().oauth2(frank).when().get("/api/datasources/" + erins).then().statusCode(404);
        given().auth().oauth2(frank).when().delete("/api/datasources/" + erins).then().statusCode(404);
        given().auth().oauth2(erin).when().get("/api/datasources/" + erins).then().statusCode(200);
        given().auth().oauth2(erin).when().get("/api/profile").then().statusCode(200).body("dataSources", is(1));
        given().auth().oauth2(erin).when().delete("/api/datasources/" + erins).then().statusCode(204);
    }

    @Test
    void storesAccessDetailsEncrypted() throws SQLException {
        String grace = AuthOnTest.token("grace@example.com", "Grace");
        int id = given().auth().oauth2(grace).contentType(ContentType.JSON)
            .body("""
                {"name":"vault","type":"database",
                 "database":{"engine":"postgresql","host":"vault-host.example.com","port":5432,
                             "database":"vaultdb","username":"vault-user","password":"vault-password-1"}}
                """)
            .when().post("/api/datasources").then().statusCode(201)
            .body("database.host", is("vault-host.example.com")).body("database.passwordSet", is(true))
            .extract().path("id");
        byte[] stored;
        byte[] key;
        try (Connection c = db.getConnection();
                PreparedStatement s = c.prepareStatement(
                    "select d.access, p.key_wrapped from data_source d join profile p on p.id = d.profile_id where d.id = ?")) {
            s.setLong(1, id);
            try (ResultSet r = s.executeQuery()) {
                assertTrue(r.next());
                stored = r.getBytes(1);
                key = r.getBytes(2);
            }
        }
        for (String clear : new String[] {"vault-host", "vaultdb", "vault-user", "vault-password-1", "postgresql"}) {
            assertFalse(contains(stored, clear.getBytes(StandardCharsets.UTF_8)), clear + " is in clear in the database");
        }
        assertTrue(key.length > 32, "the profile key is wrapped");
        // The API still reads it back.
        given().auth().oauth2(grace).when().get("/api/datasources/" + id).then().statusCode(200)
            .body("database.username", is("vault-user")).body("database.host", is("vault-host.example.com"));
    }

    private static boolean contains(byte[] haystack, byte[] needle) {
        outer:
        for (int i = 0; i + needle.length <= haystack.length; i++) {
            for (int j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    continue outer;
                }
            }
            return true;
        }
        return false;
    }
}
