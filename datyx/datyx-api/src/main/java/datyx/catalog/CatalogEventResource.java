package datyx.catalog;

import java.io.IOException;
import java.io.InputStream;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.profile.Profile;
import datyx.profile.Profiles;
import datyx.training.Training;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.jboss.logging.Logger;

/**
 * The catalogue's switches:
 * POST /api/catalog/openmetadata-events is OpenMetadata's webhook
 * (CatalogEvents), open to OpenMetadata without a sign-in and
 * authenticated by its signature instead: a post that isn't signed with
 * datyx's secret is a 401 and changes nothing; one over 1 MB a 413.
 * GET /api/catalog/events answers the latest switches of the caller's
 * sources (GroupEvent), the newest first, secured like the sources.
 */
@Path("/api/catalog")
@Produces(MediaType.APPLICATION_JSON)
public class CatalogEventResource {

    private static final Logger LOG = Logger.getLogger(CatalogEventResource.class);

    /** The largest post datyx reads: OpenMetadata's event carries the whole table. */
    static final int MAX_POST = 1024 * 1024;

    static final int MAX_EVENTS = 200;

    @Inject
    CatalogEvents events;

    @Inject
    Profiles profiles;

    @Inject
    ObjectMapper json;

    /** A switch as GET /api/catalog/events answers it. */
    public record EventView(long id, long sourceId, String source, String table, String name, String group, boolean enabled,
            String via, String version, String by, Instant at, Instant receivedAt, List<Long> runIds) {
    }

    @POST
    @Path("/openmetadata-events")
    @Consumes(MediaType.WILDCARD)
    public Response openMetadataEvent(@HeaderParam(CatalogEvents.SIGNATURE_HEADER) String signature, InputStream body) {
        byte[] bytes;
        try {
            bytes = body == null ? new byte[0] : body.readNBytes(MAX_POST + 1);
        } catch (IOException e) {
            return error(Response.Status.BAD_REQUEST, "the post can't be read");
        }
        if (bytes.length > MAX_POST) {
            return error(Response.Status.REQUEST_ENTITY_TOO_LARGE, "a post is 1 MB at most");
        }
        if (!events.verify(bytes, signature)) {
            LOG.infof("catalog: a post to the OpenMetadata webhook %s; refused", signature == null ? "without a signature"
                : "with a wrong signature");
            return error(Response.Status.UNAUTHORIZED, "the post isn't signed with datyx's secret (" + CatalogEvents.SIGNATURE_HEADER + ")");
        }
        JsonNode post;
        try {
            post = json.readTree(bytes);
        } catch (IOException e) {
            return error(Response.Status.BAD_REQUEST, "the post isn't JSON");
        }
        if (post == null || !(post.isObject() || post.isArray())) {
            return error(Response.Status.BAD_REQUEST, "the post isn't a change event");
        }
        List<Map<String, Object>> recorded = new ArrayList<>();
        for (Training.Recorded r : events.receive(post)) {
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("eventId", r.eventId());
            map.put("runIds", r.runIds());
            recorded.add(map);
        }
        return Response.ok(Map.of("recorded", recorded)).build();
    }

    @GET
    @Path("/events")
    public Response events(@QueryParam("limit") @DefaultValue("50") int limit) {
        int n = Math.max(1, Math.min(MAX_EVENTS, limit));
        List<EventView> views = QuarkusTransaction.requiringNew().call(() -> {
            Profile profile = profiles.current();
            return GroupEvent.newest(profile, n).stream().map(CatalogEventResource::view).toList();
        });
        return Response.ok(Map.of("events", views)).build();
    }

    static EventView view(GroupEvent e) {
        String fqn = e.tableFqn;
        return new EventView(e.id, e.dataSource.id, e.dataSource.name, fqn, fqn.substring(fqn.lastIndexOf('.') + 1), e.groupName,
            e.enabled, e.via, e.omVersion, e.changedBy, e.changedAt, e.receivedAt, e.runIds());
    }

    private static Response error(Response.Status status, String message) {
        return Response.status(status).entity(Map.of("error", message)).build();
    }
}
