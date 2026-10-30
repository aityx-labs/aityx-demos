# Development environment

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed.
- The app requires Dart SDK `^3.13.0`, which covers the Nix Flutter
  (Dart 3.13.0).
- **No services of its own.** The app is a static web build that calls
  aityx from the browser (see [aityx.ai integration](aityx.md)); the
  repository's index server ([Index/](../../Index)) serves it at
  `/mortgagehub/` on its port (8800), beside the index page and the other
  aityx demos, with `Cache-Control: no-cache`, `index.html` for the app's
  own routes, and the dev key's `/aityx/` proxy. From the repository's
  root, `./start-aityx.sh MortgageHub` (or `./start-aityx.sh`,
  `./start-all.sh`) builds what's stale and starts the index;
  `./stop-aityx.sh` stops it. There is no API, no web server, no
  process-compose file and no health monitor in this folder any more.
- **The build the index serves**: [scripts/build.sh](../scripts/build.sh)
  (`devbox run build`; no target, or `web`) runs `scripts/make.sh web`
  with `MODE=release` and `WEB_BASE_HREF=/mortgagehub/`, so the build is
  `flutter build web --release --base-href /mortgagehub/
  --no-web-resources-cdn` (CanvasKit from the build, no script from
  gstatic: no third-party script runs on the origin that holds the key).
  It builds only when `build/web` is missing or older than its sources:
  the app's `lib/`, `web/`, `assets/` and pubspecs, the shared package
  (`../packages/aityx_web`: `lib/` and its pubspec) and the version files;
  and when the build doesn't record its settings
  (`build/web/.aityx-services`: `base_href=/mortgagehub/
  web_resources_cdn=no`, written once a build succeeds, so a `make web` by
  hand with other settings isn't reused). A build after no change does
  nothing and takes a second; one after a change about 20 s on a laptop,
  a minute or two on a 4-core codespace. One Flutter web build runs at a
  time across the repository's demos, through a lock directory in the
  system's temp folder (`aityx-demos-flutter-web-build.lock`, holding the
  builder's PID; a lock whose process is gone, or that never got its PID
  and is a minute old, is taken over), so building every demo at once
  doesn't thrash a small machine; the checks run inside the lock, so two
  builds that overlap build once. The repository's `build-all.sh` and
  `start-all.sh` run it. Each web build also stamps its scripts' URLs
  with its build number (`flutter_bootstrap.js?b=<n>` in `index.html`,
  `main.dart.js?b=<n>` in the bootstrap, by `scripts/make.sh`), so a
  browser that cached an earlier build's scripts, which a reload doesn't
  revalidate, loads the new ones. `build/` is git-ignored.
- `bash scripts/model-test.sh` runs the app's tests tagged `aityx` on
  aityx with the key and URL from the environment, else the repository's
  `.env` (exported to the test only): by default the mortgage rules'
  expected verdicts (see [Regulatory check](regulatory-check.md#verified)),
  or the test files it's given. `flutter test` skips them
  (`dart_test.yaml`).
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
  Web builds always pass `--no-web-resources-cdn`. Native builds have no
  index page to set a key on (their key store is in memory only) and no
  dev proxy, so their regulatory check says aityx is not set up.
- **Dev container** ([.devcontainer/aityx/](../../.devcontainer/aityx)):
  the aityx group's, **aityx demos**, at the root of the repository, not
  in this folder, because that is the only place GitHub looks for one.
  The repository has one dev container per demo group, each with its own
  image; the datyx group's is in
  [.devcontainer/datyx/](../../.devcontainer/datyx), and there is no
  per-demo one and no default one. This one builds the aityx group (the
  folders whose `group.id.txt` says `aityx`: Mortgage Hub, Contact Hub,
  Cellfie, RoboRules, RiverRace and PokerFace) and starts the index,
  which serves them, with the repository's `start-all.sh`; its `DEMOS_GROUP=aityx` makes
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
  SHA-256, and the six aityx demos' release web builds (this one built
  for `/mortgagehub/`). No Docker feature: no aityx demo has a database. The demos run on the image's
  own Flutter and process-compose (`DEMOS_TOOLCHAIN=image`, see
  [demos-toolchain.sh](../../demos-toolchain.sh)): no devbox or Nix in
  a codespace. `hostRequirements` asks for 4 cores and 16 GB.
  [on-create.sh](../../.devcontainer/on-create.sh) copies the builds
  from the image into the workspace
  ([image/restore-builds.sh](../../image/restore-builds.sh)): every demo
  whose folder has the git tree hash the image was made from; a demo
  that changed since builds itself, a minute or two on 4 cores.
  [update-content.sh](../../.devcontainer/update-content.sh) runs
  `./build-all.sh` for the group (each demo's `scripts/build.sh`, which
  does nothing for a restored build).
  [post-create.sh](../../.devcontainer/post-create.sh) reports whether
  the optional `AITYX_API_KEY` (the dev key) arrived, never its value. Measured, with the former
  container that started every demo: the codespace was available about
  three minutes after the request and the demos answered within a minute
  after that. The container forwards only the index's port, 8800, which serves
  this app at `/mortgagehub/`, and adds the Dart and Flutter extensions.
- **The editor's Flutter SDK**: the image carries Flutter 3.47.0, the
  version `devbox.lock` pins, in `/opt/flutter`: on x64 the release
  archive, checked against the SHA-256 in `releases_linux.json`; on arm64,
  where Flutter publishes no Linux archive, the release tag from git. Its
  web artifacts are precached and analytics are off. `devcontainer.json`
  points `dart.flutterSdkPath` there and puts `/opt/flutter/bin` on the
  PATH of every terminal. It is the Flutter the demos build and run
  with in a codespace, and it is there from the moment VS Code attaches,
  so the Dart extension doesn't offer to download one. On a laptop,
  inside `devbox shell` (and `devbox run build`), devbox's Flutter comes
  first; the two must be kept on the same version.
- **Starts by itself**: `postStartCommand` runs
  [post-start.sh](../../.devcontainer/post-start.sh) on every start
  (after `on-create.sh`, `update-content.sh` and `post-create.sh` on the
  first), which starts the index, and with it this app at
  `/mortgagehub/`, then `public-port.sh`. Port 8800 has `onAutoForward:
  openBrowserOnce`, so the index page opens in a browser tab; the
  Mortgage Hub card links the app on the same address.
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
- **Public port**:
  [public-port.sh](../../.devcontainer/public-port.sh) in a codespace
  makes the index's port, 8800, public with `gh codespace ports
  visibility`, retried in the background until it is forwarded, and again
  from `postAttachCommand`, because a visibility set at start does not
  always stick. Each visitor sets their own key on the index page. An
  organization policy can forbid public ports, in which case the port
  stays private; the README tells the user to check the port's
  visibility in the Ports panel and set it to Public by hand if needed.
- **Codespaces secrets**: `devcontainer.json` declares an optional
  `AITYX_API_KEY` (and `AITYX_URL`) under `secrets`: a dev key the index
  server lends, through its proxy, to every visitor of the codespace who
  hasn't set their own key. Without it the app still runs; each visitor
  sets their key on the index page. The repository ships no key. A local
  dev container uses the repository's `.env`, which the index server
  reads too.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) has an
  **Open in GitHub Codespaces** badge pointing at
  `codespaces.new/aityx-labs/aityx-demos` with `devcontainer_path` set
  to `.devcontainer/aityx/devcontainer.json`, the same link as every
  aityx demo's, and `machine=standardLinux32gb`, the 4-core, 16 GB
  machine the Flutter builds want.
- **Setup screenshots**: the README's codespace steps show the
  *New secret* form and the *Create a new codespace* page
  ([docs/images/](../docs/images/)), for the optional dev key.

## Known limitations

- No release, deploy or CI workflows: the app runs where the index runs,
  on a laptop or in a codespace.
- No hot reload: the Flutter dev server would serve the app on another
  origin, where the key set on the index page isn't seen, and without the
  dev proxy. Rebuild with `bash scripts/build.sh` and reload.
