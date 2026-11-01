package datyx.openmetadata;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.annotation.RegisterProvider;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * The OpenMetadata server's API, at quarkus.rest-client.openmetadata.url
 * (application.properties). The version is public; everything else wants
 * a bearer token, which OpenMetadataSession provides (the authorization
 * argument). Entities go in and come out as JSON trees: datyx writes a
 * few fields of OpenMetadata's large schemas and reads fewer.
 *
 * The create calls are PUTs, OpenMetadata's create-or-update by name, so
 * a sync can run again: an entity keeps its id, and what people added in
 * OpenMetadata (tags, owners) stays.
 */
@Path("/api/v1")
@RegisterRestClient(configKey = "openmetadata")
@RegisterProvider(LenientJson.class)
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public interface OpenMetadataClient {

    /** The server's version: {"version":"2.0.7","revision":"...","timestamp":...}. */
    @GET
    @Path("/system/version")
    Version version();

    record Version(String version, String revision, long timestamp) {
    }

    /** Basic authentication's sign-in: the password in base64; answers {"accessToken":"...","expiryDuration":<epoch ms>}. */
    @POST
    @Path("/auth/login")
    JsonNode login(Login login);

    record Login(String email, String password) {
    }

    @PUT
    @Path("/services/databaseServices")
    JsonNode putDatabaseService(@HeaderParam("Authorization") String authorization, JsonNode service);

    @GET
    @Path("/services/databaseServices/name/{fqn}")
    JsonNode databaseService(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn);

    /** Removes a service and everything in it (its databases, schemas and tables), for good. */
    @DELETE
    @Path("/services/databaseServices/{id}")
    void deleteDatabaseService(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            @QueryParam("recursive") @DefaultValue("true") boolean recursive,
            @QueryParam("hardDelete") @DefaultValue("true") boolean hardDelete);

    @PUT
    @Path("/databases")
    JsonNode putDatabase(@HeaderParam("Authorization") String authorization, JsonNode database);

    /** A service's databases: {"data":[...],"paging":{"after":...}}. */
    @GET
    @Path("/databases")
    JsonNode databases(@HeaderParam("Authorization") String authorization, @QueryParam("service") String service,
            @QueryParam("limit") int limit, @QueryParam("after") String after);

    @PUT
    @Path("/databaseSchemas")
    JsonNode putDatabaseSchema(@HeaderParam("Authorization") String authorization, JsonNode schema);

    /** A database's schemas: {"data":[...],"paging":{"after":...}}. */
    @GET
    @Path("/databaseSchemas")
    JsonNode databaseSchemas(@HeaderParam("Authorization") String authorization, @QueryParam("database") String database,
            @QueryParam("limit") int limit, @QueryParam("after") String after);

    @PUT
    @Path("/tables")
    JsonNode putTable(@HeaderParam("Authorization") String authorization, JsonNode table);

    /** A schema's tables, with the fields asked for (columns, tags, extension). */
    @GET
    @Path("/tables")
    JsonNode tables(@HeaderParam("Authorization") String authorization, @QueryParam("databaseSchema") String schema,
            @QueryParam("fields") String fields, @QueryParam("limit") int limit, @QueryParam("after") String after);

    @GET
    @Path("/tables/name/{fqn}")
    JsonNode table(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn,
            @QueryParam("fields") String fields);

    /** A JSON Patch (RFC 6902) of a table: its columns' tags, its custom properties. */
    @PATCH
    @Path("/tables/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchTable(@HeaderParam("Authorization") String authorization, @PathParam("id") String id, JsonNode patch);

    /** Soft-deletes a table the source no longer has; a PUT of the same name brings it back. */
    @DELETE
    @Path("/tables/{id}")
    void deleteTable(@HeaderParam("Authorization") String authorization, @PathParam("id") String id);

    @PUT
    @Path("/services/messagingServices")
    JsonNode putMessagingService(@HeaderParam("Authorization") String authorization, JsonNode service);

    @GET
    @Path("/services/messagingServices/name/{fqn}")
    JsonNode messagingService(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn);

    /** Removes a messaging service and its topics, for good. */
    @DELETE
    @Path("/services/messagingServices/{id}")
    void deleteMessagingService(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            @QueryParam("recursive") @DefaultValue("true") boolean recursive,
            @QueryParam("hardDelete") @DefaultValue("true") boolean hardDelete);

    @PUT
    @Path("/topics")
    JsonNode putTopic(@HeaderParam("Authorization") String authorization, JsonNode topic);

    /** A messaging service's topics, with the fields asked for (messageSchema, tags): {"data":[...],"paging":{"after":...}}. */
    @GET
    @Path("/topics")
    JsonNode topics(@HeaderParam("Authorization") String authorization, @QueryParam("service") String service,
            @QueryParam("fields") String fields, @QueryParam("limit") int limit, @QueryParam("after") String after);

    /** A JSON Patch (RFC 6902) of a topic: its message schema's fields' tags. */
    @PATCH
    @Path("/topics/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchTopic(@HeaderParam("Authorization") String authorization, @PathParam("id") String id, JsonNode patch);

    /** Soft-deletes a topic the cluster no longer has; a PUT of the same name brings it back. */
    @DELETE
    @Path("/topics/{id}")
    void deleteTopic(@HeaderParam("Authorization") String authorization, @PathParam("id") String id);

    @PUT
    @Path("/classifications")
    JsonNode putClassification(@HeaderParam("Authorization") String authorization, JsonNode classification);

    @PUT
    @Path("/tags")
    JsonNode putTag(@HeaderParam("Authorization") String authorization, JsonNode tag);

    /** An entity type (table) or a property type (string), with its custom properties. */
    @GET
    @Path("/metadata/types/name/{name}")
    JsonNode type(@HeaderParam("Authorization") String authorization, @PathParam("name") String name,
            @QueryParam("fields") String fields);

    /** Adds or updates a custom property of an entity type. */
    @PUT
    @Path("/metadata/types/{id}")
    JsonNode putCustomProperty(@HeaderParam("Authorization") String authorization, @PathParam("id") String typeId,
            JsonNode property);
}
