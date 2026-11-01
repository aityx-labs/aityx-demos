package datyx.aityx;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Optional;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * The token services present instead of signing in
 * ({@value #HEADER}, DATYX_SERVICE_TOKEN): compared in constant time,
 * as SHA-256 digests (so not even its length shows). Unset, no token
 * matches. Never logged nor answered.
 */
@ApplicationScoped
public class ServiceToken {

    public static final String HEADER = "X-Datyx-Service-Token";

    private final byte[] digest;

    ServiceToken(@ConfigProperty(name = "datyx.service-token") Optional<String> token) {
        this.digest = token.map(String::strip).filter(t -> !t.isEmpty()).map(ServiceToken::sha256).orElse(null);
    }

    public boolean configured() {
        return digest != null;
    }

    /** Whether {@code presented} is the token; false when none is configured or none presented. */
    public boolean matches(String presented) {
        if (digest == null || presented == null) {
            return false;
        }
        return MessageDigest.isEqual(digest, sha256(presented.strip()));
    }

    private static byte[] sha256(String text) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
