package datyx.training;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.notNullValue;
import static org.hamcrest.Matchers.nullValue;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import datyx.catalog.Catalog;
import datyx.catalog.CatalogEvents;
import datyx.catalog.GroupEvent;
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
        long runId = training.queueManual(id, spec, TimeSeries.Algorithm.XGBOOST).orElseThrow();
        assertTrue(training.queueManual(id, spec, TimeSeries.Algorithm.XGBOOST).isEmpty(), "one run of a group's algorithm at a time");
        long deepAr = training.queueManual(id, spec, TimeSeries.Algorithm.DEEPAR).orElseThrow();
        assertTrue(deepAr != runId, "another algorithm's run beside it");
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
            .body("runs[0].id", is((int) deepAr)).body("runs[0].algorithm", is("DeepAR")).body("runs[0].status", is("failed"))
            .body("runs[1].id", is((int) runId)).body("errors[0]", notNullValue());
        given().when().delete("/api/datasources/" + id).then().statusCode(204);
        given().when().get("/api/training/runs/" + runId).then().statusCode(404);
    }

    /**
     * The catalogue as OpenMetadata would answer it, without OpenMetadata:
     * admissions_hourly of data source {@code sourceId}, with its acute
     * group (DeepAR) and its chronic group ({@code chronicTags}: DeepAR by
     * default) switched off or on, at a table version by admin; what the
     * table's history says; and datyx's switch, which changes the version.
     */
    static class FakeCatalog extends Catalog {

        long sourceId = 9;

        boolean chronicOff = true;

        String chronicTags = "";

        String horizon;

        String version = "0.9";

        Instant updatedAt = Instant.parse("2026-11-01T12:00:00Z");

        Catalog.Change acuteEnabled;

        /** chronic removed: its columns' roles gone, as its algorithms' and Disabled tags. */
        boolean chronicGone;

        String fqn() {
            return "datyx-ds-" + sourceId + ".healthhub.public.admissions_hourly";
        }

        JsonNode hourly() {
            try {
                List<String> tags = new java.util.ArrayList<>();
                if (chronicOff) {
                    tags.add("{\"tagFQN\":\"TimeSeries.chronic.Disabled\"}");
                }
                if (!chronicTags.isEmpty()) {
                    tags.add(chronicTags);
                }
                String table = """
                    {"id":"t-9","name":"admissions_hourly","fullyQualifiedName":"%s",
                     "databaseSchema":{"name":"public"},"version":%s,"updatedBy":"admin","updatedAt":%d,
                     "tags":[%s],
                     "columns":[
                      {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"TimeSeries.acute.SeriesKey"},{"tagFQN":"TimeSeries.chronic.SeriesKey"}]},
                      {"name":"hour_start","dataType":"TIMESTAMP","tags":[{"tagFQN":"TimeSeries.acute.Timestamp"},{"tagFQN":"TimeSeries.chronic.Timestamp"}]},
                      {"name":"acute_admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.acute.Target"}]},
                      {"name":"chronic_admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.chronic.Target"}]}],
                     "extension":{"timeSeriesFrequency":"1h","timeSeriesMissing":"zero"%s}}
                    """.formatted(fqn(), version, updatedAt.toEpochMilli(), String.join(",", tags),
                        horizon == null ? "" : ",\"timeSeriesHorizon\":\"" + horizon + "\"");
                return new ObjectMapper().readTree(chronicGone ? table.replaceAll(",?\\{\"tagFQN\":\"TimeSeries\\.chronic\\.\\w+\"}", "")
                    : table);
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

        /** OpenMetadata's next version after a change, as datyx's switch would make it. */
        void changed(String next) {
            version = next;
            updatedAt = Instant.now();
        }

        @Override
        public Catalog.Switched setEnabled(JsonNode table, String group, boolean enabled) {
            if (!"chronic".equals(group)) {
                throw new java.util.NoSuchElementException("only chronic switches here");
            }
            boolean patched = chronicOff == enabled;
            if (patched) {
                chronicOff = !enabled;
                changed(String.valueOf(Double.parseDouble(version) + 0.1).substring(0, 3));
            }
            JsonNode now = hourly();
            return new Catalog.Switched(TimeSeries.spec(now, "chronic"), Catalog.latestChange(now), patched);
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

    private int source(String name) {
        return given().contentType(ContentType.JSON)
            .body("""
                {"name":"%s","type":"database",
                 "database":{"engine":"postgresql","host":"localhost","port":5432,"database":"clinic","username":"u","password":"p"}}"""
                .formatted(name))
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
    }

    private List<GroupEvent> eventsOf(long sourceId) {
        return QuarkusTransaction.requiringNew().call(() -> GroupEvent.<GroupEvent>list("dataSource.id = ?1 order by id", sourceId));
    }

    @Test
    void switchingAGroupOnIsWhatTrainsIt() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = source("switched clinic");
        catalog.sourceId = id;
        try {
            // Off: not trained, though never trained; acute is DeepAR's, so nothing schedules it either.
            training.checkSource(id);
            assertTrue(runsOf(id).isEmpty());

            // Switched on (its Disabled tag removed) in OpenMetadata, no webhook told: one run, ENABLED, whatever the algorithm.
            catalog.chronicOff = false;
            catalog.updatedAt = Instant.now();
            training.checkSource(id);
            List<TrainingRun> runs = runsOf(id);
            assertEquals(1, runs.size());
            TrainingRun run = runs.get(0);
            assertEquals(TrainingRun.Trigger.ENABLED, run.trigger);
            assertEquals("chronic", run.groupName);
            assertEquals("DeepAR", run.algorithm);
            assertEquals("TimeSeries.chronic.Disabled removed in OpenMetadata ("
                + new Catalog.Change("0.9", "admin", catalog.updatedAt).describe() + ")", run.triggerNote);
            List<GroupEvent> events = eventsOf(id);
            assertEquals(1, events.size(), "the check keeps the switch it queued");
            assertEquals(GroupEvent.VIA_POLL, events.get(0).via);
            assertEquals(List.of(run.id), events.get(0).runIds());
            assertEquals(events.get(0).id, run.eventId);
            TrainingRun done = waitDone(run.id);
            assertEquals(TrainingRun.Status.FAILED, done.status);
            assertTrue(done.error.startsWith("datyx has no DeepAR trainer yet: only XGBoost groups train"), done.error);

            // Once: the next look trains it no more, nor keeps a switch.
            training.checkSource(id);
            assertEquals(1, runsOf(id).size());
            assertEquals(1, eventsOf(id).size());

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

    /** The secret the tests' OpenMetadata signs with (application.properties, %test). */
    private static final byte[] SECRET = "test-webhook-secret".getBytes(StandardCharsets.UTF_8);

    /** OpenMetadata's change event of the fake's table: its chronic group's Disabled tag removed (on) or added (off). */
    private String chronicSwitched(FakeCatalog catalog, boolean on, String eventId) throws Exception {
        String labels = json.writeValueAsString(json.writeValueAsString(List.of(java.util.Map.of("tagFQN", "TimeSeries.chronic.Disabled",
            "source", "Classification", "labelType", "Manual", "state", "Confirmed"))));
        ObjectNode event = json.createObjectNode()
            .put("id", eventId)
            .put("eventType", "entityUpdated")
            .put("entityType", "table")
            .put("entityFullyQualifiedName", catalog.fqn())
            .put("currentVersion", Double.parseDouble(catalog.version))
            .put("userName", "julio")
            .put("timestamp", catalog.updatedAt.toEpochMilli());
        event.set("changeDescription", json.readTree(on
            ? "{\"fieldsAdded\":[],\"fieldsUpdated\":[],\"fieldsDeleted\":[{\"name\":\"tags\",\"oldValue\":" + labels + "}]}"
            : "{\"fieldsAdded\":[{\"name\":\"tags\",\"newValue\":" + labels + "}],\"fieldsUpdated\":[],\"fieldsDeleted\":[]}"));
        event.put("entity", catalog.hourly().toString());
        return json.writeValueAsString(event);
    }

    private io.restassured.response.ValidatableResponse post(String body, String signature) {
        var request = given().contentType(ContentType.JSON).body(body.getBytes(StandardCharsets.UTF_8));
        if (signature != null) {
            request.header(CatalogEvents.SIGNATURE_HEADER, signature);
        }
        return request.when().post("/api/catalog/openmetadata-events").then();
    }

    @Test
    void openMetadatasPostIsSignedOrRefused() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = source("signed clinic");
        catalog.sourceId = id;
        try {
            catalog.chronicOff = false;
            catalog.changed("1.0");
            String body = chronicSwitched(catalog, true, "e-signed");
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            post(body, null).statusCode(401);
            post(body, "sha256=" + java.util.Base64.getEncoder().encodeToString(new byte[32])).statusCode(401);
            post(body, CatalogEvents.sign("another secret".getBytes(StandardCharsets.UTF_8), bytes)).statusCode(401);
            post(body + " ", CatalogEvents.sign(SECRET, bytes)).statusCode(401);
            assertTrue(eventsOf(id).isEmpty() && runsOf(id).isEmpty(), "a refused post changes nothing");
            post("x".repeat(1024 * 1024 + 1), CatalogEvents.sign(SECRET, "x".repeat(1024 * 1024 + 1).getBytes(StandardCharsets.UTF_8)))
                .statusCode(413);
            post("not json", CatalogEvents.sign(SECRET, "not json".getBytes(StandardCharsets.UTF_8))).statusCode(400);
            post(body, CatalogEvents.sign(SECRET, bytes)).statusCode(200).body("recorded", hasSize(1));
            assertEquals(1, eventsOf(id).size());
            waitDone(runsOf(id).get(0).id);
            // Another source's service, and one datyx doesn't have: nothing.
            String other = body.replace("datyx-ds-" + id + ".", "datyx-ds-987654.");
            post(other, CatalogEvents.sign(SECRET, other.getBytes(StandardCharsets.UTF_8))).statusCode(200).body("recorded", hasSize(0));
        } finally {
            given().when().delete("/api/datasources/" + id).then().statusCode(204);
        }
    }

    @Test
    void aSwitchOnQueuesEveryAlgorithmOnceWhoeverTellsFirst() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        catalog.chronicTags = "{\"tagFQN\":\"TimeSeries.chronic.DeepAR\"},{\"tagFQN\":\"TimeSeries.chronic.XGBoost\"}";
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = source("algorithms clinic");
        catalog.sourceId = id;
        try {
            training.checkSource(id);
            assertTrue(runsOf(id).isEmpty(), "off: nothing; chronic's XGBoost isn't ready (no horizon), acute is DeepAR's");

            // datyx's switch: the switch kept, one run per algorithm queued at once.
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\",\"enabled\":true}")
                .when().put("/api/datasources/" + id + "/timeseries/enabled").then().statusCode(200)
                .body("enabled", is(true)).body("algorithms", is(List.of("XGBoost", "DeepAR")))
                .body("event.id", notNullValue()).body("event.runIds", hasSize(2));
            List<TrainingRun> runs = runsOf(id);
            assertEquals(List.of("XGBoost", "DeepAR"), runs.stream().map(r -> r.algorithm).toList());
            assertTrue(runs.stream().allMatch(r -> r.trigger == TrainingRun.Trigger.ENABLED));
            String note = "TimeSeries.chronic.Disabled removed through datyx's switch ("
                + new Catalog.Change("1.0", "admin", catalog.updatedAt).describe() + ")";
            assertTrue(runs.stream().allMatch(r -> note.equals(r.triggerNote)), runs.get(0).triggerNote);
            List<GroupEvent> events = eventsOf(id);
            assertEquals(1, events.size());
            assertEquals(GroupEvent.VIA_API, events.get(0).via);
            assertEquals("1.0", events.get(0).omVersion);
            assertTrue(runs.stream().allMatch(r -> events.get(0).id.equals(r.eventId)));

            // The same change, as OpenMetadata's webhook and the check see it later: nothing more.
            String on = chronicSwitched(catalog, true, "e-on-1");
            post(on, CatalogEvents.sign(SECRET, on.getBytes(StandardCharsets.UTF_8))).statusCode(200).body("recorded", hasSize(0));
            training.checkSource(id);
            assertEquals(2, runsOf(id).size());
            assertEquals(1, eventsOf(id).size());
            TrainingRun xgb = waitDone(runs.get(0).id);
            TrainingRun deepAr = waitDone(runs.get(1).id);
            assertTrue(xgb.error.startsWith("the group isn't ready: the table has no timeSeriesHorizon"), xgb.error);
            assertEquals("datyx has no DeepAR trainer yet: only XGBoost groups train (this group's XGBoost run trains it with XGBoost)",
                deepAr.error);
            training.checkSource(id);
            post(on, CatalogEvents.sign(SECRET, on.getBytes(StandardCharsets.UTF_8))).statusCode(200).body("recorded", hasSize(0));
            assertEquals(2, runsOf(id).size(), "their failing doesn't queue them again");

            // Switched off and on in OpenMetadata's UI: its webhook tells, the runs queued once, whatever is delivered again.
            catalog.chronicOff = true;
            catalog.changed("1.1");
            String off = chronicSwitched(catalog, false, "e-off");
            post(off, CatalogEvents.sign(SECRET, off.getBytes(StandardCharsets.UTF_8))).statusCode(200).body("recorded", hasSize(1));
            catalog.chronicOff = false;
            catalog.changed("1.2");
            String again = chronicSwitched(catalog, true, "e-on-2");
            post(again, CatalogEvents.sign(SECRET, again.getBytes(StandardCharsets.UTF_8))).statusCode(200)
                .body("recorded", hasSize(1)).body("recorded[0].runIds", hasSize(2));
            post(again, CatalogEvents.sign(SECRET, again.getBytes(StandardCharsets.UTF_8))).statusCode(200).body("recorded", hasSize(0));
            training.checkSource(id);
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\",\"enabled\":true}")
                .when().put("/api/datasources/" + id + "/timeseries/enabled").then().statusCode(200).body("event", nullValue());
            runs = runsOf(id);
            assertEquals(4, runs.size());
            assertEquals("TimeSeries.chronic.Disabled removed in OpenMetadata ("
                + new Catalog.Change("1.2", "julio", catalog.updatedAt).describe() + "; webhook)", runs.get(3).triggerNote);
            waitDone(runs.get(2).id);
            waitDone(runs.get(3).id);

            given().when().get("/api/catalog/events").then().statusCode(200)
                .body("events.findAll { it.sourceId == " + id + " }", hasSize(3))
                .body("events.find { it.sourceId == " + id + " }.via", is("openmetadata-webhook"))
                .body("events.find { it.sourceId == " + id + " }.enabled", is(true))
                .body("events.find { it.sourceId == " + id + " }.version", is("1.2"))
                .body("events.find { it.sourceId == " + id + " }.by", is("julio"))
                .body("events.find { it.sourceId == " + id + " }.group", is("chronic"))
                .body("events.find { it.sourceId == " + id + " }.name", is("admissions_hourly"))
                .body("events.find { it.sourceId == " + id + " }.runIds", hasSize(2))
                .body("events.findAll { it.sourceId == " + id + " }[1].enabled", is(false))
                .body("events.findAll { it.sourceId == " + id + " }[2].via", is("datyx-api"));
            given().when().get("/api/training/runs/" + runs.get(3).id).then().statusCode(200)
                .body("run.eventId", is(eventsOf(id).get(2).id.intValue())).body("run.algorithm", is("DeepAR"));

            // Asked for by hand: an algorithm of the group's, XGBoost; DeepAR has no trainer; off isn't trained.
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\",\"algorithm\":\"DeepAR\"}")
                .when().post("/api/datasources/" + id + "/training").then().statusCode(409)
                .body("error", is("the group chronic of admissions_hourly can't be trained with DeepAR: datyx has no DeepAR trainer yet, only XGBoost's"));
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\",\"algorithm\":\"Prophet\"}")
                .when().post("/api/datasources/" + id + "/training").then().statusCode(400);
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"acute\",\"algorithm\":\"XGBoost\"}")
                .when().post("/api/datasources/" + id + "/training").then().statusCode(409)
                .body("error", startsWith("the group acute of admissions_hourly can't be trained with XGBoost: it isn't tagged for it"));
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\"}")
                .when().post("/api/datasources/" + id + "/training").then().statusCode(409)
                .body("error", startsWith("the group chronic of admissions_hourly can't be trained: the table has no timeSeriesHorizon"));
            catalog.horizon = "24h";
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\",\"algorithm\":\"xgboost\"}")
                .when().post("/api/datasources/" + id + "/training").then().statusCode(202)
                .body("algorithm", is("XGBoost")).body("trigger", is("manual")).body("eventId", nullValue());
            catalog.chronicOff = true;
            given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\"}")
                .when().post("/api/datasources/" + id + "/training").then().statusCode(409)
                .body("error", startsWith("the group chronic of admissions_hourly can't be trained: it is switched off"));
            waitDone(runsOf(id).get(4).id);
        } finally {
            given().when().delete("/api/datasources/" + id).then().statusCode(204);
        }
    }

    /** datyx's switch of the fake's chronic group, which keeps a switch. */
    private void switchChronic(int id, boolean on) {
        given().contentType(ContentType.JSON).body("{\"table\":\"public.admissions_hourly\",\"group\":\"chronic\",\"enabled\":" + on + "}")
            .when().put("/api/datasources/" + id + "/timeseries/enabled").then().statusCode(200).body("event.id", notNullValue());
    }

    private void waitAllDone(long sourceId) throws InterruptedException {
        for (TrainingRun run : runsOf(sourceId)) {
            waitDone(run.id);
        }
    }

    private io.restassured.response.ValidatableResponse postSigned(String body) {
        return post(body, CatalogEvents.sign(SECRET, body.getBytes(StandardCharsets.UTF_8)));
    }

    @Test
    void aSwitchOffToldLateDoesntQueueTheSwitchOnAfterItAgain() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        catalog.chronicTags = "{\"tagFQN\":\"TimeSeries.chronic.DeepAR\"},{\"tagFQN\":\"TimeSeries.chronic.XGBoost\"}";
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = source("late clinic");
        catalog.sourceId = id;
        try {
            // datyx's switch on (1.0), off (1.1) and on again (1.2), quicker than OpenMetadata's webhook tells.
            switchChronic(id, true);
            waitAllDone(id);
            switchChronic(id, false);
            String off = chronicSwitched(catalog, false, "e-late-off");
            switchChronic(id, true);
            String on = chronicSwitched(catalog, true, "e-late-on");
            assertEquals(4, runsOf(id).size());
            waitAllDone(id);
            // Its posts come now: the off is known, and older than the switch on after it; the on is known.
            postSigned(off).statusCode(200).body("recorded", hasSize(0));
            postSigned(on).statusCode(200).body("recorded", hasSize(0));
            training.checkSource(id);
            assertEquals(4, runsOf(id).size(), "no run queued again");
            assertEquals(List.of(true, false, true), eventsOf(id).stream().map(e -> e.enabled).toList());

            // Switched off in OpenMetadata's UI (1.3), on again through datyx (1.4) before the webhook tells of the off.
            catalog.chronicOff = true;
            catalog.changed("1.3");
            String uiOff = chronicSwitched(catalog, false, "e-ui-off");
            Thread.sleep(5);
            switchChronic(id, true);
            String uiOn = chronicSwitched(catalog, true, "e-ui-on");
            assertEquals(6, runsOf(id).size());
            waitAllDone(id);
            postSigned(uiOff).statusCode(200).body("recorded", hasSize(0));
            postSigned(uiOn).statusCode(200).body("recorded", hasSize(0));
            training.checkSource(id);
            assertEquals(6, runsOf(id).size(), "no run queued again");
            assertEquals(List.of(true, false, true, true), eventsOf(id).stream().map(e -> e.enabled).toList(),
                "the group isn't shown off while it is on");
        } finally {
            given().when().delete("/api/datasources/" + id).then().statusCode(204);
        }
    }

    @Test
    void theCheckSeesASwitchOnAgainAtAVersionOpenMetadataGaveBefore() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = source("merged clinic");
        catalog.sourceId = id;
        try {
            // No webhook: the check sees chronic off, then on (0.8), and queues it.
            training.checkSource(id);
            catalog.chronicOff = false;
            catalog.changed("0.8");
            Instant onAt = catalog.updatedAt;
            training.checkSource(id);
            assertEquals(1, runsOf(id).size());
            waitAllDone(id);

            // Off (0.9), seen by the check; on again by the same user within minutes, merged by OpenMetadata back into 0.8.
            catalog.chronicOff = true;
            catalog.changed("0.9");
            training.checkSource(id);
            catalog.chronicOff = false;
            catalog.version = "0.8";
            catalog.updatedAt = onAt;
            training.checkSource(id);
            List<TrainingRun> runs = runsOf(id);
            assertEquals(2, runs.size(), "another switch on, though at the version of the one before");
            assertEquals(TrainingRun.Trigger.ENABLED, runs.get(1).trigger);
            assertTrue(runs.get(1).triggerNote.contains("OpenMetadata merged it into table version 0.8"), runs.get(1).triggerNote);
            assertEquals(2, eventsOf(id).size());
            waitAllDone(id);
            training.checkSource(id);
            assertEquals(2, runsOf(id).size(), "once");
        } finally {
            given().when().delete("/api/datasources/" + id).then().statusCode(204);
        }
    }

    @Test
    void removingASwitchedOffGroupSwitchesNothingOn() throws Exception {
        FakeCatalog catalog = new FakeCatalog();
        QuarkusMock.installMockForType(catalog, Catalog.class);
        int id = source("removed clinic");
        catalog.sourceId = id;
        try {
            // chronic, switched off, removed: its roles, its algorithms and its Disabled tag in one change.
            catalog.chronicOff = false;
            catalog.chronicGone = true;
            catalog.changed("1.0");
            String gone = chronicSwitched(catalog, true, "e-gone");
            postSigned(gone).statusCode(200).body("recorded", hasSize(0));
            training.checkSource(id);
            assertTrue(runsOf(id).isEmpty(), "no run of a group that isn't there");
            assertTrue(eventsOf(id).isEmpty());
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
