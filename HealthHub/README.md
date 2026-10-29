# HealthHub

HealthHub is the next demo, and the first with a database: a Flutter app,
a Dart API and PostgreSQL, laid out like Mortgage Hub, Contact Hub and
PokerFace so the same scripts, dev containers and launchers run it. For
now the app is a map: the index, for someone not signed in, shows where
they are with a welcome over it, and home, after signing in, is a
dashboard whose one tile is the same map. What HealthHub does with
[aityx.ai](https://aityx.ai) comes next.

## Technology

| Part | Technology |
|---|---|
| App ([healthhub_app/](healthhub_app)) | [Flutter](https://flutter.dev) (Dart): web, Android, iOS and Linux from one codebase |
| API ([healthhub_api/](healthhub_api)) | Dart (`dart:io`) with the [postgres](https://pub.dev/packages/postgres) package: holds the [aityx](https://aityx.ai) key, talks to the database, serves `/api/hello` and `/api/health`, verifies Google sign-ins ([openid_client](https://pub.dev/packages/openid_client)) and passes the user's token on to the datyx API |
| Database | [PostgreSQL](https://www.postgresql.org) 17, the `postgres` service of [compose.yaml](compose.yaml); the API makes its own tables |
| Dev environment | [Devbox](https://www.jetify.com/devbox) (Nix) in a [Dev Container](https://containers.dev/), process-compose for the services, Docker for the database; or [Docker Compose](compose.yaml) for everything |

The toolchain is pinned in [devbox.json](devbox.json) and locked in
[devbox.lock](devbox.lock): Flutter, GNU Make and curl. It is the same
lock as Mortgage Hub's and Contact Hub's, so they share one Nix store.
PostgreSQL is not in it: it runs as a container, so
[Docker](https://docs.docker.com/get-docker/) is needed too.

## Run it locally with devbox

1. Install [Devbox](https://www.jetify.com/devbox/docs/installing_devbox/)
   and have Docker running.
2. Optionally put your [aityx](https://aityx.ai) key in `.env` (copy
   [.env.example](.env.example)): the same `AITYX_API_KEY` as Mortgage
   Hub's, for instance `grep '^AITYX_' ../MortgageHub/.env > .env`.
   Nothing calls aityx yet; the app only reports whether the key is set.
   The database's development password and port are in `.env.example`
   too, with defaults.
3. From this folder:

   ```bash
   devbox services up           # add --pcflags "--tui=false" when not in a terminal
   ```

That starts, from [process-compose.yaml](process-compose.yaml):

| URL | What |
|---|---|
| http://localhost:9801/app/ | The app's release build, served by a small native web server ([scripts/flutter-web.sh](scripts/flutter-web.sh)). The first start builds it (about 25 s on a laptop, a minute or two on a 4-core codespace); later starts reuse it until the app changes |
| http://localhost:9802/api/health | The API, compiled to a native executable ([scripts/api.sh](scripts/api.sh)); the web app reaches it as `/api/` on its own origin, through the web server's proxy. `/api/hello` is the greeting, from the database |
| localhost:9803 | PostgreSQL, the `postgres` container of [compose.yaml](compose.yaml), started with `docker compose up postgres` ([scripts/infra.sh](scripts/infra.sh)); its data in a Docker volume. `bash scripts/infra.sh psql` opens a prompt on the `healthhub` database |

That's what Docker Compose serves too. For hot reload while working on
the app, run the Flutter dev server instead, with
`WEB_MODE=debug devbox services up`, or on its own with `devbox run web`
(press `r` in its terminal). `devbox run build` builds the web build and
the executables ahead of time ([scripts/build.sh](scripts/build.sh)),
only what changed; `devbox run db` starts only the database.

The ports are 9801 to 9803, so HealthHub runs alongside Mortgage Hub
(8880), Contact Hub (8890) and PokerFace (8910). The app opens on the
index: a map filling the screen, the browser asking to share your
location, an orange dot where you are, and **Welcome to HealthHub** with
the sign-in over it. Signing in leads home, a dashboard with the same
map as its tile (see [Index](specs/index.md), [Home](specs/home.md) and
[The map](specs/map.md)). `/api/hello` still answers from PostgreSQL.

Once everything is ready, the `health-check` monitor prints where to open
the app (in a codespace, its forwarded URL too), waits 5 s
(`HEALTH_CHECK_DELAY`), then logs one line every 15 s
(`HEALTH_CHECK_INTERVAL`); 🐘 Postgres is the API's own connection, and
🤖 [aityx](https://aityx.ai) is ⚪ when the API has no key:

```
HealthHub is up. Open the app at:
  http://localhost:9801/app/
Health checks start in 5 s, then every 15 s.
2026-10-28 17:02:10 🌐 Web ✅ · 🔌 API ✅ · 🐘 Postgres ✅ · 🤖 aityx ⚪
```

Stop everything with `devbox services stop`; the database's data stays in
its volume (`bash scripts/infra.sh down -v` drops it). To run only the
app, use `devbox run web`, the dev server with hot reload (set
`FLUTTER_WEB_PORT` to change the port, `WEB_MODE=release` for the release
build); only the API, `devbox run api` (`API_PORT`; it needs the database).

### Testing

`dart test` in `healthhub_api/` checks the routes and the web server
without a database; `flutter test` in `healthhub_app/` the index and home
with a fake API, sign-in and location. The database round trip is checked by running the stack:
`/api/hello` answers from PostgreSQL and the health monitor's 🐘.

### Building the binaries

The [Makefile](Makefile) builds release binaries through
[scripts/make.sh](scripts/make.sh):

```bash
make            # every platform this host can build
make web        # healthhub_app/build/web/
make android    # healthhub_app/build/app/outputs/flutter-apk/app-release.apk
make ios        # healthhub_app/build/ios/iphoneos/Runner.app (macOS, unsigned)
make linux      # healthhub_app/build/linux/<arch>/release/bundle/ (Linux only)
make clean
```

Pass `MODE=profile` or `MODE=debug` for other build modes, and
`IOS_CODESIGN=1` to sign the iOS build (this needs a signing team in Xcode).
The version is `X.Y.Z`: X and Y from [version.X.txt](version.X.txt) and
[version.Y.txt](version.Y.txt), Z the build time (see
[scripts/version.sh](scripts/version.sh)).
The artifact's group and artifact IDs, `datyx:healthhub`, are in
[group.id.txt](group.id.txt) and [artifact.id.txt](artifact.id.txt).

## Run it with Docker Compose

With only [Docker](https://docs.docker.com/get-docker/) installed (no
devbox, no Flutter), from this folder:

```bash
docker compose up --build
```

and open http://localhost:9801/app/. [compose.yaml](compose.yaml) builds
and starts three services:

| Service | What |
|---|---|
| `postgres` | PostgreSQL 17, with the `healthhub` database and user made on the first start by [docker/postgres-init.sh](docker/postgres-init.sh); its data in the `postgres-data` volume, published on 127.0.0.1:9803 |
| `api` | The API compiled to a native executable ([healthhub_api/Dockerfile](healthhub_api/Dockerfile)); not published, reached only through `web`; starts once `postgres` is healthy |
| `web` | The app's release web build ([docker/web.Dockerfile](docker/web.Dockerfile)), served by nginx under `/app/`, with `/api/` proxied to the API ([docker/nginx.conf](docker/nginx.conf)) |

For the key, copy [.env.example](.env.example) to `.env` and fill in
`AITYX_API_KEY` (or export it); it goes to the API only, as does the
database password. The first build takes a few minutes (it downloads
Flutter); later ones reuse Docker's cache. Set `FLUTTER_WEB_PORT` to
change the port; the app and the database are bound to 127.0.0.1 unless
you set `HEALTHHUB_BIND_HOST=0.0.0.0`. Stop it with `docker compose
down` (`-v` drops the data). Every service has a health check, so
`docker compose up --wait` returns once they are healthy. There is no hot
reload: rebuild after a change.

## Run it in a codespace

[![Open HealthHub and the other datyx demos in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/aityx-labs/aityx-demos?devcontainer_path=.devcontainer%2Fdatyx%2Fdevcontainer.json&machine=standardLinux32gb)

That link opens this repository's **datyx demos** dev container on an
4-core machine (16 GB RAM), the largest the organization allows; a tight
fit for Elasticsearch, OpenMetadata and the Flutter builds together. It starts HealthHub with the rest
of its group, the datyx demos (the datyx API and the datyx dashboard),
and the index page that links them. To choose for yourself instead, use
*Code → Codespaces → New with options* and pick **datyx demos** as the
dev container configuration — the repository holds two groups of demos,
each with its own, so the configuration matters.

The codespace uses your [aityx](https://aityx.ai) key, the same
`AITYX_API_KEY` Codespaces secret as Mortgage Hub's and Contact Hub's.
GitHub keeps Codespaces secrets per user and grants them per repository,
so if your key already reaches this repository, there is nothing to do.
Otherwise add it at
[github.com/settings/codespaces](https://github.com/settings/codespaces)
(**New secret**, name `AITYX_API_KEY`, access to
`aityx-labs/aityx-demos`), or enter it when GitHub asks on the creation
page. Nothing calls aityx yet, so the app works without it.

The dev container adds Docker (the `docker-in-docker` feature) for the
databases. On first start,
[on-create.sh](../.devcontainer/on-create.sh) restores the group's
release web builds from the published image,
[update-content.sh](../.devcontainer/update-content.sh) builds what
changed since the image was made, and
[post-create.sh](../.devcontainer/post-create.sh) says whether your key
arrived. Then, on that and every later start,
[post-start.sh](../.devcontainer/post-start.sh) starts the datyx index
page and the datyx group in the background with `./start-all.sh` and makes
their web ports public, HealthHub's **9801** among them. There is
nothing to run: once the app is up, open port 9801 from the **Ports**
panel, or HealthHub's card on the datyx index page (port 9800, which
Codespaces opens in a browser tab for you). Its bare URL redirects to
the app at `/app/`. The API (9802) and the database (9803) stay inside
the codespace.

Watch HealthHub's services with `process-compose attach -U -u
/tmp/aityx-demos-HealthHub.sock` (or `devbox services attach` on a
laptop). Stop the group with `./stop-all.sh` from the root and start it
again with `./start-all.sh`: in the codespace both act on the datyx
group only (`DEMOS_GROUP=datyx`).

**If the app doesn't start, send us `startup.log` from the root of the
repository.** Every step of the codespace's start goes there,
timestamped, including a line saying when each demo's web app and API
first answered. It holds no secrets.

**Check the port's visibility.** In the **Ports** panel, the
*Visibility* column for 9801 should say **Public**. If it says
**Private**, right-click the port, choose **Port Visibility → Public**
and reload the app.

## Run it in a dev container locally

Open the repository root in VS Code and choose **Reopen in Container**,
then **datyx demos**. The dev containers live at the root of the
repository, in [.devcontainer/](../.devcontainer), because that is where
GitHub looks for them: one per demo group, HealthHub's in
[.devcontainer/datyx/](../.devcontainer/datyx). It runs the datyx
group's published image, `docker.io/aletyxcode/samples-and-demos-datyx`
(built by `bash image/build-image.sh datyx`, see [image/](../image)),
plus Docker for the databases.

## Contributing

1. Create a branch from an up-to-date `main`.
2. Make one change per pull request, with its tests. Run `flutter analyze`
   and `flutter test` in `healthhub_app/`, `dart analyze` and `dart test`
   in `healthhub_api/`, and start the stack to see `/api/hello` answer
   from the database.
3. Update the matching feature spec in [specs/](specs/) and add an entry to
   [specs/requests.md](specs/requests.md).
4. Open a pull request against `main`.

## Learn more

- [specs/](specs/README.md): the specification of every feature.
- [Database](specs/database.md): PostgreSQL, how it runs and what the
  API keeps in it.

## Sign-in

HealthHub is part of the datyx group and signs its users in with Google
through OpenID Connect. Put the `healthhub` OAuth client's id in `.env`
as `OIDC_CLIENT_ID` (see [.env.example](.env.example)) and the app shows
Google's sign-in button on the index, the API verifies the ID token on
every call, and the same token goes on to the datyx API when HealthHub
calls it, so datyx sees the same person (its `OIDC_EXTRA_AUDIENCES` lists this client).
Without a client id everything is anonymous. See [specs/api.md](specs/api.md)
and [specs/index.md](specs/index.md).
