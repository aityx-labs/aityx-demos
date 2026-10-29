package datyx.hello;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;

/**
 * GET /api/hello: the first endpoint. {"message":"Hello, World!"}, or
 * {"message":"Hello, <name>!"} with ?name=.
 */
@Path("/api/hello")
@Produces(MediaType.APPLICATION_JSON)
public class HelloResource {

    @GET
    public Hello hello(@QueryParam("name") String name) {
        String who = name == null || name.isBlank() ? "World" : name.strip();
        return new Hello("Hello, " + who + "!");
    }

    public record Hello(String message) {
    }
}
