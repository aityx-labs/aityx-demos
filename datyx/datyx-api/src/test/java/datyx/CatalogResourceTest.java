package datyx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.sql.Connection;
import java.sql.Statement;
import java.sql.Types;
import java.util.List;

import datyx.catalog.SchemaReader;
import io.agroal.api.AgroalDataSource;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.Test;

/**
 * The catalogue against the Dev Services Postgres, which stands in for a
 * source: SchemaReader reads its tables, and the endpoints answer what
 * they can without OpenMetadata, which the tests don't start (a 502).
 */
@QuarkusTest
class CatalogResourceTest {

    @Inject
    AgroalDataSource dataSource;

    @ConfigProperty(name = "quarkus.datasource.jdbc.url")
    String jdbcUrl;

    @ConfigProperty(name = "quarkus.datasource.username")
    String username;

    @ConfigProperty(name = "quarkus.datasource.password")
    String password;

    @Test
    void readsTablesColumnsAndKeys() throws Exception {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("create schema if not exists shop");
            s.execute("""
                create table if not exists shop.sales_hourly (
                  store text not null, hour timestamptz not null, sold int not null, price numeric(8,2),
                  primary key (store, hour))""");
            s.execute("comment on table shop.sales_hourly is 'Sales per store and hour'");
            s.execute("comment on column shop.sales_hourly.sold is 'Units sold'");
            s.execute("create or replace view shop.stores as select distinct store from shop.sales_hourly");
        }
        List<SchemaReader.Table> tables;
        try (Connection c = dataSource.getConnection()) {
            tables = SchemaReader.read(c);
        }
        SchemaReader.Table sales = tables.stream().filter(t -> t.name().equals("sales_hourly")).findFirst().orElseThrow();
        assertEquals("shop", sales.schema());
        assertEquals("TABLE", sales.type());
        assertEquals("Sales per store and hour", sales.comment());
        assertEquals(List.of("store", "hour", "sold", "price"), sales.columns().stream().map(SchemaReader.Column::name).toList());
        assertEquals(List.of("store", "hour"), sales.primaryKey());
        SchemaReader.Column sold = sales.columns().get(2);
        assertEquals(Types.INTEGER, sold.jdbcType());
        assertEquals("Units sold", sold.comment());
        assertEquals(false, sold.nullable());
        assertEquals("timestamptz", sales.columns().get(1).typeName());
        assertTrue(tables.stream().anyMatch(t -> t.name().equals("stores") && t.type().equals("VIEW")));
        assertTrue(tables.stream().noneMatch(t -> t.schema().equals("pg_catalog") || t.schema().equals("information_schema")));
    }

    @Test
    void readsOnlyDatabaseAndKafkaSources() {
        int id = given().contentType(ContentType.JSON)
            .body("{\"name\":\"catalogue lake\",\"type\":\"s3\",\"s3\":{\"bucket\":\"b\"}}")
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        given().when().post("/api/datasources/" + id + "/catalog")
            .then().statusCode(400).body("error", is("only database and kafka sources have a catalogue, not s3"));
        given().when().delete("/api/datasources/" + id).then().statusCode(204);
    }

    @Test
    void saysWhenTheSourceOrOpenMetadataCantBeReached() {
        URI url = URI.create(jdbcUrl.substring("jdbc:".length()));
        String database = url.getPath().substring(1);
        int wrong = source("catalogue wrong password", url, database, "not-" + password);
        given().when().post("/api/datasources/" + wrong + "/catalog")
            .then().statusCode(502).body("error", startsWith("the data source can't be read: "));

        // The source reads; OpenMetadata, closed in tests, is what fails.
        int right = source("catalogue test database", url, database, password);
        given().when().post("/api/datasources/" + right + "/catalog")
            .then().statusCode(502).body("error", startsWith("OpenMetadata "));
        given().when().get("/api/datasources/" + right + "/timeseries")
            .then().statusCode(502).body("error", startsWith("OpenMetadata "));
        given().when().get("/api/datasources/" + right + "/timeseries?algorithm=XGBoost")
            .then().statusCode(502).body("error", startsWith("OpenMetadata "));
        given().when().get("/api/datasources/" + right + "/timeseries?algorithm=Prophet")
            .then().statusCode(400).body("error", is("the algorithm is DeepAR or XGBoost, not 'Prophet'"));
        // Removing a source doesn't wait on the catalogue.
        given().when().delete("/api/datasources/" + right).then().statusCode(204);
        given().when().delete("/api/datasources/" + wrong).then().statusCode(204);
    }

    @Test
    void saysWhenAKafkaClusterCantBeReached() {
        int id = given().contentType(ContentType.JSON)
            .body("{\"name\":\"catalogue stream\",\"type\":\"kafka\",\"kafka\":{\"bootstrapServers\":\"localhost:1\"}}")
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        given().when().post("/api/datasources/" + id + "/catalog")
            .then().statusCode(502).body("error", startsWith("the data source can't be read: "));
        // Its topics are OpenMetadata's to answer, closed in tests.
        given().when().get("/api/datasources/" + id + "/catalog")
            .then().statusCode(502).body("error", startsWith("OpenMetadata "));
        given().when().delete("/api/datasources/" + id).then().statusCode(204);
    }

    @Test
    void answers404ForAnotherSource() {
        given().when().post("/api/datasources/987654/catalog").then().statusCode(404);
        given().when().get("/api/datasources/987654/timeseries").then().statusCode(404);
        given().contentType(ContentType.JSON).body("{\"table\":\"t\"}")
            .when().put("/api/datasources/987654/timeseries").then().statusCode(404);
    }

    private int source(String name, URI url, String database, String secret) {
        return given().contentType(ContentType.JSON)
            .body("""
                {"name":"%s","type":"database","database":{"engine":"postgresql","host":"%s","port":%d,
                 "database":"%s","username":"%s","password":"%s"}}
                """.formatted(name, url.getHost(), url.getPort(), database, username, secret))
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
    }
}
