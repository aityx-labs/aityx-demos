package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.notNullValue;
import static org.hamcrest.CoreMatchers.nullValue;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.Test;

/** /api/datasources against the Dev Services Postgres, authentication off. */
@QuarkusTest
class DataSourceResourceTest {

    @Test
    void addsListsAndRemovesADatabase() {
        int id = given()
            .contentType(ContentType.JSON)
            .body("""
                {"name":"warehouse","type":"database","description":"the warehouse",
                 "database":{"engine":"PostgreSQL","host":"db.example.com","port":5432,
                             "database":"dw","username":"reader","password":"s3cret"}}
                """)
            .when().post("/api/datasources")
            .then()
            .statusCode(201)
            .header("Location", containsString("/api/datasources/"))
            .body("id", notNullValue())
            .body("name", is("warehouse"))
            .body("type", is("database"))
            .body("createdAt", notNullValue())
            .body("createdBy", nullValue())
            .body("database.engine", is("postgresql"))
            .body("database.host", is("db.example.com"))
            .body("database.port", is(5432))
            .body("database.username", is("reader"))
            .body("database.passwordSet", is(true))
            .body("database", not(hasKey("password")))
            .body("$", not(hasKey("s3")))
            .extract().path("id");

        given()
            .when().get("/api/datasources")
            .then()
            .statusCode(200)
            .body("name", hasItem("warehouse"));

        given()
            .when().get("/api/datasources/" + id)
            .then()
            .statusCode(200)
            .body("name", is("warehouse"))
            .body("database.passwordSet", is(true));

        given().when().delete("/api/datasources/" + id).then().statusCode(204);
        given().when().get("/api/datasources/" + id).then().statusCode(404);
        given().when().delete("/api/datasources/" + id).then().statusCode(404);
    }

    @Test
    void addsAnS3BucketAndAFolder() {
        given()
            .contentType(ContentType.JSON)
            .body("""
                {"name":"lake","type":"s3",
                 "s3":{"bucket":"datyx-lake","region":"eu-west-1","prefix":"raw/",
                       "accessKeyId":"AKIAEXAMPLE","secretAccessKey":"shh"}}
                """)
            .when().post("/api/datasources")
            .then()
            .statusCode(201)
            .body("type", is("s3"))
            .body("s3.bucket", is("datyx-lake"))
            .body("s3.endpoint", nullValue())
            .body("s3.accessKeyId", is("AKIAEXAMPLE"))
            .body("s3.secretAccessKeySet", is(true))
            .body("s3", not(hasKey("secretAccessKey")));

        given()
            .contentType(ContentType.JSON)
            .body("{\"name\":\"exports\",\"type\":\"filesystem\",\"filesystem\":{\"path\":\"/data/exports\"}}")
            .when().post("/api/datasources")
            .then()
            .statusCode(201)
            .body("type", is("filesystem"))
            .body("filesystem.path", is("/data/exports"));
    }

    @Test
    void rejectsMissingOrMismatchedDetailsAndTakenNames() {
        // No details for the type.
        given()
            .contentType(ContentType.JSON)
            .body("{\"name\":\"x1\",\"type\":\"s3\"}")
            .when().post("/api/datasources")
            .then()
            .statusCode(400)
            .body("error", containsString("'s3' details"));
        // Details of another type.
        given()
            .contentType(ContentType.JSON)
            .body("{\"name\":\"x2\",\"type\":\"filesystem\",\"s3\":{\"bucket\":\"b\"}}")
            .when().post("/api/datasources")
            .then()
            .statusCode(400);
        // Two kinds of details.
        given()
            .contentType(ContentType.JSON)
            .body("{\"name\":\"x3\",\"type\":\"filesystem\",\"filesystem\":{\"path\":\"/p\"},\"s3\":{\"bucket\":\"b\"}}")
            .when().post("/api/datasources")
            .then()
            .statusCode(400)
            .body("error", containsString("only"));
        // A field constraint (Hibernate Validator): the port out of range.
        given()
            .contentType(ContentType.JSON)
            .body("{\"name\":\"x4\",\"type\":\"database\",\"database\":{\"engine\":\"mysql\",\"host\":\"h\",\"port\":70000,\"database\":\"d\"}}")
            .when().post("/api/datasources")
            .then()
            .statusCode(400);
        // A blank name.
        given()
            .contentType(ContentType.JSON)
            .body("{\"name\":\" \",\"type\":\"filesystem\",\"filesystem\":{\"path\":\"/p\"}}")
            .when().post("/api/datasources")
            .then()
            .statusCode(400);
        // A name already taken, whatever its case.
        String body = "{\"name\":\"Twice\",\"type\":\"filesystem\",\"filesystem\":{\"path\":\"/p\"}}";
        given().contentType(ContentType.JSON).body(body).when().post("/api/datasources").then().statusCode(201);
        given().contentType(ContentType.JSON).body(body.replace("Twice", "twice"))
            .when().post("/api/datasources").then().statusCode(409).body("error", containsString("already exists"));
    }

    @Test
    void countsThemInTheStatus() {
        given().when().get("/api/status").then().statusCode(200).body("dataSources", notNullValue());
    }
}
