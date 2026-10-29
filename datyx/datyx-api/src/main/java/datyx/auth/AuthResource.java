package datyx.auth;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;

import datyx.profile.Profiles;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Authentication, OpenID Connect with Google first:
 * GET /api/auth/config, public, is what the apps need to sign the user in:
 * {"enabled":true,"issuer":"https://accounts.google.com","clientId":"..."}
 * (enabled false, and no client id, when OIDC_CLIENT_ID is not set);
 * GET /api/me answers who the bearer token says is calling, and their
 * profile's id (the profile is made on this first call: the sign-in), a
 * 401 without a token once authentication is on, {"authenticated":false}
 * and the local profile while it is off.
 */
@Path("/api")
@Produces(MediaType.APPLICATION_JSON)
public class AuthResource {

    @ConfigProperty(name = AuthConfigSourceFactory.ENABLED, defaultValue = "false")
    boolean enabled;

    @ConfigProperty(name = "datyx.oidc.issuer")
    String issuer;

    @ConfigProperty(name = AuthConfigSourceFactory.CLIENT_ID)
    Optional<String> clientId;

    @Inject
    CurrentUser user;

    @Inject
    Profiles profiles;

    @GET
    @Path("/auth/config")
    public Map<String, Object> config() {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("enabled", enabled);
        map.put("issuer", issuer);
        map.put("clientId", enabled ? clientId.orElse(null) : null);
        return map;
    }

    @GET
    @Path("/me")
    @Transactional
    public Map<String, Object> me() {
        Map<String, Object> map = user.describe();
        map.put("profileId", profiles.current().id);
        return map;
    }
}
