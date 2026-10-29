package datyx.openmetadata;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * The OpenMetadata server's API, at quarkus.rest-client.openmetadata.url
 * (application.properties). Only its public endpoints so far.
 */
@Path("/api/v1/system")
@RegisterRestClient(configKey = "openmetadata")
@Produces(MediaType.APPLICATION_JSON)
public interface OpenMetadataClient {

    /** The server's version: {"version":"2.0.7","revision":"...","timestamp":...}. */
    @GET
    @Path("/version")
    Version version();

    record Version(String version, String revision, long timestamp) {
    }
}
