package datyx;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Optional;

import datyx.crypto.Crypto;
import org.junit.jupiter.api.Test;

/** Crypto alone, no Quarkus: keys wrap and unwrap, documents round-trip and are bound to their place. */
class CryptoTest {

    static final String MASTER = Base64.getEncoder().encodeToString("a-master-key-of-thirty-two-bytes".getBytes(StandardCharsets.UTF_8));

    @Test
    void encryptsAndDecryptsWithAProfileKey() {
        Crypto crypto = new Crypto(Optional.of(MASTER));
        byte[] key = crypto.newWrappedKey();
        byte[] plain = "{\"password\":\"secret\"}".getBytes(StandardCharsets.UTF_8);
        byte[] document = crypto.encrypt(key, Crypto.aadFor(7), plain);
        assertFalse(new String(document, StandardCharsets.ISO_8859_1).contains("secret"));
        assertArrayEquals(plain, crypto.decrypt(key, Crypto.aadFor(7), document));
        // Another profile's key, another place, or another master key: refused.
        assertThrows(IllegalStateException.class, () -> crypto.decrypt(crypto.newWrappedKey(), Crypto.aadFor(7), document));
        assertThrows(IllegalStateException.class, () -> crypto.decrypt(key, Crypto.aadFor(8), document));
        Crypto other = new Crypto(Optional.of(Base64.getEncoder().encodeToString("another-master-key-of-32-bytes!!".getBytes(StandardCharsets.UTF_8))));
        assertThrows(IllegalStateException.class, () -> other.decrypt(key, Crypto.aadFor(7), document));
    }

    @Test
    void wantsAProperMasterKey() {
        assertThrows(IllegalStateException.class, () -> new Crypto(Optional.of("not base64!")));
        assertThrows(IllegalStateException.class, () -> new Crypto(Optional.of(Base64.getEncoder().encodeToString("short".getBytes()))));
    }
}
