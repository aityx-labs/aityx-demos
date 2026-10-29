# Development environment

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed.
- The app requires Dart SDK `^3.13.0`, which covers the Nix Flutter
  (Dart 3.13.0).
- Flutter web runs on the `web-server` device, so no Chrome is needed.
- `devbox services up` ([process-compose.yaml](../process-compose.yaml))
  starts:
  - the web app (`2-flutter-web`, via
    [scripts/flutter-web.sh](../scripts/flutter-web.sh)) on
    http://localhost:8880/app/ (`FLUTTER_WEB_PORT`), bound to 127.0.0.1
    (`MORTGAGEHUB_BIND_HOST`), with an HTTP readiness probe of up to 15
    minutes (a first start builds the app, and when every demo starts at
    once the builds take turns). In release mode, the default (`WEB_MODE`),
    it is the app's release build served by
    [mortgagehub_api/bin/web_server.dart](../mortgagehub_api/bin/web_server.dart)
    ([lib/web_server.dart](../mortgagehub_api/lib/web_server.dart))
    compiled to a native executable, `mortgagehub_api/build/web_server`,
    about 20 MB resident: `/app/` from `mortgagehub_app/build/web/`
    (`WEB_ROOT`) with the right content types (`.wasm` included),
    `index.html` for the app's own routes, `Cache-Control: no-cache` with
    `Last-Modified` and 304 so a new build is seen on the next load and an
    unchanged file isn't downloaded again, and only files inside the
    build (`..` and escapes are refused). Each web build also stamps its
    scripts' URLs with its build number (`flutter_bootstrap.js?b=<n>` in
    `index.html`, `main.dart.js?b=<n>` in the bootstrap, by
    `scripts/make.sh`), so a browser that cached an earlier build's
    scripts, which a reload doesn't revalidate, loads the new ones;
    `/api/` and the bare `/` proxied
    to the API on 127.0.0.1:`API_PORT`, same method, query, headers and
    body, 502 when the API is down. It serves what nginx serves under
    Docker Compose, so the two paths show the same app. With
    `WEB_MODE=debug` it is Flutter's dev server instead (`flutter run` on
    the `web-server` device, hot reload with `r`, about 1 GB resident),
    which proxies `/api/` itself (`web_dev_config.yaml`, generated from
    `API_PORT`, git-ignored). On stop, its shutdown command kills whatever
    listens on the port, so neither server keeps serving the old build;
  - the API (`3-api`, via [scripts/api.sh](../scripts/api.sh)) on
    http://localhost:8881 (`API_PORT`), `bin/server.dart` compiled to a
    native executable, `mortgagehub_api/build/server`, about 15 MB
    resident and up in a second (it finds its model beside the binary,
    `build/../models/`), with a readiness probe on `/api/health`. The
    script exports `AITYX_API_KEY`, `AITYX_URL` and `ASSUMED_RATE` from
    `.env` to the server only. CORS allows the web app's origins
    (`ALLOWED_ORIGINS`);
  - the health monitor (`0-health-check`,
    [scripts/health-check.sh](../scripts/health-check.sh)), once the web
    server and the API are ready: every 15 s (`HEALTH_CHECK_INTERVAL`) one line, the
    time and each check as its emoji, a short label and ✅ / ❌, separated
    by ` · `. The checks are 🌐 Web, 🔌 API (`/api/health`) and 🤖 aityx (✅ the API
    has its key, ⚪ it doesn't). Sourcing the script defines
    `run_checks` (one pass) without starting the loop.
- **Builds for the services**: [scripts/build.sh](../scripts/build.sh)
  (`devbox run build`; targets `web`, `web_server`, `api`, `all`) builds
  only what is missing or older than its sources: `web` runs
  `scripts/make.sh web` with `WEB_BASE_HREF=/app/` and an empty
  `API_BASE_URL`, compared against `lib/`, `web/`, `assets/`, the
  pubspecs and the version files, and also when the build doesn't record
  those settings (`build/web/.aityx-services`, written once a build
  succeeds, so a `make web` by hand with other settings isn't reused);
  `web_server` and `api` run `dart compile exe`, compared
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
  overlap build once. The API's compiles share a lock of their own.
  `build/` is git-ignored.
- `devbox run web` runs only the web app, in debug mode (hot reload)
  unless `WEB_MODE=release`; `devbox run api` only the API.
- The web app calls the API at `API_BASE_URL` (a dart-define). The
  services leave it empty, in both modes: the app calls `/api/` on its own
  origin, which the web server (or the dev server) proxies to the API.
  `scripts/make.sh` passes `API_BASE_URL`, or `http://localhost:8881`.
- `bash scripts/model-test.sh` runs the mortgage rules on aityx with
  expected verdicts (see [Regulatory check](regulatory-check.md#verified)).
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1 today), Z the build time as `YYYYMMDDHHMM` UTC; the build number is
  the same time in Unix seconds
  ([scripts/version.sh](../scripts/version.sh)). It reaches the app as the
  `MORTGAGEHUB_VERSION` dart-define.
- **Coordinates**: the group ID `aityx` from `group.id.txt` and the artifact
  ID `mortgagehub` from `artifact.id.txt`; with the version, `aityx:mortgagehub:X.Y.Z`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web`, `android`, `ios` (macOS),
  `linux` (Linux), `all` (what the host can build) and `clean`, with
  `MODE` (release, profile, debug), `IOS_CODESIGN` and `WEB_BASE_HREF`.
- **Docker Compose** ([compose.yaml](../compose.yaml)): `docker compose up`
  runs the app with Docker alone, on http://localhost:8880/app/
  (`FLUTTER_WEB_PORT`), published on 127.0.0.1 unless
  `MORTGAGEHUB_BIND_HOST` says otherwise. Two services:
  - `web` ([docker/web.Dockerfile](../docker/web.Dockerfile)): installs
    the Flutter devbox.lock pins (3.47.0; on x64 the release archive
    checked against its SHA-256, on arm64 the git tag, as in the dev
    container), runs `scripts/make.sh web` with `WEB_BASE_HREF=/app/` and
    an empty `API_BASE_URL`, and serves the build with nginx 1.29, which
    redirects `/` to `/app/`, falls back to `index.html` for the app's
    routes, sends `Cache-Control: no-cache` under `/app/` and proxies
    `/api/` to `api`
    ([docker/nginx.conf](../docker/nginx.conf)). Its build context is this
    folder, narrowed by `web.Dockerfile.dockerignore` to the app, the two
    scripts and the version files; the folder's own `.dockerignore` is
    left as it was;
  - `api` ([mortgagehub_api/Dockerfile](../mortgagehub_api/Dockerfile)):
    `dart compile exe` with Dart 3.13.0, run from `scratch` with the Dart
    image's `/runtime/` (libc, CA certificates) as user 65534, the model
    beside it in `/app/models`. It binds 0.0.0.0:8881 inside the network
    and is not published. Compose passes it `AITYX_API_KEY`, `AITYX_URL`
    and `ASSUMED_RATE` (6.5 when empty) from the environment, else `.env`;
    `web` gets none of them.
  Both have Docker health checks, every 15 s: `api` runs
  `/app/bin/server healthcheck`, which asks its own `/api/health` on
  127.0.0.1 and exits 0 when it answers `ok` (the `scratch` image has no
  shell or curl); `web` fetches `/app/` and, through its proxy,
  `/api/health` with busybox `wget`. `web` starts once `api` is healthy,
  and `docker compose up --wait` returns once both are. There is no hot
  reload; both restart `unless-stopped`.
- **Dev container** ([.devcontainer/aityx/](../../.devcontainer/aityx)):
  the aityx group's, **aityx demos**, at the root of the repository, not
  in this folder, because that is the only place GitHub looks for one.
  The repository has one dev container per demo group, each with its own
  image; the datyx group's is in
  [.devcontainer/datyx/](../../.devcontainer/datyx), and there is no
  per-demo one and no default one. This one starts the aityx group (the
  folders whose `group.id.txt` says `aityx`: Mortgage Hub, Contact Hub,
  Cellfie, RoboRules, RiverRace and PokerFace) and the index page with
  the repository's `start-all.sh`; its `DEMOS_GROUP=aityx` makes
  `start-all.sh`, `stop-all.sh` and `build-all.sh` act on that group
  only. The scripts it runs are in
  [.devcontainer/](../../.devcontainer), shared by both groups.
  Mortgage Hub's own dev container, which started only this app and
  which the per-demo ones were copied from, is archived in
  [.devcontainer/archive/MortgageHub/](../../.devcontainer/archive/MortgageHub)
  and is not offered when creating a codespace (GitHub lists only a
  `devcontainer.json` directly in `.devcontainer/` or one folder below
  it). The
  container opens with a header saying what it starts and linking the
  repository, aityx.ai, aletyx.com and nu01.com. It uses the group's
  published image, `docker.io/aletyxcode/samples-and-demos-aityx`, built
  from [image/Containerfile](../../image/Containerfile) by
  `bash image/build-image.sh aityx` (see [image/](../../image/)):
  Microsoft's `ubuntu-24.04` base with Flutter 3.47.0, process-compose
  and the GitHub CLI, pinned and checked against their published
  SHA-256, and the six aityx demos' release web builds. No Docker
  feature: no aityx demo has a database. The demos run on the image's
  own Flutter and process-compose (`DEMOS_TOOLCHAIN=image`, see
  [demos-toolchain.sh](../../demos-toolchain.sh)): no devbox or Nix in
  a codespace. `hostRequirements` asks for 4 cores and 16 GB.
  [on-create.sh](../../.devcontainer/on-create.sh) copies the builds
  from the image into the workspace
  ([image/restore-builds.sh](../../image/restore-builds.sh)): every demo
  whose folder has the git tree hash the image was made from; a demo
  that changed since builds itself, a minute or two on 4 cores.
  [update-content.sh](../../.devcontainer/update-content.sh) runs
  `./build-all.sh` for the group (each demo's `scripts/build.sh`: the
  compiled API and web server, a few seconds each).
  [post-create.sh](../../.devcontainer/post-create.sh) reports whether
  `AITYX_API_KEY` arrived, never its value. Measured, with the former
  container that started every demo: the codespace was available about
  three minutes after the request and the demos answered within a minute
  after that. The container sets each aityx demo's `*_BIND_HOST` to
  `0.0.0.0` (`MORTGAGEHUB_BIND_HOST` for this one, `INDEX_BIND_HOST` for
  the index), forwards 8800 and the six web ports (8880 to 8940), and
  adds the Dart and Flutter extensions.
- **The editor's Flutter SDK**: the image carries Flutter 3.47.0, the
  version `devbox.lock` pins, in `/opt/flutter`: on x64 the release
  archive, checked against the SHA-256 in `releases_linux.json`; on arm64,
  where Flutter publishes no Linux archive, the release tag from git. Its
  web artifacts are precached and analytics are off. `devcontainer.json`
  points `dart.flutterSdkPath` there and puts `/opt/flutter/bin` on the
  PATH of every terminal. It is the Flutter the demos build and run
  with in a codespace, and it is there from the moment VS Code attaches,
  so the Dart extension doesn't offer to download one. On a laptop,
  inside `devbox shell` and `devbox services up`, devbox's Flutter comes
  first; the two must be kept on the same version.
- **Starts by itself**: `postStartCommand` runs
  [post-start.sh](../../.devcontainer/post-start.sh) on every start
  (after `on-create.sh`, `update-content.sh` and `post-create.sh` on the
  first), which starts the index page with `./start-all.sh Index`, then
  the group with `./start-all.sh` and `WAIT=900`, detached (each demo's
  services under the image's process-compose, reached through
  `/tmp/aityx-demos-<demo>.sock`; `./stop-all.sh` stops the group), then
  `public-port.sh`. Every port is
  forwarded as plain HTTP; only the index's 8800 has `onAutoForward:
  openBrowserOnce`, the others are `silent`, since the index is up in
  seconds and links each app once it answers (with its forwarded URL, in
  a codespace). The web server proxies the bare `/` to the API, which
  redirects it to `/app/` (the proxy turns that into `/app`, which
  serves the same page), so the forwarded port's URL opens the app as it
  is, as nginx does under Docker Compose.
- **Start-up log**: `startup.log` at the root of the repository
  (git-ignored, as every `*.log`), written through
  [startup-log.sh](../../.devcontainer/startup-log.sh), which the
  scripts source. Each line has a UTC time and a tag: `on-create` (the
  builds restored from the image), `update-content` (each build's output
  and duration), `post-create`, `post-start`, `start-all`
  (`start-all.sh`'s output: each demo's start and the line saying when
  it answers, or that it didn't within 15 minutes) and `public-port`.
  The scripts first log the facts a failed start comes down to: user,
  architecture, the codespace, whether `AITYX_API_KEY` and
  `GITHUB_TOKEN` are set (never their values), `AITYX_URL`, the
  toolchain (`image`: where flutter and process-compose are and which
  builds the image carries; `devbox`: devbox's and Nix's versions and
  whether each demo's `.devbox` exists) and the free disk. It's in the
  workspace so a user can download it from the Explorer and send it; the
  README asks them to when the app doesn't start.
- **Public web ports**:
  [public-port.sh](../../.devcontainer/public-port.sh) in a codespace
  makes the index's port and each demo's web port (8880 for this app)
  public with `gh codespace ports visibility`, each one retried in the
  background (every 10 s, for up to 20 minutes) until it is forwarded,
  since the demos come up one by one. `devcontainer.json` has no setting
  for it. Only the web ports are public: the API's 8881 is not forwarded,
  and the app reaches it through the web server's `/api/` proxy. It runs again from
  `postAttachCommand`, because a visibility set at start does not always
  stick; a second run while one is still retrying does nothing. An
  organization policy can forbid public ports, in which case the port
  stays private. The READMEs tell the user to check the port's visibility
  in the Ports panel and set it to Public by hand if needed.
- **Codespaces secrets**: `devcontainer.json` declares `AITYX_API_KEY`
  and optional `AITYX_URL` under `secrets`, so GitHub asks the person creating a codespace
  for their own key, keeps it against their account and passes it in as an
  environment variable. It is required: without it the app runs but the
  regulatory check cannot. `AITYX_URL`
  defaults to `https://api.aityx.ai` and `ASSUMED_RATE` to 6.5; both are
  overridden in `.env` when needed (or set the optional URL secret in a
  codespace; a stage key uses `https://api-stage.aityx.ai`). The repository ships no key.
  A local dev container uses `.env`, which the scripts already fall back
  to.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) has an
  **Open in GitHub Codespaces** badge pointing at
  `codespaces.new/aityx-labs/aityx-demos` with `devcontainer_path` set
  to `.devcontainer/aityx/devcontainer.json`, the same link as every
  aityx demo's, and `machine=standardLinux32gb`, the 4-core, 16 GB
  machine the Flutter builds want.
- **Setup screenshots**: the README's codespace steps show the
  *New secret* form and the *Create a new codespace* page
  ([docs/images/](../docs/images/)), so a reader can check that the key is
  associated with the repository before creating the codespace.

## Known limitations

- No release, deploy or CI workflows: the API runs only locally, under
  devbox or Docker Compose.
