package datyx.aityx;

import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.vertx.http.runtime.security.HttpSecurityPolicy;
import io.smallrye.mutiny.Uni;
import io.vertx.ext.web.RoutingContext;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * The gateway's paths (/api/aityx/v1/*, application.properties'
 * permission aityx-gateway): a call presenting the service token
 * ({@link ServiceToken#HEADER}) needs no sign-in; one presenting a wrong
 * token, or any while none is configured, is refused; any other wants a
 * signed-in user, as the secured paths do, unless authentication is off
 * (every path open).
 */
@ApplicationScoped
public class AityxGatewayPolicy implements HttpSecurityPolicy {

    @Inject
    ServiceToken token;

    @ConfigProperty(name = "datyx.oidc.enabled", defaultValue = "false")
    boolean authentication;

    @Override
    public String name() {
        return "aityx-gateway";
    }

    @Override
    public Uni<CheckResult> checkPermission(RoutingContext request, Uni<SecurityIdentity> identity,
            AuthorizationRequestContext context) {
        String presented = request.request().getHeader(ServiceToken.HEADER);
        if (presented != null) {
            return token.matches(presented) ? CheckResult.permit() : CheckResult.deny();
        }
        if (!authentication) {
            return CheckResult.permit();
        }
        return identity.map(i -> i.isAnonymous() ? CheckResult.DENY : CheckResult.PERMIT);
    }
}
