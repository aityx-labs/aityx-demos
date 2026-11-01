package datyx.training;

import java.sql.SQLException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.auth.CurrentUser;
import datyx.catalog.TimeSeries;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.profile.Profiles;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.panache.common.Sort;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * Inference on a source, within the caller's profile:
 * POST /api/datasources/{id}/inference scores series with the latest
 * model trained on a table's group, and keeps the call (InferenceCall):
 * who, which model, how many series, how long, and whether it failed.
 * Under its own path, like SourceTrainingResource.
 */
@Path("/api/datasources/{id}/inference")
@Produces(MediaType.APPLICATION_JSON)
public class SourceInferenceResource {

    static final int DEFAULT_LIMIT = 25;

    @Inject
    Profiles profiles;

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @Inject
    CurrentUser user;

    @Inject
    Inference inference;

    /**
     * What POST takes: a table (its name, schema.table or FQN), its group
     * (default when none), and the series to score, each its SeriesKey's
     * values by column; none scores every series still observed, the
     * highest {@code limit} (25) answered.
     */
    public record Request(String table, String group, List<Map<String, String>> series, Integer limit) {
    }

    /** What POST answers: the call, the model that answered, and its predictions. */
    public record Answer(long callId, long runId, Instant trainedAt, String table, String group, String target,
            String horizon, int requested, int scored, int millis, List<Inference.Prediction> predictions) {
    }

    private record Prepared(long sourceId, long runId, String tableFqn, String group, DatabaseAccess access,
            Inference.Model model) {
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    public Response score(@PathParam("id") long id, Request request) {
        if (request == null || request.table() == null || request.table().isBlank()) {
            return TrainingResource.error(Response.Status.BAD_REQUEST,
                "name the table: \"table\":\"schema.table\", its \"group\", and the \"series\" to score (none: all)");
        }
        String group;
        try {
            group = TimeSeries.group(request.group());
        } catch (IllegalArgumentException e) {
            return TrainingResource.error(Response.Status.BAD_REQUEST, e.getMessage());
        }
        int limit = request.limit() == null ? DEFAULT_LIMIT : Math.max(1, Math.min(Inference.MAX_SERIES, request.limit()));
        String caller = user.id();
        Prepared prepared;
        try {
            prepared = QuarkusTransaction.requiringNew().call(() -> {
                Optional<DataSource> source = DataSource.of(profiles.current(), id)
                    .filter(s -> s.type == DataSource.Type.DATABASE);
                if (source.isEmpty()) {
                    return null;
                }
                DataSource s = source.get();
                String wanted = request.table().strip();
                Optional<TrainingRun> run = TrainingRun.<TrainingRun>find(
                    "dataSource = ?1 and groupName = ?2 and status = ?3", Sort.descending("queuedAt", "id"), s, group,
                    TrainingRun.Status.SUCCEEDED).stream()
                    .filter(r -> r.tableFqn.equals(wanted) || r.tableFqn.endsWith("." + wanted)).findFirst();
                if (run.isEmpty()) {
                    throw new NoModel("no model of the group " + group + " of " + wanted + " has been trained yet");
                }
                DatabaseAccess access = AccessCodec.unseal(crypto, json, s.profile.id, s.profile.keyWrapped, s.access)
                    .database();
                TrainingRun r = run.get();
                return new Prepared(s.id, r.id, r.tableFqn, group, access, inference.model(r));
            });
        } catch (NoModel e) {
            return TrainingResource.error(Response.Status.NOT_FOUND, e.getMessage());
        } catch (IllegalStateException e) {
            return TrainingResource.error(Response.Status.CONFLICT, e.getMessage());
        }
        if (prepared == null) {
            return TrainingResource.error(Response.Status.NOT_FOUND, "no database data source with id " + id);
        }
        int requested = request.series() == null ? 0 : request.series().size();
        long started = System.nanoTime();
        try {
            List<Inference.Prediction> predictions = inference.predict(prepared.model(), prepared.access(),
                request.series(), limit);
            int millis = (int) ((System.nanoTime() - started) / 1_000_000);
            int scored = (int) predictions.stream().filter(p -> p.predicted() != null).count();
            long callId = record(prepared, millis, requested, scored, null, caller);
            var spec = prepared.model().result().spec();
            return Response.ok(new Answer(callId, prepared.runId(), prepared.model().trainedAt(), prepared.tableFqn(),
                group, spec.target(), spec.horizon(), requested, scored, millis, predictions)).build();
        } catch (Throwable e) {
            int millis = (int) ((System.nanoTime() - started) / 1_000_000);
            String error = Training.reason(e);
            long callId = record(prepared, millis, requested, 0, error, caller);
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("error", error);
            body.put("callId", callId);
            Response.Status status = e instanceof IllegalArgumentException ? Response.Status.BAD_REQUEST
                : (e instanceof SQLException ? Response.Status.BAD_GATEWAY : Response.Status.INTERNAL_SERVER_ERROR);
            return Response.status(status).entity(body).build();
        }
    }

    private long record(Prepared prepared, int millis, int requested, int scored, String error, String caller) {
        return QuarkusTransaction.requiringNew().call(() -> {
            InferenceCall call = new InferenceCall();
            call.dataSource = DataSource.findById(prepared.sourceId());
            call.trainingRun = TrainingRun.findById(prepared.runId());
            call.tableFqn = prepared.tableFqn();
            call.groupName = prepared.group();
            call.calledAt = Instant.now();
            call.millis = millis;
            call.requested = requested;
            call.scored = scored;
            call.status = error == null ? InferenceCall.Status.OK : InferenceCall.Status.FAILED;
            call.error = error == null ? null : (error.length() > 2000 ? error.substring(0, 2000) : error);
            call.caller = caller;
            call.persist();
            return call.id;
        });
    }

    /** No model to answer with: a 404. */
    static final class NoModel extends RuntimeException {
        NoModel(String message) {
            super(message);
        }
    }
}
