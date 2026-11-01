package datyx.aityx;

import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * Where calls to aityx will be personalized per profile, before the
 * gateway sends them: a profile's preferred Jev model, extra context in
 * the state, variants of a decision. {@link #personalize} answers the
 * body to send: the one given, unchanged, to send the caller's as it
 * came (byte for byte), or a new one. Today's is {@link NoPersonalization}.
 */
public interface AityxPersonalizer {

    /** Who is calling: their profile (null for a service), the caller recorded, whether a service, and the purpose. */
    record Caller(Long profileId, String caller, boolean service, String purpose) {
    }

    /** The body to send aityx for this caller: {@code body} itself when nothing changes. */
    ObjectNode personalize(Caller caller, ObjectNode body);

    /** Its name, for the account. */
    default String name() {
        return getClass().getSimpleName();
    }

    /** Whether it changes anything at all, for the account. */
    default boolean active() {
        return true;
    }
}
