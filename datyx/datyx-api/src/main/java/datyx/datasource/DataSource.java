package datyx.datasource;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonValue;
import datyx.profile.Profile;
import io.quarkus.hibernate.orm.panache.PanacheEntity;
import io.quarkus.panache.common.Sort;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

/**
 * A data source on record (table data_source): where data lives and how
 * to reach it, owned by a profile. One of three kinds so far, each with
 * its own access details: a database, an S3 bucket, or a filesystem
 * folder. The details ({@link Access}: hosts, names, users, passwords,
 * keys, paths) are one JSON document encrypted with the owning profile's
 * key (datyx.crypto.Crypto), the {@code access} column: nothing of them
 * is in clear in the database, and only the API decrypts them. Secrets
 * (a database password, an S3 secret key) are never answered back (see
 * DataSourceResource). The name is unique within a profile whatever its
 * case: a unique index on (profile_id, lower(name)), made by the Flyway
 * migration (db/migration), which the resource turns into a 409.
 */
@Entity
@Table(name = "data_source")
public class DataSource extends PanacheEntity {

    public enum Type {
        DATABASE, S3, FILESYSTEM;

        /** JSON: "database", "s3", "filesystem". */
        @JsonValue
        public String json() {
            return name().toLowerCase();
        }

        @JsonCreator
        public static Type fromJson(String value) {
            return value == null ? null : valueOf(value.trim().toUpperCase());
        }
    }

    @ManyToOne(optional = false, fetch = FetchType.LAZY)
    @JoinColumn(name = "profile_id")
    public Profile profile;

    @Column(nullable = false, length = 100)
    public String name;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    public Type type;

    @Column(length = 500)
    public String description;

    @Column(name = "created_at", nullable = false)
    public Instant createdAt;

    /** Who added it: the email of the signed-in identity, else its subject; null while authentication is off. */
    @Column(name = "created_by", length = 320)
    public String createdBy;

    @Column(name = "created_by_name", length = 200)
    public String createdByName;

    /** The access details, encrypted: see {@link Access} and DataSourceResource. */
    @Column(nullable = false)
    public byte[] access;

    /** A profile's sources, the newest first, at most {@code limit}. */
    public static List<DataSource> newest(Profile profile, int limit) {
        return find("profile = ?1", Sort.descending("createdAt", "id"), profile).page(0, limit).list();
    }

    /** A profile's source by id: empty when there is none, or it is another profile's. */
    public static Optional<DataSource> of(Profile profile, long id) {
        return find("id = ?1 and profile = ?2", id, profile).firstResultOptional();
    }

    public static long countOf(Profile profile) {
        return count("profile", profile);
    }

    /** The details of a source, the group of its type set: what the access column holds, encrypted. */
    @JsonInclude(JsonInclude.Include.NON_NULL)
    public record Access(DatabaseAccess database, S3Access s3, FilesystemAccess filesystem) {
    }

    /** A database: engine (postgresql, mysql, ...), host and port, the database, a user and its password. */
    public record DatabaseAccess(String engine, String host, Integer port, String database, String username, String password) {
    }

    /** An S3 bucket: the bucket and region, an endpoint for S3-compatible stores, a prefix, a key pair. */
    public record S3Access(String bucket, String region, String endpoint, String prefix, String accessKeyId, String secretAccessKey) {
    }

    /** A folder the API can reach. */
    public record FilesystemAccess(String path) {
    }
}
