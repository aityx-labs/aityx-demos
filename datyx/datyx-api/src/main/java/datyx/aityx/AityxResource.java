package datyx.aityx;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import datyx.auth.CurrentUser;
import datyx.profile.Profiles;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * datyx's aityx gateway and its account (specs/aityx.md):
 * POST /api/aityx/v1/systemone passes a call on to aityx with datyx's key,
 * after the personalization hook, and answers aityx's answer as it came;
 * every call is recorded (AityxCall). A signed-in user's call is their
 * profile's; a service's (the service token, AityxGatewayPolicy) the
 * services'. GET /api/aityx answers the caller's account, GET
 * /api/aityx/calls/{id} one call with its request and answer.
 */
@Path("/api/aityx")
@Produces(MediaType.APPLICATION_JSON)
public class AityxResource {

    private static final Logger LOG = Logger.getLogger(AityxResource.class);

    /** The largest request the gateway takes. */
    static final int MAX_REQUEST = 1024 * 1024;

    static final String CALLER_HEADER = "X-Datyx-Caller";

    static final String PURPOSE_HEADER = "X-Datyx-Purpose";

    /** The service a service-token call is recorded as when it doesn't say. */
    static final String DEFAULT_SERVICE = "HealthHub";

    static final int RECENT = 50;

    static final int MAX_DAYS = 30;

    static final String COMING = "Coming: per-profile Jev models, extra context and decision variants. Calls go to aityx as they come.";

    @Inject
    AityxGateway gateway;

    @Inject
    AityxPersonalizer personalizer;

    @Inject
    ServiceToken serviceToken;

    @Inject
    Profiles profiles;

    @Inject
    CurrentUser user;

    @Inject
    ObjectMapper json;

    @ConfigProperty(name = "datyx.oidc.enabled", defaultValue = "false")
    boolean authentication;

    @ConfigProperty(name = "datyx.aityx.share-service-calls")
    Optional<Boolean> shareServiceCallsSet;

    @ConfigProperty(name = "datyx.aityx.share-service-calls-by-default", defaultValue = "false")
    boolean shareServiceCallsByDefault;

    boolean shareServiceCalls() {
        return sharesServiceCalls(shareServiceCallsSet, shareServiceCallsByDefault);
    }

    /**
     * Whether every profile sees the services' calls: as set, else the
     * profile's default (dev mode only). An empty value, as Docker
     * Compose passes an unset one, counts as unset.
     */
    static boolean sharesServiceCalls(Optional<Boolean> set, boolean byDefault) {
        return set.orElse(byDefault);
    }

    /** Calls' account: how many, failed, input tokens and their cost, latency (mean, median, 95th percentile), the latest. */
    public record Totals(int calls, int failed, long inputTokens, double costUsd, Double avgMillis, Integer p50Millis,
            Integer p95Millis, Instant lastCalledAt) {
    }

    public record Hour(Instant hour, int calls, int failed, long inputTokens, Integer p50Millis) {
    }

    public record Count(String name, int calls, int failed, long inputTokens) {
    }

    /**
     * Whether the gateway can pass calls on (datyx has an aityx key), for
     * a service by its token or a signed-in user, as the gateway: what a
     * service without a key of its own (HealthHub) asks before counting
     * on aityx. Calls nothing, records nothing.
     */
    @GET
    @Path("/v1/status")
    public Response status(@HeaderParam(ServiceToken.HEADER) String token) {
        if (token != null) {
            if (!serviceToken.matches(token)) {
                return error(Response.Status.UNAUTHORIZED, "the service token isn't datyx's (" + ServiceToken.HEADER + ")");
            }
        } else if (authentication && !user.authenticated()) {
            return error(Response.Status.UNAUTHORIZED, "sign in, or present a service token");
        }
        return Response.ok(Map.of("configured", gateway.configured())).build();
    }

    @POST
    @Path("/v1/systemone")
    @Consumes(MediaType.WILDCARD)
    public Response systemone(@HeaderParam(ServiceToken.HEADER) String token, @HeaderParam(CALLER_HEADER) String serviceName,
            @HeaderParam(PURPOSE_HEADER) String purposeHeader, InputStream body) {
        // Who: a service by its token (checked again here, as AityxGatewayPolicy did), else the signed-in user.
        AityxPersonalizer.Caller caller;
        String purpose = clip(purposeHeader, 64);
        if (token != null) {
            if (!serviceToken.matches(token)) {
                return error(Response.Status.UNAUTHORIZED, "the service token isn't datyx's (" + ServiceToken.HEADER + ")");
            }
            String name = serviceName(serviceName);
            caller = new AityxPersonalizer.Caller(null, name, true, purpose);
        } else {
            if (authentication && !user.authenticated()) {
                return error(Response.Status.UNAUTHORIZED, "sign in, or present a service token");
            }
            long profileId = profiles.current().id;
            String id = user.authenticated() ? user.id() : "local";
            caller = new AityxPersonalizer.Caller(profileId, clip(id, 320), false, purpose);
        }
        if (!gateway.configured()) {
            return error(Response.Status.SERVICE_UNAVAILABLE, "datyx has no aityx key");
        }
        byte[] bytes;
        try {
            bytes = body == null ? new byte[0] : body.readNBytes(MAX_REQUEST + 1);
        } catch (IOException e) {
            return error(Response.Status.BAD_REQUEST, "the request can't be read");
        }
        if (bytes.length > MAX_REQUEST) {
            return error(Response.Status.REQUEST_ENTITY_TOO_LARGE, "a request is 1 MB at most");
        }
        ObjectNode request;
        try {
            JsonNode node = json.readTree(bytes);
            if (!(node instanceof ObjectNode object)) {
                return error(Response.Status.BAD_REQUEST, "the body isn't a JSON object");
            }
            request = object;
        } catch (IOException e) {
            return error(Response.Status.BAD_REQUEST, "the body isn't a JSON object");
        }

        ObjectNode sent = personalizer.personalize(caller, request);
        boolean personalized = sent != request;
        byte[] out;
        if (personalized) {
            try {
                out = json.writeValueAsBytes(sent);
            } catch (IOException e) {
                return error(Response.Status.INTERNAL_SERVER_ERROR, "the personalized request can't be written");
            }
        } else {
            out = bytes;
        }

        AityxCall call = new AityxCall();
        call.profileId = caller.profileId();
        call.caller = caller.caller();
        call.service = caller.service();
        call.purpose = purpose;
        call.calledAt = Instant.now();
        call.personalized = personalized;
        call.model = clip(text(sent.get("model")), 200);
        call.decision = clip(text(sent.path("decision").get("name")), 500);
        call.questions = sent.path("questions").isObject() || sent.path("questions").isArray() ? sent.path("questions").size() : null;
        keepRequest(call, out);

        long started = System.nanoTime();
        Response answer;
        try {
            AityxGateway.Answer a = gateway.post(out);
            call.millis = millisSince(started);
            call.status = a.status();
            call.mode = clip(a.mode(), 64);
            JsonNode answered = parse(a.body());
            JsonNode tokens = answered == null ? null : answered.path("usage").get("input_tokens");
            call.inputTokens = tokens != null && tokens.isNumber() ? tokens.asLong() : null;
            call.costUsd = AityxCall.cost(call.inputTokens);
            if (a.status() < 200 || a.status() > 299) {
                call.error = clip(gateway.redact(aityxError(a.status(), answered)), 500);
            }
            keepResponse(call, a.body());
            Response.ResponseBuilder builder = Response.status(a.status()).entity(a.body()).type(a.contentType());
            if (a.mode() != null) {
                builder.header(AityxGateway.MODE_HEADER, a.mode());
            }
            answer = builder.build();
        } catch (AityxGateway.Unreached e) {
            call.millis = millisSince(started);
            call.status = e.status;
            call.error = e.getMessage();
            answer = error(Response.Status.fromStatusCode(e.status), e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return error(Response.Status.SERVICE_UNAVAILABLE, "datyx is stopping");
        }

        try {
            QuarkusTransaction.requiringNew().run(() -> {
                call.persist();
                AityxCall.trim(call.profileId, AityxCall.KEEP);
            });
        } catch (RuntimeException e) {
            LOG.warnf("aityx: a call couldn't be recorded: %s", e.getClass().getSimpleName());
        }
        LOG.infof("aityx: a %s call%s, %d in %d ms%s", call.service ? "service" : "user",
            purpose == null ? "" : " for " + purpose, call.status, call.millis, personalized ? ", personalized" : "");
        return answer;
    }

    @GET
    public Response account(@QueryParam("days") @DefaultValue("7") int days) {
        int window = Math.max(1, Math.min(MAX_DAYS, days));
        long profileId = profiles.current().id;
        Instant now = Instant.now();
        Instant since = now.minus(Duration.ofDays(window));
        List<AityxCall.Row> calls = QuarkusTransaction.requiringNew().call(() -> AityxCall.since(profileId, shareServiceCalls(), since));

        Instant top = now.truncatedTo(ChronoUnit.HOURS);
        List<Hour> perHour = new ArrayList<>();
        for (int h = 23; h >= 0; h--) {
            Instant from = top.minus(Duration.ofHours(h));
            Instant to = from.plus(Duration.ofHours(1));
            List<AityxCall.Row> in = calls.stream().filter(c -> !c.calledAt().isBefore(from) && c.calledAt().isBefore(to)).toList();
            Totals t = totals(in);
            perHour.add(new Hour(from, t.calls(), t.failed(), t.inputTokens(), t.p50Millis()));
        }

        Map<String, Object> personalization = new LinkedHashMap<>();
        personalization.put("active", personalizer.active());
        personalization.put("name", personalizer.name());
        personalization.put("note", personalizer.active() ? null : COMING);

        Map<String, Object> map = new LinkedHashMap<>();
        map.put("since", since);
        map.put("days", window);
        map.put("configured", gateway.configured());
        map.put("sharesServiceCalls", shareServiceCalls());
        map.put("pricePerMillionInputTokens", AityxCall.USD_PER_MILLION_INPUT_TOKENS);
        map.put("personalization", personalization);
        map.put("totals", totals(calls));
        map.put("lastHour", (int) calls.stream().filter(c -> c.calledAt().isAfter(now.minus(Duration.ofHours(1)))).count());
        map.put("perHour", perHour);
        map.put("byPurpose", counts(calls, AityxCall.Row::purpose));
        map.put("byModel", counts(calls, AityxCall.Row::model));
        map.put("byDecision", counts(calls, AityxCall.Row::decision));
        map.put("calls", calls.stream().limit(RECENT).map(AityxResource::view).toList());
        return Response.ok(map).build();
    }

    @GET
    @Path("/calls/{id}")
    public Response call(@PathParam("id") long id) {
        long profileId = profiles.current().id;
        Map<String, Object> answer = QuarkusTransaction.requiringNew().call(() -> {
            AityxCall call = AityxCall.findById(id);
            if (call == null || !call.seenBy(profileId, shareServiceCalls())) {
                return null;
            }
            Map<String, Object> map = view(row(call));
            map.put("request", body(call.request, call.requestTruncated));
            map.put("requestTruncated", call.requestTruncated);
            map.put("response", body(call.response, call.responseTruncated));
            map.put("responseTruncated", call.responseTruncated);
            return map;
        });
        if (answer == null) {
            return error(Response.Status.NOT_FOUND, "no aityx call " + id);
        }
        return Response.ok(answer).build();
    }

    /** The account of some calls: latency percentiles by nearest rank. */
    static Totals totals(List<AityxCall.Row> calls) {
        if (calls.isEmpty()) {
            return new Totals(0, 0, 0, 0, null, null, null, null);
        }
        int[] millis = calls.stream().mapToInt(AityxCall.Row::millis).sorted().toArray();
        double avg = Arrays.stream(millis).average().orElse(0);
        double cost = calls.stream().map(AityxCall.Row::costUsd).filter(c -> c != null).mapToDouble(Double::doubleValue).sum();
        return new Totals(calls.size(), (int) calls.stream().filter(AityxCall.Row::failed).count(), tokens(calls),
            Math.round(cost * 1e12) / 1e12, Math.round(avg * 10) / 10.0, rank(millis, 0.5), rank(millis, 0.95),
            calls.stream().map(AityxCall.Row::calledAt).max(Instant::compareTo).orElse(null));
    }

    static int rank(int[] sorted, double p) {
        return sorted[Math.max(0, (int) Math.ceil(p * sorted.length) - 1)];
    }

    private static long tokens(List<AityxCall.Row> calls) {
        return calls.stream().map(AityxCall.Row::inputTokens).filter(t -> t != null).mapToLong(Long::longValue).sum();
    }

    /** Each value (null when a call had none) with its calls, the most called first. */
    static List<Count> counts(List<AityxCall.Row> calls, Function<AityxCall.Row, String> by) {
        Map<String, List<AityxCall.Row>> groups = new LinkedHashMap<>();
        for (AityxCall.Row c : calls) {
            groups.computeIfAbsent(by.apply(c), k -> new ArrayList<>()).add(c);
        }
        return groups.entrySet().stream()
            .map(e -> new Count(e.getKey(), e.getValue().size(), (int) e.getValue().stream().filter(AityxCall.Row::failed).count(),
                tokens(e.getValue())))
            .sorted(Comparator.comparingInt(Count::calls).reversed())
            .toList();
    }

    private static Map<String, Object> view(AityxCall.Row c) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("id", c.id());
        map.put("at", c.calledAt());
        map.put("caller", c.caller());
        map.put("service", c.service());
        map.put("purpose", c.purpose());
        map.put("model", c.model());
        map.put("decision", c.decision());
        map.put("questions", c.questions());
        map.put("millis", c.millis());
        map.put("status", c.status());
        map.put("mode", c.mode());
        map.put("inputTokens", c.inputTokens());
        map.put("costUsd", c.costUsd());
        map.put("error", c.error());
        map.put("personalized", c.personalized());
        return map;
    }

    private static AityxCall.Row row(AityxCall c) {
        return new AityxCall.Row(c.id, c.profileId, c.caller, c.service, c.purpose, c.calledAt, c.millis, c.status, c.mode,
            c.model, c.decision, c.questions, c.inputTokens, c.costUsd, c.error, c.personalized);
    }

    /** A recorded body: its JSON, or its text when truncated or not JSON. */
    private Object body(String text, boolean truncated) {
        if (text == null || truncated) {
            return text;
        }
        try {
            return json.readTree(text);
        } catch (IOException e) {
            return text;
        }
    }

    private void keepRequest(AityxCall call, byte[] bytes) {
        call.requestTruncated = bytes.length > AityxCall.MAX_BODY;
        call.request = gateway.redact(kept(bytes));
    }

    private void keepResponse(AityxCall call, byte[] bytes) {
        call.responseTruncated = bytes.length > AityxCall.MAX_BODY;
        call.response = gateway.redact(kept(bytes));
    }

    /** At most {@link AityxCall#MAX_BODY} bytes as text, without NULs (PostgreSQL's text can't hold them). */
    private static String kept(byte[] bytes) {
        int n = Math.min(bytes.length, AityxCall.MAX_BODY);
        return new String(bytes, 0, n, StandardCharsets.UTF_8).replace("\u0000", "");
    }

    private JsonNode parse(byte[] bytes) {
        try {
            JsonNode node = json.readTree(bytes);
            return node != null && node.isObject() ? node : null;
        } catch (IOException e) {
            return null;
        }
    }

    /** Why aityx refused: its error's code or message, else its status. */
    private static String aityxError(int status, JsonNode answered) {
        JsonNode error = answered == null ? null : answered.get("error");
        if (error != null && error.isObject()) {
            String code = text(error.get("code"));
            String message = text(error.get("message"));
            if (code != null || message != null) {
                return "aityx answered " + status + ": " + (code != null ? code : message);
            }
        } else if (error != null && error.isTextual()) {
            return "aityx answered " + status + ": " + error.asText();
        }
        return "aityx answered " + status;
    }

    /** A service's name: letters, digits, space, '.', '_', '-', at most 64; HealthHub when it gives none. */
    static String serviceName(String header) {
        String name = header == null ? "" : header.replaceAll("[^A-Za-z0-9 ._-]", "").strip();
        name = clip(name, 64);
        return name == null || name.isEmpty() ? DEFAULT_SERVICE : name;
    }

    private static String text(JsonNode node) {
        return node == null || node.isNull() || node.isContainerNode() ? null : node.asText();
    }

    /** {@code value} stripped of control characters and cut to {@code max}; null when empty. */
    static String clip(String value, int max) {
        if (value == null) {
            return null;
        }
        String v = value.replaceAll("\\p{Cntrl}", "").strip();
        if (v.isEmpty()) {
            return null;
        }
        return v.length() > max ? v.substring(0, max) : v;
    }

    private static int millisSince(long started) {
        return (int) Math.min(Integer.MAX_VALUE, (System.nanoTime() - started) / 1_000_000);
    }

    private static Response error(Response.Status status, String message) {
        return Response.status(status).type(MediaType.APPLICATION_JSON).entity(Map.of("error", message)).build();
    }
}
