# Development environment

The dashboard is a folder of its own, laid out like the demos (devbox,
process-compose, Docker Compose, the id and version files, scripts and
specs), holding only the Flutter app and what serves it. The API it shows
is the `datyx/` folder's; the two, with HealthHub, are the datyx group,
started and stopped together (`./start-datyx.sh` at the repository root).

## Toolchain

`devbox.json`: Flutter, make and curl, with the demos' `devbox.lock`
(Flutter 3.47.0, Dart 3.13.0), so they share one Nix store. Docker is
needed only for `compose.yaml`.

## Services

`devbox services up` runs `process-compose.yaml`:

- `2-flutter-web`: the dashboard (`scripts/flutter-web.sh`), by `WEB_MODE`:
  `release` (default: the release web build and the web server, built
  when stale, see [dashboard.md](dashboard.md)) or `debug` (Flutter's dev
  server with hot reload; `devbox run web`). Either proxies `/api/` and
  `/q/` to the API at `DATYX_API_URL`, answering 502 there until the API
  is up; the dashboard does not wait for the API, since that is another
  folder's service. Readiness: `/app/`. Shutdown kills whatever listens
  on its port.
- `0-health-check`: `scripts/health-check.sh`, after the dashboard is
  ready. Prints where to open it, then one line per interval: 🖥 Dash
  (`/app/`), 🔌 API (`/api/hello` at `DATYX_API_URL`), 🔀 Proxy
  (`/api/health` through the dashboard's origin, the path the
  repository's `start-all.sh` checks).

`compose.yaml` (project `datyx-dashboard`) holds the dashboard for Docker
alone: `web`, built from `docker/web.Dockerfile` (the release web build
under nginx, `docker/nginx.conf.template` proxying `/api/` and `/q/` to
`DATYX_API_URL`, by default the host's port 9900 through
`host.docker.internal`, which `extra_hosts` maps to the host gateway on
Linux too, where that is the bridge and a port bound to 127.0.0.1 isn't
reachable: there, `compose.datyx.yaml` added as a second `-f` file joins
the datyx stack's network (`datyx_default`, external) and sets
`DATYX_API_URL` to `http://api:9900`; only `DATYX_*` variables are substituted in the template, so
nginx's own variables stay). Healthy once `/app/` and `/api/health`
through the proxy both answer. The API runs from `datyx/`, with devbox or
its own `docker compose up`.

## Ports and settings

9906 the dashboard (`FLUTTER_WEB_PORT`), the port it had inside datyx;
9900 the API it calls (`API_PORT`, the name `start-all.sh` reads, or the
whole address as `DATYX_API_URL`). The published port binds to
`DATYX_BIND_HOST` (127.0.0.1), the same setting as datyx's. The demos
take 88xx and 89xx, HealthHub 98xx, datyx 99xx.

Settings come from the environment, else `.env` (`scripts/env.sh`), else
their defaults, as `.env.example` lists them: `DATYX_BIND_HOST`,
`FLUTTER_WEB_PORT`, `API_PORT`, `DATYX_API_URL`, `WEB_MODE`. There are no
secrets.

## Version and build

X.Y.Z: `version.X.txt`, `version.Y.txt`, and the build time as
`YYYYMMDDHHMM` (`scripts/version.sh`), passed to Flutter as the
`DATYX_VERSION` define and the build name. `scripts/build.sh` builds `web`
(`datyx_dashboard/build/web/`, through `scripts/make.sh`, under `/app/`
calling its own origin, with the settings recorded beside it in
`.datyx-services`) and `web_server` (`datyx_dashboard/build/web_server`),
only when the output is older than its sources or the version files, one
Flutter web build at a time across the repository through a lock in the
system's temp folder; the Makefile delegates to it, and adds `test`
(`flutter analyze`, `flutter test`), `image` (`docker compose build web`)
and `clean`. `group.id.txt` and `artifact.id.txt` hold the coordinates,
`datyx:datyx-dashboard`.

## Dev container

No dev container of its own: it runs in the datyx group's,
**datyx demos** (`.devcontainer/datyx/devcontainer.json` at the
repository root), with the datyx API and HealthHub. Its image,
`docker.io/aletyxcode/samples-and-demos-datyx` (`bash
image/build-image.sh datyx`), carries Flutter, GraalVM, the API's Maven
dependencies and the dashboard's release web build, so the API it needs
runs there too. `DEMOS_GROUP=datyx` makes the root `start-all.sh`,
`stop-all.sh` and `build-all.sh` act on the group, and `post-start.sh`
starts the index page and then the group, the dashboard on 9906
(`DATYX_BIND_HOST=0.0.0.0`, public in a codespace). The start-up log is
`startup.log` at the repository root.

## Agent and editor files

`AGENTS.md` (review before committing, project notes), `CLAUDE.md` (views
here, data and logic in the API; keeps the specs current, one PR per
change), `.vscode/settings.json`, `.gitignore`, `.dockerignore` (what the
image gets: the app's sources, the version and build scripts, nginx's
template).

## Known limitations

- The Docker image hasn't been built yet; it is HealthHub's web image
  with the API address as a template variable.
- No release, deploy or CI workflows.
