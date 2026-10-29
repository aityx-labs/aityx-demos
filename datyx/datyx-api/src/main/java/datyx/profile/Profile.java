package datyx.profile;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import io.quarkus.hibernate.orm.panache.PanacheEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.OneToMany;
import jakarta.persistence.OrderBy;
import jakarta.persistence.Table;

/**
 * A profile (table profile): the person behind a sign-in, and the owner
 * of what they add (their data sources). Made the first time one of its
 * identities calls the API, with an encryption key of its own, stored
 * wrapped by the server's master key (datyx.crypto.Crypto): the key that
 * encrypts the profile's records. Several identities can belong to one
 * profile, so a profile is not bound to one email; sharing a profile
 * between people is for later.
 */
@Entity
@Table(name = "profile")
public class Profile extends PanacheEntity {

    /** A display name, the first identity's name or email. */
    @Column(length = 200)
    public String name;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    /** The profile's key, encrypted by the master key; never answered. */
    @Column(name = "key_wrapped", nullable = false)
    public byte[] keyWrapped;

    @OneToMany(mappedBy = "profile")
    @OrderBy("addedAt asc, id asc")
    public List<ProfileIdentity> identities = new ArrayList<>();
}
