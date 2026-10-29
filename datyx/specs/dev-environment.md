# Development environment

## Toolchain

`devbox.json`: GraalVM CE (`graalvmPackages.graalvm-ce`, the JDK the API
runs on, with `native-image`), Maven, make, curl, jq. The shell's init
hook sets `JAVA_HOME` to the GraalVM. Docker must run on the host for the
containers and the tests. Flutter is not here: the dashboard is the
`datyx-dashboard/` folder's, with its own toolchain.

## Services

`devbox services up` runs `process-compose.yaml`:

- `1-postgres`, `2-search`, `3-openmetadata`: the containers of
  `compose.yaml`, one `docker compose up --attach <service> <service>` each
  (`scripts/infra.sh up`), with readiness probes on the containers' Docker
  health (`scripts/infra.sh healthy`) and `docker compose stop` on
  shutdown. OpenMetadata starts after PostgreSQL and Elasticsearch are
  healthy, and runs its migration container (`openmetadata-migrate`) first.
- `4-api`: the API on the host's GraalVM (`scripts/api.sh`), after
  PostgreSQL is healthy, by `API_MODE`: `dev` (default, `./mvnw quarkus:dev`
  in `datyx-api/` with live reload and the debugger on 9905, no
  interactive console, no analytics prompt), `jar` (the packaged API,
  built when stale) or `native` (the native executable, built when stale).
  Readiness: `/api/health/ready`. Shutdown kills whatever listens on the
  API's port, since dev mode keeps a child JVM there.
- `0-health-check`: `scripts/health-check.sh`, after OpenMetadata and the
  API are ready. Prints where to open things, then one line per
  interval: 🔌 API (`/api/hello`), 🐘 Postgres (the datasource check in
  `/api/health`), 🗂 OpenMetadata (admin `/healthcheck`), 🔎 Search
  (cluster health green or yellow).

The dashboard is not a process here: it is `datyx-dashboard/`'s own
service, which proxies `/api/` and `/q/` to the API on 9900. The
repository's `start-all.sh` waits for datyx on `/api/health` on the API's
port, since datyx has no web port of its own.

`compose.yaml` (project `datyx`) holds every service for Docker alone:
`postgres` (postgres:17, `work_mem=10MB`, `docker/postgres-init.sh` creates
the `datyx` and `openmetadata_db` databases and their users on the first
start), `search` (Elasticsearch 9.3.0, single node, no security, 1 GB
heap), `openmetadata-migrate` and `openmetadata` (OpenMetadata server
2.0.7 on PostgreSQL and Elasticsearch, basic auth, no ingestion pipeline
client, 1 GB heap) and `api` (built from `docker/api.jvm.Dockerfile`, or
`docker/api.native.Dockerfile` with `DATYX_API_DOCKERFILE`, the root as
context, see `.dockerignore`), published on `API_PORT` (9900) so the
dashboard's own compose file reaches it; on Linux the dashboard and
HealthHub join this stack's network through their `compose.datyx.yaml`
instead, since a port bound to 127.0.0.1 isn't reachable from the bridge. Data lives in the `postgres-data` and
`search-data` volumes.

## Ports and settings

9900 the API, 9901 PostgreSQL, 9902 OpenMetadata (8585 inside), 9903 its
admin port (8586), 9904 Elasticsearch (9200), 9905 the API's debugger;
9906 is the dashboard's, in `datyx-dashboard/`. Every published port
binds to `DATYX_BIND_HOST` (127.0.0.1). The demos take 88xx and 89xx,
HealthHub 98xx; datyx stays in 99xx.

Settings come from the environment, else `.env` (`scripts/env.sh`), else
their defaults, as `.env.example` lists them: the ports, the bind host,
`DATYX_DB_ADMIN_PASSWORD`, `DATYX_DB_PASSWORD`, `OPENMETADATA_DB_PASSWORD`,
`API_MODE`, the authentication settings `OIDC_CLIENT_ID`,
`OIDC_ISSUER`, `OIDC_EXTRA_AUDIENCES` ([auth.md](auth.md)) and the
master key `DATYX_MASTER_KEY` ([profiles.md](profiles.md); required by
the packaged API and Docker, a development key in dev mode), which
`scripts/api.sh` and the `api` compose service pass to the API. Secrets
reach processes through their environment only.

## Development data

Dev mode (`API_MODE=dev`, `quarkus:dev`) runs Flyway with a second
location, `db/devdata`, Java migrations seeding development records:
HealthHub's database as a data source in every profile
([api.md](api.md)). The jar, the native executable and Docker run the
schema migrations only.

## Version and build

X.Y.Z: `version.X.txt`, `version.Y.txt`, and the build time as
`YYYYMMDDHHMM` (`scripts/version.sh`), passed to Maven as `-Drevision`
(`datyx-api/pom.xml`'s version is `${revision}`, default `0.1.0-SNAPSHOT`)
(the dashboard has its own version files and gets it as a Flutter define).
`scripts/build.sh` builds `jar` (`datyx-api/target/quarkus-app/quarkus-run.jar`),
`native` (`datyx-api/target/datyx-runner`), `test` (`./mvnw verify`) and
`image` (`docker compose build api`), only when the output is older than
its sources or the version files; the Makefile delegates to it.
`group.id.txt` and `artifact.id.txt` hold the Maven coordinates, both
`datyx`; the dashboard's are `datyx:datyx-dashboard`.

## Agent and editor files

`AGENTS.md` (review before committing, project notes), `CLAUDE.md` (keeps
the specs current, one PR per change), `.vscode/settings.json`,
`.gitignore`, `.dockerignore` (what the images get: the API's sources and
the version files).
