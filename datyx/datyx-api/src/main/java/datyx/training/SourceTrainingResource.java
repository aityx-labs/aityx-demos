package datyx.training;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import datyx.catalog.Catalog;
import datyx.catalog.TimeSeries;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * A source's training, within the caller's profile:
 * POST /api/datasources/{id}/training queues a run of a table's group now,
 * with one of its algorithms (XGBoost, the one datyx trains);
 * PUT /api/datasources/{id}/training sets how often a table's groups are
 * trained again (its timeSeriesRetrain in OpenMetadata). Its own class,
 * under the longest path: a request goes to the resource whose path
 * matches the most of it, and CatalogResource has /api/datasources/{id}.
 */
@Path("/api/datasources/{id}/training")
@Produces(MediaType.APPLICATION_JSON)
public class SourceTrainingResource {

    @Inject
    TrainingResource trainingResource;

    @Inject
    Catalog catalog;

    @Inject
    Training training;

    /** What PUT takes: a table, and how often to train its groups again (a span, never, or none: 1D). */
    public record Schedule(String table, String retrain) {
    }

    /** What POST takes: a table, its group (default when none) and the algorithm (XGBoost when none). */
    public record Request(String table, String group, String algorithm) {
    }

    @POST
        @Consumes(MediaType.APPLICATION_JSON)
    public Response trainNow(@PathParam("id") long id, Request request) {
        if (request == null || request.table() == null || request.table().isBlank()) {
            return TrainingResource.error(Response.Status.BAD_REQUEST, "name the table: \"table\":\"schema.table\", and its \"group\"");
        }
        Optional<TrainingResource.SourceRef> source = trainingResource.source(id);
        if (source.isEmpty()) {
            return TrainingResource.error(Response.Status.NOT_FOUND, "no data source with id " + id);
        }
        TimeSeries.Spec spec;
        TimeSeries.Algorithm algorithm;
        try {
            String group = TimeSeries.group(request.group());
            algorithm = TimeSeries.Algorithm.named(request.algorithm());
            Optional<JsonNode> table = table(id, request.table());
            if (table.isEmpty()) {
                return TrainingResource.error(Response.Status.NOT_FOUND, "the catalogue of data source " + id + " has no table " + request.table());
            }
            spec = TimeSeries.spec(table.get(), group);
        } catch (IllegalArgumentException e) {
            return TrainingResource.error(Response.Status.BAD_REQUEST, e.getMessage());
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            return TrainingResource.error(Response.Status.BAD_GATEWAY, Training.reason(e));
        }
        String cant = "the group " + spec.group() + " of " + spec.name() + " can't be trained";
        if (algorithm == null) {
            algorithm = spec.has(TimeSeries.Algorithm.XGBOOST) ? TimeSeries.Algorithm.XGBOOST : TimeSeries.Algorithm.named(spec.algorithm());
        }
        if (!spec.enabled()) {
            return TrainingResource.error(Response.Status.CONFLICT, cant + ": it is switched off (" + TimeSeries.disabledFqn(spec.group())
                + "); switch it on, which trains it");
        }
        if (!spec.has(algorithm)) {
            return TrainingResource.error(Response.Status.CONFLICT, cant + " with " + algorithm.tag + ": it isn't tagged for it ("
                + algorithm.fqn(spec.group()) + "); its algorithms are " + String.join(" and ", spec.algorithms()));
        }
        if (algorithm != TimeSeries.Algorithm.XGBOOST) {
            return TrainingResource.error(Response.Status.CONFLICT, cant + " with " + algorithm.tag + ": datyx has no "
                + algorithm.tag + " trainer yet, only XGBoost's");
        }
        if (!Training.trainable(spec)) {
            return TrainingResource.error(Response.Status.CONFLICT, cant + ": " + String.join("; ", spec.problems()));
        }
        Optional<Long> runId = training.queueManual(id, spec, algorithm);
        if (runId.isEmpty()) {
            return TrainingResource.error(Response.Status.CONFLICT, "the group " + spec.group() + " of " + spec.name()
                + " is being trained already with " + algorithm.tag);
        }
        TrainingResource.RunView queued = QuarkusTransaction.requiringNew().call(
            () -> trainingResource.view(TrainingRun.findById(runId.get())));
        training.submit(queued.id());
        return Response.accepted(queued).build();
    }

    @PUT
        @Consumes(MediaType.APPLICATION_JSON)
    public Response schedule(@PathParam("id") long id, Schedule schedule) {
        if (schedule == null || schedule.table() == null || schedule.table().isBlank()) {
            return TrainingResource.error(Response.Status.BAD_REQUEST, "name the table: \"table\":\"schema.table\", and \"retrain\"");
        }
        if (trainingResource.source(id).isEmpty()) {
            return TrainingResource.error(Response.Status.NOT_FOUND, "no data source with id " + id);
        }
        try {
            Optional<JsonNode> table = table(id, schedule.table());
            if (table.isEmpty()) {
                return TrainingResource.error(Response.Status.NOT_FOUND, "the catalogue of data source " + id + " has no table " + schedule.table());
            }
            catalog.setRetrain(table.get(), schedule.retrain());
            JsonNode saved = catalog.table(table.get().path("fullyQualifiedName").asText());
            String retrain = saved.path("extension").path(TimeSeries.RETRAIN).asText(null);
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("table", saved.path("fullyQualifiedName").asText());
            map.put("retrain", retrain);
            map.put("retrainEvery", retrain == null ? TimeSeries.DEFAULT_RETRAIN : retrain);
            return Response.ok(map).build();
        } catch (IllegalArgumentException e) {
            return TrainingResource.error(Response.Status.BAD_REQUEST, e.getMessage());
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            return TrainingResource.error(Response.Status.BAD_GATEWAY, Training.reason(e));
        }
    }

    /** A table of the source's catalogue by its name, schema.table or FQN. */
    private Optional<JsonNode> table(long sourceId, String wanted) {
        String name = wanted.strip();
        for (JsonNode table : catalog.tables(sourceId)) {
            String schema = table.path("databaseSchema").path("name").asText();
            if (name.equals(table.path("name").asText()) || name.equals(schema + "." + table.path("name").asText())
                    || name.equals(table.path("fullyQualifiedName").asText())) {
                return Optional.of(table);
            }
        }
        return Optional.empty();
    }
}
