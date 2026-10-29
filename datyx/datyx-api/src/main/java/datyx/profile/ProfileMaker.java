package datyx.profile;

import java.time.Instant;

import datyx.auth.CurrentUser;
import datyx.crypto.Crypto;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;

/** Creates a profile and its first identity, in a transaction of its own (see Profiles). */
@ApplicationScoped
public class ProfileMaker {

    @Inject
    Crypto crypto;

    @Transactional(Transactional.TxType.REQUIRES_NEW)
    public void create(String issuer, String subject, CurrentUser user) {
        Instant now = Instant.now();
        Profile profile = new Profile();
        profile.createdAt = now;
        profile.keyWrapped = crypto.newWrappedKey();
        profile.name = user.authenticated() ? (user.name() != null ? user.name() : user.email()) : "Local";
        profile.persist();
        ProfileIdentity identity = new ProfileIdentity();
        identity.profile = profile;
        identity.issuer = issuer;
        identity.subject = subject;
        identity.email = user.authenticated() ? user.email() : null;
        identity.name = user.authenticated() ? user.name() : null;
        identity.picture = user.authenticated() ? user.picture() : null;
        identity.addedAt = now;
        identity.lastSeenAt = now;
        identity.persist();
        ProfileIdentity.flush();
    }
}
