package datyx.datasource;

import java.io.IOException;
import java.io.UncheckedIOException;

import com.fasterxml.jackson.databind.ObjectMapper;
import datyx.crypto.Crypto;
import datyx.datasource.DataSource.Access;

/**
 * How a data source's access details are stored: JSON, encrypted with the
 * owning profile's key and bound to the profile (Crypto). Static, so the
 * resource and the dev data migration (db.devdata) store the same bytes.
 */
public final class AccessCodec {

    private AccessCodec() {
    }

    public static byte[] seal(Crypto crypto, ObjectMapper json, long profileId, byte[] wrappedKey, Access access) {
        try {
            return crypto.encrypt(wrappedKey, Crypto.aadFor(profileId), json.writeValueAsBytes(access));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    public static Access unseal(Crypto crypto, ObjectMapper json, long profileId, byte[] wrappedKey, byte[] document) {
        try {
            return json.readValue(crypto.decrypt(wrappedKey, Crypto.aadFor(profileId), document), Access.class);
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }
}
