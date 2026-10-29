package datyx.crypto;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Optional;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

import io.quarkus.runtime.LaunchMode;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Encryption at rest: AES-256-GCM. Each profile has a key of its own,
 * made here when the profile is created and stored wrapped (encrypted)
 * by the server's master key, {@code datyx.master-key} (DATYX_MASTER_KEY,
 * 32 bytes in base64, {@code openssl rand -base64 32}); records are
 * encrypted with the profile's key, bound to the record by the
 * associated data (the profile's id), so a document can't be moved to
 * another row. A document is a random 12-byte nonce followed by the
 * ciphertext and its 16-byte tag. Without a master key the API runs in
 * dev and test modes on a development key, with a warning, and refuses
 * to start otherwise.
 */
@ApplicationScoped
public class Crypto {

    private static final Logger LOG = Logger.getLogger(Crypto.class);
    private static final int KEY_BYTES = 32;
    private static final int NONCE_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final byte[] KEY_WRAP_AAD = "datyx:profile-key".getBytes(StandardCharsets.UTF_8);
    /** For dev and test runs without DATYX_MASTER_KEY: known, so never for anything shared. */
    private static final String DEVELOPMENT_KEY = "ZGF0eXgtZGV2ZWxvcG1lbnQtbWFzdGVyLWtleS0wMSE=";

    private final SecureRandom random = new SecureRandom();
    private final SecretKeySpec masterKey;

    public Crypto(@ConfigProperty(name = "datyx.master-key") Optional<String> configured) {
        String encoded = configured.map(String::strip).filter(s -> !s.isEmpty()).orElse(null);
        if (encoded == null) {
            if (LaunchMode.current() == LaunchMode.NORMAL) {
                throw new IllegalStateException(
                    "DATYX_MASTER_KEY is not set: the key that protects profile keys and data source access details. "
                        + "Make one with `openssl rand -base64 32` and set it in the environment or .env.");
            }
            LOG.warn("DATYX_MASTER_KEY is not set: using the development master key (dev and test modes only)");
            encoded = DEVELOPMENT_KEY;
        }
        byte[] bytes;
        try {
            bytes = Base64.getDecoder().decode(encoded);
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException("DATYX_MASTER_KEY is not base64", e);
        }
        if (bytes.length != KEY_BYTES) {
            throw new IllegalStateException("DATYX_MASTER_KEY must be " + KEY_BYTES + " bytes in base64 (openssl rand -base64 32), not " + bytes.length);
        }
        masterKey = new SecretKeySpec(bytes, "AES");
    }

    void started(@Observes StartupEvent event) {
        // Constructed at start, so a missing key fails the start, not the first sign-in.
    }

    /** A new profile key, wrapped by the master key: what the profile row stores. */
    public byte[] newWrappedKey() {
        byte[] key = new byte[KEY_BYTES];
        random.nextBytes(key);
        return seal(masterKey, KEY_WRAP_AAD, key);
    }

    /** Encrypts a record with a profile's wrapped key; {@code aad} binds it to its place (the profile's id). */
    public byte[] encrypt(byte[] wrappedKey, byte[] aad, byte[] plain) {
        return seal(profileKey(wrappedKey), aad, plain);
    }

    /** The reverse of {@link #encrypt}: fails when the key, the data or the document changed. */
    public byte[] decrypt(byte[] wrappedKey, byte[] aad, byte[] document) {
        return open(profileKey(wrappedKey), aad, document);
    }

    /** The associated data of a profile's records. */
    public static byte[] aadFor(long profileId) {
        return ("datyx:profile:" + profileId).getBytes(StandardCharsets.UTF_8);
    }

    private SecretKeySpec profileKey(byte[] wrappedKey) {
        return new SecretKeySpec(open(masterKey, KEY_WRAP_AAD, wrappedKey), "AES");
    }

    private byte[] seal(SecretKeySpec key, byte[] aad, byte[] plain) {
        byte[] nonce = new byte[NONCE_BYTES];
        random.nextBytes(nonce);
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, nonce));
            cipher.updateAAD(aad);
            byte[] sealed = cipher.doFinal(plain);
            byte[] document = new byte[NONCE_BYTES + sealed.length];
            System.arraycopy(nonce, 0, document, 0, NONCE_BYTES);
            System.arraycopy(sealed, 0, document, NONCE_BYTES, sealed.length);
            return document;
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("encryption failed", e);
        }
    }

    private static byte[] open(SecretKeySpec key, byte[] aad, byte[] document) {
        if (document == null || document.length < NONCE_BYTES + TAG_BITS / 8) {
            throw new IllegalStateException("not an encrypted document");
        }
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, document, 0, NONCE_BYTES));
            cipher.updateAAD(aad);
            return cipher.doFinal(document, NONCE_BYTES, document.length - NONCE_BYTES);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("decryption failed: the key or the document changed", e);
        }
    }
}
