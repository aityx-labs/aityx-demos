package db.devdata;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.crypto.Crypto;
import datyx.datasource.AccessCodec;
import datyx.datasource.DataSource.Access;
import datyx.datasource.DevData;
import datyx.profile.ProfileIdentity;
import org.eclipse.microprofile.config.ConfigProvider;
import org.flywaydb.core.api.migration.BaseJavaMigration;
import org.flywaydb.core.api.migration.Context;
import org.jboss.logging.Logger;

/**
 * Development data, dev mode only (db/devdata is a Flyway location in the
 * dev profile alone): HealthHub as two data sources ({@link DevData}), its
 * PostgreSQL named HealthHub and its Kafka named HealthHub Kafka, each in
 * every profile that has none of that name, the local profile included
 * (made here when missing, so authentication off has them too). A profile
 * made after this ran gets them when it is made (ProfileMaker). The
 * details are HealthHub's development ones, at the addresses the
 * configuration gives (localhost:9803 and localhost:9804 on a laptop).
 * Encrypted as the API stores them (AccessCodec), with the same master
 * key. A repeatable migration: it runs again when {@link #VERSION}
 * changes, and then seeds the profiles without them. A profile whose key
 * another master key wrapped is skipped with a warning.
 */
public class R__HealthHub_data_source extends BaseJavaMigration {

    /** Bump to run the seed again (the migration's checksum). */
    static final int VERSION = 2;

    private static final Logger LOG = Logger.getLogger(R__HealthHub_data_source.class);

    @Override
    public Integer getChecksum() {
        return VERSION;
    }

    @Override
    public String getDescription() {
        // Unchanged since the seed had one source: Flyway knows the migration by it.
        return "HealthHub data source";
    }

    @Override
    public void migrate(Context context) throws Exception {
        Connection c = context.getConnection();
        Crypto crypto = new Crypto(ConfigProvider.getConfig().getOptionalValue("datyx.master-key", String.class));
        ObjectMapper json = new ObjectMapper();
        Instant now = Instant.now();
        ensureLocalProfile(c, crypto, now);
        for (DevData.Seed seed : DevData.healthHub(ConfigProvider.getConfig())) {
            seed(c, crypto, json, now, seed.name(), seed.type().name(), seed.description(), seed.access());
        }
    }

    /** A data source of this name, type and details, in every profile without one of the name. */
    private static void seed(Connection c, Crypto crypto, ObjectMapper json, Instant now, String name, String type,
            String description, Access access) throws Exception {
        int seeded = 0;
        for (long[] profile : profilesWithout(c, name)) {
            long id = profile[0];
            byte[] wrappedKey = wrappedKey(c, id);
            byte[] sealed;
            try {
                sealed = AccessCodec.seal(crypto, json, id, wrappedKey, access);
            } catch (IllegalStateException e) {
                // A key wrapped by another master key (the development one,
                // before DATYX_MASTER_KEY was set): not this seed's to fix.
                LOG.warnf("dev data: profile %d skipped, its key can't be read with this master key", id);
                continue;
            }
            try (PreparedStatement s = c.prepareStatement("""
                insert into data_source (id, profile_id, name, type, description, created_at, created_by, created_by_name, access)
                values (nextval('data_source_seq'), ?, ?, ?, ?, ?, null, ?, ?)""")) {
                s.setLong(1, id);
                s.setString(2, name);
                s.setString(3, type);
                s.setString(4, description);
                s.setTimestamp(5, Timestamp.from(now));
                s.setString(6, DevData.CREATED_BY_NAME);
                s.setBytes(7, sealed);
                s.executeUpdate();
            }
            seeded++;
        }
        LOG.infof("dev data: the %s data source added to %d profile(s)", name, seeded);
    }

    /** The local profile (issuer local, subject anonymous), as Profiles makes it, when there is none yet. */
    private static void ensureLocalProfile(Connection c, Crypto crypto, Instant now) throws Exception {
        try (PreparedStatement s = c.prepareStatement("select 1 from profile_identity where issuer = ? and subject = ?")) {
            s.setString(1, ProfileIdentity.LOCAL_ISSUER);
            s.setString(2, ProfileIdentity.LOCAL_SUBJECT);
            try (ResultSet r = s.executeQuery()) {
                if (r.next()) {
                    return;
                }
            }
        }
        long id;
        try (PreparedStatement s = c.prepareStatement(
                "insert into profile (id, name, created_at, key_wrapped) values (nextval('profile_seq'), 'Local', ?, ?) returning id")) {
            s.setTimestamp(1, Timestamp.from(now));
            s.setBytes(2, crypto.newWrappedKey());
            try (ResultSet r = s.executeQuery()) {
                r.next();
                id = r.getLong(1);
            }
        }
        try (PreparedStatement s = c.prepareStatement("""
                insert into profile_identity (id, profile_id, issuer, subject, added_at, last_seen_at)
                values (nextval('profile_identity_seq'), ?, ?, ?, ?, ?)""")) {
            s.setLong(1, id);
            s.setString(2, ProfileIdentity.LOCAL_ISSUER);
            s.setString(3, ProfileIdentity.LOCAL_SUBJECT);
            s.setTimestamp(4, Timestamp.from(now));
            s.setTimestamp(5, Timestamp.from(now));
            s.executeUpdate();
        }
    }

    /** The ids of the profiles with no data source of this name. */
    private static List<long[]> profilesWithout(Connection c, String name) throws Exception {
        List<long[]> ids = new ArrayList<>();
        try (PreparedStatement s = c.prepareStatement(
                "select p.id from profile p where not exists (select 1 from data_source d where d.profile_id = p.id and lower(d.name) = lower(?)) order by p.id")) {
            s.setString(1, name);
            try (ResultSet r = s.executeQuery()) {
                while (r.next()) {
                    ids.add(new long[] {r.getLong(1)});
                }
            }
        }
        return ids;
    }

    private static byte[] wrappedKey(Connection c, long profileId) throws Exception {
        try (PreparedStatement s = c.prepareStatement("select key_wrapped from profile where id = ?")) {
            s.setLong(1, profileId);
            try (ResultSet r = s.executeQuery()) {
                r.next();
                return r.getBytes(1);
            }
        }
    }
}
