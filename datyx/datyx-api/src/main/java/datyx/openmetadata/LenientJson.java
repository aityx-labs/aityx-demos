package datyx.openmetadata;

import com.fasterxml.jackson.core.json.JsonReadFeature;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.json.JsonMapper;
import jakarta.ws.rs.ext.ContextResolver;

/**
 * The JSON reader of the OpenMetadata client only: OpenMetadata answers
 * an entity type with its JSON Schema as a string holding raw line
 * breaks, which strict JSON (and Jackson by default) refuses.
 */
public class LenientJson implements ContextResolver<ObjectMapper> {

    private static final ObjectMapper MAPPER = JsonMapper.builder()
        .enable(JsonReadFeature.ALLOW_UNESCAPED_CONTROL_CHARS)
        .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
        .build();

    @Override
    public ObjectMapper getContext(Class<?> type) {
        return MAPPER;
    }
}
