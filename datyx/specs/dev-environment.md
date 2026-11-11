# Development environment

## Toolchain

`devbox.json`: GraalVM CE (`graalvmPackages.graalvm-ce`, the JDK the API
runs on, with `native-image`), Maven, make, curl, jq. The shell's init
hook sets `JAVA_HOME` to the GraalVM. Docker must run on the host for the
containers and the tests. Flutter is not here: the dashboard is the
`datyx-dashboard/` folder's, with its own toolchain. The trainer's
XGBoost4J needs an OpenMP runtime outside devbox: on macOS Homebrew's
`libomp` (`brew install libomp`); on Linux GCC's `libgomp` (the dev
container's, and the JVM image installs it). Without it the API runs,
and its training runs fail saying so ([training.md](training.md)).

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
  interval: 🔌 API (`/api/health/live`), 🐘 Postgres (the datasource check in
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
context, see `.dockerignore`; built and run with the Quarkus profile
`DATYX_API_PROFILE`, `dev` by default, the Dockerfiles' `PROFILE`
argument, `prod` when built without compose), published on `API_PORT` (9900) so the
dashboard's own compose file reaches it; on Linux the dashboard and
HealthHub join this stack's network through their `compose.datyx.yaml`
instead, since a port bound to 127.0.0.1 isn't reachable from the bridge. Data lives in the `postgres-data` and
`search-data` volumes.

`k8s/` runs the same services on the repository's local Kubernetes
cluster (kind, `../k8s/`), in the datyx group's namespace, `datyx`:
`bash k8s/deploy.sh datyx` at the repository root builds the API's image
(`k8s/build.sh`: `docker/api.jvm.Dockerfile` with the dev profile, plus
Swagger UI through the Dockerfile's `PACKAGE_ARGS`), applies the
manifests and runs `k8s/verify.sh`. The StatefulSets `datyx-postgres`
(its init script is `docker/postgres-init.sh`, a ConfigMap made by
`docker/kustomization.yaml`) and `datyx-search` (a 512 MB heap), the
Deployment `openmetadata` (the migration as an init container), and the
Deployment `datyx-api` (an init container waits for PostgreSQL, as
compose's `depends_on` does: the API exits when its database doesn't
answer), the Service `datyx-api:9900` that the dashboard
and HealthHub call. This host reaches the API on 19900 and OpenMetadata
on 19902. The API's settings are compose.yaml's with the cluster's hosts;
the aityx key, its staging URL and the service token come from the root
`.env` (the Secret `demo-env`). Sign-in is on there when that `.env` has
an `OIDC_CLIENT_ID`: Google's, with the root `.env`'s client, HealthHub's
(`healthhub`), whose origins list the dashboard's on the cluster
(`http://localhost:19906`, `../k8s/README.md`); without one it is off
and every call is the Local profile. Each Google user gets a profile of
their own, made with the dev data's HealthHub sources (Development data,
below), so the dashboard shows them from the first sign-in, and their
catalogue and models within minutes: the dev catalogue syncs and curates
a new profile's sources at its next half-minute tick
([curation.md](curation.md)), and the trainer then queues its initial
runs, five of them, 30 to 90 s each and one at a time, about 5 minutes
in all on the cluster's machine. The addresses that differ from a
laptop's are the API's environment, with no port forwarder in the pod
(one container, after the init container):

- the dev data's HealthHub sources at HealthHub's Services,
  `DATYX_HEALTHHUB_DB_HOST=healthhub-postgres`,
  `DATYX_HEALTHHUB_DB_PORT=5432` and
  `DATYX_HEALTHHUB_KAFKA=healthhub-kafka:19092` (a laptop's defaults are
  `localhost:9803` and `localhost:9804`,
  [data-sources.md](data-sources.md#development-data));
- OpenMetadata at its Service for the API's calls,
  `DATYX_OPENMETADATA_URL=http://openmetadata:8585`, and at this host's
  port for a browser, `DATYX_OPENMETADATA_PUBLIC_URL=http://localhost:19902`:
  `/api/health` reports the second and the dashboard's Health tab links
  to it ([api.md](api.md)).

A packaged API wants `DATYX_MASTER_KEY`: the root `.env`'s, else one
drawn at each start, which loses nothing as the dev profile empties the
database at every start. The dev-profile image answers only the localhost names and
`host.docker.internal` (`CallbackHostConfigSourceFactory` reads the
profile's defaults, not the environment), so the manifest lists the
Service's names in `quarkus.http.host-validation.allowed-hosts` and the
probes send `Host: localhost`. Training is sized for a shared machine:
four processors for the JVM, four threads for libtorch and OpenMP, two
malloc arenas, a 384 MB heap, in a 2 GiB limit: DeepAR's training peaks
near 1.2 GB of the process's own memory, and libtorch's 300 MB of files
count on top, which left the container standing at a 1536 MiB limit.
`k8s/verify.sh` checks, with sign-in on or off: the API ready and its
address for OpenMetadata opening from this host, sign-in (on: the
user's paths refuse an anonymous call; off: the caller's sources and
models through the API), HealthHub's two sources in every profile in
PostgreSQL, HealthHub's PostgreSQL and Kafka answering at the addresses
the API's container is given, asked from the datyx pods, HealthHub's
tables and topics in OpenMetadata, the training runs, and the aityx
gateway.

## Ports and settings

9900 the API, 9901 PostgreSQL, 9902 OpenMetadata (8585 inside), 9903 its
admin port (8586), 9904 Elasticsearch (9200), 9905 the API's debugger;
9906 is the dashboard's, in `datyx-dashboard/`. Every published port
binds to `DATYX_BIND_HOST` (127.0.0.1). The demos take 88xx and 89xx,
HealthHub 98xx; datyx stays in 99xx.

Settings come from the environment, else `.env` (`scripts/env.sh`), else
their defaults, as `.env.example` lists them: the ports, the bind host,
`DATYX_DB_ADMIN_PASSWORD`, `DATYX_DB_PASSWORD`, `OPENMETADATA_DB_PASSWORD`,
`API_MODE`, `DATYX_API_PROFILE` (Docker's profile), the authentication settings `OIDC_CLIENT_ID`,
`OIDC_ISSUER`, `OIDC_EXTRA_AUDIENCES` ([auth.md](auth.md)) and the
master key `DATYX_MASTER_KEY` ([profiles.md](profiles.md); required by
the packaged API and Docker, a development key in dev mode), and the
catalogue's sign-in to OpenMetadata, `DATYX_OPENMETADATA_TOKEN` or
`DATYX_OPENMETADATA_EMAIL` and `DATYX_OPENMETADATA_PASSWORD` (the stack's
admin by default; [catalog.md](catalog.md)), and OpenMetadata's webhook
back to the API, `DATYX_OPENMETADATA_CALLBACK_URL` (empty: the API as
OpenMetadata reaches it, `http://host.docker.internal:{API port}/api/catalog/openmetadata-events`
from the host, `http://api:9900/...` in Docker Compose) and
`DATYX_OPENMETADATA_WEBHOOK_SECRET` (empty: drawn at each start), and
aityx's ([aityx.md](aityx.md)): datyx's key `AITYX_API_KEY`, aityx's URL
`DATYX_AITYX_URL` (else `AITYX_URL`, else `https://api.aityx.ai`), the
services' token `DATYX_SERVICE_TOKEN` and `DATYX_AITYX_SHARE_SERVICE_CALLS`,
and the addresses that depend on where the API runs:
`DATYX_OPENMETADATA_PUBLIC_URL`, where a browser opens OpenMetadata
(empty: the URL the API calls, right on a laptop; Docker Compose
defaults it to `http://localhost:{DATYX_OPENMETADATA_PORT}`, since its
API calls `http://openmetadata:8585`), and the development data's
HealthHub, `DATYX_HEALTHHUB_DB_HOST`, `DATYX_HEALTHHUB_DB_PORT`,
`DATYX_HEALTHHUB_DB_PASSWORD` and `DATYX_HEALTHHUB_KAFKA` (`localhost`,
9803, HealthHub's development password and `localhost:9804`), all of
which `scripts/api.sh` and the `api` compose service pass to the API.
The scripts pass these five only when set, and the API takes an empty
one as its default, so Compose's empty pass-through changes nothing.
`AITYX_API_KEY`, `AITYX_URL` and `DATYX_SERVICE_TOKEN` are also read
from the repository root's `.env` when datyx's has none: the file
HealthHub reads, so both share the key and the token. `.env.example`
names `AITYX_API_KEY` commented out, so the root `start-all.sh` doesn't
link datyx's `.env` to the root's. The API
on localhost allows the callback's host in the Host header too
(Quarkus's host validation; [catalog.md](catalog.md)). Secrets
reach processes through their environment only.

## Development data

The dev profile starts from an empty database, Flyway's `clean-at-start`:
every start (and every live reload's restart) drops the schema and
migrates from zero, so data sources and profiles made in development don't
outlive it. It runs Flyway with a second location, `db/devdata`, Java
migrations seeding development records, and sets
`datyx.devdata.enabled`: HealthHub's database and its Kafka are data
sources of every profile, those there at start from the migration, the
Local one included, and each profile made later, by a first sign-in, as
it is made ([data-sources.md](data-sources.md#development-data)). So
with sign-in on, each user sees them at once. Reading them into the
catalogue wants HealthHub running (`./start-datyx.sh`) where the
`DATYX_HEALTHHUB_*` settings say: by default this host's ports 9803 and
9804, right for `devbox services up` and wrong inside a container. The
API of `docker compose up` therefore lists the two sources without
reading them, until those settings name a HealthHub its container
reaches (`compose.yaml` puts none on its network); the cluster's
manifest sets them. Development runs the dev
profile everywhere: `API_MODE=dev` (`quarkus:dev`, the default for
`devbox services up`) and Docker Compose (`DATYX_API_PROFILE=dev`, the
default). The jar and the native executable (`API_MODE=jar` or `native`)
and an image built with `DATYX_API_PROFILE=prod` run the schema
migrations only. `/api/health`'s `datyx` check says which profile and
launch mode run.

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
