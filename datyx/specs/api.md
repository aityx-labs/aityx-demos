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
  (`V1__data_sources.sql`, `V2__profiles_and_encrypted_access.sql`,
  `V3__drop_hibernate_unique_name.sql`, `V4__kafka_sources.sql`, `V5__training_runs.sql`,
`V6__inference_calls.sql`, `V7__training_trigger_note.sql`, `V8__group_events.sql`,
`V9__aityx_calls.sql`)
  run at every start in every profile (a fresh database, under Docker
  alone or a jar or native build, gets its tables), tests and the dev
  profile clean the schema first (`clean-at-start`: every start drops
  everything and migrates from zero), a database Hibernate made before Flyway is baselined as
  version 1, and Hibernate only validates that the entities match. The
  locations differ by Quarkus profile: `db/migration` alone in prod and
  test (`quarkus.flyway.locations`, fixed at build time, so a packaged
  build has the locations of the profile it was built with); the dev
  profile adds `db/devdata`, the
  development data: Java migrations in package `db.devdata`, which
  prod never runs. So far `R__HealthHub_data_source`, a repeatable
  migration that adds the development data's two sources (`DevData`:
  HealthHub's PostgreSQL as a data source named HealthHub, its Kafka as
  one named HealthHub Kafka, at the addresses the settings give,
  [data-sources.md](data-sources.md#development-data)) to every profile
  lacking one of the name, the local
  profile included (made when missing), encrypted as the API stores it
  (`AccessCodec`); it runs again when its `VERSION` constant changes, and
  skips, with a warning, a profile whose key another master key wrapped.
  A profile made after it ran gets the same two as it is made
  (`ProfileMaker`, with `datyx.devdata.enabled`, true in the dev profile
  alone; [profiles.md](profiles.md)).
- `javax.crypto` (AES-256-GCM) for encryption at rest, see
  [profiles.md](profiles.md).
- Hibernate Validator: request bodies are validated, a 400 on failure.
- A REST client for OpenMetadata (`OpenMetadataClient`, config key
  `openmetadata`, URL from `DATYX_OPENMETADATA_URL`): its public
  `/api/v1/system/version`, and the database services, databases,
  schemas, tables, messaging services, topics, classifications, tags and
  custom properties the catalogue writes and reads, the profiles, test
  cases and results of its checks, the teams, domains, data products,
  glossaries, pipelines, lineage and data contracts a curation writes,
  and the event subscription that posts tables' changes back to datyx
  (its webhook), signed in by `OpenMetadataSession` ([catalog.md](catalog.md),
  [curation.md](curation.md)).
- JDBC's `DatabaseMetaData`, on the PostgreSQL driver, to read a database
  source's tables (`SchemaReader`, [catalog.md](catalog.md)).
- Kafka's client (`quarkus-kafka-client`, its Dev Services off: datyx
  has no broker of its own), to read a Kafka source's topics and latest
  records (`StreamReader`, [catalog.md](catalog.md)).
- SmallRye Health: `/api/health`, `/api/health/live`, `/api/health/ready`
  (503 when a check is DOWN, the checks still in the body), the system as
  the API sees it and what the dashboard's Health tab shows:
  - `datyx` (`ModeHealthCheck`), a liveness check, always UP, saying how
    the API runs: `version`, `profile` (the Quarkus configuration
    profile, injected as `quarkus.profile`: `dev`, `test`, `prod`, or
    several, comma-separated), `launchMode` (the injected `LaunchMode`:
    `development` for `quarkus:dev`, `test`, `normal` for a packaged jar
    or native executable), `image` (`jvm` or `native`) and `startedAt`.
  - `Database connections health check`, the datasource's readiness check.
  - `OpenMetadata` (`OpenMetadataHealthCheck`), a readiness check, UP
    with the server's version and URL, DOWN with the error. The URL is
    where a browser opens OpenMetadata, since the dashboard links to it:
    `DATYX_OPENMETADATA_PUBLIC_URL` (`datyx.openmetadata.public-url`)
    when set, else the URL the API calls (`DATYX_OPENMETADATA_URL`). The
    two differ where the API reaches OpenMetadata by a name only its
    network knows: `http://openmetadata:8585` in Docker Compose and on
    the Kubernetes cluster, reported as `http://localhost:9902` and
    `http://localhost:19902`.

  The API is ready only with the database and OpenMetadata, as
  process-compose and `compose.yaml` already start it after OpenMetadata.
  The OpenMetadata check is off in tests, which run without it. The
  services' readiness probe uses `/api/health/ready`, the health monitor
  `/api/health/live` and `/api/health`.
- SmallRye OpenAPI: `/q/openapi`, and Swagger UI at `/q/swagger-ui` in dev.
- Quarkus OIDC: bearer tokens verified against the issuer, see
  [auth.md](auth.md).
- Quarkus Scheduler: the trainer's check every minute, XGBoost4J
  (XGBoost through JNI) and DJL's DeepAR on its PyTorch engine (libtorch
  through JNI), see [training.md](training.md).

## Endpoints

- `/api/health`: see SmallRye Health above.
- `/api/datasources`: see [data-sources.md](data-sources.md).
- `/api/datasources/{id}/catalog` and `/api/datasources/{id}/timeseries`
  (with `/timeseries/enabled`), `/api/catalog/events` and
  `/api/catalog/openmetadata-events` (OpenMetadata's webhook, signed, not
  signed in): see [catalog.md](catalog.md).
- `/api/training`, `/api/training/runs/{id}` and
  `/api/datasources/{id}/training`: see [training.md](training.md).
- `/api/inference` and `/api/datasources/{id}/inference`: see
  [inference.md](inference.md).
- `/api/aityx/v1/systemone` (the gateway to aityx, for signed-in users
  and for services with the service token), `/api/aityx/v1/status`
  (whether datyx has an aityx key, for the same callers), `/api/aityx` and
  `/api/aityx/calls/{id}`: see [aityx.md](aityx.md).
- `/api/auth/config` and `/api/me`: see [auth.md](auth.md).
- `/api/profile`: see [profiles.md](profiles.md).

## Entities

- `DataSource` (table `data_source`): see [data-sources.md](data-sources.md).
- `Profile` (table `profile`) and `ProfileIdentity` (`profile_identity`):
  see [profiles.md](profiles.md).
- `GroupEvent` (table `group_event`): see [catalog.md](catalog.md).
- `TrainingRun` (table `training_run`): see [training.md](training.md).
- `InferenceCall` (table `inference_call`): see [inference.md](inference.md).
- `AityxCall` (table `aityx_call`): see [aityx.md](aityx.md).

## Settings

Every setting reads an environment variable (`application.properties`):
`DATYX_API_PORT` (9900), `DATYX_BIND_HOST` (localhost in dev, every
interface otherwise), `DATYX_DB_URL` (`jdbc:postgresql://localhost:9901/datyx`),
`DATYX_DB_USER`, `DATYX_DB_PASSWORD`, `DATYX_OPENMETADATA_URL`
(`http://localhost:9902`), `DATYX_OPENMETADATA_PUBLIC_URL` (empty: the
URL before it; what `/api/health` reports), `OIDC_CLIENT_ID`, `OIDC_ISSUER`,
`OIDC_EXTRA_AUDIENCES` ([auth.md](auth.md)), `DATYX_MASTER_KEY`
([profiles.md](profiles.md); tests use a fixed one), and
`DATYX_OPENMETADATA_TOKEN`, `DATYX_OPENMETADATA_EMAIL`,
`DATYX_OPENMETADATA_PASSWORD` ([catalog.md](catalog.md); dev mode signs in
as the stack's admin when unset), `DATYX_OPENMETADATA_CALLBACK_URL`
(where OpenMetadata's webhook posts; dev:
`http://host.docker.internal:{port}/api/catalog/openmetadata-events`,
none in prod), `DATYX_OPENMETADATA_WEBHOOK_SECRET` (the webhook's
signing secret; drawn at start when unset; tests use a fixed one) and
`DATYX_OPENMETADATA_SUBSCRIPTION` (`datyx-catalog-events`)
([catalog.md](catalog.md)), `DATYX_TRAINING_ENABLED` (true; tests false,
[training.md](training.md)), `AITYX_API_KEY`, `DATYX_AITYX_URL`
(`https://api.aityx.ai`), `DATYX_SERVICE_TOKEN` and
`DATYX_AITYX_SHARE_SERVICE_CALLS` (empty: true in dev mode only)
([aityx.md](aityx.md); tests have no key, no token and aityx on a
closed port, unless a test profile sets them), and the development
data's HealthHub, `DATYX_HEALTHHUB_DB_HOST` (`localhost`),
`DATYX_HEALTHHUB_DB_PORT` (9803), `DATYX_HEALTHHUB_DB_PASSWORD`
(HealthHub's development one) and `DATYX_HEALTHHUB_KAFKA`
(`localhost:9804`), each its default when empty
([data-sources.md](data-sources.md#development-data)). Tests set no database URL
and get a Postgres test container from Dev Services, and point the
OpenMetadata client at a closed port (`localhost:1`) so its check fails
predictably whether or not the stack runs; Quarkus's own compose Dev
Services and Keycloak Dev Services are off.

## Tests

`./mvnw verify` in `datyx-api/` (Docker must be up): `HealthTest`
(`/api/health` UP with the database; the `datyx` liveness check says the
`test` profile and launch mode, `jvm`, a version and a start time),
`DataSourceResourceTest` ([data-sources.md](data-sources.md)),
`AuthOffTest` and `AuthOnTest` ([auth.md](auth.md)), `CatalogResourceTest`,
`CatalogEventsTest`, `StreamReaderTest`, `TimeSeriesTest`, `PiiTest` and `QualityTest` ([catalog.md](catalog.md)),
`CurationTest` ([curation.md](curation.md)), `XgbTrainerTest` and
`TrainingTest` ([training.md](training.md)), `InferenceTest`
([inference.md](inference.md)), `AityxGatewayTest`, `AityxAuthTest` and
`AityxNoKeyTest` ([aityx.md](aityx.md)), `ProfileTest` and
`CryptoTest` ([profiles.md](profiles.md)), `DevDataTest`, which adds
`db/devdata` to the test's locations and reads the local profile's two
HealthHub data sources back through the API, at their default
addresses, and `DevDataProfileTest`, the same data in a profile made by
a first sign-in ([profiles.md](profiles.md)).
