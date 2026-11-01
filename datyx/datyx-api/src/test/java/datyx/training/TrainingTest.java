package datyx.training;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.notNullValue;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.sql.Connection;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.Catalog;
import datyx.catalog.TimeSeries;
import datyx.datasource.DataSource;
import io.agroal.api.AgroalDataSource;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;

/**
 * Training against the Dev Services Postgres, which stands in for a
 * source's table; OpenMetadata isn't started, so the endpoints that need
 * it answer what they can, and the trainer's own check is off.
 */
@QuarkusTest
class TrainingTest {

    @Inject
    AgroalDataSource dataSource;

    @Inject
    Training training;

    private final ObjectMapper json = new ObjectMapper();

    /** clinic.patient_days, a column's name needing quotes, tagged as the care group for XGBoost, 14 days ahead. */
    private TimeSeries.Spec spec() throws Exception {
        return TimeSeries.spec(json.readTree("""
            {"name":"patient_days","fullyQualifiedName":"datyx-ds-9.quarkus.clinic.patient_days",
             "databaseSchema":{"name":"clinic"},"tags":[{"tagFQN":"TimeSeries.care.XGBoost"}],
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"person_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"day","dataType":"DATE","tags":[{"tagFQN":"TimeSeries.care.Timestamp"}]},
              {"name":"chronic","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.StaticCategorical"}]},
              {"name":"age","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.StaticReal"}]},
              {"name":"stay \\"hours\\"","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.Target"}]}],
             "extension":{"timeSeriesFrequency":"1D","timeSeriesMissing":"zero","timeSeriesHorizon":"14D","timeSeriesRetrain":"6h"}}
            """), "care");
    }

    @Test
    void readsTheGroupsTableAndTrainsOnIt() throws Exception {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("create schema if not exists clinic");
            s.execute("drop table if exists clinic.patient_days");
            s.execute("""
                create table clinic.patient_days (run_id text, person_id text, day date, chronic text, age int,
                  "stay ""hours""\" int, note text)""");
            // 40 people over 240 days: the chronic ones every 10 days for 3 hours, everyone now and then.
            s.execute("""
                insert into clinic.patient_days
                select 'r1', 'p' || p, date '2026-01-01' + d, case when p % 2 = 0 then 'copd' else 'none' end, 30 + p,
                       (case when p % 2 = 0 and d % 10 = p % 10 then 3 else 0 end)
                       + (case when (p * 31 + d * 17) % 53 = 0 then 1 else 0 end), 'not read'
                from generate_series(0, 39) p, generate_series(0, 239) d
                where (p % 2 = 0 and d % 10 = p % 10) or (p * 31 + d * 17) % 53 = 0 or d = 0""");
        }
        TimeSeries.Spec spec = spec();
        assertTrue(spec.ready(), spec.problems().toString());
        assertEquals("SELECT \"day\", \"stay \"\"hours\"\"\", \"run_id\", \"person_id\", \"chronic\", \"age\" "
            + "FROM \"clinic\".\"patient_days\"", TableReader.query(spec));
        Dataset.Builder builder = new Dataset.Builder(spec);
        try (Connection c = dataSource.getConnection()) {
            TableReader.read(c, spec, builder);
        }
        Dataset data = builder.build();
        assertEquals(40, data.summary.series());
        assertEquals(40 * 240, data.summary.steps());
        XgbTrainer.Trained trained = XgbTrainer.train(data);
        XgbTrainer.Metrics test = trained.result().test();
        assertTrue(test.mae() < test.naiveMae(), test.toString());
        assertEquals(25, trained.result().scores().size());
        assertTrue(trained.result().scores().get(0).series().get("person_id").startsWith("p"));
    }

    @Test
    void schedulesFromTheLatestRunAndTheTablesRetrain() {
        Instant at = Instant.parse("2026-11-01T10:00:00Z");
        assertEquals(Optional.of(Instant.EPOCH), Training.nextAt(null, "6h"), "never trained: now");
        assertEquals(Optional.of(at.plus(Duration.ofHours(6))), Training.nextAt(run(TrainingRun.Status.SUCCEEDED, at), "6h"));
        assertEquals(Optional.of(at.plus(Duration.ofDays(1))), Training.nextAt(run(TrainingRun.Status.SUCCEEDED, at), null),
            "1D when the table doesn't say");
        assertEquals(Optional.of(at.plus(Duration.ofHours(1))), Training.nextAt(run(TrainingRun.Status.FAILED, at), "1W"),
            "an hour after a failure, at most");
        assertEquals(Optional.of(at.plus(Duration.ofMinutes(30))), Training.nextAt(run(TrainingRun.Status.FAILED, at), "30min"));
        assertEquals(Optional.empty(), Training.nextAt(run(TrainingRun.Status.SUCCEEDED, at), "never"));
        assertEquals(Optional.empty(), Training.nextAt(run(TrainingRun.Status.RUNNING, at), "6h"), "one run at a time");
        assertTrue(Training.reason(new UnsatisfiedLinkError("no libomp")).startsWith("XGBoost's native library can't load"));
    }

    private static TrainingRun run(TrainingRun.Status status, Instant queuedAt) {
        TrainingRun run = new TrainingRun();
        run.status = status;
        run.queuedAt = queuedAt;
        return run;
    }

    @Test
    void aRunAStopInterruptedIsFailedAtStart() throws Exception {
        int id = given().contentType(ContentType.JSON)
            .body("""
                {"name":"training clinic","type":"database",
                 "database":{"engine":"postgresql","host":"localhost","port":5432,"database":"clinic","username":"u","password":"p"}}""")
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        TimeSeries.Spec spec = spec();
        long runId = QuarkusTransaction.requiringNew().call(() -> {
            TrainingRun run = training.queueManual(DataSource.findById((long) id), spec).orElseThrow();
            assertTrue(training.queueManual(DataSource.findById((long) id), spec).isEmpty(), "one run of a group at a time");
            return run.id;
        });
        training.onStart(null);
        QuarkusTransaction.requiringNew().run(() -> {
            TrainingRun run = TrainingRun.findById(runId);
            assertEquals(TrainingRun.Status.FAILED, run.status);
            assertEquals("interrupted: the API stopped before the run finished", run.error);
            assertEquals(TrainingRun.Trigger.MANUAL, run.trigger);
        });
        given().when().get("/api/training/runs/" + runId).then().statusCode(200)
            .body("run.status", is("failed")).body("run.trigger", is("manual")).body("run.group", is("care"))
            .body("run.name", is("patient_days"));
        given().when().get("/api/training").then().statusCode(200)
            .body("runs[0].id", is((int) runId)).body("errors[0]", notNullValue());
        given().when().delete("/api/datasources/" + id).then().statusCode(204);
        given().when().get("/api/training/runs/" + runId).then().statusCode(404);
    }

    /**
     * The catalogue as OpenMetadata would answer it, without OpenMetadata:
     * admissions_hourly with its chronic group (DeepAR) switched off or on,
     * at table version 0.9 by admin; and what the table's history says.
     */
    static class FakeCatalog extends Catalog {

        boolean chronicOff = true;

        Catalog.Change acuteEnabled;

        JsonNode hourly() {
            try {
                return new ObjectMapper().readTree("""
                    {"id":"t-9","name":"admissions_hourly","fullyQualifiedName":"datyx-ds-9.healthhub.public.admissions_hourly",
                     "databaseSchema":{"name":"public"},"version":0.9,"updatedBy":"admin","updatedAt":1793534400000,
                     "tags":%s,
                     "columns":[
                      {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"TimeSeries.acute.SeriesKey"},{"tagFQN":"TimeSeries.chronic.SeriesKey"}]},
                      {"name":"hour_start","dataType":"TIMESTAMP","tags":[{"tagFQN":"TimeSeries.acute.Timestamp"},{"tagFQN":"TimeSeries.chronic.Timestamp"}]},
                      {"name":"acute_admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.acute.Target"}]},
                      {"name":"chronic_admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.chronic.Target"}]}],
                     "extension":{"timeSeriesFrequency":"1h","timeSeriesMissing":"zero"}}
                    """.formatted(chronicOff ? "[{\"tagFQN\":\"TimeSeries.chronic.Disabled\"}]" : "[]"));
            } catch (Exception e) {
                throw new IllegalStateException(e);
            }
        }

        @Override
        public List<JsonNode> tables(long sourceId) {
            return List.of(hourly());
        }

        @Override
        public JsonNode table(String fqn) {
            return hourly();
        }

        @Override
        public void forget(long sourceId, DataSource.Type type) {
        }

        @Override
        public Optional<Catalog.Change> enabledAfter(JsonNode table, String group, Instant after) {
            return "acute".equals(group) && acuteEnabled != null && acuteEnabled.at().isAfter(after)
                ? Optional.of(acuteEnabled) : Optional.empty();
        }
    }

    private List<TrainingRun> runsOf(long sourceId) {
        return QuarkusTransaction.requiringNew().call(() -> TrainingRun.<TrainingRun>list("dataSource.id = ?1 order by id", sourceId));
    }

    private TrainingRun waitDone(long runId) throws InterruptedException {
        for (int i = 0; i < 100; i++) {
            TrainingRun run = QuarkusTransaction.requiringNew().call(() -> TrainingRun.findById(runId));
            if (run.status.done()) {
                return run;
            }
            Thread.sleep(100);
        }
        throw new AssertionError("run " + runId + " didn't finish");
    }

    @Test
    void switchingAGroupOnIsWhatTrainsIt() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = given().contentType(ContentType.JSON)
            .body("""
                {"name":"switched clinic","type":"database",
                 "database":{"engine":"postgresql","host":"localhost","port":5432,"database":"clinic","username":"u","password":"p"}}""")
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        try {
            // Off: not trained, though never trained; acute is DeepAR's, so nothing schedules it either.
            training.checkSource(id);
            assertTrue(runsOf(id).isEmpty());

            // Switched on (its Disabled tag removed): one run, ENABLED, whatever the algorithm.
            catalog.chronicOff = false;
            training.checkSource(id);
            List<TrainingRun> runs = runsOf(id);
            assertEquals(1, runs.size());
            TrainingRun run = runs.get(0);
            assertEquals(TrainingRun.Trigger.ENABLED, run.trigger);
            assertEquals("chronic", run.groupName);
            assertEquals("DeepAR", run.algorithm);
            assertEquals("TimeSeries.chronic.Disabled removed in OpenMetadata (table version 0.9, by admin, 2026-11-01 12:00 UTC)",
                run.triggerNote);
            TrainingRun done = waitDone(run.id);
            assertEquals(TrainingRun.Status.FAILED, done.status);
            assertTrue(done.error.startsWith("datyx has no DeepAR trainer yet: only XGBoost groups train"), done.error);

            // Once: the next look trains it no more.
            training.checkSource(id);
            assertEquals(1, runsOf(id).size());

            // OpenMetadata's history says acute was switched on (in its UI, while datyx wasn't looking).
            catalog.acuteEnabled = new Catalog.Change("0.8", "julio", Instant.parse("2026-11-01T11:00:00Z"));
            training.checkSource(id);
            runs = runsOf(id);
            assertEquals(2, runs.size());
            assertEquals("acute", runs.get(1).groupName);
            assertEquals("TimeSeries.acute.Disabled removed in OpenMetadata (table version 0.8, by julio, 2026-11-01 11:00 UTC)",
                runs.get(1).triggerNote);
            waitDone(runs.get(1).id);
            given().when().get("/api/training/runs/" + runs.get(1).id).then().statusCode(200)
                .body("run.trigger", is("enabled")).body("run.triggerNote", is(runs.get(1).triggerNote));
        } finally {
            given().when().delete("/api/datasources/" + id).then().statusCode(204);
        }
    }

    @Test
    void aSwitchedOffGroupIsNotTrainable() throws Exception {
        TimeSeries.Spec on = spec();
        assertTrue(Training.trainable(on));
        TimeSeries.Spec off = TimeSeries.spec(json.readTree(new ObjectMapper().writeValueAsString(
            json.readTree("""
                {"name":"patient_days","fullyQualifiedName":"f","databaseSchema":{"name":"clinic"},
                 "tags":[{"tagFQN":"TimeSeries.care.XGBoost"},{"tagFQN":"TimeSeries.care.Disabled"}],
                 "columns":[{"name":"day","dataType":"DATE","tags":[{"tagFQN":"TimeSeries.care.Timestamp"}]},
                  {"name":"h","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.Target"}]}],
                 "extension":{"timeSeriesFrequency":"1D","timeSeriesHorizon":"14D"}}"""))), "care");
        assertTrue(off.ready());
        assertTrue(!off.enabled() && !Training.trainable(off));
    }

    @Test
    void saysWhatItCantDo() {
        given().contentType(ContentType.JSON).body("{\"table\":\"t\",\"group\":\"care\",\"enabled\":true}")
            .when().put("/api/datasources/987654/timeseries/enabled").then().statusCode(404);
        given().contentType(ContentType.JSON).body("{\"table\":\"t\",\"group\":\"care\"}")
            .when().post("/api/datasources/987654/training").then().statusCode(404);
        given().contentType(ContentType.JSON).body("{}")
            .when().post("/api/datasources/987654/training").then().statusCode(400);
        given().contentType(ContentType.JSON).body("{\"table\":\"t\",\"retrain\":\"6h\"}")
            .when().put("/api/datasources/987654/training").then().statusCode(404);
        given().when().get("/api/training/runs/987654").then().statusCode(404);
    }
}
