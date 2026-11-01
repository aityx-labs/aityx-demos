package datyx.training;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import datyx.catalog.Catalog;
import datyx.catalog.TimeSeries;
import datyx.datasource.DataSource;
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
 * POST /api/datasources/{id}/training queues a run of a table's group now;
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

    /** What POST takes: a table and its group (default when none). */
    public record Request(String table, String group) {
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
        try {
            String group = TimeSeries.group(request.group());
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
        if (!Training.trainable(spec)) {
            return TrainingResource.error(Response.Status.CONFLICT, "the group " + spec.group() + " of " + spec.name() + " can't be trained: "
                + (TimeSeries.Algorithm.XGBOOST.tag.equals(spec.algorithm()) ? String.join("; ", spec.problems())
                    : "it isn't tagged for XGBoost"));
        }
        Optional<TrainingResource.RunView> queued = QuarkusTransaction.requiringNew().call(
            () -> training.queueManual(DataSource.findById(id), spec).map(trainingResource::view));
        if (queued.isEmpty()) {
            return TrainingResource.error(Response.Status.CONFLICT, "the group " + spec.group() + " of " + spec.name() + " is being trained already");
        }
        training.submit(queued.get().id());
        return Response.accepted(queued.get()).build();
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
