# Development environment

RoboRules' environment is Contact Hub's (see its
[spec](../../ContactHub/specs/dev-environment.md)), with its own names and
ports:

- **Ports**: the web app on **8920**, the API on **8921**, so it runs
  alongside Mortgage Hub (8880/8881), Contact Hub (8890/8891) and the
  other samples in this folder (8900/8901, 8910/8911).
- `devbox services up` ([process-compose.yaml](../process-compose.yaml))
  starts:
  - the web app (`2-flutter-web`, via
    [scripts/flutter-web.sh](../scripts/flutter-web.sh)) on
    http://localhost:8920/app/ (`FLUTTER_WEB_PORT`), bound to 127.0.0.1
    (`ROBORULES_BIND_HOST`), with an HTTP readiness probe of up to 15
    minutes (a first start builds the app, and when every demo starts at
    once the builds take turns). In release mode, the default (`WEB_MODE`),
    it is the app's release build served by
    [roborules_api/bin/web_server.dart](../roborules_api/bin/web_server.dart)
    ([lib/web_server.dart](../roborules_api/lib/web_server.dart))
    compiled to a native executable, `roborules_api/build/web_server`,
    about 14 MB resident: `/app/` from `roborules_app/build/web/`
    (`WEB_ROOT`) with the right content types (`.wasm` included),
    `index.html` for the app's own routes, `Cache-Control: no-cache` with
    `Last-Modified` and 304 so a new build is seen on the next load and an
    unchanged file isn't downloaded again, and only files inside the
    build (`..` and escapes are refused); `/api/` and the bare `/` proxied
    to the API on 127.0.0.1:`API_PORT`, same method, query, headers and
    body, with no deadline of its own (a batch of turns waits as long as
    the API waits for aityx), 502 when the API is down. It serves what
    nginx serves under Docker Compose, so the two paths show the same app.
    With `WEB_MODE=debug` it is Flutter's dev server instead (`flutter run`
    on the `web-server` device, hot reload with `r`, about 1 GB resident),
    which proxies `/api/` itself (`web_dev_config.yaml`, generated from
    `API_PORT`, git-ignored). On stop, its shutdown command kills whatever
    listens on the port, so neither server keeps serving the old build;
  - the API (`3-api`, via [scripts/api.sh](../scripts/api.sh)) on
    http://localhost:8921 (`API_PORT`), `bin/server.dart` compiled to a
    native executable, `roborules_api/build/server`, about 13 MB resident
    and up in a second (it finds its models beside the binary,
    `build/../models/`, as in the Docker image), with a readiness probe on
    `/api/health`. The script exports `AITYX_API_KEY` and `AITYX_URL` from
    the environment, else `.env`, to the server only. CORS allows the web
    app's origins (`ALLOWED_ORIGINS`);
  - the health monitor (`0-health-check`,
    [scripts/health-check.sh](../scripts/health-check.sh)), once the web
    app and the API are ready: every 15 s (`HEALTH_CHECK_INTERVAL`) one
    line, 🌐 Web, 🔌 API (`/api/health`) and 🤖 aityx (✅ the API has its
    key, ⚪ it doesn't).
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
  serving, so a start after no change builds nothing and serves in a
  second or two; a first start, or one after a change, takes the build
  (about 25 s on a laptop, a minute or two on a 4-core codespace). One
  Flutter web build runs at a time across the repository's demos, through
  a lock directory in the system's temp folder
  (`aityx-demos-flutter-web-build.lock`, holding the builder's PID; a
  lock whose process is gone, or that never got its PID and is a minute
  old, is taken over), so starting every demo at once doesn't thrash a
  small machine; the checks run inside the lock, so two starts that
  overlap build once. The API's compiles share a lock of their own. `build/` is git-ignored.
- `devbox run web` runs only the web app, in debug mode (hot reload)
  unless `WEB_MODE=release`; `devbox run api` only the API.
- The web app calls the API at `API_BASE_URL` (a dart-define). The
  services leave it empty, in both modes: the app calls `/api/` on its own
  origin, which the web server (or the dev server) proxies to the API.
  `scripts/make.sh` passes `API_BASE_URL`, or `http://localhost:8921`.
- `bash scripts/model-test.sh` runs
  [test/model_scenarios_test.dart](../roborules_api/test/model_scenarios_test.dart)
  on aityx (tagged `aityx`, skipped by a plain `dart test`).
- `python3 tool/build_world.py models/world.json`, from `roborules_api/`,
  rewrites the world model.
- **Docker Compose** ([compose.yaml](../compose.yaml)): the web app's
  release build under nginx and the API compiled, with `models/` beside it.
- **Dev container**: the aityx group's
  ([.devcontainer/aityx/](../../.devcontainer/aityx)), named **aityx
  demos**, shared with the other five aityx demos (there is no per-demo
  one), forwarding 8920 among the group's web ports and the index's 8800,
  and asking for the same `AITYX_API_KEY` Codespaces secret as the other
  samples. It uses the group's published image
  (`docker.io/aletyxcode/samples-and-demos-aityx`, built by
  `bash image/build-image.sh aityx`, see [image/](../../image/)), which
  carries the six aityx demos' release web builds: `on-create.sh` copies
  them into the workspace (unless a demo's folder changed since the image
  was made: then that app builds itself), `update-content.sh` runs
  `build-all.sh` for the group (RoboRules' API and web server among them)
  and `post-start.sh` starts the index page and then the group
  (`DEMOS_GROUP=aityx`) detached with `start-all.sh` and the image's
  process-compose (RoboRules' socket is
  `/tmp/aityx-demos-RoboRules.sock`, `DEMOS_TOOLCHAIN=image`, see
  [demos-toolchain.sh](../../demos-toolchain.sh)); no devbox in a
  codespace. Every step goes to `startup.log` at the root of the
  repository (see [startup-log.sh](../../.devcontainer/startup-log.sh)).
- The app is web only: `make` (or `make web`) builds it; `make clean`.
