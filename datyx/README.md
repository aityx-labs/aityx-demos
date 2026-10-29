# datyx

The datyx system's API: a Quarkus API on GraalVM with its PostgreSQL
database and an [OpenMetadata](https://open-metadata.org) server. The
whole stack starts with one command, on a laptop with
[Devbox](https://www.jetify.com/devbox) or anywhere with Docker Compose.

This folder is API only. **Data and logic live here**, in
[datyx-api/](datyx-api/); **views live in the dashboard**,
[../datyx-dashboard/](../datyx-dashboard/), a Flutter app in a folder of
its own that only invokes this API and shows the details of each call.
The API, the dashboard and [HealthHub](../HealthHub/) are the datyx
group, started and stopped together.

## Run it

From the repository root, the whole group:

```bash
./start-datyx.sh               # the datyx group: the API, the dashboard and HealthHub
./stop-datyx.sh
```

Or from this folder, the API alone:

```bash
cp .env.example .env         # optional: ports, passwords, API_MODE
devbox services up           # PostgreSQL, Elasticsearch, OpenMetadata, the API
devbox services up -b        # the same, detached; devbox services attach to watch
devbox services stop
```

Devbox installs the toolchain from [devbox.json](devbox.json): GraalVM CE
(the JDK the API runs on, with `native-image`), Maven, make, curl and jq.
`devbox services up` runs [process-compose.yaml](process-compose.yaml):
PostgreSQL, Elasticsearch and OpenMetadata as the containers of
[compose.yaml](compose.yaml) (one `docker compose up <service>` each, so
Docker must be running) and the API on the host's GraalVM in Quarkus dev
mode with live reload ([scripts/api.sh](scripts/api.sh)). A first start
takes a few minutes: OpenMetadata migrates its schema before its server
comes up and Maven downloads the API's dependencies. The health monitor
([scripts/health-check.sh](scripts/health-check.sh)) prints where to open
things once everything answers, then one status line per interval.

| What | Where |
|---|---|
| The API | http://localhost:9900/api/hello, status at [/api/status](http://localhost:9900/api/status), health at [/api/health](http://localhost:9900/api/health), OpenAPI at [/q/openapi](http://localhost:9900/q/openapi), Swagger UI at [/q/swagger-ui](http://localhost:9900/q/swagger-ui) |
| The dashboard | http://localhost:9906/app/, from [../datyx-dashboard/](../datyx-dashboard/) when the group is up |
| PostgreSQL | `localhost:9901`, databases `datyx` (user `datyx`) and `openmetadata_db` (user `openmetadata_user`) |
| OpenMetadata | http://localhost:9902/, sign in as `admin@open-metadata.org` / `admin`; admin port 9903 (`/healthcheck`) |
| Elasticsearch | http://localhost:9904/, OpenMetadata's search index |
| The API's debugger | `localhost:9905`, in dev mode |

datyx lives in the aityx-demos repository and starts like the demos
(`./start-all.sh` waits for it on the API's `/api/health`, since it has no
web app of its own). It takes port 9900 and the 99xx range so it never
collides with the demos (88xx and 89xx) or HealthHub (98xx). Every port,
the bind address and the passwords are settings: see
[.env.example](.env.example). The containers keep their data in Docker
volumes (`datyx_postgres-data`, `datyx_search-data`);
`bash scripts/infra.sh down -v` drops them.

`devbox run api` runs the API alone, without the containers.

### With Docker alone

```bash
docker compose up            # the stack, with the API built in its image
docker compose up -d --wait  # detached, back when everything is healthy
```

The API's image is [docker/api.jvm.Dockerfile](docker/api.jvm.Dockerfile),
the packaged app on the GraalVM JDK; `DATYX_API_DOCKERFILE=docker/api.native.Dockerfile`
builds the native executable instead (give Docker 6 GB or more). The API
is published on 9900, where the dashboard's own `docker compose up`
reaches it.

## The API (datyx-api/)

A Quarkus 3 REST API, package `datyx`, built by Maven ([datyx-api/pom.xml](datyx-api/pom.xml),
[datyx-api/mvnw](datyx-api/mvnw)): Quarkus REST with Jackson, Hibernate ORM
with Panache on PostgreSQL, Hibernate Validator, SmallRye Health and
OpenAPI, and a REST client for OpenMetadata.

- `GET /api/hello` (`?name=` greets by name).
- `GET /api/status`: the system as the API sees it: name, version, uptime,
  PostgreSQL (ok, version), OpenMetadata (ok, version, URL), the number of
  greetings on record.
- `GET /api/greetings` lists the greetings on record, newest first;
  `POST /api/greetings {"message":"..."}` stores one (the `Greeting`
  Panache entity). Hibernate keeps the schema in dev (`update`);
  production leaves it alone.
- `/api/datasources`: the data sources on record, the first entity:
  databases, S3 buckets and folders with their access details (secrets
  never answered back), listed, added (`POST`) and removed (`DELETE`),
  within the caller's profile. See
  [specs/data-sources.md](specs/data-sources.md).
- `/api/profile`: the caller's profile, made the first time an identity
  signs in, which owns their data sources and holds a key of its own:
  the access details of its sources are encrypted with it at rest, the
  profile keys with the master key `DATYX_MASTER_KEY` (`openssl rand
  -base64 32` into `.env`; a development key in dev mode). See
  [specs/profiles.md](specs/profiles.md).
- Authentication: OpenID Connect with Google. Set `OIDC_CLIENT_ID` in
  `.env` (the `datyx` OAuth client's id) and the data sources and
  `GET /api/me` want a signed-in user, whose ID token the API verifies
  against Google's keys; `GET /api/auth/config` tells the apps how to
  sign in, and `OIDC_EXTRA_AUDIENCES` lets HealthHub's tokens through so
  the same person reaches datyx from there. Without a client id
  everything is open. See [specs/auth.md](specs/auth.md).

## Build

```bash
devbox shell                 # GraalVM and Maven on the PATH
make                         # jar: what the services serve with API_MODE=jar
make jar                     # datyx-api/target/quarkus-app/quarkus-run.jar
make native                  # datyx-api/target/datyx-runner, by GraalVM native-image
make test                    # ./mvnw verify (a Postgres test container)
make image                   # docker compose build api
```

`API_MODE=jar` or `API_MODE=native` makes `devbox services up` serve a
build of the API instead of dev mode, built first when stale
([scripts/build.sh](scripts/build.sh)).

### Version

X.Y.Z: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time as `YYYYMMDDHHMM`
([scripts/version.sh](scripts/version.sh)). The scripts pass it to Maven
as `-Drevision`; a bare `./mvnw` builds `0.1.0-SNAPSHOT`. The Maven
coordinates are `datyx:datyx` ([group.id.txt](group.id.txt),
[artifact.id.txt](artifact.id.txt)); the dashboard's are
`datyx:datyx-dashboard`, HealthHub's `datyx:healthhub`.

## Layout

- [datyx-api/](datyx-api/): the API, a Maven project.
- [compose.yaml](compose.yaml): every service as a container, for Docker
  alone and for the infrastructure under devbox.
- [process-compose.yaml](process-compose.yaml): what `devbox services up`
  runs, with readiness probes and the health monitor.
- [scripts/](scripts/): `api.sh`, `infra.sh` (the containers), `build.sh`
  (jar, native, test, image), `health-check.sh`, `env.sh` (settings from
  the environment or `.env`), `version.sh`.
- [docker/](docker/): the API's Dockerfiles and PostgreSQL's init script
  (the two databases and their users).
- [specs/](specs/): the specification, one file per feature, and the
  history of requests.
