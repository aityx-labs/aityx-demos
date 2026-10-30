# Development environment

PokerFace is one Flutter app, [pokerface_app](../pokerface_app), that runs
in the browser and calls aityx itself ([Deciding on aityx](aityx.md)).
There is no API, no web server of its own and no services: the
repository's index server ([Index/bin/server.dart](../../Index/bin/server.dart),
port 8800) serves the release web build at `/pokerface/`, on the same
origin as the index page and the other aityx demos, so a key the user
sets once on the index page works here too.

- [devbox.json](../devbox.json) manages the toolchain: Flutter, GNU Make
  and curl. [devbox.lock](../devbox.lock) is committed, and is the same as
  Mortgage Hub's and Contact Hub's, so they share one Flutter (Dart 3.13.0)
  and one Nix store. The app requires Dart SDK `^3.13.0`. `devbox run
  build` builds the web app; `devbox run model-test` runs the strategies
  on aityx.
- **The shared package**: the app depends on
  [packages/aityx_web](../../packages/aityx_web/README.md) by path
  (`../../packages/aityx_web`): the key, the systemone call and the aityx
  light, the same in every aityx demo.
- **The web build** ([scripts/build.sh](../scripts/build.sh), run by the
  repository's `build-all.sh` and `start-all.sh`, or by hand): `flutter
  build web --release --base-href /pokerface/ --no-web-resources-cdn`,
  through `scripts/make.sh web`, into `pokerface_app/build/web/`. CanvasKit
  comes from the build itself, not Google's CDN, so no third-party script
  runs on the origin that holds the user's key. It builds only when the
  build is missing or older than its sources (`lib/`, `web/`, `assets/`,
  the pubspecs, `packages/aityx_web`'s `lib/` and pubspec, the version
  files), or doesn't record the settings it needs
  (`build/web/.aityx-build`: the base href and the no-CDN flag, written
  once a build succeeds and required to be newer than the build, so a
  `make web` by hand with other settings isn't reused). A start after no
  change builds nothing; a build takes about 30 s on a laptop, a minute or
  two on a 4-core codespace. One Flutter web build runs at a time across
  the repository's demos, through a lock directory in the system's temp
  folder (`aityx-demos-flutter-web-build.lock`, holding the builder's PID;
  a lock whose process is gone, or that never got its PID and is a minute
  old, is taken over); the checks run inside the lock, so two starts that
  overlap build once. `build/` is git-ignored.
- **Running it**: `./start-aityx.sh PokerFace` (or `./start-all.sh`) at
  the repository root builds what's stale and starts the index server;
  open http://localhost:8800/pokerface/. With a key in the root `.env` the
  index server's dev proxy (`/aityx/v1/systemone`) adds it to the app's
  calls, and the key never reaches the browser; without one, users set
  theirs on the index page.
- **Tests**: `flutter analyze` and `flutter test` in `pokerface_app/`: the
  engine, the screens, the table logic ported from the API, and every
  decision path against a MockClient. `bash scripts/model-test.sh` runs
  the scenarios tagged `aityx` on the real aityx (`flutter test
  --run-skipped --tags aityx`, which plain `flutter test` skips; see
  [Strategies](strategies.md#verified)), with `AITYX_API_KEY` and
  `AITYX_URL` from the environment, else the repository's root `.env`,
  exported to the test only; run it after changing a model.
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1 today), Z the build time as `YYYYMMDDHHMM` UTC; the build number is
  the same time in Unix seconds
  ([scripts/version.sh](../scripts/version.sh)). It reaches the app as the
  `POKERFACE_VERSION` dart-define.
- **Coordinates**: the group ID `aityx` from `group.id.txt` and the artifact
  ID `pokerface` from `artifact.id.txt`; with the version, `aityx:pokerface:X.Y.Z`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web` (base href `/pokerface/`
  unless `WEB_BASE_HREF` says otherwise, always without the CDN),
  `android`, `ios` (macOS), `linux` (Linux), `all` (what the host can
  build) and `clean`, with `MODE` and `IOS_CODESIGN`. The native builds
  have no dev proxy and only an in-memory key store, empty at start, so
  their decisions answer "aityx is not set up".
- **Dev container**: the aityx group's
  ([.devcontainer/aityx/](../../.devcontainer/aityx)), named **aityx
  demos**, which PokerFace shares with Mortgage Hub, Contact Hub, Cellfie,
  RoboRules and RiverRace; the datyx group has its own, and there is no
  per-demo one. It runs the group's published image
  (`docker.io/aletyxcode/samples-and-demos-aityx`, built from
  [image/Containerfile](../../image/Containerfile) by `bash
  image/build-image.sh aityx`), which carries the six aityx demos'
  release web builds; `on-create.sh` restores PokerFace's
  ([image/restore-builds.sh](../../image/restore-builds.sh)) unless the
  app or `packages/` changed since the image was made, and then it
  builds itself. The codespace serves it on the index's port, 8800, at
  `/pokerface/`. The `AITYX_API_KEY` Codespaces secret is optional: it
  becomes the dev key every visitor of the codespace uses. See the
  [repository README](../../README.md).
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) and
  the repository README have an **Open in GitHub Codespaces** badge with
  `devcontainer_path=.devcontainer/aityx/devcontainer.json` and
  `machine=standardLinux32gb`, the same link as every aityx demo's.

## Known limitations

- No release, deploy or CI workflows.
- `pokerface_app/build/web` only works under `/pokerface/`; served
  elsewhere, rebuild it with another `WEB_BASE_HREF`.
