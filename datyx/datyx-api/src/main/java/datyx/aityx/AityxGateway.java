package datyx.aityx;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.http.HttpTimeoutException;
import java.time.Duration;
import java.util.Optional;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * aityx's /v1/systemone, called with datyx's key (datyx.aityx.key,
 * AITYX_API_KEY) at datyx.aityx.url (DATYX_AITYX_URL). The key goes in
 * the Authorization header and nowhere else: never logged, answered or
 * put in an error ({@link #redact} blanks it out of any text that is
 * kept). Redirects aren't followed, so the key goes to that URL only.
 */
@ApplicationScoped
public class AityxGateway {

    public static final String DEFAULT_URL = "https://api.aityx.ai";

    public static final String MODE_HEADER = "X-aityx-Mode";

    /** aityx's answer: its status, body, content type and mode. */
    public record Answer(int status, byte[] body, String contentType, String mode) {
    }

    /** aityx wasn't reached, or didn't answer in time: the status the gateway answers and why. */
    public static class Unreached extends Exception {

        public final int status;

        Unreached(int status, String message) {
            super(message, null, false, false);
            this.status = status;
        }
    }

    private final String key;

    private final URI systemone;

    private final Duration timeout;

    private final HttpClient client;

    AityxGateway(@ConfigProperty(name = "datyx.aityx.key") Optional<String> key,
            @ConfigProperty(name = "datyx.aityx.url") Optional<String> url,
            @ConfigProperty(name = "datyx.aityx.timeout", defaultValue = "60S") Duration timeout) {
        this.key = key.map(String::strip).filter(k -> !k.isEmpty()).orElse(null);
        String base = url.map(String::strip).filter(u -> !u.isEmpty()).orElse(DEFAULT_URL).replaceAll("/+$", "");
        this.systemone = URI.create(base + "/v1/systemone");
        this.timeout = timeout;
        this.client = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .connectTimeout(Duration.ofSeconds(10))
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();
    }

    /** Whether datyx has an aityx key. */
    public boolean configured() {
        return key != null;
    }

    public Duration timeout() {
        return timeout;
    }

    /** Posts {@code body} (JSON) to aityx's /v1/systemone and answers what aityx answered. */
    public Answer post(byte[] body) throws Unreached, InterruptedException {
        if (key == null) {
            throw new IllegalStateException("datyx has no aityx key");
        }
        HttpRequest request = HttpRequest.newBuilder(systemone)
            .timeout(timeout)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .header("Authorization", "Bearer " + key)
            .POST(HttpRequest.BodyPublishers.ofByteArray(body))
            .build();
        HttpResponse<byte[]> response;
        try {
            response = client.send(request, HttpResponse.BodyHandlers.ofByteArray());
        } catch (HttpTimeoutException e) {
            throw new Unreached(504, "aityx didn't answer within " + timeout.toSeconds() + " s");
        } catch (IOException e) {
            throw new Unreached(502, "aityx can't be reached");
        }
        return new Answer(response.statusCode(), response.body(),
            response.headers().firstValue("Content-Type").orElse("application/json"),
            response.headers().firstValue(MODE_HEADER).orElse(null));
    }

    /** {@code text} with datyx's key blanked out, should it ever carry it. */
    public String redact(String text) {
        return text == null || key == null ? text : text.replace(key, "[redacted]");
    }
}
