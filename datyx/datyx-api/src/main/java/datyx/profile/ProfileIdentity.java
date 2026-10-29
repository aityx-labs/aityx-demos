package datyx.profile;

import java.time.Instant;
import java.util.Optional;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * An identity of a profile (table profile_identity): who an issuer says
 * is calling, its subject (a Google account's id, stable whatever the
 * email), unique per issuer, with the claims last seen (email, name,
 * picture). Without authentication every call is the local identity,
 * issuer "local", subject "anonymous".
 */
@Entity
@Table(name = "profile_identity")
public class ProfileIdentity extends PanacheEntity {

    public static final String LOCAL_ISSUER = "local";
    public static final String LOCAL_SUBJECT = "anonymous";

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "profile_id")
    public Profile profile;

    @Column(nullable = false, length = 500)
    public String issuer;

    @Column(nullable = false, length = 500)
    public String subject;

    @Column(length = 320)
    public String email;

    @Column(length = 200)
    public String name;

    @Column(length = 1000)
    public String picture;

    @Column(name = "added_at", nullable = false)
    public Instant addedAt;

    @Column(name = "last_seen_at", nullable = false)
    public Instant lastSeenAt;

    public static Optional<ProfileIdentity> find(String issuer, String subject) {
        return find("issuer = ?1 and subject = ?2", issuer, subject).firstResultOptional();
    }
}
