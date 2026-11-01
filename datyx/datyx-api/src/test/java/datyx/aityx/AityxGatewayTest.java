package datyx.aityx;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.CoreMatchers.nullValue;
import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.logging.Handler;
import java.util.logging.LogRecord;
import java.util.logging.Logger;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.agroal.api.AgroalDataSource;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.http.ContentType;
import io.restassured.response.ExtractableResponse;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * The gateway with authentication off (every call the local profile's)
 * and aityx a local stub (AityxStub): what it forwards and answers, what
 * it records, the service token, the personalization hook and the
 * account.
 */
@QuarkusTest
@TestProfile(AityxGatewayTest.Profile.class)
class AityxGatewayTest {

    static final String KEY = "test-aityx-key-0f1e2d3c4b5a";
    static final String TOKEN = "test-service-token-9a8b7c";

    public static class Profile implements QuarkusTestProfile {
        @Override
        public Map<String, String> getConfigOverrides() {
            return Map.of(
                "%test.datyx.aityx.key", KEY,
                "%test.datyx.service-token", TOKEN,
                "datyx.aityx.share-service-calls", "true");
        }

        @Override
        public List<TestResourceEntry> testResources() {
            return List.of(new TestResourceEntry(AityxStub.class));
        }
    }

    static final String BODY = """
        {"model":"jev-latest","questions":{"pain":{"type":"choice"},"onset":{"type":"choice"},"noise":{"type":"noul"}},
         "decision":{"name":"HealthHub · Triage at the desk","decisions":{}},"state":{"complaint":"a cough","age":54}}""";

    @ConfigProperty(name = "datyx.aityx.url")
    String aityx;

    @Inject
    AgroalDataSource dataSource;

    @Inject
    ObjectMapper json;

    final List<String> logged = new ArrayList<>();

    final Handler capture = new Handler() {
        @Override
        public void publish(LogRecord record) {
            String message = record.getMessage();
            Object[] params = record.getParameters();
            synchronized (logged) {
                logged.add(message + (params == null ? "" : " " + java.util.Arrays.toString(params))
                    + (record.getThrown() == null ? "" : " " + record.getThrown()));
            }
        }

        @Override
        public void flush() {
        }

        @Override
        public void close() {
        }
    };

    @BeforeEach
    void clean() throws Exception {
        AityxStub.reset(aityx);
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            s.execute("delete from aityx_call");
        }
        Logger.getLogger("").addHandler(capture);
    }

    @AfterEach
    void stopCapturing() {
        Logger.getLogger("").removeHandler(capture);
    }

    private ExtractableResponse<Response> post(String body, String purpose) {
        var request = given().contentType(ContentType.JSON).body(body.getBytes(StandardCharsets.UTF_8))
            .header("Authorization-Like", "nothing").header("X-Something", "not for aityx");
        if (purpose != null) {
            request.header("X-Datyx-Purpose", purpose);
        }
        return request.when().post("/api/aityx/v1/systemone").then().extract();
    }

    private List<String> rowsAsText() throws Exception {
        List<String> rows = new ArrayList<>();
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement();
                ResultSet r = s.executeQuery("select t::text from aityx_call t")) {
            while (r.next()) {
                rows.add(r.getString(1));
            }
        }
        return rows;
    }

    @Test
    void forwardsTheBodyAndAnswersAityxsAnswerAsItCame() throws Exception {
        String answer = "{\"answers\":{\"pain\":\"mild\"},  \"usage\":{\"input_tokens\":4017}, \"z\":[1,2]}";
        AityxStub.next(aityx, 200, answer, "live");
        ExtractableResponse<Response> r = post(BODY, "triage");
        assertEquals(200, r.statusCode());
        assertEquals(answer, r.asString(), "aityx's body, byte for byte");
        assertEquals("live", r.header("X-aityx-Mode"));

        JsonNode got = AityxStub.last(aityx);
        assertEquals("POST", got.path("method").asText());
        assertEquals("/v1/systemone", got.path("path").asText());
        assertEquals(BODY, got.path("body").asText(), "the caller's body, byte for byte");
        assertEquals("Bearer " + KEY, got.path("headers").path("authorization").asText(), "datyx's key, to aityx only");
        assertTrue(got.path("headers").path("x-something").isMissingNode(), "the caller's headers stay here");
        assertTrue(got.path("headers").path("x-datyx-purpose").isMissingNode());

        assertFalse(r.asString().contains(KEY));
        r.headers().forEach(h -> assertFalse(h.getValue().contains(KEY), h.getName()));
        for (String row : rowsAsText()) {
            assertFalse(row.contains(KEY), "the key isn't recorded");
        }
        synchronized (logged) {
            assertFalse(logged.isEmpty(), "the call is logged");
            for (String line : logged) {
                assertFalse(line.contains(KEY), "the key isn't logged: " + line);
                assertFalse(line.contains(TOKEN), "nor the token: " + line);
            }
        }
    }

    @Test
    void anErrorIsAnsweredAsItCameAndRecordedAsFailed() throws Exception {
        String answer = "{\"error\":{\"code\":\"rate_limited\",\"message\":\"slow down\"}}";
        AityxStub.next(aityx, 429, answer, null);
        ExtractableResponse<Response> r = post(BODY, null);
        assertEquals(429, r.statusCode());
        assertEquals(answer, r.asString());
        assertNull(r.header("X-aityx-Mode"));
        given().when().get("/api/aityx").then().statusCode(200)
            .body("totals.calls", is(1)).body("totals.failed", is(1))
            .body("calls[0].status", is(429)).body("calls[0].error", is("aityx answered 429: rate_limited"))
            .body("calls[0].inputTokens", nullValue()).body("calls[0].costUsd", nullValue())
            .body("calls[0].mode", nullValue()).body("calls[0].purpose", nullValue());
    }

    @Test
    void refusesTooLargeAndNotJson() throws Exception {
        byte[] big = new byte[AityxResource.MAX_REQUEST + 1];
        java.util.Arrays.fill(big, (byte) ' ');
        big[0] = '{';
        given().contentType(ContentType.JSON).body(big).when().post("/api/aityx/v1/systemone").then().statusCode(413)
            .body("error", is("a request is 1 MB at most"));
        given().contentType(ContentType.JSON).body("[1,2]").when().post("/api/aityx/v1/systemone").then().statusCode(400)
            .body("error", is("the body isn't a JSON object"));
        given().contentType(ContentType.TEXT).body("not json").when().post("/api/aityx/v1/systemone").then().statusCode(400);
        assertEquals(0, AityxStub.count(aityx), "nothing reached aityx");
        given().when().get("/api/aityx").then().statusCode(200).body("totals.calls", is(0));
    }

    @Test
    void recordsTheCall() throws Exception {
        ExtractableResponse<Response> r = post(BODY, "  triage ");
        assertEquals(200, r.statusCode());
        JsonNode account = json.readTree(given().when().get("/api/aityx").then().statusCode(200).extract().asString());
        JsonNode call = account.path("calls").get(0);
        assertEquals("local", call.path("caller").asText());
        assertFalse(call.path("service").asBoolean());
        assertEquals("triage", call.path("purpose").asText());
        assertEquals("jev-latest", call.path("model").asText());
        assertEquals("HealthHub · Triage at the desk", call.path("decision").asText());
        assertEquals(3, call.path("questions").asInt());
        assertEquals(200, call.path("status").asInt());
        assertEquals("test", call.path("mode").asText());
        assertEquals(4017, call.path("inputTokens").asLong());
        assertEquals(4017 * 0.042 / 1e6, call.path("costUsd").asDouble(), 1e-12);
        assertFalse(call.path("personalized").asBoolean());
        assertTrue(call.path("request").isMissingNode(), "the list has no bodies");

        long id = call.path("id").asLong();
        JsonNode one = json.readTree(given().when().get("/api/aityx/calls/" + id).then().statusCode(200).extract().asString());
        assertEquals(json.readTree(BODY), one.path("request"));
        assertEquals(json.readTree(AityxStub.DEFAULT_ANSWER), one.path("response"));
        assertFalse(one.path("requestTruncated").asBoolean());
        assertFalse(one.path("responseTruncated").asBoolean());
        given().when().get("/api/aityx/calls/" + (id + 1000)).then().statusCode(404).body("error", is("no aityx call " + (id + 1000)));
    }

    @Test
    void keepsLargeBodiesTruncated() throws Exception {
        String big = "{\"model\":\"jev-latest\",\"state\":{\"complaint\":\"" + "a".repeat(100_000) + "\"}}";
        assertEquals(200, post(big, null).statusCode());
        assertEquals(big, AityxStub.last(aityx).path("body").asText(), "sent whole");
        long id = json.readTree(given().when().get("/api/aityx").then().extract().asString()).path("calls").get(0).path("id").asLong();
        JsonNode one = json.readTree(given().when().get("/api/aityx/calls/" + id).then().statusCode(200).extract().asString());
        assertTrue(one.path("requestTruncated").asBoolean());
        assertEquals(AityxCall.MAX_BODY, one.path("request").asText().length());
        assertTrue(one.path("request").isTextual());
    }

    @Test
    void aServiceCallsWithItsToken() throws Exception {
        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", TOKEN)
            .header("X-Datyx-Caller", "Health<Hub>!é ward-2").header("X-Datyx-Purpose", "triage")
            .when().post("/api/aityx/v1/systemone").then().statusCode(200);
        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", TOKEN)
            .when().post("/api/aityx/v1/systemone").then().statusCode(200);
        assertTrue(AityxStub.last(aityx).path("headers").path("x-datyx-service-token").isMissingNode(), "the token stays here");
        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", TOKEN + "x")
            .when().post("/api/aityx/v1/systemone").then().statusCode(401);
        given().contentType(ContentType.JSON).body(BODY).header("X-Datyx-Service-Token", "")
            .when().post("/api/aityx/v1/systemone").then().statusCode(401);
        assertEquals(2, AityxStub.count(aityx), "the refused never reach aityx");
        given().when().get("/api/aityx").then().statusCode(200)
            .body("sharesServiceCalls", is(true))
            .body("calls", hasSize(2))
            .body("calls[0].caller", is("HealthHub")).body("calls[0].service", is(true))
            .body("calls[1].caller", is("HealthHub ward-2")).body("calls[1].purpose", is("triage"));
        for (String row : rowsAsText()) {
            assertFalse(row.contains(TOKEN), "the token isn't recorded");
        }
    }

    @Test
    void theTokenIsComparedAsADigest() {
        ServiceToken token = new ServiceToken(java.util.Optional.of(" " + TOKEN + " "));
        assertTrue(token.configured());
        assertTrue(token.matches(TOKEN));
        assertFalse(token.matches(TOKEN.substring(1)));
        assertFalse(token.matches(null));
        ServiceToken none = new ServiceToken(java.util.Optional.empty());
        assertFalse(none.configured());
        assertFalse(none.matches(""));
        assertFalse(new ServiceToken(java.util.Optional.of("  ")).configured());
    }

    @Test
    void thePersonalizationHookShapesWhatAityxGets() throws Exception {
        List<AityxPersonalizer.Caller> seen = new ArrayList<>();
        // A subclass of the default bean, as QuarkusMock wants: another personalizer.
        QuarkusMock.installMockForType(new NoPersonalization() {
            @Override
            public boolean active() {
                return true;
            }

            @Override
            public ObjectNode personalize(Caller caller, ObjectNode body) {
                seen.add(caller);
                ObjectNode copy = body.deepCopy();
                copy.put("model", "jev-personal");
                ((ObjectNode) copy.path("state")).put("context", "prefers short waits");
                return copy;
            }
        }, AityxPersonalizer.class);
        assertEquals(200, post(BODY, "triage").statusCode());
        assertEquals(1, seen.size());
        assertEquals("local", seen.get(0).caller());
        assertFalse(seen.get(0).service());
        assertEquals("triage", seen.get(0).purpose());
        assertNotNull(seen.get(0).profileId());
        JsonNode sent = json.readTree(AityxStub.last(aityx).path("body").asText());
        assertEquals("jev-personal", sent.path("model").asText());
        assertEquals("prefers short waits", sent.path("state").path("context").asText());
        given().when().get("/api/aityx").then().statusCode(200)
            .body("calls[0].personalized", is(true)).body("calls[0].model", is("jev-personal"))
            .body("personalization.active", is(true));
    }

    @Test
    void personalizationIsComingNotActive() {
        given().when().get("/api/aityx").then().statusCode(200)
            .body("configured", is(true))
            .body("personalization.active", is(false)).body("personalization.name", is("none"))
            .body("personalization.note", is(AityxResource.COMING))
            .body("pricePerMillionInputTokens", is(0.042f))
            .body("days", is(7)).body("perHour", hasSize(24))
            .body("totals.calls", is(0)).body("totals.p50Millis", nullValue()).body("totals.costUsd", is(0.0f));
    }

    @Test
    void accountsForTheCalls() throws Exception {
        assertEquals(200, post(BODY, "triage").statusCode());
        assertEquals(200, post(BODY, "triage").statusCode());
        AityxStub.next(aityx, 500, "{\"error\":\"boom\"}", "live");
        assertEquals(500, post(BODY.replace("jev-latest", "jev-other"), "triage").statusCode());
        AityxStub.next(aityx, 200, AityxStub.DEFAULT_ANSWER, "test");
        assertEquals(200, post("{\"model\":\"jev-latest\"}", "summary").statusCode());
        // An old call, outside a 1-day window.
        QuarkusTransaction.requiringNew().run(() -> {
            AityxCall old = new AityxCall();
            old.profileId = null;
            old.caller = "HealthHub";
            old.service = true;
            old.calledAt = Instant.now().minusSeconds(3 * 86_400);
            old.millis = 10;
            old.status = 200;
            old.persist();
        });

        JsonNode a = json.readTree(given().when().get("/api/aityx").then().statusCode(200).extract().asString());
        JsonNode totals = a.path("totals");
        assertEquals(5, totals.path("calls").asInt());
        assertEquals(1, totals.path("failed").asInt());
        assertEquals(3 * 4017, totals.path("inputTokens").asLong());
        assertEquals(3 * 4017 * 0.042 / 1e6, totals.path("costUsd").asDouble(), 1e-9);
        assertNotNull(totals.path("p50Millis").numberValue());
        assertNotNull(totals.path("p95Millis").numberValue());
        assertFalse(totals.path("lastCalledAt").isNull());
        assertEquals(4, a.path("lastHour").asInt());
        JsonNode hour = a.path("perHour").get(23);
        assertEquals(4, hour.path("calls").asInt());
        assertEquals(1, hour.path("failed").asInt());
        assertEquals(3 * 4017, hour.path("inputTokens").asLong());
        assertEquals("triage", a.path("byPurpose").get(0).path("name").asText());
        assertEquals(3, a.path("byPurpose").get(0).path("calls").asInt());
        assertEquals(1, a.path("byPurpose").get(0).path("failed").asInt());
        assertEquals(3, a.path("byModel").get(0).path("calls").asInt());
        assertEquals("jev-latest", a.path("byModel").get(0).path("name").asText());
        assertEquals(3, a.path("byDecision").get(0).path("calls").asInt(), "three named the decision");
        assertEquals("summary", a.path("calls").get(0).path("purpose").asText(), "newest first");
        assertEquals("aityx answered 500: boom", a.path("calls").get(1).path("error").asText());

        given().when().get("/api/aityx?days=1").then().statusCode(200).body("totals.calls", is(4)).body("days", is(1));
        given().when().get("/api/aityx?days=99").then().statusCode(200).body("days", is(30));
    }

    @Test
    void keepsTheLatestCallsOfEachBucket() throws Exception {
        long profileId = given().when().get("/api/me").then().extract().jsonPath().getLong("profileId");
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            // A full profile's worth, and a few services', all older than now.
            s.execute("""
                insert into aityx_call (id, profile_id, caller, service, called_at, millis, status, personalized,
                  request_truncated, response_truncated)
                select -g, %d, 'local', false, now() - g * interval '1 minute', 5, 200, false, false, false
                from generate_series(1, %d) g""".formatted(profileId, AityxCall.KEEP));
            s.execute("""
                insert into aityx_call (id, profile_id, caller, service, called_at, millis, status, personalized,
                  request_truncated, response_truncated)
                select -100000 - g, null, 'HealthHub', true, now() - g * interval '1 minute', 5, 200, false, false, false
                from generate_series(1, 5) g""");
        }
        assertEquals(200, post(BODY, null).statusCode());
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            ResultSet r = s.executeQuery("select count(*), min(id) from aityx_call where profile_id = " + profileId);
            r.next();
            assertEquals(AityxCall.KEEP, r.getInt(1), "the latest 2,000 kept");
            assertEquals(-(AityxCall.KEEP - 1), r.getLong(2), "the oldest gone");
            r = s.executeQuery("select count(*) from aityx_call where profile_id is null");
            r.next();
            assertEquals(5, r.getInt(1), "the services' untouched");
        }
        long deleted = QuarkusTransaction.requiringNew().call(() -> AityxCall.trim(null, 3));
        assertEquals(2, deleted);
        try (Connection c = dataSource.getConnection(); Statement s = c.createStatement()) {
            ResultSet r = s.executeQuery("select array_agg(id order by id) from aityx_call where profile_id is null");
            r.next();
            assertArrayEquals(new Long[] {-100003L, -100002L, -100001L}, (Long[]) r.getArray(1).getArray());
        }
    }

    @Test
    void aityxUnreachedIsA502OrA504() throws Exception {
        AityxGateway nowhere = new AityxGateway(java.util.Optional.of(KEY), java.util.Optional.of("http://127.0.0.1:1"),
            java.time.Duration.ofSeconds(5));
        AityxGateway.Unreached e = org.junit.jupiter.api.Assertions.assertThrows(AityxGateway.Unreached.class,
            () -> nowhere.post("{}".getBytes(StandardCharsets.UTF_8)));
        assertEquals(502, e.status);
        assertEquals("aityx can't be reached", e.getMessage());

        AityxStub.next(aityx, 200, AityxStub.DEFAULT_ANSWER, "test", 3_000);
        AityxGateway slow = new AityxGateway(java.util.Optional.of(KEY), java.util.Optional.of(aityx), java.time.Duration.ofSeconds(1));
        e = org.junit.jupiter.api.Assertions.assertThrows(AityxGateway.Unreached.class,
            () -> slow.post("{}".getBytes(StandardCharsets.UTF_8)));
        assertEquals(504, e.status);
        assertEquals("aityx didn't answer within 1 s", e.getMessage());
        assertFalse(e.getMessage().contains(KEY));
        assertEquals("a [redacted] b", slow.redact("a " + KEY + " b"));
        assertFalse(new AityxGateway(java.util.Optional.of(" "), java.util.Optional.empty(), java.time.Duration.ofSeconds(1)).configured());
    }

    @Test
    void namesAndPurposesAreCleaned() {
        assertEquals("HealthHub", AityxResource.serviceName(null));
        assertEquals("HealthHub", AityxResource.serviceName("<>!"));
        assertEquals("Ward 7_a.b-c", AityxResource.serviceName(" Ward 7_a.b-c\r\n"));
        assertEquals(64, AityxResource.serviceName("x".repeat(100)).length());
        assertNull(AityxResource.clip(" \t", 64));
        assertEquals("triage", AityxResource.clip("tri\u0000age", 64));
        assertTrue(new AityxCall.Row(1L, null, null, true, null, Instant.now(), 1, 503, null, null, null, null, null, null, null, false).failed());
        AityxCall shared = new AityxCall();
        assertTrue(shared.seenBy(7, true));
        assertFalse(shared.seenBy(7, false));
        shared.profileId = 7L;
        assertTrue(shared.seenBy(7, false));
        assertFalse(shared.seenBy(8, true));
    }
}
