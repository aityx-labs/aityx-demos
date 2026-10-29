# The API

The datyx API is a Quarkus 3 REST API (Java 21 bytecode, run on GraalVM
CE 25), Maven coordinates `datyx:datyx`, package `datyx`, in `datyx-api/`.
Every piece of data and logic of the system lives here; the dashboard
([../../datyx-dashboard/specs/dashboard.md](../../datyx-dashboard/specs/dashboard.md),
a folder of its own) only calls it.

## Components

- Quarkus REST with Jackson: JSON endpoints under `/api/`.
- Hibernate ORM with Panache on PostgreSQL (the `datyx` database, user
  `datyx`), and Flyway for the schema: the migrations in `db/migration`
  (`V1__greetings_and_data_sources.sql`, `V2__profiles_and_encrypted_access.sql`,
  `V3__drop_hibernate_unique_name.sql`)
  run at every start in every profile (a fresh database, under Docker
  alone or a jar or native build, gets its tables), tests clean the
  schema first, a database Hibernate made before Flyway is baselined as
  version 1, and Hibernate only validates that the entities match. The
  locations differ by Quarkus profile: `db/migration` alone in prod and
  test (`quarkus.flyway.locations`); dev mode adds `db/devdata`, the
  development data: Java migrations in package `db.devdata`, which
  prod never runs. So far `R__HealthHub_data_source`, a repeatable
  migration that adds HealthHub's PostgreSQL (localhost, 9802, database
  `healthhub`, user `healthhub`, HealthHub's development defaults) as a
  data source named HealthHub to every profile lacking one, the local
  profile included (made when missing), encrypted as the API stores it
  (`AccessCodec`); it runs again when its `VERSION` constant changes, and
  skips, with a warning, a profile whose key another master key wrapped.
- `javax.crypto` (AES-256-GCM) for encryption at rest, see
  [profiles.md](profiles.md).
- Hibernate Validator: request bodies are validated, a 400 on failure.
- A REST client for OpenMetadata (`OpenMetadataClient`, config key
  `openmetadata`, URL from `DATYX_OPENMETADATA_URL`), its public
  `/api/v1/system/version` so far.
- SmallRye Health: `/api/health`, `/api/health/live`, `/api/health/ready`, with
  the datasource check. The services' readiness probe and the health
  monitor use it.
- SmallRye OpenAPI: `/q/openapi`, and Swagger UI at `/q/swagger-ui` in dev.
- Quarkus OIDC: bearer tokens verified against the issuer, see
  [auth.md](auth.md).

## Endpoints

- `GET /api/hello` answers `{"message":"Hello, World!"}`; `?name=<name>`
  answers `{"message":"Hello, <name>!"}` (blank names count as missing).
- `GET /api/status` answers the system as the API sees it, what the
  dashboard's cards show: `name`, `version`, `startedAt`, `uptimeSeconds`,
  `database` (`ok`, `version` from `select version()`, or `error`),
  `openmetadata` (`ok`, `version` from the server, `url`, or `error`),
  `greetings`, `dataSources` and `profiles` (how many are on record;
  null while the database is out). A dependency that fails is reported, not an error for
  the call.
- `GET /api/greetings?limit=50` lists the greetings on record, newest
  first (`limit` between 1 and 500).
- `POST /api/greetings` with `{"message":"..."}` stores one (the message
  stripped; blank or over 200 characters is a 400) and answers 201 with it
  and a `Location`.
- `/api/datasources`: see [data-sources.md](data-sources.md).
- `/api/auth/config` and `/api/me`: see [auth.md](auth.md).
- `/api/profile`: see [profiles.md](profiles.md).

## Entities

- `Greeting` (table `greeting`): `id`, `message` (up to 200 characters,
  required), `createdAt` (`created_at`, required).
- `DataSource` (table `data_source`): see [data-sources.md](data-sources.md).
- `Profile` (table `profile`) and `ProfileIdentity` (`profile_identity`):
  see [profiles.md](profiles.md).

## Settings

Every setting reads an environment variable (`application.properties`):
`DATYX_API_PORT` (9900), `DATYX_BIND_HOST` (localhost in dev, every
interface otherwise), `DATYX_DB_URL` (`jdbc:postgresql://localhost:9901/datyx`),
`DATYX_DB_USER`, `DATYX_DB_PASSWORD`, `DATYX_OPENMETADATA_URL`
(`http://localhost:9902`), `OIDC_CLIENT_ID`, `OIDC_ISSUER`,
`OIDC_EXTRA_AUDIENCES` ([auth.md](auth.md)), and `DATYX_MASTER_KEY`
([profiles.md](profiles.md); tests use a fixed one). Tests set no database URL
and get a Postgres test container from Dev Services, and point the
OpenMetadata client at a closed port (`localhost:1`) so its check fails
predictably whether or not the stack runs; Quarkus's own compose Dev
Services and Keycloak Dev Services are off.

## Tests

`./mvnw verify` in `datyx-api/` (Docker must be up): `HelloResourceTest`
(hello, hello by name, `/api/health` UP), `GreetingResourceTest` (store and
list, a blank message is a 400), `StatusResourceTest` (the database part
ok, the OpenMetadata part reporting the failure, since the tests point at
a closed port), `DataSourceResourceTest` ([data-sources.md](data-sources.md)),
`AuthOffTest` and `AuthOnTest` ([auth.md](auth.md)), `ProfileTest` and
`CryptoTest` ([profiles.md](profiles.md)), and `DevDataTest`, which adds
`db/devdata` to the test's locations and reads the HealthHub data source
back through the API.
