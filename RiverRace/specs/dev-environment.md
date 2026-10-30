# Development environment

RiverRace is a Flutter web app with no services of its own: the index
server ([Index/bin/server.dart](../../Index/bin/server.dart), port 8800)
serves its release build at `/riverrace/`, with the index page and the
other aityx demos, on one origin, and the app calls aityx itself (see
[aityx calls](api.md)). [Mortgage Hub's spec](../../MortgageHub/specs/dev-environment.md)
explains the reasons behind the shared pieces.

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed, and is
  the same as the other aityx demos', so they use the same Flutter (Dart
  3.13.0) and share one Nix store. All require Dart SDK `^3.13.0`.
- The app depends on the repository's shared package
  [packages/aityx_web](../../packages/aityx_web/README.md) by path
  (`../../packages/aityx_web`): the key, the systemone call and the status
  light.
- **The web build** ([scripts/build.sh](../scripts/build.sh), `devbox run
  build`): `flutter build web --release --base-href /riverrace/
  --no-web-resources-cdn`, through `scripts/make.sh web` (which adds the
  version), into `riverrace_app/build/web/`. `--no-web-resources-cdn`
  keeps CanvasKit on the origin, so no third-party script runs on the
  origin that holds the user's key. It builds only when the build is
  missing or older than the app's `lib/`, `web/`, `assets/`, its pubspecs,
  the shared package's `lib/` and pubspec, or the version files, and when
  the build doesn't record its settings (`build/web/.aityx-services`:
  `base_href=/riverrace/ web_resources_cdn=no`, written once a build
  succeeds and required to be newer than the build, so a `make web` by
  hand with other settings isn't reused). The repository's `build-all.sh`
  and `start-all.sh` run it, so a start after no change builds nothing; a
  first build takes about 20 s on a laptop, a minute or two on a 4-core
  codespace. One Flutter web build runs at a time across the repository's
  demos, through a lock directory in the system's temp folder
  (`aityx-demos-flutter-web-build.lock`, holding the builder's PID; a lock
  whose process is gone, or that never got its PID and is a minute old, is
  taken over); the checks run inside the lock, so two starts that overlap
  build once. `build/` is git-ignored.
- **Running it**: `./start-all.sh` (or `./start-aityx.sh`) at the
  repository root builds what's stale and starts the index server; open
  http://localhost:8800/riverrace/. Set your aityx key on the index page
  (http://localhost:8800/#aityx-key), or put `AITYX_API_KEY` in the
  repository's `.env` for the index server's dev key (see
  [aityx calls](api.md)). Without either, the game runs but the aityx
  pilots fly straight on, and the light is red.
- `bash scripts/model-test.sh` runs strategies on aityx (see
  [Decisions](decisions.md#verified)): `flutter test --run-skipped --tags
  aityx` in `riverrace_app/`, with `AITYX_API_KEY` and `AITYX_URL` from the
  environment, else the repository's `.env`, exported to the test only.
  Run it after changing the model or `lib/aityx/decision_request.dart`.
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
  `MODE`, `IOS_CODESIGN` and `WEB_BASE_HREF` (`/` by default;
  `scripts/build.sh` passes `/riverrace/`). A native build has no index
  page and no dev proxy, and keeps a key only in memory, which nothing
  sets: its aityx pilots fly straight on.
- **Dev container**: the aityx group's
  ([.devcontainer/aityx/](../../.devcontainer/aityx)), named **aityx
  demos**, which RiverRace shares with Mortgage Hub, Contact Hub, Cellfie,
  PokerFace and RoboRules; the datyx group has its own. It runs the
  group's published image (`docker.io/aletyxcode/samples-and-demos-aityx`,
  built from [image/Containerfile](../../image/Containerfile) by `bash
  image/build-image.sh aityx`, with the six aityx demos' release web
  builds). `on-create.sh` copies the group's web builds from the image
  ([image/restore-builds.sh](../../image/restore-builds.sh), skipped for a
  demo that changed since the image was made: that app then builds
  itself), and `post-start.sh` builds what's stale and starts the index
  server, which serves RiverRace at `/riverrace/` on the forwarded port
  8800. The `AITYX_API_KEY` Codespaces secret is optional: it gives the
  index server a dev key that every visitor of the codespace uses.
  Everything goes to `startup.log` at the root of the repository (see
  [startup-log.sh](../../.devcontainer/startup-log.sh)), which holds no
  secrets.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) and
  the repository README have an **Open in GitHub Codespaces** badge with
  `devcontainer_path=.devcontainer/aityx/devcontainer.json` and
  `machine=standardLinux32gb`, the same link as every aityx demo's.

## Known limitations

- No release, deploy or CI workflows.
- No hot reload: rebuild (`bash scripts/build.sh`) and reload the page.
