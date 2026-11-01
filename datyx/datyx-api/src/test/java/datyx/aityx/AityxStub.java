package datyx.aityx;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.atomic.AtomicInteger;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import io.quarkus.test.common.QuarkusTestResourceLifecycleManager;

/**
 * aityx standing in, on a local port: POST /v1/systemone keeps what it
 * got (headers and body) and answers what it was told to (by default 200,
 * usage of 4017 input tokens, mode "test"). Tests drive it over HTTP, as
 * it runs outside Quarkus's class loader: POST /_next sets the next
 * answers' status, body, mode and delay, GET /_last answers the last request,
 * GET /_count how many came, POST /_reset forgets them all. Its URL is datyx.aityx.url.
 */
public class AityxStub implements QuarkusTestResourceLifecycleManager {

    static final String DEFAULT_ANSWER = "{\"answers\":{\"pain\":\"mild\"},\"decisions\":{\"level\":\"green\"},\"usage\":{\"input_tokens\":4017}}";

    private static final ObjectMapper JSON = new ObjectMapper();

    private HttpServer server;

    private volatile int status = 200;
    private volatile String answer = DEFAULT_ANSWER;
    private volatile String mode = "test";
    private volatile String last = "{}";
    private volatile long delayMillis;
    private final AtomicInteger count = new AtomicInteger();

    @Override
    public Map<String, String> start() {
        try {
            server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
        server.createContext("/v1/systemone", this::systemone);
        server.createContext("/_next", this::next);
        server.createContext("/_last", x -> send(x, 200, last, null));
        server.createContext("/_count", x -> send(x, 200, Integer.toString(count.get()), null));
        server.createContext("/_reset", x -> {
            status = 200;
            answer = DEFAULT_ANSWER;
            mode = "test";
            last = "{}";
            delayMillis = 0;
            count.set(0);
            send(x, 204, null, null);
        });
        server.start();
        return Map.of("%test.datyx.aityx.url", "http://127.0.0.1:" + server.getAddress().getPort() + "/");
    }

    @Override
    public void stop() {
        if (server != null) {
            server.stop(0);
        }
    }

    private void systemone(HttpExchange x) throws IOException {
        byte[] body = x.getRequestBody().readAllBytes();
        Map<String, String> headers = new TreeMap<>();
        x.getRequestHeaders().forEach((k, v) -> headers.put(k.toLowerCase(), String.join(",", v)));
        last = JSON.writeValueAsString(Map.of("method", x.getRequestMethod(), "path", x.getRequestURI().getPath(),
            "headers", headers, "body", new String(body, StandardCharsets.UTF_8)));
        count.incrementAndGet();
        if (delayMillis > 0) {
            try {
                Thread.sleep(delayMillis);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
        send(x, status, answer, mode);
    }

    private void next(HttpExchange x) throws IOException {
        JsonNode next = JSON.readTree(x.getRequestBody().readAllBytes());
        status = next.path("status").asInt(200);
        answer = next.path("body").asText(DEFAULT_ANSWER);
        mode = next.path("mode").isNull() ? null : next.path("mode").asText("test");
        delayMillis = next.path("delayMillis").asLong(0);
        send(x, 204, null, null);
    }

    private static void send(HttpExchange x, int status, String body, String mode) throws IOException {
        if (mode != null) {
            x.getResponseHeaders().add("x-aityx-mode", mode);
        }
        if (body == null) {
            x.sendResponseHeaders(status, -1);
            x.close();
            return;
        }
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        x.getResponseHeaders().add("Content-Type", "application/json");
        x.sendResponseHeaders(status, bytes.length);
        x.getResponseBody().write(bytes);
        x.close();
    }

    // The tests' side.

    private static final HttpClient CLIENT = HttpClient.newHttpClient();

    /** The next answers: this status, body and mode (null for none). */
    static void next(String base, int status, String body, String mode) throws Exception {
        next(base, status, body, mode, 0);
    }

    /** The same, answered after {@code delayMillis}. */
    static void next(String base, int status, String body, String mode, long delayMillis) throws Exception {
        Map<String, Object> next = new TreeMap<>();
        next.put("delayMillis", delayMillis);
        next.put("status", status);
        next.put("body", body);
        next.put("mode", mode);
        CLIENT.send(HttpRequest.newBuilder(URI.create(base.replaceAll("/+$", "") + "/_next"))
            .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(next))).build(), HttpResponse.BodyHandlers.discarding());
    }

    /** The default answers again, nothing received. */
    static void reset(String base) throws Exception {
        CLIENT.send(HttpRequest.newBuilder(URI.create(base.replaceAll("/+$", "") + "/_reset"))
            .POST(HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.discarding());
    }

    /** The last request: method, path, headers (lower-case names) and body. */
    static JsonNode last(String base) throws Exception {
        return JSON.readTree(CLIENT.send(HttpRequest.newBuilder(URI.create(base.replaceAll("/+$", "") + "/_last")).build(),
            HttpResponse.BodyHandlers.ofString()).body());
    }

    static int count(String base) throws Exception {
        return Integer.parseInt(CLIENT.send(HttpRequest.newBuilder(URI.create(base.replaceAll("/+$", "") + "/_count")).build(),
            HttpResponse.BodyHandlers.ofString()).body());
    }
}
