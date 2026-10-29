package datyx.profile;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import datyx.datasource.DataSource;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

/**
 * GET /api/profile: the caller's profile, made on their first call:
 * {"id":1,"name":"Alice","createdAt":"...","dataSources":2,
 *  "identities":[{"issuer":"https://accounts.google.com","subject":"...","email":"alice@example.com",
 *                 "name":"Alice","picture":"...","addedAt":"...","lastSeenAt":"..."}]}
 * Secured like the data sources: a 401 without a token once
 * authentication is on; the local profile while it is off.
 */
@Path("/api/profile")
@Produces(MediaType.APPLICATION_JSON)
public class ProfileResource {

    @Inject
    Profiles profiles;

    @GET
    @Transactional
    public Map<String, Object> get() {
        return view(profiles.current());
    }

    static Map<String, Object> view(Profile profile) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("id", profile.id);
        map.put("name", profile.name);
        map.put("createdAt", profile.createdAt.toString());
        map.put("dataSources", DataSource.countOf(profile));
        List<Map<String, Object>> identities = profile.identities.stream().map(ProfileResource::view).toList();
        map.put("identities", identities);
        return map;
    }

    static Map<String, Object> view(ProfileIdentity identity) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("issuer", identity.issuer);
        map.put("subject", identity.subject);
        map.put("email", identity.email);
        map.put("name", identity.name);
        map.put("picture", identity.picture);
        map.put("addedAt", identity.addedAt.toString());
        map.put("lastSeenAt", identity.lastSeenAt.toString());
        return map;
    }
}
