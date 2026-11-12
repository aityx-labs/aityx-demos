package datyx.profile;

import java.time.Instant;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.auth.CurrentUser;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource;
import datyx.datasource.DevData;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import org.eclipse.microprofile.config.Config;

/**
 * Creates a profile and its first identity, in a transaction of its own
 * (see Profiles). In dev mode the profile is made with the development
 * data ({@link DevData}): HealthHub's two data sources, as the profiles
 * there at start have them from the Flyway migration (db.devdata), so
 * whoever signs in has them to see, and the dev catalogue and the trainer
 * pick them up (DevCatalog, Training).
 */
@ApplicationScoped
public class ProfileMaker {

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @Inject
    Config config;

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
        if (DevData.enabled(config)) {
            for (DevData.Seed seed : DevData.healthHub(config)) {
                DataSource source = new DataSource();
                source.profile = profile;
                source.name = seed.name();
                source.type = seed.type();
                source.description = seed.description();
                source.createdAt = now;
                source.createdByName = DevData.CREATED_BY_NAME;
                source.access = AccessCodec.seal(crypto, json, profile.id, profile.keyWrapped, seed.access());
                source.persist();
            }
        }
        ProfileIdentity.flush();
    }
}
