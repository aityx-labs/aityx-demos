package datyx.training;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.notNullValue;
import static org.hamcrest.CoreMatchers.nullValue;
import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertEquals;

import java.net.URI;
import java.sql.Connection;
import java.sql.Statement;
import java.time.Instant;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.TimeSeries;
import datyx.datasource.DataSource;
import io.agroal.api.AgroalDataSource;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.Test;

/**
 * Inference against the Dev Services Postgres, which stands in for the
 * source: a model trained on a table scores its series through the API
 * as training scored them, and every call is accounted for.
 */
@QuarkusTest
class InferenceTest {

    @Inject
    AgroalDataSource dataSource;

    @Inject
    ObjectMapper json;

    @ConfigProperty(name = "quarkus.datasource.jdbc.url")
    String jdbcUrl;

    @ConfigProperty(name = "quarkus.datasource.username")
    String username;

    @ConfigProperty(name = "quarkus.datasource.password")
    String password;

    /** ward.stays: two runs of 30 people, a category and an INT in the key, tagged as the care group, 14 days ahead. */
    private TimeSeries.Spec spec() throws Exception {
        return TimeSeries.spec(json.readTree("""
            {"name":"stays","fullyQualifiedName":"datyx-ds-7.quarkus.ward.stays","databaseSchema":{"name":"ward"},
             "tags":[{"tagFQN":"TimeSeries.care.XGBoost"}],
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"person","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.SeriesKey"}]},
              {"name":"day","dataType":"DATE","tags":[{"tagFQN":"TimeSeries.care.Timestamp"}]},
              {"name":"chronic","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.care.StaticCategorical"}]},
              {"name":"hours","dataType":"INT","tags":[{"tagFQN":"TimeSeries.care.Target"}]}],
             "extension":{"timeSeriesFrequency":"1D","timeSeriesMissing":"zero","timeSeriesHorizon":"14D"}}
            """), "care");
    }

    @Test
    void scoresSeriesAsTrainingDidAndAccountsForEveryCall() throws Exception {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("create schema if not exists ward");
            s.execute("drop table if exists ward.stays");
            s.execute("create table ward.stays (run_id text, person int, day date, chronic text, hours int)");
            // Run a ends on day 199, run b (still going) on day 239; the chronic come every 10 days.
            s.execute("""
                insert into ward.stays
                select r, p, date '2026-01-01' + d, case when p % 3 = 0 then 'copd' when p % 3 = 1 then 'asthma' else 'none' end,
                       (case when p % 3 < 2 and d % 10 = p % 10 then 3 else 0 end) + (case when (p * 7 + d) % 41 = 0 then 1 else 0 end)
                from (values ('a', 199), ('b', 239)) runs(r, last), generate_series(0, 29) p, generate_series(0, 239) d
                where d <= last and ((p % 3 < 2 and d % 10 = p % 10) or (p * 7 + d) % 41 = 0 or d = 0)""");
        }
        TimeSeries.Spec spec = spec();
        Dataset.Builder builder = new Dataset.Builder(spec);
        try (Connection c = dataSource.getConnection()) {
            TableReader.read(c, spec, builder);
        }
        XgbTrainer.Trained trained = XgbTrainer.train(builder.build());
        assertEquals(25, trained.result().scores().size(), "run b's 30 people are still observed, the top 25 kept");

        URI url = URI.create(jdbcUrl.substring("jdbc:".length()));
        int sourceId = given().contentType(ContentType.JSON)
            .body("""
                {"name":"inference ward","type":"database","database":{"engine":"postgresql","host":"%s","port":%d,
                 "database":"%s","username":"%s","password":"%s"}}
                """.formatted(url.getHost(), url.getPort(), url.getPath().substring(1), username, password))
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        given().contentType(ContentType.JSON).body("{\"table\":\"ward.stays\",\"group\":\"care\"}")
            .when().post("/api/datasources/" + sourceId + "/inference").then().statusCode(404)
            .body("error", is("no model of the group care of ward.stays has been trained yet"));
        String results = json.writeValueAsString(trained.result());
        long runId = QuarkusTransaction.requiringNew().call(() -> {
            TrainingRun run = new TrainingRun();
            run.dataSource = DataSource.findById((long) sourceId);
            run.tableFqn = spec.table();
            run.groupName = "care";
            run.algorithm = "XGBoost";
            run.trigger = TrainingRun.Trigger.MANUAL;
            run.status = TrainingRun.Status.SUCCEEDED;
            run.queuedAt = Instant.now();
            run.finishedAt = Instant.now();
            run.results = results;
            run.model = trained.model();
            run.persist();
            // A later run of the group's other algorithm, as if datyx trained DeepAR: never what scores.
            TrainingRun deepAr = new TrainingRun();
            deepAr.dataSource = run.dataSource;
            deepAr.tableFqn = spec.table();
            deepAr.groupName = "care";
            deepAr.algorithm = "DeepAR";
            deepAr.trigger = TrainingRun.Trigger.ENABLED;
            deepAr.status = TrainingRun.Status.SUCCEEDED;
            deepAr.queuedAt = Instant.now().plusSeconds(1);
            deepAr.finishedAt = Instant.now().plusSeconds(2);
            deepAr.results = "{}";
            deepAr.persist();
            return run.id;
        });

        // One person by key, as training scored them, though only their rows and their run's end are read.
        XgbTrainer.Score top = trained.result().scores().get(0);
        JsonNode one = json.readTree(given().contentType(ContentType.JSON)
            .body(Map.of("table", "ward.stays", "group", "care",
                "series", List.of(top.series(), Map.of("run_id", "b", "person", "999"))))
            .when().post("/api/datasources/" + sourceId + "/inference").then().statusCode(200)
            .body("runId", is((int) runId)).body("requested", is(2)).body("scored", is(1))
            .body("target", is("hours")).body("horizon", is("14D"))
            .body("predictions[1].predicted", nullValue()).body("predictions[1].note", is("no rows for this series"))
            .extract().asString());
        assertEquals(top.predicted(), one.path("predictions").get(0).path("predicted").asDouble(), 0.001);
        assertEquals(top.last(), one.path("predictions").get(0).path("last").asDouble(), 0.001);

        // None named: every series still observed, the highest first, as training's scores.
        JsonNode all = json.readTree(given().contentType(ContentType.JSON)
            .body("{\"table\":\"stays\",\"group\":\"care\",\"limit\":5}")
            .when().post("/api/datasources/" + sourceId + "/inference").then().statusCode(200)
            .body("predictions", hasSize(5)).body("requested", is(0)).extract().asString());
        for (int i = 0; i < 5; i++) {
            assertEquals(trained.result().scores().get(i).predicted(), all.path("predictions").get(i).path("predicted").asDouble(),
                0.001);
        }

        // A series without its whole key is refused, and accounted for as a failure.
        given().contentType(ContentType.JSON)
            .body(Map.of("table", "ward.stays", "group", "care", "series", List.of(Map.of("run_id", "b"))))
            .when().post("/api/datasources/" + sourceId + "/inference").then().statusCode(400)
            .body("error", is("a series names its key: run_id, person"));

        given().when().get("/api/inference").then().statusCode(200)
            .body("totals.calls", is(3)).body("totals.failed", is(1)).body("totals.scored", is(6))
            .body("lastHour", is(3)).body("hours", is(24)).body("perHour", hasSize(24)).body("perHour[23].calls", is(3))
            .body("perHour[23].failed", is(1)).body("perHour[23].scored", is(6))
            .body("perHour[23].p50Millis", notNullValue()).body("perHour[23].p95Millis", notNullValue())
            .body("perHour[23].byModel", hasSize(1)).body("perHour[23].byModel[0].algorithm", is("XGBoost"))
            .body("perHour[23].byModel[0].group", is("care")).body("perHour[23].byModel[0].name", is("stays"))
            .body("perHour[23].byModel[0].calls", is(3)).body("perHour[23].byModel[0].failed", is(1))
            .body("perHour[22].calls", is(0)).body("perHour[22].p50Millis", nullValue()).body("perHour[22].byModel", hasSize(0))
            .body("models.find { it.runId == " + runId + " }.stats.calls", is(3))
            .body("models.find { it.runId == " + runId + " }.algorithm", is("XGBoost"))
            .body("models.find { it.runId == " + runId + " }.seriesKey", is(List.of("run_id", "person")))
            // A model each algorithm the group has: XGBoost's answered every call, DeepAR's none.
            .body("models.findAll { it.table == 'datyx-ds-7.quarkus.ward.stays' }", hasSize(2))
            .body("models.find { it.table == 'datyx-ds-7.quarkus.ward.stays' && it.algorithm == 'DeepAR' }.stats.calls", is(0))
            .body("calls", hasSize(3)).body("calls[0].status", is("failed")).body("calls[2].requested", is(2))
            .body("calls[0].algorithm", is("XGBoost"));
        // Hour by hour over the whole window, at most; at least one.
        given().when().get("/api/inference?hours=168").then().statusCode(200)
            .body("hours", is(168)).body("perHour", hasSize(168)).body("perHour[167].calls", is(3));
        given().when().get("/api/inference?hours=1000").then().statusCode(200).body("perHour", hasSize(168));
        given().when().get("/api/inference?hours=0").then().statusCode(200).body("perHour", hasSize(1));

        // A call DeepAR's model answered is its model's, apart from XGBoost's, in the models as in the hour.
        QuarkusTransaction.requiringNew().run(() -> {
            TrainingRun deepAr = TrainingRun.find("dataSource.id = ?1 and algorithm = ?2", (long) sourceId, "DeepAR").firstResult();
            InferenceCall call = new InferenceCall();
            call.dataSource = deepAr.dataSource;
            call.trainingRun = deepAr;
            call.tableFqn = deepAr.tableFqn;
            call.groupName = "care";
            call.calledAt = Instant.now();
            call.millis = 400;
            call.requested = 1;
            call.scored = 1;
            call.status = InferenceCall.Status.OK;
            call.persist();
        });
        given().when().get("/api/inference").then().statusCode(200)
            .body("totals.calls", is(4)).body("perHour[23].byModel", hasSize(2))
            .body("models.findAll { it.table == 'datyx-ds-7.quarkus.ward.stays' }", hasSize(2))
            .body("models.find { it.runId == " + runId + " }.stats.calls", is(3))
            .body("models.find { it.table == 'datyx-ds-7.quarkus.ward.stays' && it.algorithm == 'DeepAR' }.stats.calls", is(1))
            .body("models.find { it.table == 'datyx-ds-7.quarkus.ward.stays' && it.algorithm == 'DeepAR' }.stats.p50Millis", is(400))
            .body("models.find { it.runId == " + runId + " }.stats.p95Millis", org.hamcrest.Matchers.lessThan(400));

        given().when().delete("/api/datasources/" + sourceId).then().statusCode(204);
        given().when().get("/api/inference").then().statusCode(200).body("totals.calls", is(0));
    }

    /** ward.hourly: admissions per run, hospital and hour, the hospital a category; DeepAR's, 24 hours ahead by default. */
    private TimeSeries.Spec hourly() throws Exception {
        return TimeSeries.spec(json.readTree("""
            {"name":"hourly","fullyQualifiedName":"datyx-ds-7.quarkus.ward.hourly","databaseSchema":{"name":"ward"},
             "columns":[
              {"name":"run_id","dataType":"TEXT","tags":[{"tagFQN":"TimeSeries.SeriesKey"}]},
              {"name":"hospital_id","dataType":"INT","tags":[{"tagFQN":"TimeSeries.SeriesKey"},
                {"tagFQN":"TimeSeries.StaticCategorical"}]},
              {"name":"hour_start","dataType":"TIMESTAMP","tags":[{"tagFQN":"TimeSeries.Timestamp"}]},
              {"name":"admissions","dataType":"INT","tags":[{"tagFQN":"TimeSeries.Target"}]}],
             "extension":{"timeSeriesFrequency":"1h","timeSeriesMissing":"zero"}}
            """), TimeSeries.DEFAULT_GROUP);
    }

    @Test
    void forecastsADeepArGroupStepByStep() throws Exception {
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("create schema if not exists ward");
            s.execute("drop table if exists ward.hourly");
            s.execute("create table ward.hourly (run_id text, hospital_id int, hour_start timestamp, admissions int)");
            // Run a ends at hour 600, run b (still going) at 720; admissions by day, more at hospital 1.
            s.execute("""
                insert into ward.hourly
                select r, h, timestamp '2026-01-01 00:00' + make_interval(hours => t),
                       case when t % 24 between 8 and 17 and (h * 7 + t) % 3 = 0 then 1 + (h = 1)::int else 0 end
                from (values ('a', 600), ('b', 720)) runs(r, last), generate_series(1, 4) h, generate_series(0, 720) t
                where t <= last and ((t % 24 between 8 and 17 and (h * 7 + t) % 3 = 0) or (t = last and h = 1))""");
        }
        TimeSeries.Spec spec = hourly();
        DeepArData.Builder builder = new DeepArData.Builder(spec);
        try (Connection c = dataSource.getConnection()) {
            TableReader.read(c, spec, builder);
        }
        DeepArTrainer.Trained trained = DeepArTrainer.train(builder.build(), 2, java.time.Duration.ofMinutes(1), 3);
        assertEquals(4, trained.result().scores().size(), "run b's four hospitals are still observed");

        URI url = URI.create(jdbcUrl.substring("jdbc:".length()));
        int sourceId = given().contentType(ContentType.JSON)
            .body("""
                {"name":"inference hourly","type":"database","database":{"engine":"postgresql","host":"%s","port":%d,
                 "database":"%s","username":"%s","password":"%s"}}
                """.formatted(url.getHost(), url.getPort(), url.getPath().substring(1), username, password))
            .when().post("/api/datasources").then().statusCode(201).extract().path("id");
        String results = json.writeValueAsString(trained.result());
        long runId = QuarkusTransaction.requiringNew().call(() -> {
            TrainingRun run = new TrainingRun();
            run.dataSource = DataSource.findById((long) sourceId);
            run.tableFqn = spec.table();
            run.groupName = TimeSeries.DEFAULT_GROUP;
            run.algorithm = "DeepAR";
            run.trigger = TrainingRun.Trigger.MANUAL;
            run.status = TrainingRun.Status.SUCCEEDED;
            run.queuedAt = Instant.now();
            run.finishedAt = Instant.now();
            run.results = results;
            run.model = trained.model();
            run.persist();
            return run.id;
        });
        try {
            // A hospital of run b, by key: the next 24 hours from the run's end, step by step; one never seen has no rows.
            JsonNode one = json.readTree(given().contentType(ContentType.JSON)
                .body(Map.of("table", "ward.hourly",
                    "series", List.of(Map.of("run_id", "b", "hospital_id", "1"), Map.of("run_id", "b", "hospital_id", "9"))))
                .when().post("/api/datasources/" + sourceId + "/inference").then().statusCode(200)
                .body("runId", is((int) runId)).body("group", is("default")).body("scored", is(1))
                .body("target", is("admissions")).body("horizon", is("1D"))
                .body("predictions[0].forecast", hasSize(24))
                .body("predictions[0].forecast[0].at", is("2026-01-31T01:00"))
                .body("predictions[0].forecast[23].at", is("2026-02-01T00:00"))
                .body("predictions[1].note", is("no rows for this series")).body("predictions[1].forecast", nullValue())
                .extract().asString());
            double sum = 0;
            for (JsonNode step : one.path("predictions").get(0).path("forecast")) {
                sum += step.path("mean").asDouble();
                double p10 = step.path("p10").asDouble();
                double p50 = step.path("p50").asDouble();
                double p90 = step.path("p90").asDouble();
                assertEquals(true, p10 <= p50 && p50 <= p90 && p50 == Math.rint(p50), step.toString());
            }
            assertEquals(sum, one.path("predictions").get(0).path("predicted").asDouble(), 0.05, "the mean summed over the horizon");

            // None named: run b's hospitals, the highest first.
            JsonNode all = json.readTree(given().contentType(ContentType.JSON).body("{\"table\":\"hourly\",\"limit\":3}")
                .when().post("/api/datasources/" + sourceId + "/inference").then().statusCode(200)
                .body("predictions", hasSize(3)).extract().asString());
            JsonNode predictions = all.path("predictions");
            for (int i = 0; i < 3; i++) {
                assertEquals("b", predictions.get(i).path("series").path("run_id").asText());
                assertEquals(true, i == 0 || predictions.get(i - 1).path("predicted").asDouble()
                    >= predictions.get(i).path("predicted").asDouble());
            }
        } finally {
            given().when().delete("/api/datasources/" + sourceId).then().statusCode(204);
        }
    }

    @Test
    void anHourCountsItsCallsAndEachModels() {
        DataSource source = new DataSource();
        source.id = 4L;
        TrainingRun xgb = new TrainingRun();
        xgb.algorithm = "XGBoost";
        TrainingRun deepAr = new TrainingRun();
        deepAr.algorithm = "DeepAR";
        Instant hour = Instant.parse("2026-11-01T10:00:00Z");
        List<InferenceCall> in = List.of(call(source, deepAr, 40, 24, InferenceCall.Status.OK),
            call(source, xgb, 5, 2, InferenceCall.Status.OK), call(source, xgb, 9, 0, InferenceCall.Status.FAILED),
            call(source, xgb, 7, 1, InferenceCall.Status.OK));
        InferenceResource.Hour h = InferenceResource.hour(hour, in);
        assertEquals(new InferenceResource.Hour(hour, 4, 1, 27, 7, 40, List.of(
            new InferenceResource.HourModel(4, "ds.h.public.admissions", "admissions", "care", "DeepAR", 1, 0, 24),
            new InferenceResource.HourModel(4, "ds.h.public.admissions", "admissions", "care", "XGBoost", 3, 1, 3))), h);
        assertEquals(new InferenceResource.Hour(hour, 0, 0, 0, null, null, List.of()), InferenceResource.hour(hour, List.of()));
    }

    private static InferenceCall call(DataSource source, TrainingRun run, int millis, int scored, InferenceCall.Status status) {
        InferenceCall c = new InferenceCall();
        c.dataSource = source;
        c.trainingRun = run;
        c.tableFqn = "ds.h.public.admissions";
        c.groupName = "care";
        c.calledAt = Instant.parse("2026-11-01T10:30:00Z");
        c.millis = millis;
        c.scored = scored;
        c.status = status;
        return c;
    }

    @Test
    void percentilesAreByNearestRank() {
        int[] millis = {3, 5, 7, 9, 100};
        assertEquals(7, InferenceResource.rank(millis, 0.5));
        assertEquals(100, InferenceResource.rank(millis, 0.95));
        assertEquals(3, InferenceResource.rank(new int[] {3}, 0.95));
    }
}
