package datyx.aityx;

import java.time.Instant;
import java.util.List;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Parameters;
import io.quarkus.panache.common.Sort;
import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;

/**
 * One call the gateway passed on to aityx (table aityx_call): whose (a
 * profile's, or null for a service's), who (the user's email or subject,
 * or the service's name) and why (the purpose), when, how long, aityx's
 * status and mode, what was asked (model, decision, questions), the input
 * tokens and their cost, a short error, and the request sent and answer
 * received, each truncated to {@link #MAX_BODY} bytes. Never a header.
 */
@Entity
@Table(name = "aityx_call")
public class AityxCall extends PanacheEntity {

    /** aityx's price, in US dollars per million input tokens. */
    public static final double USD_PER_MILLION_INPUT_TOKENS = 0.042;

    /** The most of a request or an answer kept, in bytes. */
    public static final int MAX_BODY = 64 * 1024;

    /** The calls kept per profile, and for the services. */
    public static final int KEEP = 2_000;

    /** Null for a service's call: the services' bucket. */
    @Column(name = "profile_id")
    public Long profileId;

    @Column(length = 320)
    public String caller;

    @Column(nullable = false)
    public boolean service;

    @Column(length = 64)
    public String purpose;

    @Column(name = "called_at", nullable = false)
    public Instant calledAt;

    @Column(nullable = false)
    public int millis;

    /** aityx's HTTP status, or the gateway's when aityx wasn't reached (502, 504). */
    @Column(nullable = false)
    public int status;

    @Column(length = 64)
    public String mode;

    @Column(length = 200)
    public String model;

    @Column(length = 500)
    public String decision;

    public Integer questions;

    @Column(name = "input_tokens")
    public Long inputTokens;

    @Column(name = "cost_usd")
    public Double costUsd;

    @Column(length = 500)
    public String error;

    @Column(nullable = false)
    public boolean personalized;

    @Column(columnDefinition = "text")
    public String request;

    @Column(name = "request_truncated", nullable = false)
    public boolean requestTruncated;

    @Column(columnDefinition = "text")
    public String response;

    @Column(name = "response_truncated", nullable = false)
    public boolean responseTruncated;

    /** A call without its bodies, as the account reads it. */
    @RegisterForReflection
    public record Row(Long id, Long profileId, String caller, boolean service, String purpose, Instant calledAt, int millis,
            int status, String mode, String model, String decision, Integer questions, Long inputTokens, Double costUsd,
            String error, boolean personalized) {

        public boolean failed() {
            return status < 200 || status > 299;
        }
    }

    /** The cost of so many input tokens, in US dollars; null without a count. */
    public static Double cost(Long inputTokens) {
        return inputTokens == null ? null : Math.round(inputTokens * USD_PER_MILLION_INPUT_TOKENS * 1_000_000) / 1e12;
    }

    /** The calls a profile sees (its own, and the services' when shared) since {@code since}, newest first, without bodies. */
    public static List<Row> since(long profileId, boolean shared, Instant since) {
        return find((shared ? "(profileId = :p or profileId is null)" : "profileId = :p") + " and calledAt >= :since",
            Sort.descending("calledAt", "id"), Parameters.with("p", profileId).and("since", since))
            .project(Row.class).list();
    }

    /** Whether a profile sees this call. */
    public boolean seenBy(long profileId, boolean shared) {
        return this.profileId == null ? shared : this.profileId == profileId;
    }

    /** Deletes all but the latest {@code keep} calls of a profile, or of the services (null). */
    public static long trim(Long profileId, int keep) {
        String bucket = profileId == null ? "profile_id is null" : "profile_id = :p";
        var query = getEntityManager().createNativeQuery("delete from aityx_call where " + bucket
            + " and id not in (select id from aityx_call where " + bucket + " order by called_at desc, id desc limit :keep)");
        if (profileId != null) {
            query.setParameter("p", profileId);
        }
        return query.setParameter("keep", keep).executeUpdate();
    }
}
