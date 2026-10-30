# Requests

The history of requests that shaped datyx, newest first.

## 2026-10-30: the health with the profile; hello, greetings and status gone

Asked: a health check as the Quarkus SmallRye Health guide describes, with
an attribute stating the execution mode or profile, injected by Quarkus;
dev mode in local, process-compose and Docker Compose development; remove
the greeting and hello resources, and the status resource, the greetings'
table out of the migrations; reset the database to zero in dev mode.

Changed: `ModeHealthCheck`, a liveness check named `datyx` in
`/api/health`, always UP with the version, the profile (`quarkus.profile`),
the launch mode (the injected `LaunchMode`), `jvm` or `native` and the
start time. `GreetingResource`, `Greeting`, `HelloResource` and
`StatusResource` are gone, with their tests (`HealthTest` covers the
health); the greetings' table is out of the migrations altogether (V1 is
now `V1__data_sources.sql`), and the dev profile starts from an empty
database (`%dev.quarkus.flyway.clean-at-start=true`). The health
monitor checks the API on `/api/health/live`, and the dashboard reads
`/api/health` (its own spec says how). `API_MODE=dev` (`quarkus:dev`) was
already the default for `devbox services up`; Docker Compose now builds and
runs the API with the `dev` profile (`DATYX_API_PROFILE`, the Dockerfiles'
`PROFILE` argument, `prod` when built without compose), so the dev data
loads there too: Flyway's locations are fixed at build time.

## 2026-10-29: the index on 9800, HealthHub's database on 9803

Asked: make the datyx index the first port of the group (9800).

Changed: the index (datyx-index/) moves from 9907 to 9800 and HealthHub
up one, to 9801 to 9803; the dev data source for HealthHub's PostgreSQL
(`R__HealthHub_data_source`), its test and the API spec now say port 9803.

## 2026-10-29: OpenMetadata in the API's health check

Asked: remove the OpenMetadata card from the datyx index, and cover
OpenMetadata in the datyx API's health check, on the API's card.

Changed: `OpenMetadataHealthCheck`, a readiness check in `/api/health`
beside the database's, through `OpenMetadataClient` (off in the test
profile); the index's OpenMetadata card is gone and the API card says its
health check covers PostgreSQL and OpenMetadata, with OpenMetadata's UI
and sign-in; the API spec.

## 2026-10-29: Flyway locations by profile, dev data for HealthHub

Asked: Flyway on the datyx API with different folders for the Quarkus
dev runtime and the regular (prod) runtime, so migrations and data can
differ between them; in dev, a data source pointing at HealthHub's
database.

Changed: `quarkus.flyway.locations` is `db/migration` and dev mode adds
`db/devdata`; `db.devdata.R__HealthHub_data_source`, a repeatable Java
migration seeding HealthHub's PostgreSQL as the HealthHub data source of
every profile (the local one made when missing), encrypted through the
new `AccessCodec`, which the resource uses too; `DevDataTest`; the API,
data sources, dev-environment specs.

## 2026-10-29: profiles, and encryption at rest

Asked: profiles on the API and the dashboard, as the other apps have:
when someone signs in with an identity such as an email, create a profile
for it if there is none, else load it; a profile can have more than one
identity, so it isn't bound to one email, and may be shared later; for
now the basic creation, and with each profile an encryption key that
encrypts the sensitive data, such as data source usernames, passwords
and locations.

Changed: the `Profile` and `ProfileIdentity` entities, `Profiles`
resolving the caller's profile by the token's issuer and subject and
making one on the first call (`ProfileMaker`), `Crypto` (AES-256-GCM: a
master key from `DATYX_MASTER_KEY` wrapping a key per profile, a
development key in dev and test modes, required otherwise),
`GET /api/profile`, `profileId` in `GET /api/me`, `profiles` in the
status; data sources owned by a profile, listed, read and removed within
it, their access details one encrypted document (`access`) in place of
the clear columns, and the name unique per profile
(`V2__profiles_and_encrypted_access.sql`, which drops the pre-profile
rows); `DATYX_MASTER_KEY` in `.env.example`, the scripts and
`compose.yaml`; `ProfileTest`, `CryptoTest`, the auth-off test; the
`profiles.md` spec, and the data sources, auth, API and dev-environment
specs. The dashboard gained a Profile tab
([../../datyx-dashboard/specs/dashboard.md](../../datyx-dashboard/specs/dashboard.md)).

## 2026-10-29: the API starts without a .env

Asked: spin up a codespace for each demo group. In the datyx one the API
never answered: "Failed to load config value ... datyx.oidc.issuer".

Changed: scripts/env.sh exported `OIDC_ISSUER` empty when neither the
environment nor `.env` set it, which overrode the Google default in
application.properties with nothing. It now defaults to
`https://accounts.google.com` too, so a fresh checkout (a codespace has
no `.env`) starts the API, with authentication still off until
`OIDC_CLIENT_ID` is set.

## 2026-10-29: the dev containers by demo group

Asked: separate the dev containers, images and Codespaces configurations
by demo group.

Changed: nothing in this folder. The API now runs in a codespace, in the
datyx group's dev container, **datyx demos**
(`.devcontainer/datyx/devcontainer.json` at the repository root), on the
group's image `docker.io/aletyxcode/samples-and-demos-datyx` (`bash
image/build-image.sh datyx`: GraalVM, Flutter and the API's Maven
dependencies), which starts it with the dashboard, HealthHub and the
index page. There was no per-demo dev container for it to replace; the
per-demo ones of the other folders were removed.

## 2026-10-28: data sources, and OpenID Connect with Google

Asked: the first entity, data sources, which users add and remove:
databases, S3 or filesystem for now, each with its access details; OIDC
authentication on the API, the dashboard and HealthHub, with the user's
identity propagated through, from HealthHub to the datyx API seamlessly;
Google sign-in set up, with `datyx` and `healthhub` as the Google ids.

Changed: the `DataSource` entity and `/api/datasources` (list, get, add,
remove; [data-sources.md](data-sources.md)), counted in `/api/status`;
Quarkus OIDC as a bearer-token service with Google as the issuer,
`/api/auth/config` and `/api/me`, `CurrentUser`, and
`AuthConfigSourceFactory`, which turns authentication on when
`OIDC_CLIENT_ID` is set and accepts `OIDC_EXTRA_AUDIENCES` (HealthHub's
client) too ([auth.md](auth.md)); the settings in `.env.example`,
`scripts/env.sh`, `scripts/api.sh` and `compose.yaml`; the tests point
OpenMetadata at a closed port; `DataSourceResourceTest`, `AuthOffTest`,
`AuthOnTest` (the OIDC test server as the issuer). The dashboard and
HealthHub changed in their own folders.

## 2026-10-28: API only; the dashboard in its own folder

Asked: create `datyx-dashboard`, a Flutter app like the other demos',
accessing the datyx API; the `datyx` module becomes API only, the
dashboard a separate app that invokes it.

Changed: `datyx-dash/` moved to `../datyx-dashboard/datyx_dashboard/`,
with its own devbox, process-compose, Docker Compose, scripts, id and
version files and specs ([../../datyx-dashboard/specs/](../../datyx-dashboard/specs/)).
Here: the `5-dash` process, the `dash` compose service, `scripts/dash.sh`,
`scripts/make.sh`, `docker/dash.Dockerfile`, `docker/nginx.conf`, the web
targets of `build.sh` and the Makefile, Flutter in `devbox.json`, and
`FLUTTER_WEB_PORT`, `DATYX_DASH_PORT` and `WEB_MODE` are gone; the health
monitor starts after the API and checks API, Postgres, OpenMetadata and
Search; the API's port is published by `compose.yaml` so the dashboard's
container reaches it; README, CLAUDE.md (data and logic here, views in the
dashboard's folder), AGENTS.md and these specs. The repository's
`start-all.sh` waits for datyx on the API's `/api/health`, since it has
no web port.

## 2026-10-28: the dashboard, datyx-dash

Asked: a separate module, `datyx-dash`, a Flutter dashboard (like every
demo's app) that invokes the API; from now on, data and logic go in the
API and views in the dashboard, recorded in the project's CLAUDE.md.

Changed: the Quarkus project moved into `datyx-api/`; `datyx-dash/`, a
Flutter web app with status cards, a hello call, the greetings on record
and a panel of every API call, served under `/app/` on 9906 by a small
Dart web server (release) or Flutter's dev server (debug), both proxying
`/api/` to the API; the API gained `GET /api/status` (database,
OpenMetadata, greetings count) and `GET`/`POST /api/greetings` on the
`Greeting` entity, with an OpenMetadata REST client; `scripts/api.sh`
(was `app.sh`, `API_MODE`), `scripts/dash.sh`, `scripts/make.sh`,
`build.sh` with the web targets, the `5-dash` process, the `api` and
`dash` compose services with their Dockerfiles and nginx; `DATYX_PORT`
became `DATYX_API_PORT`, `DATYX_DASH_PORT` added; Flutter in devbox; the
module convention in CLAUDE.md; README and specs.

## 2026-10-28: start datyx

Asked: a new `datyx` folder for the system, following the demos' patterns
(devbox, process-compose, Docker Compose, the id and version files), with
group and artifact id both `datyx`; a Quarkus app on GraalVM, a PostgreSQL
database and an OpenMetadata server, on port 9900 for the app and 99xx for
the rest; start it up. Then: keep the app a simple hello-world REST API, no
pages, with the usual components (health, Hibernate ORM with Panache).

Changed: the folder, as a git repository, with `devbox.json` (GraalVM CE,
Maven), `process-compose.yaml`, `compose.yaml`, the scripts, the
Dockerfiles, PostgreSQL's init script, the Quarkus project (`GET
/api/hello`, the `Greeting` entity, health, OpenAPI, tests), the Makefile,
the id and version files, README, AGENTS.md, CLAUDE.md and these specs.
