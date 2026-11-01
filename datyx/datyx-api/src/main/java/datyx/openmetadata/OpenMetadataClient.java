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

    /**
     * A table's versions, newest first: {"versions": [...]}, each the
     * entity as it was, as a JSON string, with its version, updatedBy,
     * updatedAt and changeDescription.
     */
    @GET
    @Path("/tables/{id}/versions")
    JsonNode tableVersions(@HeaderParam("Authorization") String authorization, @PathParam("id") String id);

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

    /**
     * Creates or updates an event subscription by its name (an alert, in
     * OpenMetadata's UI): which entities' changes it sends, and where, such
     * as a webhook's endpoint and the secret it signs its posts with.
     */
    @PUT
    @Path("/events/subscriptions")
    JsonNode putEventSubscription(@HeaderParam("Authorization") String authorization, JsonNode subscription);

    /** An event subscription by its name; a 404 when there is none. */
    @GET
    @Path("/events/subscriptions/name/{name}")
    JsonNode eventSubscription(@HeaderParam("Authorization") String authorization, @PathParam("name") String name);

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

    @GET
    @Path("/databases/name/{fqn}")
    JsonNode database(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn,
            @QueryParam("fields") String fields);

    @GET
    @Path("/databaseSchemas/name/{fqn}")
    JsonNode databaseSchema(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn,
            @QueryParam("fields") String fields);

    @GET
    @Path("/topics/name/{fqn}")
    JsonNode topic(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn,
            @QueryParam("fields") String fields);

    /** A JSON Patch of a database service: its owners. */
    @PATCH
    @Path("/services/databaseServices/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchDatabaseService(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            JsonNode patch);

    /** A JSON Patch of a messaging service: its owners. */
    @PATCH
    @Path("/services/messagingServices/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchMessagingService(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            JsonNode patch);

    /** A JSON Patch of a database: its description, owners, tags. */
    @PATCH
    @Path("/databases/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchDatabase(@HeaderParam("Authorization") String authorization, @PathParam("id") String id, JsonNode patch);

    /** A JSON Patch of a database schema: its description, owners, tags. */
    @PATCH
    @Path("/databaseSchemas/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchDatabaseSchema(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            JsonNode patch);

    /** A JSON Patch of a pipeline: its owners, tags. */
    @PATCH
    @Path("/pipelines/{id}")
    @Consumes("application/json-patch+json")
    JsonNode patchPipeline(@HeaderParam("Authorization") String authorization, @PathParam("id") String id, JsonNode patch);

    /** A team: {"name","displayName","description","teamType":"Group"}. */
    @PUT
    @Path("/teams")
    JsonNode putTeam(@HeaderParam("Authorization") String authorization, JsonNode team);

    /** A domain: {"name","displayName","description","domainType"}. */
    @PUT
    @Path("/domains")
    JsonNode putDomain(@HeaderParam("Authorization") String authorization, JsonNode domain);

    /** Puts assets in a domain: {"assets":[{"id","type"}]}. */
    @PUT
    @Path("/domains/{name}/assets/add")
    JsonNode addDomainAssets(@HeaderParam("Authorization") String authorization, @PathParam("name") String name,
            JsonNode assets);

    /** A data product of a domain: {"name","displayName","description","domains":[...]}. */
    @PUT
    @Path("/dataProducts")
    JsonNode putDataProduct(@HeaderParam("Authorization") String authorization, JsonNode product);

    /** Puts assets in a data product: {"assets":[{"id","type"}]}. */
    @PUT
    @Path("/dataProducts/{name}/assets/add")
    JsonNode addDataProductAssets(@HeaderParam("Authorization") String authorization, @PathParam("name") String name,
            JsonNode assets);

    @PUT
    @Path("/glossaries")
    JsonNode putGlossary(@HeaderParam("Authorization") String authorization, JsonNode glossary);

    @PUT
    @Path("/glossaryTerms")
    JsonNode putGlossaryTerm(@HeaderParam("Authorization") String authorization, JsonNode term);

    @PUT
    @Path("/services/pipelineServices")
    JsonNode putPipelineService(@HeaderParam("Authorization") String authorization, JsonNode service);

    @PUT
    @Path("/pipelines")
    JsonNode putPipeline(@HeaderParam("Authorization") String authorization, JsonNode pipeline);

    /** A lineage edge: {"edge":{"fromEntity":{"id","type"},"toEntity":{...},"lineageDetails":{...}}}. */
    @PUT
    @Path("/lineage")
    void putLineage(@HeaderParam("Authorization") String authorization, JsonNode lineage);

    /** A data quality test case of a table or column, by name within it: {"name","entityLink","testDefinition",...}. */
    @PUT
    @Path("/dataQuality/testCases")
    JsonNode putTestCase(@HeaderParam("Authorization") String authorization, JsonNode testCase);

    /** A test case's result: {"timestamp","testCaseStatus","result","testResultValue":[...]}. */
    @POST
    @Path("/dataQuality/testCases/testCaseResults/{fqn}")
    JsonNode addTestCaseResult(@HeaderParam("Authorization") String authorization, @PathParam("fqn") String fqn,
            JsonNode result);

    /** A table's profile: {"tableProfile":{"timestamp","rowCount","columnCount"},"columnProfile":[...]}. */
    @PUT
    @Path("/tables/{id}/tableProfile")
    JsonNode putTableProfile(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            JsonNode profile);

    /** A table's test cases with their latest results: {"data":[...]}. */
    @GET
    @Path("/dataQuality/testCases")
    JsonNode testCases(@HeaderParam("Authorization") String authorization, @QueryParam("entityLink") String entityLink,
            @QueryParam("includeAllTests") boolean includeAllTests, @QueryParam("fields") String fields,
            @QueryParam("limit") int limit);

    /** An entity's data contract; 404 when it has none. */
    @GET
    @Path("/dataContracts/entity")
    JsonNode dataContractOf(@HeaderParam("Authorization") String authorization, @QueryParam("entityId") String entityId,
            @QueryParam("entityType") String entityType, @QueryParam("fields") String fields);

    @PUT
    @Path("/dataContracts")
    JsonNode putDataContract(@HeaderParam("Authorization") String authorization, JsonNode contract);

    /** A data contract's validation result: {"dataContractFQN","timestamp","contractExecutionStatus",...}. */
    @PUT
    @Path("/dataContracts/{id}/results")
    JsonNode putDataContractResult(@HeaderParam("Authorization") String authorization, @PathParam("id") String id,
            JsonNode result);

    /** Runs one of OpenMetadata's applications now (DataInsightsApplication). */
    @POST
    @Path("/apps/trigger/{name}")
    void triggerApp(@HeaderParam("Authorization") String authorization, @PathParam("name") String name, JsonNode config);
}
