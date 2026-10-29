package datyx.hello;

import java.net.URI;
import java.time.Instant;
import java.util.List;

import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * The greetings on record:
 * GET /api/greetings?limit=50 lists the newest first;
 * POST /api/greetings {"message":"..."} stores one and answers 201 with it.
 * A blank or over-long message is a 400 (Hibernate Validator).
 */
@Path("/api/greetings")
@Produces(MediaType.APPLICATION_JSON)
public class GreetingResource {

    @GET
    public List<Greeting> list(@QueryParam("limit") @DefaultValue("50") int limit) {
        return Greeting.newest(Math.clamp(limit, 1, 500));
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Transactional
    public Response create(@Valid NewGreeting body) {
        Greeting greeting = new Greeting();
        greeting.message = body.message().strip();
        greeting.createdAt = Instant.now();
        greeting.persist();
        return Response.created(URI.create("/api/greetings/" + greeting.id)).entity(greeting).build();
    }

    public record NewGreeting(@NotBlank @Size(max = 200) String message) {
    }
}
