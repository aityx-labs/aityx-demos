# Development environment

RiverRace's environment is Contact Hub's, with its own names and ports;
[Mortgage Hub's spec](../../MortgageHub/specs/dev-environment.md)
explains the reasons behind each piece.

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed, and is
  the same as Mortgage Hub's and Contact Hub's, so the three use the same
  Flutter (Dart 3.13.0) and share one Nix store. All require Dart SDK
  `^3.13.0`.
- `devbox services up` ([process-compose.yaml](../process-compose.yaml)),
  run in this folder, starts:
  - the web app (`2-flutter-web`, via
    [scripts/flutter-web.sh](../scripts/flutter-web.sh)) on
    http://localhost:8940/app/ (`FLUTTER_WEB_PORT`), bound to 127.0.0.1
    (`RIVERRACE_BIND_HOST`), with an HTTP readiness probe of up to 15
    minutes (a first start builds the app, and when every demo starts at
    once the builds take turns). In release mode, the default (`WEB_MODE`),
    it is the app's release build served by
    [riverrace_api/bin/web_server.dart](../riverrace_api/bin/web_server.dart)
    ([lib/web_server.dart](../riverrace_api/lib/web_server.dart)) compiled
    to a native executable, `riverrace_api/build/web_server`, about 20 MB
    resident: `/app/` from `riverrace_app/build/web/` (`WEB_ROOT`) with the
    right content types (`.wasm` included), `index.html` for the app's
    own routes, `Cache-Control: no-cache` with `Last-Modified` and 304 so
    a new build is seen on the next load and an unchanged file isn't
    downloaded again, and only files inside the build (`..` and escapes
    are refused); `/api/` and the bare `/` proxied to the API on
    127.0.0.1:`API_PORT`, same method, query, headers and body, 502 when
    the API is down. It serves what nginx serves under Docker Compose, so
    the two paths show the same app. With `WEB_MODE=debug` it is
    Flutter's dev server instead (`flutter run` on the `web-server`
    device, so no Chrome is needed, hot reload with `r`, about 1 GB
    resident), which proxies `/api/` itself (`web_dev_config.yaml`,
    generated from `API_PORT`, git-ignored). On stop, its shutdown command
    kills whatever listens on the port, so neither server keeps serving
    the old build;
  - the API (`3-api`, via [scripts/api.sh](../scripts/api.sh)) on
    http://localhost:8941 (`API_PORT`), `bin/server.dart` compiled to a
    native executable, `riverrace_api/build/server`, about 15 MB resident
    and up in a second (it finds the river model beside the binary,
    `build/../models/river.json`, as in the Docker image), with a readiness
    probe on `/api/health`. The script exports `AITYX_API_KEY` and
    `AITYX_URL` from the environment, else `.env`, to the server only.
    CORS allows the web app's origins (`ALLOWED_ORIGINS`);
  - the health monitor (`0-health-check`,
    [scripts/health-check.sh](../scripts/health-check.sh)), once both are
    ready. It first prints where to open the app,
    `http://localhost:8940/app/` and, in a codespace, the forwarded URL,
    and waits 5 s (`HEALTH_CHECK_DELAY`). Then every 15 s
    (`HEALTH_CHECK_INTERVAL`) one line with the time, 🌐 Web, 🔌 API
    (`/api/health`) and 🤖 aityx (✅ the API has its key, ⚪ it doesn't).
- The ports, 8940 and 8941, differ from Mortgage Hub's (8880, 8881) and
  Contact Hub's (8890, 8891), so all three can run at once.
- **Builds for the services**: [scripts/build.sh](../scripts/build.sh)
  (`devbox run build`; targets `web`, `web_server`, `api`, `all`) builds
  only what is missing or older than its sources: `web` runs
  `scripts/make.sh web` with `WEB_BASE_HREF=/app/` and an empty
  `API_BASE_URL`, compared against `lib/`, `web/`, `assets/`, the
  pubspecs and the version files, and also when the build doesn't record
  those settings (`build/web/.aityx-services`, written once a build
  succeeds and required to be newer than the build, so a `make web` by
  hand with other settings isn't reused); `web_server` and `api` run `dart compile exe`, compared
  against `bin/`, `lib/` and the pubspecs. The two scripts run it before
  serving, so a start after no change builds nothing and serves in
  seconds; a first start, or one after a change, takes the build (about
  20 s on a laptop, a minute or two on a 4-core codespace). One Flutter
  web build runs at a time across the repository's demos, through a lock
  directory in the system's temp folder
  (`aityx-demos-flutter-web-build.lock`, holding the builder's PID; a
  lock whose process is gone, or that never got its PID and is a minute
  old, is taken over), so starting every demo at once doesn't thrash a
  small machine; the checks run inside the lock, so two starts that
  overlap build once. The API's compiles share a lock of their own. `build/` is git-ignored.
- `devbox run web` runs only the web app, in debug mode (hot reload)
  unless `WEB_MODE=release`; `devbox run api` only the API.
- The web app calls the API at `API_BASE_URL` (a dart-define). The
  services leave it empty, in both modes: the app calls `/api/` on its own
  origin, which the web server (or the dev server) proxies to the API,
  with the bare `/` as well, which the API redirects to `/app/`.
  `scripts/make.sh` passes `API_BASE_URL`, or `http://localhost:8941`.
- `bash scripts/model-test.sh` runs strategies on aityx (see
  [Decisions](decisions.md#verified)); run it after changing the model or
  `lib/strategy.dart`.
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1 today), Z the build time as `YYYYMMDDHHMM` UTC; the build number is
  the same time in Unix seconds
  ([scripts/version.sh](../scripts/version.sh)). It reaches the app as the
  `RIVERRACE_VERSION` dart-define, shown in the app bar.
- **Coordinates**: the group ID `aityx` from `group.id.txt` and the artifact
  ID `riverrace` from `artifact.id.txt`; with the version, `aityx:riverrace:X.Y.Z`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web`, `android`, `ios` (macOS),
  `linux` (Linux), `all` (what the host can build) and `clean`, with
  `MODE`, `IOS_CODESIGN` and `WEB_BASE_HREF`.
- **Docker Compose** ([compose.yaml](../compose.yaml)): `docker compose up`
  runs the app with Docker alone on http://localhost:8940/app/, published
  on 127.0.0.1 unless `RIVERRACE_BIND_HOST` says otherwise. `web`
  ([docker/web.Dockerfile](../docker/web.Dockerfile)) builds the release
  web app with the Flutter devbox.lock pins and serves it with nginx under
  `/app/`, redirecting `/` and proxying `/api/` to `api`
  ([docker/nginx.conf](../docker/nginx.conf)). `api`
  ([riverrace_api/Dockerfile](../riverrace_api/Dockerfile)) is the server
  compiled with `dart compile exe`, run from `scratch` as user 65534 and
  not published; Compose passes it `AITYX_API_KEY` and `AITYX_URL` from
  the environment, else `.env`, and `web` gets neither. Both have health
  checks (`api` runs `/app/bin/server healthcheck`), and `web` starts once
  `api` is healthy.
- **Dev container**: the aityx group's
  ([.devcontainer/aityx/](../../.devcontainer/aityx)), named **aityx
  demos**, which RiverRace shares with Mortgage Hub, Contact Hub, Cellfie,
  PokerFace and RoboRules; the datyx group has its own, and there is no
  per-demo one. It runs the group's published image
  (`docker.io/aletyxcode/samples-and-demos-aityx`, built from
  [image/Containerfile](../../image/Containerfile) by `bash
  image/build-image.sh aityx`: Flutter 3.47.0, process-compose and the
  GitHub CLI, pinned and checksum-verified, and the six aityx demos'
  release web builds) with the scripts in
  [.devcontainer/](../../.devcontainer), which both groups share.
  `DEMOS_GROUP=aityx` makes them, and the root `start-all.sh`,
  `stop-all.sh` and `build-all.sh`, act on the folders whose
  `group.id.txt` says `aityx`. The demos run on the image's own Flutter
  and process-compose (`DEMOS_TOOLCHAIN=image`, see
  [demos-toolchain.sh](../../demos-toolchain.sh)): no devbox or Nix in a
  codespace. `on-create.sh` copies the group's release web builds from the
  image ([image/restore-builds.sh](../../image/restore-builds.sh), skipped
  for a folder that changed since the image was made: that app then builds
  itself); `update-content.sh` runs `build-all.sh` (RiverRace's compiled
  API and web server among the rest, a few seconds each); `post-create.sh`
  reports whether `AITYX_API_KEY` arrived (never its value);
  `post-start.sh` starts the index page and then the group detached with
  `start-all.sh` on every start (RiverRace's socket is
  `/tmp/aityx-demos-RiverRace.sock`), which logs when each demo's `/app/`
  and `/api/health` answer; `public-port.sh` makes the index's and the
  group's web ports public, 8940 among them (again on attach). Everything
  goes to `startup.log` at the root of the repository (see
  [startup-log.sh](../../.devcontainer/startup-log.sh)), git-ignored,
  which holds no secrets. The container sets `RIVERRACE_BIND_HOST=0.0.0.0`
  with the other demos' bind hosts, forwards the index's port 8800 and
  each demo's web port, 8940 among them, and adds the Dart and Flutter
  extensions. Measured with the former per-demo dev container: the
  codespace was available about three minutes after the request and the
  app answered within a minute after that.
- **Codespaces secrets**: the group's `devcontainer.json` declares `AITYX_API_KEY` and
  optional `AITYX_URL`,
  the same secret as Mortgage Hub's and Contact Hub's. Codespaces secrets
  belong to a user and are granted per repository, so a key granted to
  this repository for either reaches RiverRace too. GitHub asks for it on
  the creation page otherwise. `AITYX_URL` defaults to
  `https://api.aityx.ai`; `.env` overrides it. Both values are forwarded
  only to the API process. A local dev container uses `.env`.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) and
  the repository README have an **Open in GitHub Codespaces** badge with
  `devcontainer_path=.devcontainer/aityx/devcontainer.json` and
  `machine=standardLinux32gb`, the same link as every aityx demo's.

## Known limitations

- No release, deploy or CI workflows.
