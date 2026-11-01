package datyx.training;

import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.profile.Profile;
import datyx.profile.Profiles;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.panache.common.Sort;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * GET /api/inference: the account of the caller's models' inference
 * calls over the last {@link #WINDOW} (at most {@link #MAX_CALLS}): the
 * totals, each model's (each algorithm a group has a trained model of,
 * its latest, and any a call named; its calls those that algorithm answered), the calls per hour of the last day (or of up to the whole
 * window: {@code ?hours=}), and the latest calls.
 */
@Path("/api/inference")
@Produces(MediaType.APPLICATION_JSON)
public class InferenceResource {

    static final Duration WINDOW = Duration.ofDays(7);

    static final int MAX_CALLS = 10_000;

    static final int RECENT = 50;

    /** The hours {@code perHour} covers by default, and at most: the window's. */
    static final int HOURS = 24;

    static final int MAX_HOURS = (int) WINDOW.toHours();

    @Inject
    Profiles profiles;

    @Inject
    ObjectMapper json;

    /** Calls' account: how many, how many failed, series scored, latency (mean, median, 95th percentile), the latest. */
    public record Stats(int calls, int failed, long scored, Double avgMillis, Integer p50Millis, Integer p95Millis,
            Instant lastCalledAt) {
    }

    /** A model (a group's algorithm, its latest run) and its calls' account; the series key to name a series by. */
    public record ModelStats(long sourceId, String source, String table, String name, String group, String algorithm,
            Long runId, Instant trainedAt, String target, String horizon, List<String> seriesKey, Stats stats) {
    }

    public record CallView(long id, long sourceId, String source, String table, String name, String group,
            String algorithm, long runId, Instant calledAt, int millis, int requested, int scored, String status, String error, String caller) {
    }

    /**
     * An hour's calls: how many, how many failed, series scored, latency (median, 95th percentile, by
     * nearest rank; null without a call), and each model's (a group's algorithm) calls in it.
     */
    public record Hour(Instant hour, int calls, int failed, long scored, Integer p50Millis, Integer p95Millis,
            List<HourModel> byModel) {
    }

    /** A model's calls in an hour: the group's algorithm (the run's that answered). */
    public record HourModel(long sourceId, String table, String name, String group, String algorithm, int calls, int failed,
            long scored) {
    }

    private record ModelKey(long sourceId, String table, String group, String algorithm) {
    }

    @GET
    public Response account(@QueryParam("hours") Integer hours) {
        int span = hours == null ? HOURS : Math.max(1, Math.min(MAX_HOURS, hours));
        Map<String, Object> answer = QuarkusTransaction.requiringNew().call(() -> {
            Profile profile = profiles.current();
            Instant now = Instant.now();
            List<InferenceCall> calls = InferenceCall.since(profile, now.minus(WINDOW), MAX_CALLS);

            // A model each group's algorithm has, its latest run's, and its calls: those that algorithm answered.
            Map<ModelKey, ModelStats> models = new LinkedHashMap<>();
            for (TrainingRun run : TrainingRun.<TrainingRun>find("dataSource.profile = ?1 and status = ?2",
                    Sort.descending("queuedAt", "id"), profile, TrainingRun.Status.SUCCEEDED).list()) {
                ModelKey key = new ModelKey(run.dataSource.id, run.tableFqn, run.groupName, run.algorithm);
                if (!models.containsKey(key)) {
                    models.put(key, model(run, calls.stream().filter(c -> key.equals(key(c))).toList()));
                }
            }
            for (InferenceCall c : calls) {
                models.computeIfAbsent(key(c), k -> model(c.trainingRun, calls.stream().filter(x -> k.equals(key(x))).toList()));
            }

            Instant top = now.truncatedTo(ChronoUnit.HOURS);
            Map<Instant, List<InferenceCall>> byHour = new HashMap<>();
            for (InferenceCall c : calls) {
                byHour.computeIfAbsent(c.calledAt.truncatedTo(ChronoUnit.HOURS), h -> new ArrayList<>()).add(c);
            }
            List<Hour> perHour = new ArrayList<>();
            for (int h = span - 1; h >= 0; h--) {
                Instant from = top.minus(Duration.ofHours(h));
                perHour.add(hour(from, byHour.getOrDefault(from, List.of())));
            }

            Map<String, Object> map = new LinkedHashMap<>();
            map.put("since", now.minus(WINDOW));
            map.put("hours", span);
            map.put("totals", stats(calls));
            map.put("lastHour", (int) calls.stream().filter(c -> c.calledAt.isAfter(now.minus(Duration.ofHours(1)))).count());
            map.put("models", List.copyOf(models.values()));
            map.put("perHour", perHour);
            map.put("calls", calls.stream().limit(RECENT).map(InferenceResource::view).toList());
            return map;
        });
        return Response.ok(answer).build();
    }

    /** The model a call asked: its group's algorithm, the run's that answered. */
    private static ModelKey key(InferenceCall c) {
        return new ModelKey(c.dataSource.id, c.tableFqn, c.groupName, c.trainingRun.algorithm);
    }

    /** An hour's account: its calls' and each model's, the models in the order of their first call in it (newest first). */
    static Hour hour(Instant from, List<InferenceCall> in) {
        Map<ModelKey, List<InferenceCall>> models = new LinkedHashMap<>();
        for (InferenceCall c : in) {
            models.computeIfAbsent(key(c), k -> new ArrayList<>()).add(c);
        }
        Stats stats = stats(in);
        return new Hour(from, stats.calls(), stats.failed(), stats.scored(), stats.p50Millis(), stats.p95Millis(),
            models.entrySet().stream().map(e -> {
                ModelKey k = e.getKey();
                Stats s = stats(e.getValue());
                return new HourModel(k.sourceId(), k.table(), k.table().substring(k.table().lastIndexOf('.') + 1), k.group(),
                    k.algorithm(), s.calls(), s.failed(), s.scored());
            }).toList());
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
            run.groupName, run.algorithm, run.id, run.finishedAt, target, horizon, seriesKey, stats(calls));
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
            c.groupName, c.trainingRun.algorithm, c.trainingRun.id, c.calledAt, c.millis, c.requested, c.scored, c.status.name().toLowerCase(),
            c.error, c.caller);
    }
}
