# Development environment

Cellfie is a Flutter web app and nothing else: it calls aityx from the
browser ([aityx calls](aityx-calls.md)), so it has no API and no services
of its own. The repository's index server
([Index/bin/server.dart](../../Index/bin/server.dart), port 8800) serves
its release build at `/cellfie/`, beside the index page and the other
aityx demos, on one origin, so a key the user sets once on the index page
works in every demo.

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed, and is
  the same as Mortgage Hub's and Contact Hub's, so they use the same
  Flutter (Dart 3.13.0) and share one Nix store. All require Dart SDK
  `^3.13.0`. `devbox run build` runs `scripts/build.sh`; `devbox run
  model-test` runs `scripts/model-test.sh`.
- The app depends on the repository's shared package
  [packages/aityx_web](../../packages/aityx_web/README.md) by path
  (`../../packages/aityx_web`): the key, the systemone calls and the
  status light.
- **The web build**: [scripts/build.sh](../scripts/build.sh) (`devbox run
  build`, and the repository's `build-all.sh` and `start-all.sh`) builds
  `cellfie_app/build/web/` through `scripts/make.sh web`, as
  `flutter build web --release --base-href /cellfie/
  --no-web-resources-cdn` (CanvasKit from the app's own origin, so no
  third-party script runs where the user's key is kept), only when the
  build is missing or older than the app's `lib/`, `web/`, `assets/`,
  pubspecs, aityx_web's `lib/` and pubspec, or the version files, and
  also when the build doesn't record its settings
  (`build/web/.aityx-services`, `base_href=/cellfie/
  web_resources_cdn=off`, written once a build succeeds and required to
  be newer than the build, so a `make web` by hand with other settings
  isn't reused). A start after no change builds nothing; a first start,
  or one after a change, takes the build (about 25 s on a laptop, a
  minute or two on a 4-core codespace). One Flutter web build runs at a
  time across the repository's demos, through a lock directory in the
  system's temp folder (`aityx-demos-flutter-web-build.lock`, holding the
  builder's PID; a lock whose process is gone, or that never got its PID
  and is a minute old, is taken over), so starting every demo at once
  doesn't thrash a small machine; the checks run inside the lock, so two
  starts that overlap build once. `build/` is git-ignored.
- **Running it**: from the repository root, `./start-aityx.sh` (or
  `./start-all.sh`) builds what's stale and starts the index server; open
  http://localhost:8800/cellfie/. After a change, `bash scripts/build.sh`
  and a reload: the index server serves the new build at once.
- **Checks**: `flutter analyze` and `flutter test` in `cellfie_app/`,
  then `bash scripts/build.sh`.
- `bash scripts/model-test.sh` runs the Life model on aityx: `flutter
  test --run-skipped --tags aityx` in `cellfie_app/` (see
  [Generation](generation.md#verified)), with `AITYX_API_KEY` and
  `AITYX_URL` from the environment, else the repository's root `.env`,
  exported to the test only. Run it after changing the model. `dart run
  tool/catalogue.dart` in `cellfie_app/` regenerates the model's pattern
  catalogue in `assets/models/life.json` (see [Patterns](patterns.md)).
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1 today), Z the build time as `YYYYMMDDHHMM` UTC; the build number is
  the same time in Unix seconds
  ([scripts/version.sh](../scripts/version.sh)). It reaches the app as the
  `CELLFIE_VERSION` dart-define; the app doesn't show it.
- **Coordinates**: the group ID `aityx` from `group.id.txt` and the artifact
  ID `cellfie` from `artifact.id.txt`; with the version, `aityx:cellfie:X.Y.Z`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web` (under `/cellfie/` unless
  `WEB_BASE_HREF` says otherwise, always without the CDN), `android`,
  `ios` (macOS), `linux` (Linux), `all` (what the host can build) and
  `clean`, with `MODE` and `IOS_CODESIGN`. The native builds have no index
  page and no dev proxy, and aityx_web keeps a key only in memory there:
  they run, but no generation can.
- **Dev container**: the aityx group's
  ([.devcontainer/aityx/](../../.devcontainer/aityx)), named **aityx
  demos**, which Cellfie shares with Mortgage Hub, Contact Hub, PokerFace,
  RoboRules and RiverRace; the datyx group has its own, and there is no
  per-demo one. It runs the group's published image
  (`docker.io/aletyxcode/samples-and-demos-aityx`, built from
  [image/Containerfile](../../image/Containerfile) by `bash
  image/build-image.sh aityx`, with the six aityx demos' release web
  builds) with the scripts in [.devcontainer/](../../.devcontainer).
  `on-create.sh` copies the group's release web builds from the image
  ([image/restore-builds.sh](../../image/restore-builds.sh), skipped for
  a folder that changed since the image was made: that app then builds
  itself), and `post-start.sh` starts the index server, which serves
  Cellfie at `/cellfie/` on port 8800. Everything goes to `startup.log`
  at the root of the repository, which holds no secrets.
- **The key**: each user sets theirs on the index page. The
  `AITYX_API_KEY` Codespaces secret, or the repository's `.env`, is
  optional: it gives the index server a dev key, which it adds to the
  calls through its own proxy for anyone who opens the demos without a
  key of their own (see [aityx calls](aityx-calls.md)); it never reaches
  the app.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) and
  the repository README have an **Open in GitHub Codespaces** badge with
  `devcontainer_path=.devcontainer/aityx/devcontainer.json` and
  `machine=standardLinux32gb`, the same link as every aityx demo's.

## Known limitations

- No release, deploy or CI workflows.
- No hot reload with a key: `flutter run` serves the app on another
  origin, which sees neither the index page's key nor the dev proxy, so
  the board works there but no generation can.
