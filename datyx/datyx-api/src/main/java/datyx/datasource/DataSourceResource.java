package datyx.datasource;

import java.net.URI;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.auth.CurrentUser;
import datyx.crypto.Crypto;
import datyx.datasource.DataSource.Access;
import datyx.datasource.DataSource.Type;
import datyx.db.UniqueViolation;
import datyx.profile.Profile;
import datyx.profile.Profiles;
import jakarta.inject.Inject;
import jakarta.persistence.PersistenceException;
import jakarta.transaction.Transactional;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.DefaultValue;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

/**
 * The data sources of the caller's profile (datyx.profile.Profiles):
 * GET /api/datasources?limit=100 lists them, newest first;
 * GET /api/datasources/{id} answers one;
 * POST /api/datasources adds one and answers 201 with it and a Location;
 * DELETE /api/datasources/{id} removes one (204).
 * Another profile's sources are not there: a 404 by id, absent from the list.
 * A body names the source, its type (database, s3, filesystem) and the
 * access details of that type, under a key of the same name:
 * {"name":"warehouse","type":"database","description":"...",
 *  "database":{"engine":"postgresql","host":"db","port":5432,"database":"dw","username":"u","password":"p"}}
 * {"name":"lake","type":"s3","s3":{"bucket":"b","region":"eu-west-1","endpoint":null,"prefix":"raw/","accessKeyId":"...","secretAccessKey":"..."}}
 * {"name":"exports","type":"filesystem","filesystem":{"path":"/data/exports"}}
 * Missing or mismatched details are a 400, a name the profile already
 * uses (whatever its case: the database's unique index decides, so a race
 * has one winner) a 409.
 * The details are stored encrypted with the profile's key (Crypto) and
 * decrypted to answer; answers carry them without their secrets:
 * passwordSet and secretAccessKeySet say whether one was given. Every
 * call needs a signed-in user once authentication is on; who added a
 * source is kept as createdBy (email) and createdByName.
 */
@Path("/api/datasources")
@Produces(MediaType.APPLICATION_JSON)
public class DataSourceResource {

    @Inject
    CurrentUser user;

    @Inject
    Profiles profiles;

    @Inject
    Crypto crypto;

    @Inject
    ObjectMapper json;

    @GET
    @Transactional
    public List<Map<String, Object>> list(@QueryParam("limit") @DefaultValue("100") int limit) {
        Profile profile = profiles.current();
        return DataSource.newest(profile, Math.clamp(limit, 1, 1000)).stream().map(this::view).toList();
    }

    @GET
    @Path("/{id}")
    @Transactional
    public Response get(@PathParam("id") long id) {
        Optional<DataSource> source = DataSource.of(profiles.current(), id);
        return source.isEmpty() ? notFound(id) : Response.ok(view(source.get())).build();
    }

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Transactional
    public Response create(@Valid NewDataSource body) {
        String problem = body.problem();
        if (problem != null) {
            return Response.status(Response.Status.BAD_REQUEST).entity(Map.of("error", problem)).build();
        }
        Profile profile = profiles.current();
        String name = body.name().strip();
        DataSource source = new DataSource();
        source.profile = profile;
        source.name = name;
        source.type = body.type();
        source.description = blankToNull(body.description());
        source.createdAt = Instant.now();
        source.createdBy = user.id();
        source.createdByName = user.name();
        source.access = seal(profile, body.access());
        source.persist();
        try {
            // Now, not at commit: a duplicate name is this call's 409, and the
            // transaction is left marked for rollback.
            DataSource.flush();
        } catch (PersistenceException e) {
            if (UniqueViolation.in(e)) {
                return Response.status(Response.Status.CONFLICT)
                    .entity(Map.of("error", "a data source named '" + name + "' already exists")).build();
            }
            throw e;
        }
        return Response.created(URI.create("/api/datasources/" + source.id)).entity(view(source)).build();
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public Response delete(@PathParam("id") long id) {
        Optional<DataSource> source = DataSource.of(profiles.current(), id);
        if (source.isEmpty()) {
            return notFound(id);
        }
        source.get().delete();
        return Response.noContent().build();
    }

    private static Response notFound(long id) {
        return Response.status(Response.Status.NOT_FOUND)
            .entity(Map.of("error", "no data source with id " + id)).build();
    }

    /** The access details as the row stores them (AccessCodec): encrypted with the profile's key, bound to the profile. */
    private byte[] seal(Profile profile, Access access) {
        return AccessCodec.seal(crypto, json, profile.id, profile.keyWrapped, access);
    }

    private Access unseal(DataSource source) {
        return AccessCodec.unseal(crypto, json, source.profile.id, source.profile.keyWrapped, source.access);
    }

    /** The JSON of a source: its fields and the details of its type, secrets replaced by whether they are set. */
    Map<String, Object> view(DataSource source) {
        Access access = unseal(source);
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("id", source.id);
        map.put("name", source.name);
        map.put("type", source.type.json());
        map.put("description", source.description);
        map.put("createdAt", source.createdAt.toString());
        map.put("createdBy", source.createdBy);
        map.put("createdByName", source.createdByName);
        switch (source.type) {
            case DATABASE -> {
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("engine", access.database().engine());
                d.put("host", access.database().host());
                d.put("port", access.database().port());
                d.put("database", access.database().database());
                d.put("username", access.database().username());
                d.put("passwordSet", access.database().password() != null);
                map.put("database", d);
            }
            case S3 -> {
                Map<String, Object> d = new LinkedHashMap<>();
                d.put("bucket", access.s3().bucket());
                d.put("region", access.s3().region());
                d.put("endpoint", access.s3().endpoint());
                d.put("prefix", access.s3().prefix());
                d.put("accessKeyId", access.s3().accessKeyId());
                d.put("secretAccessKeySet", access.s3().secretAccessKey() != null);
                map.put("s3", d);
            }
            case FILESYSTEM -> map.put("filesystem", Map.of("path", access.filesystem().path()));
        }
        return map;
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.strip();
    }

    /** POST's body. The details of the named type are required, the others must be absent. */
    public record NewDataSource(
            @NotBlank @Size(max = 100) String name,
            @NotNull Type type,
            @Size(max = 500) String description,
            @Valid DatabaseDetails database,
            @Valid S3Details s3,
            @Valid FilesystemDetails filesystem) {

        /** What is wrong with the body beyond the field constraints, or null. */
        String problem() {
            int given = (database != null ? 1 : 0) + (s3 != null ? 1 : 0) + (filesystem != null ? 1 : 0);
            String expected = type.json();
            boolean present = switch (type) {
                case DATABASE -> database != null;
                case S3 -> s3 != null;
                case FILESYSTEM -> filesystem != null;
            };
            if (!present) {
                return "a " + expected + " data source needs its '" + expected + "' details";
            }
            if (given > 1) {
                return "a " + expected + " data source takes only its '" + expected + "' details";
            }
            return null;
        }

        /** The details of the type, cleaned, as stored. */
        Access access() {
            return switch (type) {
                case DATABASE -> new Access(database.toAccess(), null, null);
                case S3 -> new Access(null, s3.toAccess(), null);
                case FILESYSTEM -> new Access(null, null, filesystem.toAccess());
            };
        }
    }

    public record DatabaseDetails(
            @NotBlank @Size(max = 40) String engine,
            @NotBlank @Size(max = 255) String host,
            @NotNull @Min(1) @Max(65535) Integer port,
            @NotBlank @Size(max = 200) String database,
            @Size(max = 200) String username,
            @Size(max = 500) String password) {

        DataSource.DatabaseAccess toAccess() {
            return new DataSource.DatabaseAccess(engine.strip().toLowerCase(), host.strip(), port, database.strip(),
                blankToNull(username), password == null || password.isEmpty() ? null : password);
        }
    }

    public record S3Details(
            @NotBlank @Size(max = 255) String bucket,
            @Size(max = 40) String region,
            @Size(max = 500) String endpoint,
            @Size(max = 1000) String prefix,
            @Size(max = 200) String accessKeyId,
            @Size(max = 500) String secretAccessKey) {

        DataSource.S3Access toAccess() {
            return new DataSource.S3Access(bucket.strip(), blankToNull(region), blankToNull(endpoint), blankToNull(prefix),
                blankToNull(accessKeyId), secretAccessKey == null || secretAccessKey.isEmpty() ? null : secretAccessKey);
        }
    }

    public record FilesystemDetails(@NotBlank @Size(max = 1000) String path) {

        DataSource.FilesystemAccess toAccess() {
            return new DataSource.FilesystemAccess(path.strip());
        }
    }
}
