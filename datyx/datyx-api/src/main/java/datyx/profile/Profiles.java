package datyx.profile;

import java.time.Instant;
import java.util.Objects;
import java.util.Optional;

import datyx.auth.CurrentUser;
import datyx.db.UniqueViolation;
import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * The profile of the current call: found by the identity the token
 * carries (its issuer and subject), made on the first call of an identity
 * the API has not seen, with a new key (Crypto), and the identity's
 * claims kept current. Request-scoped: resolved once per call. The
 * secured resources call {@link #current()} inside their transaction.
 */
@RequestScoped
public class Profiles {

    private static final Logger LOG = Logger.getLogger(Profiles.class);

    @Inject
    CurrentUser user;

    @Inject
    ProfileMaker maker;

    @ConfigProperty(name = "datyx.oidc.issuer")
    String configuredIssuer;

    private Profile profile;

    /** The caller's profile, created on their first call. */
    @Transactional
    public Profile current() {
        if (profile == null) {
            profile = resolve();
        }
        return profile;
    }

    private Profile resolve() {
        String issuer = user.authenticated() ? Objects.requireNonNullElse(user.issuer(), configuredIssuer) : ProfileIdentity.LOCAL_ISSUER;
        String subject = user.authenticated() ? user.subject() : ProfileIdentity.LOCAL_SUBJECT;
        Optional<ProfileIdentity> found = ProfileIdentity.find(issuer, subject);
        if (found.isEmpty()) {
            // In a transaction of its own: a lost race (the same identity's
            // first two calls at once) rolls back only that one, and the
            // winner's row is found below.
            try {
                maker.create(issuer, subject, user);
            } catch (RuntimeException e) {
                if (!UniqueViolation.in(e)) {
                    throw e;
                }
                LOG.debugf("profile for %s/%s created concurrently: %s", issuer, subject, e.getMessage());
            }
            found = ProfileIdentity.find(issuer, subject);
        }
        ProfileIdentity identity = found.orElseThrow(() -> new IllegalStateException("no profile for " + issuer + "/" + subject));
        touch(identity);
        return identity.profile;
    }

    /** Keeps the claims last seen, and when they were. */
    private void touch(ProfileIdentity identity) {
        identity.lastSeenAt = Instant.now();
        if (user.authenticated()) {
            identity.email = user.email();
            identity.name = user.name();
            identity.picture = user.picture();
        }
    }
}
