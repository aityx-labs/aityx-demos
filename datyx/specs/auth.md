# Authentication

OpenID Connect, with Google as the first provider. The apps (the datyx
dashboard and HealthHub) sign the user in with Google and send the ID
token as a bearer on every call; the API verifies it against the issuer's
published keys (Quarkus OIDC, `application-type=service`) and reads the
identity claims. Code in `datyx-api/src/main/java/datyx/auth/`.

## Settings

- `OIDC_CLIENT_ID`: the OAuth client id the datyx apps sign in with (the
  Google Cloud project `datyx`, its Web application client `datyx`, with
  the dashboard's origin `http://localhost:9906` among its authorized
  JavaScript origins). Empty, the default: authentication is **off**,
  every path is open and every call anonymous.
- `OIDC_ISSUER`: the provider, `https://accounts.google.com` by default.
- `OIDC_EXTRA_AUDIENCES`: other client ids of the same issuer whose tokens
  are accepted too, comma-separated: HealthHub's, so HealthHub's API can
  pass its user's token on unchanged and datyx sees the same person.

`AuthConfigSourceFactory` (a SmallRye `ConfigSourceFactory`, registered
in `META-INF/services`) derives the rest from the client id at start:
`quarkus.oidc.tenant-enabled`, the policy of the secured paths
(`authenticated`, or `permit` without a client id) and
`quarkus.oidc.token.audience` (the client id plus the extra audiences).
The principal is the `email` claim. Keycloak Dev Services are off: the
issuer is always set.

## What is secured

`/api/datasources`, `/api/datasources/*`, `/api/me`, `/api/profile` and
`/api/profile/*` want a signed-in user once authentication is on: a 401 without a valid token (unsigned,
expired, from another issuer, or for a client not in the audiences).
Everything else stays open: the sign-in config, health, OpenAPI.

## Endpoints

- `GET /api/auth/config`, open: what the apps need to sign the user in,
  `{"enabled":true,"issuer":"https://accounts.google.com","clientId":"..."}`
  (`enabled` false and `clientId` null while authentication is off). The
  apps read this at start, so no client id is built into them.
- `GET /api/me`: who the token says is calling, and their profile,
  made on this first call ([profiles.md](profiles.md)):
  `{"authenticated":true,"subject":"...","email":"...","name":"...","picture":"...","profileId":1}`;
  `{"authenticated":false,"profileId":1}` (the local profile) while
  authentication is off.

## Identity in the API

`CurrentUser` (request-scoped): `authenticated()`, `issuer()`,
`subject()`, `email()`, `name()`, `picture()`, and `id()` (the email, else
the subject), from the `SecurityIdentity`'s JSON Web Token. The issuer
and subject name the identity, and the identity its profile
([profiles.md](profiles.md)), which owns what the user adds. Records
also carry who added them: a data source's `createdBy` and
`createdByName`.

## Tests

`AuthOffTest`: the config says off, `/api/me` says anonymous. `AuthOnTest`
(a test profile with a client id and the OIDC test server, WireMock,
as the issuer): the config publishes the client id; the secured paths
answer 401 without a token, with a bad one and with one for another
client, while the open paths answer; a token for the extra audience is
accepted; `/api/me` tells who is signed in; a data source added carries
its author.

## Known limitations

- Google's ID tokens live an hour; the apps sign in again silently when
  the API refuses one, where the provider allows.
- One issuer at a time.
