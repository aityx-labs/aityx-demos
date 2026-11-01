package datyx.training;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.catalog.TimeSeries;
import datyx.profile.Profile;
import datyx.profile.Profiles;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.panache.common.Sort;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * GET /api/inference: the account of the caller's models' inference
 * calls over the last {@link #WINDOW} (at most {@link #MAX_CALLS}): the
 * totals, each model's (every group with a trained model, and any a call
 * named), the calls per hour of the last day, and the latest calls.
 */
@Path("/api/inference")
@Produces(MediaType.APPLICATION_JSON)
public class InferenceResource {

    static final Duration WINDOW = Duration.ofDays(7);

    static final int MAX_CALLS = 10_000;

    static final int RECENT = 50;

    @Inject
    Profiles profiles;

    @Inject
    ObjectMapper json;

    /** Calls' account: how many, how many failed, series scored, latency (mean, median, 95th percentile), the latest. */
    public record Stats(int calls, int failed, long scored, Double avgMillis, Integer p50Millis, Integer p95Millis,
            Instant lastCalledAt) {
    }

    /** A model (a group with a trained model) and its calls' account; the series key to name a series by. */
    public record ModelStats(long sourceId, String source, String table, String name, String group, Long runId,
            Instant trainedAt, String target, String horizon, List<String> seriesKey, Stats stats) {
    }

    public record CallView(long id, long sourceId, String source, String table, String name, String group, long runId,
            Instant calledAt, int millis, int requested, int scored, String status, String error, String caller) {
    }

    public record Hour(Instant hour, int calls, int failed) {
    }

    private record Key(long sourceId, String table, String group) {
    }

    @GET
    public Response account() {
        Map<String, Object> answer = QuarkusTransaction.requiringNew().call(() -> {
            Profile profile = profiles.current();
            Instant now = Instant.now();
            List<InferenceCall> calls = InferenceCall.since(profile, now.minus(WINDOW), MAX_CALLS);

            Map<Key, ModelStats> models = new LinkedHashMap<>();
            for (TrainingRun run : TrainingRun.<TrainingRun>find("dataSource.profile = ?1 and status = ?2",
                    Sort.descending("queuedAt", "id"), profile, TrainingRun.Status.SUCCEEDED).stream()
                    // XGBoost's first, as POST .../inference prefers it: the model a group's calls get.
                    .sorted(Comparator.comparing(r -> !TimeSeries.Algorithm.XGBOOST.tag.equals(r.algorithm))).toList()) {
                Key key = new Key(run.dataSource.id, run.tableFqn, run.groupName);
                if (!models.containsKey(key)) {
                    models.put(key, model(run, calls.stream().filter(c -> key.equals(key(c))).toList()));
                }
            }
            for (InferenceCall c : calls) {
                models.computeIfAbsent(key(c), k -> model(c.trainingRun, calls.stream().filter(x -> k.equals(key(x))).toList()));
            }

            Instant top = now.truncatedTo(ChronoUnit.HOURS);
            List<Hour> perHour = new ArrayList<>();
            for (int h = 23; h >= 0; h--) {
                Instant from = top.minus(Duration.ofHours(h));
                Instant to = from.plus(Duration.ofHours(1));
                List<InferenceCall> in = calls.stream().filter(c -> !c.calledAt.isBefore(from) && c.calledAt.isBefore(to)).toList();
                perHour.add(new Hour(from, in.size(), (int) in.stream().filter(c -> c.status == InferenceCall.Status.FAILED).count()));
            }

            Map<String, Object> map = new LinkedHashMap<>();
            map.put("since", now.minus(WINDOW));
            map.put("totals", stats(calls));
            map.put("lastHour", (int) calls.stream().filter(c -> c.calledAt.isAfter(now.minus(Duration.ofHours(1)))).count());
            map.put("models", List.copyOf(models.values()));
            map.put("perHour", perHour);
            map.put("calls", calls.stream().limit(RECENT).map(InferenceResource::view).toList());
            return map;
        });
        return Response.ok(answer).build();
    }

    private static Key key(InferenceCall c) {
        return new Key(c.dataSource.id, c.tableFqn, c.groupName);
    }

    private ModelStats model(TrainingRun run, List<InferenceCall> calls) {
        String target = null;
        String horizon = null;
        List<String> seriesKey = List.of();
        try {
            JsonNode results = json.readTree(run.results);
            JsonNode spec = results.path("spec");
            target = spec.path("target").asText(null);
            // A DeepAR model's horizon is its own, the table's or the default's steps.
            horizon = results.path("dataset").path("horizon").asText(spec.path("horizon").asText(null));
            List<String> keys = new ArrayList<>();
            spec.path("seriesKey").forEach(k -> keys.add(k.asText()));
            seriesKey = keys;
        } catch (java.io.IOException | IllegalArgumentException e) {
            target = null;
        }
        String fqn = run.tableFqn;
        return new ModelStats(run.dataSource.id, run.dataSource.name, fqn, fqn.substring(fqn.lastIndexOf('.') + 1),
            run.groupName, run.id, run.finishedAt, target, horizon, seriesKey, stats(calls));
    }

    /** The account of some calls: latency percentiles by nearest rank. */
    static Stats stats(List<InferenceCall> calls) {
        if (calls.isEmpty()) {
            return new Stats(0, 0, 0, null, null, null, null);
        }
        int[] millis = calls.stream().mapToInt(c -> c.millis).sorted().toArray();
        double avg = calls.stream().mapToInt(c -> c.millis).average().orElse(0);
        Instant last = calls.stream().map(c -> c.calledAt).max(Instant::compareTo).orElse(null);
        return new Stats(calls.size(), (int) calls.stream().filter(c -> c.status == InferenceCall.Status.FAILED).count(),
            calls.stream().mapToLong(c -> c.scored).sum(), Math.round(avg * 10) / 10.0, rank(millis, 0.5), rank(millis, 0.95),
            last);
    }

    static int rank(int[] sorted, double p) {
        return sorted[Math.max(0, (int) Math.ceil(p * sorted.length) - 1)];
    }

    private static CallView view(InferenceCall c) {
        String fqn = c.tableFqn;
        return new CallView(c.id, c.dataSource.id, c.dataSource.name, fqn, fqn.substring(fqn.lastIndexOf('.') + 1),
            c.groupName, c.trainingRun.id, c.calledAt, c.millis, c.requested, c.scored, c.status.name().toLowerCase(),
            c.error, c.caller);
    }
}
