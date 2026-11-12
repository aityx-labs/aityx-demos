# Agent instructions

## Before committing and pushing

Review all new and modified code for **correctness** and **security** before
every commit and push:

- **Correctness**: verify the change does what it claims — run the relevant
  code path, not just a syntax check. For this project that means `dart
  test` in `poker_core/`, `aws_lite/` and `pokertour_api/` (with Floci
  running, `devbox services up` or `docker compose -f floci/compose.yaml
  up -d`, so `test/floci_test.dart` runs the table and the bucket on it
  instead of skipping), `flutter analyze` and `flutter test` in
  `pokertour_app/`, and `bash
  scripts/build.sh` builds the web app (base href `/pokertour/`, no CDN) and
  compiles the server. A change to `pokertour_api/bin/lambda.dart`,
  `lib/lambda/`, `lib/aws/` or `deploy/` is verified on AWS (`bash
  deploy/deploy.sh`, then `/api/health` through CloudFront and the
  runner's log). After
  changing anything in `pokertour_app/assets/models/`, also run `bash
  scripts/model-test.sh`, which runs every strategy's rules on aityx.
- **Secrets**, such as the aityx keys: the host's keys are the
  leaderboard's alone, production's in the S3 object
  `pokertour/leaderboard.key` (which only the Lambda functions' role
  can read) and staging's in the laptop server's environment
  (`POKERTOUR_LEADERBOARD_KEY`, from `.env`). Players bring their own
  keys and never get the host's: never give a player role, an object, an
  API answer or a page access to a leaderboard key. Never compile a key
  into the app, serve it from the API, print it, log it, show it in the
  calls sidebar, write it to the leaderboard's file or the tour's table,
  put it on a command line (deploy.sh pipes it to `aws s3 cp -`), or in
  a CloudFormation parameter or a function's environment. A player's
  own key stays in their browser; the local server's relay to aityx
  staging (`lib/aityx_relay.dart`) passes their Authorization header on
  and must never log it, store it, or add a key of its own. The players'
  ID tokens go to the server (as bearers), nowhere else.
- **Security**: check for hardcoded secrets or tokens, unsafe shell patterns
  (unquoted variables, `curl | bash` of unpinned sources, world-writable
  files), injection risks, third-party scripts on the app's origin, and
  unnecessarily broad permissions or exposed ports. Every call that
  enters or reads strategies needs a verified Google token for an
  allowed domain. Never commit credentials, even placeholders that look
  real.

Do not commit or push code that has not passed both checks.

## Project notes

- Toolchain is managed by [devbox.json](devbox.json); enter it with
  `devbox shell` and keep [devbox.lock](devbox.lock) committed.
- One service: the server (`pokertour_api`) serves the web build at
  `/pokertour/` on port 9810 and the API at `/api/` (`./start-multyx.sh
  PokerTour` at the root), keeping the tour in Floci, the local AWS
  (`floci/compose.yaml`, port 9811; see [CLAUDE.md](CLAUDE.md)). The app
  depends on the shared packages `../packages/aityx_web` and
  `../poker_core` by path; the server on `../poker_core` and
  `../aws_lite`.
- On AWS the same server code is two Lambda functions (`bin/lambda.dart`)
  behind CloudFront, deployed by `deploy/deploy.sh`; the container build
  and the deployment are documented in the [README](README.md).
