package datyx.catalog;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource;
import datyx.datasource.DataSource.DatabaseAccess;
import datyx.profile.Profile;
import datyx.profile.Profiles;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;

/**
 * A data source in the catalogue (Catalog), and the time series in it,
 * within the caller's profile like the sources themselves:
 * POST /api/datasources/{id}/catalog reads the source and writes it to
 * OpenMetadata, answering what it wrote;
 * GET /api/datasources/{id}/catalog answers its tables as OpenMetadata
 * has them, each column with its type and tags;
 * GET /api/datasources/{id}/timeseries answers each group of TimeSeries
 * roles a table's columns are tagged with, read as a time series
 * (TimeSeries.Spec), or with ?algorithm=XGBoost only the groups that
 * algorithm trains: what a trainer looks for;
 * PUT /api/datasources/{id}/timeseries sets one group's roles and
 * algorithm in a table, and the table's frequency, missing rows and
 * horizon, and answers the group's spec.
 * Only database sources (PostgreSQL so far) have a catalogue: another
 * type, or another engine, is a 400. A source or OpenMetadata that can't
 * be reached is a 502 naming which. No database transaction is held
 * while datyx talks to them.
 */
@Path("/api/datasources/{id}")
@Produces(MediaType.APPLICATION_JSON)
public class CatalogResource {

    private static final Logger LOG = Logger.getLogger(CatalogResource.class);

    @Inject
    Profiles profiles;

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @Inject
    Catalog catalog;

    /** A source of the caller's, its access details decrypted: read in a transaction of its own. */
    record Source(long id, String name, String description, DataSource.Type type, DatabaseAccess database) {
    }

    @POST
    @Path("/catalog")
    public Response sync(@PathParam("id") long id) {
        Optional<Source> source = source(id);
        if (source.isEmpty()) {
            return notFound(id);
        }
        Source s = source.get();
        if (s.type() != DataSource.Type.DATABASE) {
            return error(Response.Status.BAD_REQUEST, "only database sources have a catalogue, not " + s.type().json());
        }
        try {
            return Response.ok(catalog.sync(s.id(), s.name(), s.description(), s.database())).build();
        } catch (IllegalArgumentException e) {
            return error(Response.Status.BAD_REQUEST, e.getMessage());
        } catch (SQLException e) {
            LOG.infof("catalogue: data source %d can't be read: %s", id, e.getMessage());
            return error(Response.Status.BAD_GATEWAY, "the data source can't be read: " + e.getMessage());
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            return openMetadataFailed(id, e);
        }
    }

    @GET
    @Path("/catalog")
    public Response tables(@PathParam("id") long id) {
        Optional<Source> source = source(id);
        if (source.isEmpty()) {
            return notFound(id);
        }
        try {
            List<Map<String, Object>> tables = new ArrayList<>();
            for (JsonNode table : catalog.tables(id)) {
                tables.add(view(table));
            }
            return Response.ok(Map.of("service", Catalog.serviceName(id), "tables", tables)).build();
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            return openMetadataFailed(id, e);
        }
    }

    @GET
    @Path("/timeseries")
    public Response timeSeries(@PathParam("id") long id, @QueryParam("algorithm") String algorithm) {
        Optional<Source> source = source(id);
        if (source.isEmpty()) {
            return notFound(id);
        }
        TimeSeries.Algorithm only;
        try {
            only = TimeSeries.Algorithm.named(algorithm);
        } catch (IllegalArgumentException e) {
            return error(Response.Status.BAD_REQUEST, e.getMessage());
        }
        try {
            List<TimeSeries.Spec> series = new ArrayList<>();
            for (JsonNode table : catalog.tables(id)) {
                for (TimeSeries.Spec spec : TimeSeries.specs(table)) {
                    if (only == null || only.tag.equals(spec.algorithm())) {
                        series.add(spec);
                    }
                }
            }
            return Response.ok(Map.of("service", Catalog.serviceName(id), "series", series)).build();
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            return openMetadataFailed(id, e);
        }
    }

    @PUT
    @Path("/timeseries")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response setRoles(@PathParam("id") long id, Catalog.Roles roles) {
        Optional<Source> source = source(id);
        if (source.isEmpty()) {
            return notFound(id);
        }
        if (roles == null || roles.table() == null || roles.table().isBlank()) {
            return error(Response.Status.BAD_REQUEST, "name the table: \"table\":\"schema.table\", or its name alone");
        }
        try {
            String wanted = roles.table().strip();
            List<JsonNode> matches = new ArrayList<>();
            for (JsonNode table : catalog.tables(id)) {
                String name = table.path("name").asText();
                String schema = table.path("databaseSchema").path("name").asText();
                if (wanted.equals(name) || wanted.equals(schema + "." + name)
                        || wanted.equals(table.path("fullyQualifiedName").asText())) {
                    matches.add(table);
                }
            }
            if (matches.isEmpty()) {
                return error(Response.Status.NOT_FOUND, "the catalogue of data source " + id + " has no table " + wanted
                    + " (POST /api/datasources/" + id + "/catalog reads the source again)");
            }
            if (matches.size() > 1) {
                return error(Response.Status.BAD_REQUEST, wanted + " is in more than one schema: name it as schema.table");
            }
            return Response.ok(catalog.applyRoles(matches.get(0), roles)).build();
        } catch (IllegalArgumentException e) {
            return error(Response.Status.BAD_REQUEST, e.getMessage());
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            return openMetadataFailed(id, e);
        }
    }

    /** A table for GET .../catalog: its names, type and tags, and each column's type, constraint and tags. */
    private static Map<String, Object> view(JsonNode table) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("fqn", table.path("fullyQualifiedName").asText());
        map.put("schema", table.path("databaseSchema").path("name").asText(null));
        map.put("name", table.path("name").asText());
        map.put("type", table.path("tableType").asText(null));
        map.put("description", table.path("description").asText(null));
        List<String> tableTags = new ArrayList<>();
        table.path("tags").forEach(tag -> tableTags.add(tag.path("tagFQN").asText()));
        map.put("tags", tableTags);
        List<Map<String, Object>> columns = new ArrayList<>();
        for (JsonNode column : table.path("columns")) {
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("name", column.path("name").asText());
            c.put("dataType", column.path("dataType").asText(null));
            c.put("constraint", column.path("constraint").asText(null));
            List<String> tags = new ArrayList<>();
            column.path("tags").forEach(tag -> tags.add(tag.path("tagFQN").asText()));
            c.put("tags", tags);
            columns.add(c);
        }
        map.put("columns", columns);
        Map<String, Object> constraints = new LinkedHashMap<>();
        for (JsonNode constraint : table.path("tableConstraints")) {
            List<String> names = new ArrayList<>();
            constraint.path("columns").forEach(c -> names.add(c.asText()));
            constraints.put(constraint.path("constraintType").asText(), names);
        }
        if (!constraints.isEmpty()) {
            map.put("constraints", constraints);
        }
        if (table.path("extension").isObject() && !table.path("extension").isEmpty()) {
            map.put("properties", table.path("extension"));
        }
        return map;
    }

    private Optional<Source> source(long id) {
        return QuarkusTransaction.requiringNew().call(() -> {
            Profile profile = profiles.current();
            return DataSource.of(profile, id).map(s -> new Source(s.id, s.name, s.description, s.type,
                s.type == DataSource.Type.DATABASE
                    ? AccessCodec.unseal(crypto, json, profile.id, profile.keyWrapped, s.access).database()
                    : null));
        });
    }

    private static Response notFound(long id) {
        return error(Response.Status.NOT_FOUND, "no data source with id " + id);
    }

    private static Response openMetadataFailed(long id, RuntimeException e) {
        String reason = e instanceof WebApplicationException w
            ? "answered " + w.getResponse().getStatus() + " " + w.getResponse().getStatusInfo().getReasonPhrase() + said(w)
            : String.valueOf(e.getMessage());
        LOG.warnf("catalogue: OpenMetadata failed for data source %d: %s", id, reason);
        return error(Response.Status.BAD_GATEWAY, "OpenMetadata " + reason);
    }

    /** OpenMetadata's own message for an error, when its answer carries one: {"code":400,"message":"..."}. */
    private static String said(WebApplicationException e) {
        try {
            String body = e.getResponse().readEntity(String.class);
            String message = body == null ? "" : new ObjectMapper().readTree(body).path("message").asText("");
            return message.isBlank() ? "" : ": " + message;
        } catch (RuntimeException | java.io.IOException ignored) {
            return "";
        }
    }

    private static Response error(Response.Status status, String message) {
        return Response.status(status).entity(Map.of("error", message)).build();
    }
}
