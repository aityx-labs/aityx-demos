package datyx.training;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.Catalog;
import datyx.catalog.TimeSeries;
import datyx.datasource.DataSource;
import datyx.profile.Profile;
import datyx.profile.Profiles;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * Training, within the caller's profile like the data sources:
 * GET /api/training answers each group of the caller's sources tagged for
 * XGBoost (among its algorithms), with how often it is trained, its latest
 * XGBoost run and latest success, and when it is next due, and the latest
 * runs of them all, whatever their algorithm;
 * GET /api/training/runs/{id} answers a run with all it found. A
 * source's own training calls are SourceTrainingResource's.
 */
@Path("/api/training")
@Produces(MediaType.APPLICATION_JSON)
public class TrainingResource {

    static final int RUNS = 50;

    @Inject
    Profiles profiles;

    @Inject
    Catalog catalog;

    @Inject
    Training training;

    @Inject
    ObjectMapper json;

    /** A run at a glance: what, why, when, how it went, and its test metrics once it succeeded. */
    public record RunView(long id, long sourceId, String source, String table, String name, String group,
            String algorithm, String trigger, String triggerNote, Long eventId, String status, Instant queuedAt, Instant startedAt, Instant finishedAt,
            Double seconds, String error, Integer examples, XgbTrainer.Metrics test) {
    }

    /** A group tagged for XGBoost, as GET /api/training answers it: switched on or off, and when it is next trained (none when off). */
    public record ModelView(long sourceId, String source, String table, String schema, String name, String group,
            String algorithm, boolean enabled, String target, List<String> seriesKey, boolean ready, List<String> problems, String frequency,
            String horizon, String retrain,
            String retrainEvery, Instant nextAt, RunView latest, RunView lastSucceeded) {
    }

    record SourceRef(long id, String name) {
    }

    @GET
    public Response overview() {
        List<SourceRef> sources = QuarkusTransaction.requiringNew().call(() -> {
            Profile profile = profiles.current();
            return DataSource.<DataSource>list("profile = ?1 and type = ?2", profile, DataSource.Type.DATABASE).stream()
                .map(s -> new SourceRef(s.id, s.name)).toList();
        });
        List<Map.Entry<SourceRef, TimeSeries.Spec>> groups = new ArrayList<>();
        List<String> errors = new ArrayList<>();
        for (SourceRef source : sources) {
            try {
                for (JsonNode table : catalog.tables(source.id())) {
                    for (TimeSeries.Spec spec : TimeSeries.specs(table)) {
                        if (spec.has(TimeSeries.Algorithm.XGBOOST)) {
                            groups.add(Map.entry(source, spec));
                        }
                    }
                }
            } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
                errors.add(source.name() + ": the catalogue can't be read (" + Training.reason(e) + ")");
            }
        }
        Map<String, Object> answer = QuarkusTransaction.requiringNew().call(() -> {
            Profile profile = profiles.current();
            List<ModelView> models = new ArrayList<>();
            for (Map.Entry<SourceRef, TimeSeries.Spec> g : groups) {
                DataSource source = DataSource.findById(g.getKey().id());
                TimeSeries.Spec spec = g.getValue();
                String algorithm = TimeSeries.Algorithm.XGBOOST.tag;
                TrainingRun latest = TrainingRun.latest(source, spec.table(), spec.group(), algorithm).orElse(null);
                TrainingRun succeeded = TrainingRun.latestSucceeded(source, spec.table(), spec.group(), algorithm).orElse(null);
                Instant next = spec.ready() && spec.enabled() ? Training.nextAt(latest, spec.retrain()).orElse(null) : null;
                models.add(new ModelView(source.id, source.name, spec.table(), spec.schema(), spec.name(), spec.group(),
                    algorithm, spec.enabled(), spec.target(), spec.seriesKey(), spec.ready(), spec.problems(), spec.frequency(), spec.horizon(), spec.retrain(),
                    spec.retrain() == null ? TimeSeries.DEFAULT_RETRAIN : spec.retrain(),
                    Instant.EPOCH.equals(next) ? Instant.now() : next, view(latest), view(succeeded)));
            }
            List<RunView> runs = TrainingRun.newest(profile, RUNS).stream().map(this::view).toList();
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("models", models);
            map.put("runs", runs);
            map.put("errors", errors);
            return map;
        });
        return Response.ok(answer).build();
    }

    @GET
    @Path("/runs/{id}")
    public Response run(@PathParam("id") long id) {
        return QuarkusTransaction.requiringNew().call(() -> {
            Optional<TrainingRun> run = TrainingRun.of(profiles.current(), id);
            if (run.isEmpty()) {
                return error(Response.Status.NOT_FOUND, "no training run with id " + id);
            }
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("run", view(run.get()));
            map.put("results", run.get().results == null ? null : json.readTree(run.get().results));
            return Response.ok(map).build();
        });
    }

    Optional<SourceRef> source(long id) {
        return QuarkusTransaction.requiringNew().call(() -> DataSource.of(profiles.current(), id)
            .filter(s -> s.type == DataSource.Type.DATABASE).map(s -> new SourceRef(s.id, s.name)));
    }

    RunView view(TrainingRun run) {
        if (run == null) {
            return null;
        }
        Double seconds = run.startedAt == null || run.finishedAt == null ? null
            : Duration.between(run.startedAt, run.finishedAt).toMillis() / 1000.0;
        XgbTrainer.Metrics test = null;
        Integer examples = null;
        if (run.results != null) {
            try {
                JsonNode results = json.readTree(run.results);
                test = json.treeToValue(results.path("test"), XgbTrainer.Metrics.class);
                examples = results.path("dataset").path("examples").asInt();
            } catch (java.io.IOException | IllegalArgumentException e) {
                test = null;
            }
        }
        String fqn = run.tableFqn;
        return new RunView(run.id, run.dataSource.id, run.dataSource.name, fqn, fqn.substring(fqn.lastIndexOf('.') + 1),
            run.groupName, run.algorithm, run.trigger.name().toLowerCase(), run.triggerNote, run.eventId, run.status.name().toLowerCase(),
            run.queuedAt,
            run.startedAt, run.finishedAt, seconds, run.error, examples, test);
    }

    static Response error(Response.Status status, String message) {
        return Response.status(status).entity(Map.of("error", message)).build();
    }
}
