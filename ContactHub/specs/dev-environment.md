# Development environment

Contact Hub is one Flutter app, [contacthub_app/](../contacthub_app), that
calls aityx itself, from the browser (see
[Routing](routing.md#calling-aityx)). There's no Contact Hub API, web
server, Docker Compose or process-compose of its own: the repository's
index server ([Index/](../../Index)) serves the release web build at
`/contacthub/`, on one origin with the index page and the other aityx
demos, so a key set once on the index page reaches every demo.

- [devbox.json](../devbox.json) manages the toolchain: Flutter,
  GNU Make and curl. [devbox.lock](../devbox.lock) is committed, and is
  the same as Mortgage Hub's, so the two use the same Flutter (Dart
  3.13.0) and share one Nix store. The app requires Dart SDK `^3.13.0`.
- **The shared package**: the app depends on
  [packages/aityx_web](../../packages/aityx_web/README.md) (a path
  dependency, `../../packages/aityx_web`) for the key, the systemone calls
  and the [status light](aityx-status.md).
- **Running it**: from the repository root, `./start-all.sh ContactHub`
  (or `./start-all.sh` for every demo) builds what's stale and starts the
  index server; the app is at http://localhost:8800/contacthub/. Set your
  aityx key on the index page (http://localhost:8800/#aityx-key), or put
  one in the repository's `.env` for the dev key (see
  [../.env.example](../.env.example)).
- **The web build** ([scripts/build.sh](../scripts/build.sh), `devbox run
  build`, also run by the repository's `build-all.sh`):
  `flutter build web --release --base-href /contacthub/ --no-web-resources-cdn`,
  through `scripts/make.sh web`, which adds the version. No dart-define
  points it at an API any more. `--no-web-resources-cdn` keeps CanvasKit
  on our origin rather than gstatic's. It builds only when the build is
  missing or older than `lib/`, `web/`, `assets/`, the pubspecs, the
  shared package (`packages/aityx_web/lib` and its pubspec) or the version
  files, or when the build doesn't record its settings
  (`build/web/.aityx-services`, `base_href=/contacthub/
  web_resources_cdn=no`, written once a build succeeds and required to be
  newer than the build, so a `make web` by hand with other settings isn't
  reused). One Flutter web build runs at a time across the repository's
  demos, through a lock directory in the system's temp folder
  (`aityx-demos-flutter-web-build.lock`, holding the builder's PID; a
  lock whose process is gone, or that never got its PID and is a minute
  old, is taken over); the checks run inside the lock, so two starts that
  overlap build once. A build takes about 20 to 40 s on a laptop.
  `build/` is git-ignored.
- **Hot reload**: `flutter run -d web-server` in `contacthub_app/` runs the
  app on a port of its own, an origin without the index page or the dev
  proxy, so it has no key: routing says to set one. Work on the screens
  with the tests' fakes, or rebuild and reload the index server's
  `/contacthub/`.
- `bash scripts/model-test.sh` runs the routing model's rules on aityx at
  the policy's limits (see [Order policy](order-policy.md#verified)): it
  runs `flutter test --run-skipped --tags aityx` in `contacthub_app/`,
  with `AITYX_API_KEY` and `AITYX_URL` from the environment, else the
  repository's `.env`, exported to the test only; run it after changing
  the model. `dart run tool/route_samples.dart` in `contacthub_app/`
  routes every sample on aityx, with the same key, and says where each
  went against its label; `--save DIR` keeps each routing in the shape
  the routing screen reads, which is how the app's test fixture is made.
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1 today), Z the build time as `YYYYMMDDHHMM` UTC; the build number is
  the same time in Unix seconds
  ([scripts/version.sh](../scripts/version.sh)). It reaches the app as the
  `CONTACTHUB_VERSION` dart-define.
- **Coordinates**: the group ID `aityx` from `group.id.txt` and the artifact
  ID `contacthub` from `artifact.id.txt`; with the version, `aityx:contacthub:X.Y.Z`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web`, `android`, `ios` (macOS),
  `linux` (Linux), `all` (what the host can build) and `clean`, with
  `MODE`, `IOS_CODESIGN` and `WEB_BASE_HREF`. The native builds have no
  index page and no dev proxy: their key store is in memory only, so they
  can't route.
- **Dev container**: the aityx group's
  ([.devcontainer/aityx/](../../.devcontainer/aityx)), named **aityx
  demos**, which Contact Hub shares with Mortgage Hub, Cellfie, PokerFace,
  RoboRules and RiverRace; the datyx group has its own. It runs the
  group's published image (`docker.io/aletyxcode/samples-and-demos-aityx`,
  built from [image/Containerfile](../../image/Containerfile) by `bash
  image/build-image.sh aityx`) with the scripts in
  [.devcontainer/](../../.devcontainer), which restore the release web
  builds from the image, build what changed and start the index server,
  where Contact Hub is at `/contacthub/` on port 8800 (see the image's
  and the dev container's READMEs). The `AITYX_API_KEY` Codespaces secret
  is optional: it's the dev key, which every visitor of the codespace
  uses; without it, each visitor sets their own key on the index page.
- **Launch link**: the [README](../README.md#run-it-in-a-codespace) and
  the repository README have an **Open in GitHub Codespaces** badge with
  `devcontainer_path=.devcontainer/aityx/devcontainer.json` and
  `machine=standardLinux32gb`, the same link as every aityx demo's.

## Known limitations

- No release, deploy or CI workflows.
- The app needs the index server: served elsewhere (any static host), it
  works only with a key set on that origin's index page, and has no dev
  key.
