package datyx.catalog;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import datyx.datasource.DataSource;
import datyx.openmetadata.OpenMetadataClient;
import datyx.openmetadata.OpenMetadataSession;
import datyx.training.Training;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.scheduler.Scheduled;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.ProcessingException;
import jakarta.ws.rs.WebApplicationException;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.jboss.logging.Logger;

/**
 * OpenMetadata telling datyx when a table changes, so switching a group on
 * trains it at once. datyx keeps an event subscription in OpenMetadata
 * ({@code datyx.openmetadata.subscription-name}, datyx-catalog-events): a
 * webhook posting each update of a table to datyx's
 * POST /api/catalog/openmetadata-events, at
 * {@code datyx.openmetadata.callback-url} (none: no subscription, the
 * trainer's minute check alone). It is made, or brought back to what datyx
 * wants, a few seconds after start and at every minute's look while
 * OpenMetadata can't be reached or the subscription isn't there.
 *
 * OpenMetadata signs each post with the subscription's secret: its
 * X-OM-Signature header is sha256= and the base64 of the HMAC-SHA256 of the
 * body. The secret is {@code datyx.openmetadata.webhook-secret}, or one
 * datyx draws at start (and gives OpenMetadata then). A post without the
 * right signature changes nothing.
 *
 * A post is OpenMetadata's change event: a table of one of datyx's
 * database sources (its service datyx-ds-{id}) whose tags lost a group's
 * Disabled tag switched the group on, one that gained it switched it off.
 * Each is kept, and a switch on queues the group's runs, one per
 * algorithm (Training.switched), the group read again from OpenMetadata
 * (from the post when OpenMetadata can't be read).
 */
@ApplicationScoped
public class CatalogEvents {

    private static final Logger LOG = Logger.getLogger(CatalogEvents.class);

    /** The header OpenMetadata signs a webhook's post in. */
    public static final String SIGNATURE_HEADER = "X-OM-Signature";

    private static final String SIGNATURE_PREFIX = "sha256=";

    private static final Pattern SERVICE = Pattern.compile("datyx-ds-(\\d{1,18})");

    @Inject
    @RestClient
    OpenMetadataClient client;

    @Inject
    OpenMetadataSession session;

    @Inject
    ObjectMapper json;

    @Inject
    Catalog catalog;

    @Inject
    Training training;

    @ConfigProperty(name = "datyx.openmetadata.callback-url")
    Optional<String> callbackUrl;

    @ConfigProperty(name = "datyx.openmetadata.webhook-secret")
    Optional<String> configuredSecret;

    @ConfigProperty(name = "datyx.openmetadata.subscription-name", defaultValue = "datyx-catalog-events")
    String subscriptionName;

    private byte[] secret;

    private volatile boolean subscribed;

    private volatile boolean warned;

    @PostConstruct
    void init() {
        String configured = configuredSecret.map(String::strip).filter(s -> !s.isEmpty()).orElse(null);
        if (configured != null) {
            secret = configured.getBytes(StandardCharsets.UTF_8);
        } else {
            byte[] random = new byte[32];
            new SecureRandom().nextBytes(random);
            secret = Base64.getUrlEncoder().withoutPadding().encodeToString(random).getBytes(StandardCharsets.UTF_8);
        }
    }

    /** The URL OpenMetadata posts to, or null when datyx asks for no posts. */
    String callback() {
        return callbackUrl.map(String::strip).filter(s -> !s.isEmpty()).orElse(null);
    }

    /** Whether the subscription is made, as far as datyx knows. */
    public boolean subscribed() {
        return subscribed;
    }

    /**
     * Makes the subscription, or makes it again when it is gone or posts
     * elsewhere; nothing without a callback URL. OpenMetadata unreachable:
     * tried again at the next look.
     */
    @Scheduled(every = "${datyx.training.check-every:60s}", delayed = "${datyx.openmetadata.subscribe-after:3s}",
        concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void ensureSubscribed() {
        String url = callback();
        if (url == null) {
            return;
        }
        try {
            if (subscribed) {
                try {
                    JsonNode found = session.call(auth -> client.eventSubscription(auth, subscriptionName));
                    if (found.path("enabled").asBoolean(true)
                            && url.equals(found.path("destinations").path(0).path("config").path("endpoint").asText())) {
                        return;
                    }
                } catch (WebApplicationException e) {
                    if (e.getResponse().getStatus() != 404) {
                        throw e;
                    }
                }
            }
            session.call(auth -> client.putEventSubscription(auth, subscriptionBody(subscriptionName, url, secret)));
            subscribed = true;
            warned = false;
            LOG.infof("catalog: OpenMetadata's event subscription %s posts tables' changes to %s", subscriptionName, url);
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            subscribed = false;
            String reason = e instanceof WebApplicationException w ? "answered " + w.getResponse().getStatus() : e.getMessage();
            if (!warned) {
                LOG.warnf("catalog: OpenMetadata's event subscription %s can't be made (%s): the minute's check alone "
                    + "sees groups switched on until it is; trying again each minute", subscriptionName, reason);
                warned = true;
            } else {
                LOG.debugf("catalog: event subscription %s still can't be made: %s", subscriptionName, reason);
            }
        }
    }

    /**
     * OpenMetadata's create request of the subscription: a Notification
     * alert on tables' updates (OpenMetadata 2.0 filters a table's events by
     * type, not by field: datyx reads the tags of each), posted to
     * {@code url} by a webhook signing with {@code secret}.
     */
    ObjectNode subscriptionBody(String name, String url, byte[] secret) {
        ObjectNode body = json.createObjectNode()
            .put("name", name)
            .put("displayName", "datyx: tables switched on and off")
            .put("description", "datyx's: tells datyx when a table of its sources changes, so a group switched on "
                + "(its TimeSeries Disabled tag removed) trains at once. Made by datyx; it makes it again when gone.")
            .put("alertType", "Notification")
            .put("enabled", true)
            .put("batchSize", 10)
            .put("retries", 3)
            .put("pollInterval", 5);
        body.putArray("resources").add("table");
        ObjectNode filter = body.putObject("input").putArray("filters").addObject()
            .put("name", "filterByEventType")
            .put("effect", "include")
            .put("prefixCondition", "AND");
        filter.putArray("arguments").addObject().put("name", "eventTypeList").putArray("input").add("entityUpdated");
        ((ObjectNode) body.path("input")).putArray("actions");
        ObjectNode destination = body.putArray("destinations").addObject()
            .put("category", "External")
            .put("type", "Webhook")
            .put("timeout", 10)
            .put("readTimeout", 12);
        ObjectNode config = destination.putObject("config")
            .put("endpoint", url)
            .put("httpMethod", "POST");
        config.putObject("authType")
            .put("type", "bearer")
            .put("secretKey", new String(secret, StandardCharsets.UTF_8));
        return body;
    }

    /** Whether {@code signature} (X-OM-Signature) is OpenMetadata's for {@code body}, compared in constant time. */
    public boolean verify(byte[] body, String signature) {
        return verify(secret, body, signature);
    }

    static boolean verify(byte[] secret, byte[] body, String signature) {
        if (signature == null || !signature.strip().startsWith(SIGNATURE_PREFIX)) {
            return false;
        }
        byte[] given = signature.strip().substring(SIGNATURE_PREFIX.length()).getBytes(StandardCharsets.US_ASCII);
        byte[] expected = Base64.getEncoder().encode(hmac(secret, body));
        return MessageDigest.isEqual(expected, given);
    }

    /** The signature OpenMetadata sends for {@code body}: sha256= and the base64 of its HMAC-SHA256. */
    public static String sign(byte[] secret, byte[] body) {
        return SIGNATURE_PREFIX + Base64.getEncoder().encodeToString(hmac(secret, body));
    }

    private static byte[] hmac(byte[] secret, byte[] body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret, "HmacSHA256"));
            return mac.doFinal(body);
        } catch (NoSuchAlgorithmException | InvalidKeyException e) {
            throw new IllegalStateException("HmacSHA256 isn't available", e);
        }
    }

    /**
     * A group switched in OpenMetadata, as one change event says it: the
     * source, the table, the group, on or off, the table's version after it,
     * who and when, the event's id, and the table as the event carries it.
     */
    public record TagSwitch(long sourceId, String table, String group, boolean enabled, String version, String by, Instant at,
            String eventId, JsonNode entity) {
    }

    /**
     * The groups one of OpenMetadata's change events switched: a table of a
     * datyx source (service datyx-ds-{id}, exactly as datyx names it, the
     * table's FQN under it) whose own tags (not a column's)
     * lost a group's Disabled tag (on) or gained it (off). None for another
     * entity, another service, or other tags.
     */
    List<TagSwitch> switches(JsonNode event) {
        List<TagSwitch> switches = new ArrayList<>();
        if (!"table".equals(event.path("entityType").asText())) {
            return switches;
        }
        JsonNode entity = event.path("entity");
        if (entity.isTextual()) {
            try {
                entity = json.readTree(entity.asText());
            } catch (IOException e) {
                entity = json.missingNode();
            }
        }
        String table = event.path("entityFullyQualifiedName").asText(entity.path("fullyQualifiedName").asText(""));
        String service = entity.path("service").path("name").asText(null);
        if (service == null) {
            service = table.contains(".") ? table.substring(0, table.indexOf('.')) : table;
        }
        Matcher matcher = SERVICE.matcher(service);
        if (table.isEmpty() || !matcher.matches()) {
            return switches;
        }
        long sourceId = Long.parseLong(matcher.group(1));
        if (!service.equals(Catalog.serviceName(sourceId)) || !table.startsWith(service + ".")) {
            // datyx-ds-07 isn't source 7's service (datyx-ds-7), and the table must be its service's.
            return switches;
        }
        Set<String> removed = new LinkedHashSet<>();
        Set<String> added = new LinkedHashSet<>();
        JsonNode change = event.path("changeDescription");
        for (JsonNode field : change.path("fieldsAdded")) {
            if ("tags".equals(field.path("name").asText())) {
                added.addAll(tagFqns(field.path("newValue")));
            }
        }
        for (JsonNode field : change.path("fieldsDeleted")) {
            if ("tags".equals(field.path("name").asText())) {
                removed.addAll(tagFqns(field.path("oldValue")));
            }
        }
        for (JsonNode field : change.path("fieldsUpdated")) {
            if ("tags".equals(field.path("name").asText())) {
                Set<String> before = tagFqns(field.path("oldValue"));
                Set<String> after = tagFqns(field.path("newValue"));
                for (String tag : before) {
                    if (!after.contains(tag)) {
                        removed.add(tag);
                    }
                }
                for (String tag : after) {
                    if (!before.contains(tag)) {
                        added.add(tag);
                    }
                }
            }
        }
        Map<String, Boolean> groups = new LinkedHashMap<>();
        for (String tag : removed) {
            String group = TimeSeries.disabledGroupOf(tag);
            if (group != null && !added.contains(tag)) {
                groups.put(group, true);
            }
        }
        for (String tag : added) {
            String group = TimeSeries.disabledGroupOf(tag);
            if (group != null && !removed.contains(tag)) {
                groups.put(group, false);
            }
        }
        String version = event.has("currentVersion") ? event.path("currentVersion").asText()
            : entity.path("version").asText(null);
        String by = event.path("userName").asText(entity.path("updatedBy").asText(null));
        long millis = event.path("timestamp").asLong(entity.path("updatedAt").asLong(0));
        Instant at = millis > 0 ? Instant.ofEpochMilli(millis) : Instant.now();
        String eventId = event.path("id").asText(null);
        JsonNode carried = entity.isObject() ? entity : null;
        groups.forEach((group, enabled) -> switches.add(new TagSwitch(sourceId, table, group, enabled, version, by, at,
            eventId == null ? null : eventId + ":" + group, carried)));
        return switches;
    }

    /** A change's value, tag labels as JSON or as its text: their tagFQNs. */
    private Set<String> tagFqns(JsonNode value) {
        Set<String> fqns = new LinkedHashSet<>();
        JsonNode labels = value;
        if (value.isTextual()) {
            try {
                labels = json.readTree(value.asText());
            } catch (IOException e) {
                return fqns;
            }
        }
        if (labels.isObject()) {
            labels = json.createArrayNode().add(labels);
        }
        for (JsonNode label : labels) {
            String fqn = label.path("tagFQN").asText(null);
            if (fqn != null) {
                fqns.add(fqn);
            }
        }
        return fqns;
    }

    /**
     * Keeps the switches of OpenMetadata's post (one change event, or an
     * array of them) and queues the runs of each switch on: what was kept,
     * each GroupEvent's id and its runs. A source datyx doesn't have, or
     * that isn't a database, is passed over; so is a group the table, read
     * again, no longer has (removing a group's roles removes its Disabled
     * tag: no switch on).
     */
    public List<Training.Recorded> receive(JsonNode post) {
        List<Training.Recorded> recorded = new ArrayList<>();
        List<JsonNode> events = new ArrayList<>();
        if (post.isArray()) {
            post.forEach(events::add);
        } else {
            events.add(post);
        }
        for (JsonNode event : events) {
            for (TagSwitch s : switches(event)) {
                boolean known = QuarkusTransaction.requiringNew().call(() -> DataSource.<DataSource>findByIdOptional(s.sourceId())
                    .filter(source -> source.type == DataSource.Type.DATABASE).isPresent());
                if (!known) {
                    LOG.debugf("catalog: OpenMetadata's event for %s: no database data source %d", s.table(), s.sourceId());
                    continue;
                }
                JsonNode table = tableOf(s);
                if (table == null && s.enabled()) {
                    LOG.infof("catalog: %s group %s switched on, but the table can't be read: the minute's check queues it",
                        s.table(), s.group());
                    continue;
                }
                if (table != null && !TimeSeries.groups(table).contains(s.group())) {
                    // The group was removed: its Disabled tag went with its roles and algorithms. No switch.
                    LOG.debugf("catalog: %s has no group %s now: its Disabled tag's change switches nothing", s.table(), s.group());
                    continue;
                }
                TimeSeries.Spec spec = table == null ? null : TimeSeries.spec(table, s.group());
                String note = TimeSeries.disabledFqn(s.group()) + (s.enabled() ? " removed" : " added") + " in OpenMetadata ("
                    + new Catalog.Change(s.version(), s.by(), s.at()).describe() + "; webhook)";
                training.switched(new Training.Switch(s.sourceId(), s.table(), s.group(), s.enabled(), GroupEvent.VIA_WEBHOOK,
                    s.version(), s.by(), s.at(), s.eventId()), spec, s.at(), note).ifPresent(recorded::add);
            }
        }
        return recorded;
    }

    /** The switch's table, read again from OpenMetadata; as the event carries it when it can't be read; null without either. */
    private JsonNode tableOf(TagSwitch s) {
        try {
            return catalog.table(s.table());
        } catch (WebApplicationException | ProcessingException | IllegalStateException e) {
            LOG.debugf("catalog: %s can't be read again (%s): the event's table", s.table(), e.getMessage());
            return s.entity();
        }
    }
}
