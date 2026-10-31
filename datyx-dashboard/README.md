# datyx-dashboard

The datyx dashboard: a Flutter web app, in the aityx palette like every
demo's app, that invokes the [datyx API](../datyx/) and shows what it
answers, with every call in a side panel. Views only: the data and the
logic live in the API, which runs from the `datyx/` folder. The two are
one system in two folders, started together with HealthHub as the datyx
group.

## Run it

From the repository root, the whole group:

```bash
./start-datyx.sh               # the datyx group: the API, the dashboard and HealthHub
./stop-datyx.sh
```

Or from this folder, with the API already running from `../datyx/`:

```bash
cp .env.example .env         # optional: ports, bind address, WEB_MODE
devbox services up           # the dashboard and its health monitor
devbox services up -b        # the same, detached; devbox services attach to watch
devbox services stop
```

Devbox installs the toolchain from [devbox.json](devbox.json): Flutter,
make and curl, with the demos' [devbox.lock](devbox.lock). `devbox
services up` runs [process-compose.yaml](process-compose.yaml): the
dashboard's release build served by a small native server
([scripts/flutter-web.sh](scripts/flutter-web.sh)), built first when
stale ([scripts/build.sh](scripts/build.sh), a minute or two the first
time), and the health monitor ([scripts/health-check.sh](scripts/health-check.sh)),
which prints where to open it and then one status line per interval.

| What | Where |
|---|---|
| The dashboard | http://localhost:9906/app/ |
| The API, through the dashboard | http://localhost:9906/api/health, Swagger UI at `/q/swagger-ui`: the same paths on the API's own port, 9900, proxied |

The dashboard calls `/api/` and `/q/` on its own origin; the web server
(and the dev server, and nginx under Docker Compose) proxies them to the
API at `DATYX_API_URL`, the host's port 9900 unless set
([.env.example](.env.example)). There is no CORS to set up, and a
forwarded port works. Until the API is up, those paths answer 502 and the
dashboard shows the API as down.

The port, 9906, is datyx's dashboard port from the start; the datyx group
has 99xx (the API and its containers) and 98xx (HealthHub), the demos
88xx and 89xx.

`devbox run web` runs the dashboard on Flutter's dev server instead, with
hot reload (`WEB_MODE=debug`).

### With Docker alone

```bash
docker compose up            # the release build under nginx
docker compose up -d --wait  # detached, back when it is healthy
```

[docker/web.Dockerfile](docker/web.Dockerfile) builds the release web
build and serves it with nginx under `/app/`, proxying `/api/` and `/q/`
to `DATYX_API_URL` ([docker/nginx.conf.template](docker/nginx.conf.template)),
by default the host's port 9900 through `host.docker.internal` (Docker
Desktop; on Linux add `-f compose.datyx.yaml` to join the datyx stack's
network and reach its `api` service by name instead), so it
reaches the API whether that runs from devbox or from datyx's own
`docker compose up`. The container is healthy once the app and the API
through the proxy both answer.

## The dashboard (datyx_dashboard/)

One screen, five tabs: Data sources, the ones on record with a dialog
to add one and a button to remove one; Catalog, what datyx makes of the
data in each source (not read yet, so each shows as not catalogued);
Audit, every call made: method, path, status, time, and the request and
response bodies; Health, status cards (API with its profile and mode,
PostgreSQL, OpenMetadata, sign-in) from `/api/health`, refreshed every
15 s, and the
dashboard's own version; Profile, the signed-in user's profile and its
identities. A reload keeps the open tab (in the address, `?tab=`), the
sign-in and the audit (in the browser tab's session storage). See
[specs/dashboard.md](specs/dashboard.md).

## Build

```bash
devbox shell                 # Flutter on the PATH
make                         # web and web_server: what the services serve
make web                     # datyx_dashboard/build/web/ (scripts/make.sh)
make test                    # flutter analyze and flutter test
make image                   # docker compose build web
```

### Version

X.Y.Z: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time as `YYYYMMDDHHMM`
([scripts/version.sh](scripts/version.sh)), compiled in as
`DATYX_VERSION` and shown in the app bar. The coordinates are
`datyx:datyx-dashboard` ([group.id.txt](group.id.txt),
[artifact.id.txt](artifact.id.txt)): the `datyx` group, with the API
(`datyx:datyx`) and HealthHub (`datyx:healthhub`).

## Layout

- [datyx_dashboard/](datyx_dashboard/): the Flutter project, with the web
  server that serves its release build (`bin/web_server.dart`).
- [compose.yaml](compose.yaml): the dashboard as a container, for Docker
  alone.
- [process-compose.yaml](process-compose.yaml): what `devbox services up`
  runs, with its readiness probe and the health monitor.
- [scripts/](scripts/): `flutter-web.sh`, `build.sh` (web, web_server),
  `make.sh` (the Flutter builds), `health-check.sh`, `env.sh` (settings
  from the environment or `.env`), `version.sh`.
- [docker/](docker/): the Dockerfile and nginx's config template.
- [specs/](specs/): the specification and the history of requests.

## Sign-in

When the datyx API has `OIDC_CLIENT_ID` set (see `../datyx/.env.example`),
the dashboard shows Google's sign-in button, signs the user in with the
client id the API publishes at `GET /api/auth/config`, and sends the ID
token with every call; the data sources then show who added them. The
dashboard itself needs no setting for this. See
[specs/dashboard.md](specs/dashboard.md).
