# Development environment

Poker Tour is four Dart packages in one folder, and one service (two
functions on AWS, [On AWS](aws.md)):

- [pokertour_app](../pokertour_app), the Flutter app: PokerFace's, with
  the sign-in, the player's own key and the leaderboard ([The
  tour](tour.md)).
- [poker_core](../poker_core), pure Dart: the engine (cards, the hand
  evaluator, the game) and the table logic (a strategy, the models from
  their JSON, the checks on a situation, the body of a decision's call to
  aityx and the action in its answer), once the app's `lib/engine/` and
  `lib/aityx/table.dart`, moved out so the server plays the same game.
  The app depends on it and on
  [packages/aityx_web](../../packages/aityx_web/README.md) by path; the
  models stay the app's assets, which the server and poker_core's tests
  read from `pokertour_app/assets/models/`.
- [aws_lite](../aws_lite), pure Dart: AWS Signature Version 4 (the
  signed headers the server calls S3, DynamoDB and Lambda with, and a
  presigned URL form) and credentials; the server's.
- [pokertour_api](../pokertour_api), the server (`dart:io`, with
  [openid_client](https://pub.dev/packages/openid_client) for the
  tokens): the app's static files under `/pokertour/`, the API under `/api/`,
  the leaderboard in its store and the tour's table, and the runner. `bin/server.dart` is one
  process on one port, **9810** (the multyx group's index is on 9700 and
  tatyx on 9710; this one keeps 9810, the origin the Google sign-in
  client allows); the variables every demo uses,
  `FLUTTER_WEB_PORT` and `API_PORT`, name the same port. `bin/lambda.dart`
  is the same API and runner as Lambda functions (`lib/lambda/` is the
  custom runtime, `lib/aws/` the S3, DynamoDB and Lambda calls).
- **Floci**, the local AWS ([floci/compose.yaml](../floci/compose.yaml)):
  every AWS service a local run needs is [Floci](https://floci.io/) in
  Docker, never another emulator, a file stand-in or the real account
  ([CLAUDE.md](../CLAUDE.md)). The container `pokertour-floci` (its own
  Compose project, `pokertour-floci`, so it never takes other
  repositories' `floci` containers for its own; the image pinned by
  digest) listens on `127.0.0.1:9811` (`POKERTOUR_FLOCI_PORT`) and keeps
  its state in the Docker volume `pokertour-floci`; its init hook
  ([floci/init/ready.d/10-tour.sh](../floci/init/ready.d/10-tour.sh))
  makes the bucket and the table, both `pokertour-local`, when missing.
  The server keeps the tour there as the functions keep it in AWS, with
  Floci's dummy credentials, and refuses an AWS address in
  `POKERTOUR_AWS_ENDPOINT`.

- [devbox.json](../devbox.json) manages the toolchain: Flutter (with
  Dart), GNU Make and curl; [devbox.lock](../devbox.lock) is committed,
  the same as PokerFace's. `devbox run serve` starts the server; `devbox
  run build` builds; `devbox run model-test` runs the presets on aityx.
- **The group**: `group.id.txt` says `multyx`, the group of the
  multiplayer games on aityx, shared with [tatyx](../../tatyx/), so
  `./start-multyx.sh`, `./stop-multyx.sh`, `./build-all.sh` and the
  multyx group's dev container take it with the group, and `start-all.sh` links this
  folder's `.env` to the repository's root one (its `.env.example` names
  `AITYX_API_KEY` and the leaderboard's keys,
  `POKERTOUR_LEADERBOARD_KEY` and `POKERTOUR_PROD_LEADERBOARD_KEY`).
  `./start-multyx.sh PokerTour` starts it alone.
- **The build** ([scripts/build.sh](../scripts/build.sh), run by
  `scripts/serve.sh`, the repository's `build-all.sh` and `start-all.sh`,
  or by hand): `web`, `flutter build web --release --base-href /pokertour/
  --no-web-resources-cdn` through `scripts/make.sh web` into
  `pokertour_app/build/web/`, recorded in `build/web/.pokertour-services`
  (what the dev container image's `build-image.sh` looks for); and
  `server`, `dart compile exe` of `pokertour_api/bin/server.dart` to
  `pokertour_api/build/server`. Each only when missing or older than its
  sources (the app or the API, poker_core, aws_lite, aityx_web, the
  version files). One Flutter web build at a time across the repository, through
  the shared lock in the temp folder, as PokerFace's.
- **Running it** ([process-compose.yaml](../process-compose.yaml)):
  `0-floci` starts Floci (`docker compose -f floci/compose.yaml up`,
  ready when its init hooks are), then `1-server` runs
  [scripts/serve.sh](../scripts/serve.sh), which builds what's stale and
  runs the server with `WEB_ROOT`, `POKERTOUR_MODELS` (the app's assets)
  and `POKERTOUR_AWS_ENDPOINT` (Floci) set, and the settings from the
  environment, else `.env` ([scripts/env.sh](../scripts/env.sh), see
  [.env.example](../.env.example)): the leaderboard's key reaches the
  server's environment only. `/api/health` is the readiness probe. The server plays a tournament at the schedule's hours
  (a timer) and when an admin asks.
- **The deployment** ([deploy/](../deploy)): `deploy.sh` builds the web
  build and, in Docker with the official Dart image for Linux arm64
  (the Nix Dart can't cross-compile), the functions' `bootstrap`
  ([lambda.Dockerfile](../docker/lambda.Dockerfile), `--output` to
  `deploy/out/`, git-ignored), zips it with the models, uploads it to the
  code bucket, deploys [template.yaml](../deploy/template.yaml) with
  the AWS CLI, syncs the web build and the leaderboard's key, and prints
  the address;
  `destroy.sh` removes the stack. `.dockerignore` also keeps the builds,
  Dart's caches and `deploy/out` out of both Docker contexts.
- **The container** ([Dockerfile](../Dockerfile), [compose.yaml](../compose.yaml)):
  a build stage with the pinned Flutter builds the app and compiles the
  server; the runtime is `scratch` with Dart's `/runtime/` (libc, CA
  certificates), the server, the web build and the models, as user
  65534. [compose.yaml](../compose.yaml) runs Floci beside it as a
  service of the same project (extending `floci/compose.yaml`, no host
  port, the same `pokertour-floci` volume), which the server reaches at
  `http://floci:4566`. The build context is this folder, with the repository's
  `packages/` as a second context named `packages` (compose's
  `additional_contexts`), for aityx_web. `docker compose up` runs it on
  9810. `.dockerignore` carries the git-ignore rules
  (`sync-dockerignore.sh`).
- **The local cluster** ([k8s/](../k8s)): the repository's kind
  cluster (the root's `k8s/`: `bash k8s/up.sh`, then `bash k8s/deploy.sh
  PokerTour`) runs it in the multyx namespace beside tatyx and the
  multyx index, at **http://localhost:19810/pokertour/** (the node port
  31810; the usual port plus 10000, so it runs beside a laptop's).
  `build.sh` builds the Dockerfile's image as compose.yaml does and
  pushes it to the cluster's registry; the Deployment `pokertour` runs
  it with compose.yaml's settings, the keys and Poker Tour's Google
  client id from the Secret `demo-env` (the root `.env`, staging), and
  `AITYX_URL` required, so staging's key never goes to production; one
  server at a time (`Recreate`), as a server takes itself for its
  table's only player. Floci is the StatefulSet `pokertour-floci`, the
  same image, persistent in a volume, with the same init hook from a
  ConfigMap that [floci/kustomization.yaml](../floci/kustomization.yaml)
  makes (kustomize reads no files outside a kustomization's folder), and
  the hook's timeout raised for a busy node; the Service
  `pokertour-floci:4566` is for the server alone, the app never calling
  AWS. The `pokertour-web` client lists `http://localhost:19810` among
  its authorized JavaScript origins, so the Google sign-in works on the
  cluster as it does on 9810 (Google can take a while to apply a change
  to a client's origins). `verify.sh` checks, from the host, the app,
  the API, the tour in Floci's bucket and table (the history the API
  answers is the bucket's), the signed-in calls refusing a caller
  without a Google token and the relay reaching aityx staging;
  `TOURNAMENT=1` also plays a tournament, queued in Floci's table as
  the API would queue it, since only a signed-in admin can ask for one.
- **Tests**: `dart test` in `poker_core/` (the engine, the table logic),
  `aws_lite/` (the signer) and `pokertour_api/` (the leaderboard, the
  store and the table, the runner on a fake aityx, the routes, the
  schedule; `floci_test.dart` runs the table and the bucket on Floci, and
  is skipped when Floci isn't running); `flutter analyze` and `flutter
  test` in `pokertour_app/` (the screens, the decision paths against a
  mock, the player's key and **Play** waiting for it, Profile's alias and
  strategies, the server's answers, the welcome page). `bash
  scripts/model-test.sh` runs the scenarios tagged `aityx` on the real
  aityx, as PokerFace's.
- **Version**: `X.Y.Z`, X and Y from `version.X.txt` and `version.Y.txt`
  (0.1), Z the build time ([scripts/version.sh](../scripts/version.sh)),
  the `POKERTOUR_VERSION` dart-define, shown in the app bar.
- **Coordinates**: the group `multyx` from `group.id.txt` and the artifact
  `pokertour` from `artifact.id.txt`.
- **Builds**: the [Makefile](../Makefile) runs
  [scripts/make.sh](../scripts/make.sh): `web` (base href `/pokertour/` unless
  `WEB_BASE_HREF` says otherwise), `android`, `ios`, `linux`, `all`,
  `clean`. The native builds have no sign-in: they never reach the table.
- **Dev container**: the multyx group's
  ([.devcontainer/multyx/](../../.devcontainer/multyx)), named **multyx
  demos**, shared with tatyx; Docker in it for Floci; it forwards 9810
  and sets `POKERTOUR_BIND_HOST=0.0.0.0`, and `post-start.sh` makes the
  port public, as the app asks for a sign-in before anything but the
  leaderboard. The group's published image (Flutter and Node) carries
  the app's release web build once it is built with
  `bash image/build-image.sh multyx`; until then a codespace builds it.
- **The index**: a card on the multyx group's page
  ([multyx-index/](../../multyx-index), port 9700), beside tatyx's.

## Known limitations

- The dev container's image doesn't carry this demo's build until it is
  rebuilt and pushed: the first codespace builds it, a minute or two.
- `flutter run -d chrome` runs the app on an origin without the server:
  no config, so the welcome page waits for one. Use `scripts/serve.sh`.
