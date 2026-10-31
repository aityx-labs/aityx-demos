package datyx.openmetadata;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;
import java.util.function.Consumer;
import java.util.function.Function;

import com.fasterxml.jackson.databind.JsonNode;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;

/**
 * datyx's sign-in to OpenMetadata, for the calls that want one. A token
 * set as datyx.openmetadata.token (a bot's JWT, from OpenMetadata's
 * Settings > Bots) is used as is. Otherwise datyx signs in with
 * datyx.openmetadata.email and password (basic authentication, the
 * stack's admin in development) and keeps the token until a minute before
 * it expires (an hour, by default). A call answered 401 signs in again
 * and is tried once more, so a restarted server or a revoked session
 * doesn't stick.
 */
@ApplicationScoped
public class OpenMetadataSession {

    @Inject
    @RestClient
    OpenMetadataClient client;

    @ConfigProperty(name = "datyx.openmetadata.token")
    Optional<String> configuredToken;

    @ConfigProperty(name = "datyx.openmetadata.email")
    Optional<String> email;

    @ConfigProperty(name = "datyx.openmetadata.password")
    Optional<String> password;

    private String token;
    private Instant expiresAt = Instant.EPOCH;

    /** Runs {@code call} with "Bearer <token>", signing in again once when OpenMetadata answers 401. */
    public <T> T call(Function<String, T> call) {
        try {
            return call.apply(authorization(false));
        } catch (WebApplicationException e) {
            if (e.getResponse().getStatus() != 401) {
                throw e;
            }
            return call.apply(authorization(true));
        }
    }

    /** {@link #call} for calls that answer nothing. */
    public void run(Consumer<String> call) {
        call(authorization -> {
            call.accept(authorization);
            return null;
        });
    }

    private synchronized String authorization(boolean renew) {
        Optional<String> fixed = configuredToken.filter(t -> !t.isBlank());
        if (fixed.isPresent()) {
            return "Bearer " + fixed.get().strip();
        }
        if (renew || token == null || Instant.now().isAfter(expiresAt.minusSeconds(60))) {
            signIn();
        }
        return "Bearer " + token;
    }

    private void signIn() {
        String user = email.filter(e -> !e.isBlank()).orElseThrow(() -> new IllegalStateException(
            "no OpenMetadata credentials: set DATYX_OPENMETADATA_TOKEN, or DATYX_OPENMETADATA_EMAIL and DATYX_OPENMETADATA_PASSWORD"));
        String secret = password.orElse("");
        JsonNode answer = client.login(new OpenMetadataClient.Login(user,
            Base64.getEncoder().encodeToString(secret.getBytes(StandardCharsets.UTF_8))));
        String accessToken = answer.path("accessToken").asText(null);
        if (accessToken == null || accessToken.isBlank()) {
            throw new IllegalStateException("OpenMetadata's sign-in answered no token");
        }
        token = accessToken;
        long expiry = answer.path("expiryDuration").asLong(0);
        // expiryDuration is the expiry instant in epoch milliseconds; without
        // it, assume OpenMetadata's default hour.
        expiresAt = expiry > 0 ? Instant.ofEpochMilli(expiry) : Instant.now().plusSeconds(3600);
    }
}
