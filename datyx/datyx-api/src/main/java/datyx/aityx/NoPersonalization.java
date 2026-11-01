package datyx.aityx;

import com.fasterxml.jackson.databind.node.ObjectNode;
import io.quarkus.arc.DefaultBean;
import jakarta.enterprise.context.ApplicationScoped;

/**
 * Today's personalization: none, every body goes to aityx as it came. The
 * default bean: any other {@link AityxPersonalizer} replaces it.
 */
@DefaultBean
@ApplicationScoped
public class NoPersonalization implements AityxPersonalizer {

    @Override
    public ObjectNode personalize(Caller caller, ObjectNode body) {
        return body;
    }

    @Override
    public String name() {
        return "none";
    }

    @Override
    public boolean active() {
        return false;
    }
}
