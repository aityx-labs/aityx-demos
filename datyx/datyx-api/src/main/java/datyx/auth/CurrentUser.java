package datyx.auth;

import java.util.LinkedHashMap;
import java.util.Map;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.enterprise.context.RequestScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.jwt.JsonWebToken;

/**
 * Who is calling, from the bearer token the OIDC extension verified: the
 * subject and the identity claims the provider sends (Google: email, name,
 * picture). Anonymous when the call has no token, or when authentication
 * is off (no client id; see AuthConfigSourceFactory).
 */
@RequestScoped
public class CurrentUser {

    @Inject
    SecurityIdentity identity;

    public boolean authenticated() {
        return !identity.isAnonymous();
    }

    /** The token's issuer (iss), null while anonymous. */
    public String issuer() {
        return authenticated() ? claim("iss") : null;
    }

    public String subject() {
        return authenticated() ? claim("sub") : null;
    }

    public String email() {
        return authenticated() ? claim("email") : null;
    }

    public String name() {
        return authenticated() ? claim("name") : null;
    }

    public String picture() {
        return authenticated() ? claim("picture") : null;
    }

    /** The email, else the subject: what records carry as their author. */
    public String id() {
        String email = email();
        return email != null ? email : subject();
    }

    /** What GET /api/me answers. */
    public Map<String, Object> describe() {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("authenticated", authenticated());
        if (authenticated()) {
            map.put("subject", subject());
            map.put("email", email());
            map.put("name", name());
            map.put("picture", picture());
        }
        return map;
    }

    private String claim(String name) {
        if (identity.getPrincipal() instanceof JsonWebToken token) {
            Object value = token.getClaim(name);
            return value == null ? null : value.toString();
        }
        return "sub".equals(name) ? identity.getPrincipal().getName() : null;
    }
}
